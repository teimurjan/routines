import Foundation

public struct PageStatus: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case ok, warning, error, neutral }

    public var state: State
    public var label: String
    public var detail: String?

    public init(state: State, label: String, detail: String? = nil) {
        self.state = state
        self.label = label
        self.detail = detail
    }
}

/// One part of a plugin page. The host draws each kind, so a plugin sends data and no code.
public enum PageBlock: Codable, Equatable, Sendable {
    case markdown(String)
    case status(PageStatus)

    private enum Kind: String, Codable { case markdown, status }
    private enum CodingKeys: String, CodingKey { case type, text }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .markdown: self = .markdown(try values.decode(String.self, forKey: .text))
        case .status: self = .status(try PageStatus(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .markdown(let text):
            try values.encode(Kind.markdown, forKey: .type)
            try values.encode(text, forKey: .text)
        case .status(let status):
            try values.encode(Kind.status, forKey: .type)
            try status.encode(to: encoder)
        }
    }
}

public struct Page: Codable, Equatable, Sendable {
    public var blocks: [PageBlock]
    /// The last change of the blocks. A publish of the same blocks keeps it.
    public var updatedAt: Date
}
