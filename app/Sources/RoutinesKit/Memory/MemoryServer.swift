import Foundation

/// `Routines --memory-mcp --routine <id>`: a stdio MCP server with one tool that only reads memory (FR-034).
public enum MemoryServer {
    public static let flag = "--memory-mcp"
    static let name = "routines-memory"

    static let tool: JSONValue = .object([
        "name": .string("search"),
        "description": .string("Search the memory of this routine. It returns the closest entries first."),
        "inputSchema": .object([
            "type": .string("object"), "required": .array([.string("query")]),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(Double(MemorySearch.maxEntries))]),
            ]),
        ]),
    ])

    /// Reads one request per line and writes one answer per line, until stdin ends.
    public static func serve(routine: String, entries: URL) {
        while let line = readLine(strippingNewline: true) {
            guard let answer = respond(line, routine: routine, entries: entries) else { continue }
            FileHandle.standardOutput.write(Data((answer + "\n").utf8))
        }
    }

    /// The answer to one JSON-RPC 2.0 message, or nil for a notification. It opens the entries read-only for each call.
    public static func respond(_ line: String, routine: String, entries: URL) -> String? {
        guard let data = line.data(using: .utf8), case .object(let message)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return reply(id: .null, error: (-32700, "Parse error"))
        }
        guard let id = message["id"] else { return nil }
        guard case .string(let method)? = message["method"] else { return reply(id: id, error: (-32600, "Invalid Request")) }
        let params: [String: JSONValue] = if case .object(let object)? = message["params"] { object } else { [:] }
        switch method {
        case "initialize":
            let version = params["protocolVersion"] ?? .string("2025-06-18")
            return reply(id: id, result: .object([
                "protocolVersion": version, "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": .string(name), "version": .string("1")]),
            ]))
        case "tools/list": return reply(id: id, result: .object(["tools": .array([tool])]))
        case "tools/call": return call(id: id, params: params, routine: routine, entries: entries)
        default: return reply(id: id, error: (-32601, "Method not found: \(method)"))
        }
    }

    private static func call(id: JSONValue, params: [String: JSONValue], routine: String, entries url: URL) -> String {
        guard case .string("search")? = params["name"] else { return reply(id: id, error: (-32602, "Unknown tool")) }
        let arguments: [String: JSONValue] = if case .object(let object)? = params["arguments"] { object } else { [:] }
        guard case .string(let query)? = arguments["query"] else { return reply(id: id, error: (-32602, "search needs a query")) }
        let tags: [String] = if case .array(let values)? = arguments["tags"] { values.compactMap { if case .string(let tag) = $0 { tag } else { nil } } } else { [] }
        let limit: Int = if case .number(let number)? = arguments["limit"] { Int(number) } else { MemorySearch.maxEntries }
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder.memory.decode([MemoryEntry].self, from: $0) } ?? []
        let found = MemorySearch.search(stored, routine: routine, query: query, tags: tags, limit: limit).map { entry in
            Found(type: entry.type.rawValue, text: entry.text, tags: entry.tags, writtenAt: ISO8601.format(entry.writtenAt))
        }
        let text = Reply.encode(found) ?? "[]"
        return reply(id: id, result: .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])])]))
    }

    private struct Found: Encodable {
        var type: String
        var text: String
        var tags: [String]
        var writtenAt: String
    }

    private static func reply(id: JSONValue, result: JSONValue) -> String {
        Reply.encode(JSONValue.object(["jsonrpc": .string("2.0"), "id": id, "result": result])) ?? ""
    }

    private static func reply(id: JSONValue, error: (code: Int, message: String)) -> String {
        Reply.encode(JSONValue.object([
            "jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(Double(error.code)), "message": .string(error.message)]),
        ])) ?? ""
    }
}

extension JSONDecoder {
    static var memory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ISO8601.decoding
        return decoder
    }
}
