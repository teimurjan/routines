import Foundation

public struct HTTPRequest: Decodable, Sendable {
    public var url: String
    public var method: String?
    public var headers: [String: String]?
    public var body: String?
    public var bodyBase64: String?
    public var timeoutMs: Int?
    public var redirect: String?
}

public struct HTTPReply: Encodable, Sendable {
    public var status: Int
    public var url: String
    public var headers: [[String]]
    public var body: String
    public var bodyBase64: String?
}

/// One request per call. No cookie store, so plugins share no session and a plugin sets its cookies itself.
public enum HTTPService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private final class ManualRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    public static func send(_ request: HTTPRequest) async -> Result<HTTPReply, HostError> {
        guard let url = URL(string: request.url) else { return .failure(.failed("invalid URL \(request.url)")) }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method ?? "GET"
        urlRequest.timeoutInterval = Double(request.timeoutMs ?? 60_000) / 1000
        for (name, value) in request.headers ?? [:] { urlRequest.setValue(value, forHTTPHeaderField: name) }
        if let body = request.body { urlRequest.httpBody = Data(body.utf8) }
        if let base64 = request.bodyBase64 { urlRequest.httpBody = Data(base64Encoded: base64) }

        do {
            let delegate = request.redirect == "manual" ? ManualRedirect() : nil
            let (data, response) = try await session.data(for: urlRequest, delegate: delegate)
            guard let http = response as? HTTPURLResponse else { return .failure(.failed("not an HTTP response")) }
            let text = String(data: data, encoding: .utf8)
            return .success(
                HTTPReply(
                    status: http.statusCode,
                    url: http.url?.absoluteString ?? request.url,
                    headers: headerPairs(http),
                    body: text ?? "",
                    bodyBase64: text == nil ? data.base64EncodedString() : nil
                ))
        } catch {
            return .failure(.failed((error as NSError).localizedDescription))
        }
    }

    // Foundation joins repeated Set-Cookie headers, so the cookies come back one per pair from their own parser.
    static func headerPairs(_ response: HTTPURLResponse) -> [[String]] {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { pairs, field in
            pairs[String(describing: field.key)] = String(describing: field.value)
        }
        let plain = fields.filter { $0.key.lowercased() != "set-cookie" }.map { [$0.key.lowercased(), $0.value] }
        guard let url = response.url, fields.keys.contains(where: { $0.lowercased() == "set-cookie" }) else { return plain }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map { ["set-cookie", "\($0.name)=\($0.value)"] }
        return plain + cookies
    }
}
