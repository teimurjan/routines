import Foundation

public enum Column: String, Codable, CaseIterable, Sendable, Identifiable {
    case planned
    case working
    case needsYou = "needs-you"
    case done
    case failed

    public var id: String { rawValue }

    /// Done and failed cards need nothing more, so they can be deleted.
    public var isClosed: Bool { self == .done || self == .failed }

    public var title: String {
        switch self {
        case .planned: "Planned"
        case .working: "In progress"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}

/// One action of a plugin. The manifest lists each one. See specs/003-custom-ui-everywhere/contracts/actions.md.
public struct CardAction: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Style: String, Codable, Sendable { case primary, destructive, normal }
    public struct Input: Codable, Equatable, Hashable, Sendable { public var placeholder: String }
    /// An item action needs an item of the plugin. A plugin action takes none.
    public enum Target: String, Codable, Sendable { case item, plugin }

    public var id: String
    public var label: String
    public var style: Style?
    public var input: Input?
    /// The app asks you before each press. External actions skip the dialog.
    public var confirm: Bool?
    /// Absent means `plugin`.
    public var target: Target?

    public init(id: String, label: String, style: Style? = nil, input: Input? = nil, confirm: Bool? = nil, target: Target? = nil) {
        self.id = id
        self.label = label
        self.style = style
        self.input = input
        self.confirm = confirm
        self.target = target
    }

    public var needsConfirmation: Bool { confirm == true }
    public var isItemAction: Bool { target == .item }
}

public struct CardLink: Codable, Equatable, Hashable, Sendable {
    public var label: String
    public var url: String

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }
}

/// One item of work of a plugin. The plugin owns every field but `updatedAt`.
public struct Card: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var body: String?
    public var column: Column
    public var progress: Double?
    public var date: String?
    public var tags: [String]?
    public var links: [CardLink]?
    public var images: [String]?
    public var status: String?
    /// Fields for the UI of the same plugin. The host stores them and does not read them.
    public var data: JSONValue?
    public var updatedAt: Date?

    public init(
        id: String, title: String, body: String? = nil, column: Column, progress: Double? = nil, date: String? = nil, tags: [String]? = nil,
        links: [CardLink]? = nil, images: [String]? = nil, status: String? = nil, data: JSONValue? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.column = column
        self.progress = progress
        self.date = date
        self.tags = tags
        self.links = links
        self.images = images
        self.status = status
        self.data = data
        self.updatedAt = updatedAt
    }

    public var dateValue: Date? {
        guard let date else { return nil }
        return ISO8601.parse(date)
    }
}

public enum ISO8601 {
    private nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let plain = ISO8601DateFormatter()

    private nonisolated(unsafe) static let day: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    public static func parse(_ text: String) -> Date? {
        withFraction.date(from: text) ?? plain.date(from: text) ?? day.date(from: text)
    }

    /// Accepts a time with or without milliseconds, because JavaScript writes them and Foundation does not.
    public static let decoding: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let date = parse(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 time: \(text)"))
        }
        return date
    }

    public static func format(_ date: Date) -> String {
        withFraction.string(from: date)
    }
}
