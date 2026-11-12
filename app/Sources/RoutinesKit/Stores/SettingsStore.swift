import Foundation
import Observation

/// The setting values of each plugin, the values that plugins share, the plugins that you turned off and the plugins that you pinned.
@MainActor
@Observable
public final class SettingsStore {
    struct Saved: Codable {
        var shared: [String: String] = [:]
        var plugins: [String: [String: String]] = [:]
        var disabled: [String] = []
        var launchAtLogin: Bool? = nil
        var retentionDays: [String: Int]? = nil
        var pinned: [String]? = nil
        var agent: AgentConfig? = nil
    }

    private var saved = Saved()
    private let file: JSONFile<Saved>

    public init(url: URL) {
        file = JSONFile(url: url)
        if case .success(let loaded) = file.load(default: Saved()) { saved = loaded }
    }

    public func value(_ field: SettingField, pluginId: String) -> String {
        let stored = field.shared ? saved.shared[field.key] : saved.plugins[pluginId]?[field.key]
        return stored ?? ""
    }

    public func set(_ value: String, field: SettingField, pluginId: String) {
        if field.shared {
            saved.shared[field.key] = value
        } else {
            saved.plugins[pluginId, default: [:]][field.key] = value
        }
        file.save(saved)
    }

    /// The values that a run gets. An empty value falls back to the default of the manifest.
    public func resolved(_ manifest: Manifest) -> [String: String] {
        manifest.settings.reduce(into: [:]) { values, field in
            let value = value(field, pluginId: manifest.id)
            if let resolved = value.isEmpty ? field.defaultValue : value { values[field.key] = resolved }
        }
    }

    public func missing(_ manifest: Manifest) -> [SettingField] {
        let values = resolved(manifest)
        return manifest.settings.filter { $0.required && (values[$0.key] ?? "").isEmpty }
    }

    public func isEnabled(_ pluginId: String) -> Bool {
        !saved.disabled.contains(pluginId)
    }

    public func setEnabled(_ enabled: Bool, pluginId: String) {
        saved.disabled.removeAll { $0 == pluginId }
        if !enabled { saved.disabled.append(pluginId) }
        file.save(saved)
    }

    /// The pinned plugins, in the order that you pinned them.
    public var pinned: [String] { saved.pinned ?? [] }

    public func isPinned(_ pluginId: String) -> Bool {
        pinned.contains(pluginId)
    }

    public func setPinned(_ isPinned: Bool, pluginId: String) {
        let others = pinned.filter { $0 != pluginId }
        saved.pinned = isPinned ? others + [pluginId] : others
        file.save(saved)
    }

    /// Your retention of done cards for a plugin, or the default of its manifest.
    public func retentionDays(_ manifest: Manifest) -> Int {
        saved.retentionDays?[manifest.id] ?? manifest.doneCards.retentionDays
    }

    public func setRetentionDays(_ days: Int, pluginId: String) {
        saved.retentionDays = (saved.retentionDays ?? [:]).merging([pluginId: max(0, days)]) { _, new in new }
        file.save(saved)
    }

    /// The coding agent of the threads.
    public var agent: AgentConfig {
        get { saved.agent ?? AgentConfig() }
        set {
            saved.agent = newValue
            file.save(saved)
        }
    }

    public var launchAtLogin: Bool {
        get { saved.launchAtLogin ?? false }
        set {
            saved.launchAtLogin = newValue
            file.save(saved)
        }
    }
}
