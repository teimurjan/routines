import Foundation

/// The host side of one plugin call. It checks each request against the manifest and answers with the JSON of a `Result`.
public final class Bridge: Sendable {
    public let pluginId: String
    /// Owns the locks and browser sessions of this call, so the host frees them when the call ends.
    public let callId: String
    let check: PermissionCheck
    let info: [String: String]
    let log: RunLog
    let services: HostServices

    init(pluginId: String, callId: String, check: PermissionCheck, info: [String: String], log: RunLog, services: HostServices) {
        self.pluginId = pluginId
        self.callId = callId
        self.check = check
        self.info = info
        self.log = log
        self.services = services
    }

    var infoJSON: String { Reply.encode(info) ?? "{}" }

    public func handle(method: String, payload: String) async -> String {
        let reply = await route(method, Data(payload.utf8))
        if case .failure(let error) = reply, case .denied = error { log.write("\(method): \(error)") }
        return Reply.envelope(reply)
    }

    private func route(_ method: String, _ payload: Data) async -> Result<String, HostError> {
        switch method {
        case "exec": return await exec(payload)
        case "which": return decode(Named.self, payload).flatMap { request in
            ExecService.which(request.name, home: check.home).map { Reply.json($0) }.map(Result.success) ?? .failure(.failed("\(request.name) is not on the PATH"))
        }
        case "fs.exists": return path(payload) { .success(Reply.json(FileService.exists($0))) }
        case "fs.readText": return path(payload) { path in FileService.readText(path).map { Reply.json($0) } }
        case "fs.readBase64": return path(payload) { path in FileService.readBase64(path).map { Reply.json($0) } }
        case "fs.writeText": return decode(WriteText.self, payload).flatMap { request in
            check.path(request.path).flatMap { FileService.write(Data(request.text.utf8), to: $0, mode: request.mode) }.map { "null" }
        }
        case "fs.writeBase64": return decode(WriteBase64.self, payload).flatMap { request in
            guard let data = Data(base64Encoded: request.base64) else { return .failure(.failed("invalid base64")) }
            return check.path(request.path).flatMap { FileService.write(data, to: $0) }.map { "null" }
        }
        case "fs.remove": return path(payload) { FileService.remove($0).map { "null" } }
        case "fs.mkdir": return path(payload) { FileService.mkdir($0).map { "null" } }
        case "fs.list": return path(payload) { path in FileService.list(path).map { Reply.encode($0) ?? "[]" } }
        case "lock.acquire": return await lockAcquire(payload)
        case "lock.release": return await lockRelease(payload)
        case "board.upsert": return await boardUpsert(payload)
        case "board.remove": return await boardRemove(payload)
        case "board.list": return await boardList()
        case "notify": return await notify(payload)
        case "run.soon": return await runSoon(payload)
        case "notes.list": return await notesList()
        case "activity.list": return await activityList(payload)
        case "page.publish": return await pagePublish(payload)
        case "page.get": return await pageGet()
        case "http": return await http(payload)
        case "timer.sleep": return await sleep(payload)
        case "browser.open", "browser.goto", "browser.waitFor", "browser.evaluate", "browser.close": return await browser(method, payload)
        default: return .failure(.failed("unknown host call \(method)"))
        }
    }

    // MARK: Calls

