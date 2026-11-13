import Foundation
import Observation
import Security

/// Where the allow list lives. Only the app changes it (FR-026). See specs/004-actionables/research.md, section 10.
public protocol AllowListVault: Sendable {
    func load() -> [String: Set<String>]
    func save(_ list: [String: Set<String>])
}

/// One generic password item in the login Keychain. Another process must ask you before it reads or changes it.
public struct KeychainVault: AllowListVault {
    static let service = "Routines allow list"
    static let account = "allow-list"

    public init() {}

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account]
    }

    public func load() -> [String: Set<String>] {
        var found: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &found) == errSecSuccess, let data = found as? Data,
            let list = try? JSONDecoder().decode([String: Set<String>].self, from: data)
        else { return [:] }
        return list
    }

    public func save(_ list: [String: Set<String>]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// The vault of the tests.
public final class MemoryVault: AllowListVault, @unchecked Sendable {
    private var list: [String: Set<String>]
    private let lock = NSLock()

    public init(_ list: [String: Set<String>] = [:]) {
        self.list = list
    }

    public func load() -> [String: Set<String>] { lock.withLock { list } }
    public func save(_ list: [String: Set<String>]) { lock.withLock { self.list = list } }
}

/// The allow list that the app reads at launch and saves after each change of yours.
@MainActor
@Observable
public final class AllowList {
    public private(set) var list: [String: Set<String>]
    @ObservationIgnored private let vault: AllowListVault

    public init(vault: AllowListVault) {
        self.vault = vault
        list = vault.load()
    }

    /// Only the ids that the manifest declares as `outward` or `destructive` count.
    public static func effective(_ ids: Set<String>, manifest: Manifest) -> Set<String> {
        ids.filter { id in manifest.transition(id)?.risk.needsConsent == true }
    }

    public func allowed(_ routine: String, manifest: Manifest) -> Set<String> {
        Self.effective(list[routine] ?? [], manifest: manifest)
    }

    public func contains(_ transition: String, routine: String) -> Bool {
        list[routine]?.contains(transition) == true
    }

    public func set(_ allowed: Bool, transition: String, routine: String) {
        var ids = list[routine] ?? []
        if allowed { ids.insert(transition) } else { ids.remove(transition) }
        list[routine] = ids.isEmpty ? nil : ids
        vault.save(list)
    }
}
