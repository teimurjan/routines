import Foundation

/// Reads and writes one Codable value as a JSON file.
struct JSONFile<Value: Codable> {
    let url: URL

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ISO8601.decoding
        return decoder
    }

    /// A file that does not parse returns an error, so the caller does not replace it with an empty value.
    func load(default empty: Value) -> Result<Value, HostError> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(empty) }
        do {
            return .success(try Self.decoder.decode(Value.self, from: Data(contentsOf: url)))
        } catch {
            return .failure(.failed("\(url.path): \(error.localizedDescription)"))
        }
    }

    @discardableResult
    func save(_ value: Value) -> Result<Void, HostError> {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: url, options: .atomic)
            return .success(())
        } catch {
            return .failure(.failed("\(url.path): \(error.localizedDescription)"))
        }
    }
}