    private func exec(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let request) = decode(ExecRequest.self, payload) else { return .failure(.failed("invalid exec request")) }
        if case .failure(let error) = check.command(request.cmd) { return .failure(error) }
        if let cwd = request.cwd, case .failure(let error) = check.path(cwd) { return .failure(error) }
        log.write("exec: \(request.cmd.prefix(3).joined(separator: " "))")
        return await ExecService.run(request, home: check.home).map { Reply.json($0) }
    }

    private func lockAcquire(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let request) = decode(LockRequest.self, payload) else { return .failure(.failed("invalid lock request")) }
        let acquired = await services.locks.acquire(request.name, owner: callId, timeoutMs: request.timeoutMs ?? 5000)
        return .success(Reply.json(acquired))
    }

    private func lockRelease(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let request) = decode(LockRequest.self, payload) else { return .failure(.failed("invalid lock request")) }
        await services.locks.release(request.name, owner: callId)
        return .success("null")
    }

    private func boardUpsert(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let card) = decode(Card.self, payload) else { return .failure(.failed("invalid card: \(String(decoding: payload, as: UTF8.self).prefix(200))")) }
        let pluginId = pluginId
        return await services.board { $0.upsert(card, pluginId: pluginId) }.map { "null" }
    }

    private func boardRemove(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let request) = decode(Identified.self, payload) else { return .failure(.failed("invalid card id")) }
        let pluginId = pluginId
        return await services.board { $0.remove(request.id, pluginId: pluginId) }.map { "null" }
    }

    private func boardList() async -> Result<String, HostError> {
        let pluginId = pluginId
        let cards = await services.board { $0.cards(of: pluginId) }
        return .success(Reply.encode(cards) ?? "[]")
    }

    private func notify(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let request) = decode(NotifyRequest.self, payload) else { return .failure(.failed("invalid notification")) }
        await services.notify(pluginId: pluginId, title: request.title, body: request.body, cardId: request.cardId)
        return .success("null")
    }

    private func runSoon(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let request) = decode(Delay.self, payload) else { return .failure(.failed("invalid run request")) }
        await services.requestRun(pluginId: pluginId, delayMs: request.delayMs)
        return .success("null")
    }

    private func notesList() async -> Result<String, HostError> {
        let pluginId = pluginId
        let notes = await services.notes { $0.notes(of: pluginId).map { PluginNote(number: $0.number, text: $0.text) } }
        return .success(Reply.encode(notes) ?? "[]")
    }

    private func activityList(_ payload: Data) async -> Result<String, HostError> {
        if case .failure(let error) = check.activity() { return .failure(error) }
        guard case .success(let request) = decode(Since.self, payload) else { return .failure(.failed("invalid activity request")) }
        return .success(Reply.json(await services.activity(reader: pluginId, since: request.since)))
    }

    private func pagePublish(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let request) = decode(PageRequest.self, payload) else { return .failure(.failed("invalid page: \(String(decoding: payload, as: UTF8.self).prefix(200))")) }
        let pluginId = pluginId
        return await services.pages { $0.publish(request.blocks, pluginId: pluginId) }.map { "null" }
    }

    private func pageGet() async -> Result<String, HostError> {
        let pluginId = pluginId
        let page = await services.pages { $0.page(of: pluginId) }
        return .success(page.flatMap { Reply.encode($0) } ?? "null")
    }

    private func http(_ payload: Data) async -> Result<String, HostError> {
        guard case .success(let request) = decode(HTTPRequest.self, payload) else { return .failure(.failed("invalid HTTP request")) }
        if case .failure(let error) = check.host(of: request.url) { return .failure(error) }
        return await HTTPService.send(request).map { Reply.encode($0) ?? "null" }
    }

    private func sleep(_ payload: Data) async -> Result<String, HostError> {
        let ms = (try? JSONDecoder().decode(Sleep.self, from: payload).ms) ?? 0
        try? await Task.sleep(for: .milliseconds(max(0, ms)))
        return .success("null")
    }

    private func browser(_ method: String, _ payload: Data) async -> Result<String, HostError> {
        if case .failure(let error) = check.browser() { return .failure(error) }
        let owner = callId
        let browser = services.browser
        switch method {
        case "browser.open":
            guard case .success(let request) = decode(BrowserOpen.self, payload) else { return .failure(.failed("invalid browser request")) }
            return .success(Reply.json(await browser.open(profile: request.profile, pluginId: pluginId, owner: owner)))
        case "browser.goto":
            guard case .success(let request) = decode(BrowserGoto.self, payload) else { return .failure(.failed("invalid browser request")) }
            if case .failure(let error) = check.host(of: request.url) { return .failure(error) }
            return await browser.goto(session: request.session, url: request.url, timeoutMs: request.timeoutMs ?? 60_000, owner: owner).map { "null" }
        case "browser.waitFor":
            guard case .success(let request) = decode(BrowserWait.self, payload) else { return .failure(.failed("invalid browser request")) }
            return await browser.waitFor(session: request.session, expression: request.expression, timeoutMs: request.timeoutMs ?? 60_000, owner: owner)
                .map { Reply.json($0) }
        case "browser.evaluate":
            guard case .success(let request) = decode(BrowserEvaluate.self, payload) else { return .failure(.failed("invalid browser request")) }
            return await browser.evaluate(session: request.session, body: request.body, argumentsJSON: request.argumentsJSON, owner: owner)
        default:
            guard case .success(let request) = decode(BrowserSession.self, payload) else { return .failure(.failed("invalid browser request")) }
            await browser.close(session: request.session, owner: owner)
            return .success("null")
        }
    }

    // MARK: Helpers

    private func path(_ payload: Data, _ work: (String) -> Result<String, HostError>) -> Result<String, HostError> {
        decode(PathRequest.self, payload).flatMap { check.path($0.path) }.flatMap(work)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ payload: Data) -> Result<T, HostError> {
        do {
            return .success(try Reply.decoder.decode(type, from: payload))
        } catch {
            return .failure(.failed("invalid request: \(error)"))
        }
    }
}

// MARK: Requests

private struct Named: Decodable { var name: String }
private struct PathRequest: Decodable { var path: String }
private struct WriteText: Decodable { var path: String; var text: String; var mode: Int? }
private struct WriteBase64: Decodable { var path: String; var base64: String }
private struct LockRequest: Decodable { var name: String; var timeoutMs: Int? }
private struct Identified: Decodable { var id: String }
private struct NotifyRequest: Decodable { var title: String; var body: String; var cardId: String? }
private struct PluginNote: Encodable { var number: Int; var text: String }
private struct Since: Decodable { var since: Date }
private struct PageRequest: Decodable { var blocks: [PageBlock] }
private struct Sleep: Decodable { var ms: Int }
private struct Delay: Decodable { var delayMs: Int }
private struct BrowserOpen: Decodable { var profile: String }
private struct BrowserSession: Decodable { var session: String }
private struct BrowserGoto: Decodable { var session: String; var url: String; var timeoutMs: Int? }
private struct BrowserWait: Decodable { var session: String; var expression: String; var timeoutMs: Int? }

private struct BrowserEvaluate: Decodable {
    var session: String
    var body: String
    var argumentsJSON: String

    enum CodingKeys: String, CodingKey { case session, body, args }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        session = try values.decode(String.self, forKey: .session)
        body = try values.decode(String.self, forKey: .body)
        argumentsJSON = (try? values.decode(JSONValue.self, forKey: .args)).flatMap { Reply.encode($0) } ?? "{}"
    }
}

enum Reply {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ISO8601.decoding
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.format(date))
        }
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }

    static func json<T: Encodable>(_ value: T) -> String {
        encode(value) ?? "null"
    }

    /// `value` is already JSON text.
    static func envelope(_ result: Result<String, HostError>) -> String {
        switch result {
        case .success(let value): "{\"ok\":true,\"value\":\(value)}"
        case .failure(let error): "{\"ok\":false,\"error\":\(json(error.description))}"
        }
    }
}
