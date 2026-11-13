import Foundation

/// The `plugin.json` of a plugin. See specs/001-swift-host/contracts/plugin-api.md.
public struct Manifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var color: String
    public var icon: String
    /// One emoji that stands for the plugin in the sidebar and in the threads.
    public var emoji: String?
    public var main: String
    public var schedule: [ClockSlot]
    public var runAtLaunch: Bool
    public var timeoutMinutes: Int
    public var settings: [SettingField]
    public var permissions: Permissions
    public var doneCards: DoneCards
    /// Each action of the plugin. An item action calls `onAction` and a plugin action calls `onPluginAction`.
    public var actions: [CardAction]
    /// The page that the plugin ships in `dist/ui`. The plugin page shows it as its first tab.
    public var ui: PluginUI?
    /// A hidden plugin still runs, but the sidebar leaves it out.
    public var hidden: Bool
    /// The kinds and states that a routine handles.
    public var handles: [Handle]
    /// The kinds that the plugin declares. Each one has a schema in `dist/kinds.json`.
    public var kinds: [String]
    public var transitions: [TransitionDeclaration]
    public var source: SourceDeclaration?

    public init(
        id: String, name: String, description: String = "", color: String = "#6B7280", icon: String = "puzzlepiece", emoji: String? = nil,
        main: String = "dist/plugin.js", schedule: [ClockSlot] = [], runAtLaunch: Bool = false, timeoutMinutes: Int = 150,
        settings: [SettingField] = [], permissions: Permissions = Permissions(), doneCards: DoneCards = DoneCards(), actions: [CardAction] = [],
        ui: PluginUI? = nil, hidden: Bool = false, handles: [Handle] = [], kinds: [String] = [], transitions: [TransitionDeclaration] = [],
        source: SourceDeclaration? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.color = color
        self.icon = icon
        self.emoji = emoji
        self.main = main
        self.schedule = schedule
        self.runAtLaunch = runAtLaunch
        self.timeoutMinutes = timeoutMinutes
        self.settings = settings
        self.permissions = permissions
        self.doneCards = doneCards
        self.actions = actions
        self.ui = ui
        self.hidden = hidden
        self.handles = handles
        self.kinds = kinds
        self.transitions = transitions
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        color = try values.decodeIfPresent(String.self, forKey: .color) ?? "#6B7280"
        icon = try values.decodeIfPresent(String.self, forKey: .icon) ?? "puzzlepiece"
        emoji = try values.decodeIfPresent(String.self, forKey: .emoji).flatMap { $0.isEmpty ? nil : $0 }
        main = try values.decodeIfPresent(String.self, forKey: .main) ?? "dist/plugin.js"
        schedule = try values.decodeIfPresent([ClockSlot].self, forKey: .schedule) ?? []
        runAtLaunch = try values.decodeIfPresent(Bool.self, forKey: .runAtLaunch) ?? false
        timeoutMinutes = try values.decodeIfPresent(Int.self, forKey: .timeoutMinutes) ?? 150
        settings = try values.decodeIfPresent([SettingField].self, forKey: .settings) ?? []
        permissions = try values.decodeIfPresent(Permissions.self, forKey: .permissions) ?? Permissions()
        doneCards = try values.decodeIfPresent(DoneCards.self, forKey: .doneCards) ?? DoneCards()
        actions = try values.decodeIfPresent([CardAction].self, forKey: .actions) ?? []
        ui = try values.decodeIfPresent(PluginUI.self, forKey: .ui)
        hidden = try values.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        handles = try values.decodeIfPresent([Handle].self, forKey: .handles) ?? []
        kinds = try values.decodeIfPresent([String].self, forKey: .kinds) ?? []
        transitions = try values.decodeIfPresent([TransitionDeclaration].self, forKey: .transitions) ?? []
        source = try values.decodeIfPresent(SourceDeclaration.self, forKey: .source)
    }

    public enum Role: Sendable { case source, routine, legacy }

    /// A plugin with none of the new fields is a plugin of today, and it uses the board adapter.
    public var role: Role {
        if source != nil { return .source }
        return handles.isEmpty && transitions.isEmpty ? .legacy : .routine
    }

    /// The transitions that the policy checks. The item actions of a plugin of today count as `outward` transitions from each open state.
    public var effectiveTransitions: [TransitionDeclaration] {
        guard role == .legacy else { return transitions }
        return actions.filter(\.isItemAction).map { action in
            TransitionDeclaration(
                id: action.id, label: action.label, from: Actionable.State.open, risk: .outward, input: action.input, confirm: action.confirm,
                style: action.style)
        }
    }

    public func transition(_ id: String) -> TransitionDeclaration? {
        effectiveTransitions.first { $0.id == id }
    }
}

public struct Handle: Codable, Equatable, Sendable {
    public var kind: String
    public var states: [Actionable.State]

    public init(kind: String, states: [Actionable.State]) {
        self.kind = kind
        self.states = states
    }
}

/// The effect of a transition outside the app.
public enum Risk: String, Codable, Sendable {
    case read, reversible, outward, destructive

    /// An `outward` or `destructive` transition needs your press, your answer or the allow list.
    public var needsConsent: Bool { self == .outward || self == .destructive }
}

/// A named state change that a routine declares in its manifest.
public struct TransitionDeclaration: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var from: [Actionable.State]
    public var risk: Risk
    public var input: CardAction.Input?
    /// Only a press in the app starts it, after the dialog.
    public var confirm: Bool?
    public var style: CardAction.Style?

    public init(
        id: String, label: String, from: [Actionable.State], risk: Risk, input: CardAction.Input? = nil, confirm: Bool? = nil,
        style: CardAction.Style? = nil
    ) {
        self.id = id
        self.label = label
        self.from = from
        self.risk = risk
        self.input = input
        self.confirm = confirm
        self.style = style
    }

    public var needsConfirmation: Bool { confirm == true }
}

/// A source plugin creates and updates actionables through the shared poll.
public struct SourceDeclaration: Codable, Equatable, Sendable {
    public var kinds: [String]
    /// The read tools of the connectors that the poll needs.
    public var tools: [String]

    public init(kinds: [String], tools: [String]) {
        self.kinds = kinds
        self.tools = tools
    }
}

public struct PluginUI: Codable, Equatable, Sendable {
    /// The label of the UI tab.
    public var title: String

    public init(title: String) {
        self.title = title
    }
}

/// What happens to the cards in Done and Failed. You can change the retention in the Settings tab of the plugin.
public struct DoneCards: Codable, Equatable, Sendable {
    public static let defaultRetentionDays = 14

    /// Days after its last change until the host deletes a done or failed card. 0 keeps the cards.
    public var retentionDays: Int

    public init(retentionDays: Int = DoneCards.defaultRetentionDays) {
        self.retentionDays = retentionDays
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        retentionDays = max(0, try values.decodeIfPresent(Int.self, forKey: .retentionDays) ?? Self.defaultRetentionDays)
    }
}

public struct SettingField: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var required: Bool
    public var shared: Bool
    public var placeholder: String?
    public var defaultValue: String?

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, required, shared, placeholder
        case defaultValue = "default"
    }

    public init(key: String, label: String, required: Bool = false, shared: Bool = false, placeholder: String? = nil, defaultValue: String? = nil) {
        self.key = key
        self.label = label
        self.required = required
        self.shared = shared
        self.placeholder = placeholder
        self.defaultValue = defaultValue
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? key
        required = try values.decodeIfPresent(Bool.self, forKey: .required) ?? false
        shared = try values.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        placeholder = try values.decodeIfPresent(String.self, forKey: .placeholder)
        defaultValue = try values.decodeIfPresent(String.self, forKey: .defaultValue)
    }
}

public struct Permissions: Codable, Equatable, Sendable {
    public var exec: [String]
    public var hosts: [String]
    public var paths: [String]
    public var browser: Bool
    /// Reads the cards, notifications and failed runs of all plugins.
    public var activity: Bool
    /// The ids of the plugin actions and the transitions that another program can start with a `routines://` URL.
    public var external: [String]

    public init(exec: [String] = [], hosts: [String] = [], paths: [String] = [], browser: Bool = false, activity: Bool = false, external: [String] = []) {
        self.exec = exec
        self.hosts = hosts
        self.paths = paths
        self.browser = browser
        self.activity = activity
        self.external = external
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        exec = try values.decodeIfPresent([String].self, forKey: .exec) ?? []
        hosts = try values.decodeIfPresent([String].self, forKey: .hosts) ?? []
        paths = try values.decodeIfPresent([String].self, forKey: .paths) ?? []
        browser = try values.decodeIfPresent(Bool.self, forKey: .browser) ?? false
        activity = try values.decodeIfPresent(Bool.self, forKey: .activity) ?? false
        external = try values.decodeIfPresent([String].self, forKey: .external) ?? []
    }
}
