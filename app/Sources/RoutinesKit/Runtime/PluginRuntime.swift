import Foundation
import JavaScriptCore

/// One JavaScriptCore context for one call of a plugin. All JavaScript runs on its own serial queue.
final class PluginRuntime: @unchecked Sendable {
    private let queue: DispatchQueue
    private let bridge: Bridge
    private var context: JSContext?

    init(bridge: Bridge) {
        self.bridge = bridge
        queue = DispatchQueue(label: "routines.plugin.\(bridge.pluginId).\(bridge.callId)")
    }

    /// Evaluates the prelude and the bundle. The bundle must call `definePlugin`.
    func load(prelude: String, bundle: String, bundleURL: URL) async -> Result<Void, HostError> {
        await onQueue { [self] in
            guard let context = JSContext(virtualMachine: JSVirtualMachine()) else { return .failure(.failed("JavaScriptCore did not start")) }
            context.name = bridge.pluginId
            installNative(in: context)
            self.context = context
            context.evaluateScript(prelude, withSourceURL: URL(string: "routines://prelude.js"))
            if let error = takeException(context) { return .failure(.failed("prelude: \(error)")) }
            context.evaluateScript(bundle, withSourceURL: bundleURL)
            if let error = takeException(context) { return .failure(.failed(error)) }
            let plugin = context.objectForKeyedSubscript("__plugin")
            return plugin?.isObject == true ? .success(()) : .failure(.failed("the bundle did not call definePlugin"))
        }
    }

    /// Calls a function of the plugin with JSON arguments and returns the JSON of its value. A function that the plugin did not define returns nil.
    func call(_ name: String, arguments: [String], timeout: TimeInterval) async -> Result<String?, HostError> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<String?, HostError>, Never>) in
            let once = Once(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(.failure(.failed("timed out after \(Int(timeout / 60)) minutes")))
            }
            queue.async { [self] in
                guard let context, let plugin = context.objectForKeyedSubscript("__plugin"), plugin.isObject else {
                    return once.resume(.failure(.failed("the plugin is not loaded")))
                }
                guard let function = plugin.objectForKeyedSubscript(name), !function.isUndefined else { return once.resume(.success(nil)) }
                let json = context.objectForKeyedSubscript("JSON")
                let values = arguments.map { json?.invokeMethod("parse", withArguments: [$0]) as Any }
                let returned = plugin.invokeMethod(name, withArguments: values)
                if let error = takeException(context) { return once.resume(.failure(.failed(error))) }

                let fulfilled: @convention(block) (JSValue) -> Void = { value in
                    let text = json?.invokeMethod("stringify", withArguments: [value])
                    once.resume(.success(text?.isUndefined == false ? text?.toString() : "null"))
                }
                let rejected: @convention(block) (JSValue) -> Void = { reason in
                    once.resume(.failure(.failed(Self.describe(reason))))
                }
                let promise = context.objectForKeyedSubscript("Promise")?.invokeMethod("resolve", withArguments: [returned as Any])
                promise?.invokeMethod("then", withArguments: [JSValue(object: fulfilled, in: context) as Any, JSValue(object: rejected, in: context) as Any])
            }
        }
    }

    private func installNative(in context: JSContext) {
        let native = JSValue(newObjectIn: context)
        let bridge = bridge
        let queue = queue

        let call: @convention(block) (String, String) -> JSValue? = { method, payload in
            guard let current = JSContext.current() else { return nil }
            return JSValue(newPromiseIn: current) { resolve, _ in
                let resolver = Unchecked(resolve)
                Task.detached {
                    let reply = await bridge.handle(method: method, payload: payload)
                    queue.async { _ = resolver.value?.call(withArguments: [reply]) }
                }
            }
        }
        let log: @convention(block) (String) -> Void = { message in bridge.log.write(message) }
        let info: @convention(block) () -> String = { bridge.infoJSON }
        let randomBytes: @convention(block) (Int) -> [Int] = { count in (0..<max(0, min(count, 65_536))).map { _ in Int.random(in: 0...255) } }

        native?.setObject(call, forKeyedSubscript: "call" as NSString)
        native?.setObject(log, forKeyedSubscript: "log" as NSString)
        native?.setObject(info, forKeyedSubscript: "info" as NSString)
        native?.setObject(randomBytes, forKeyedSubscript: "randomBytes" as NSString)
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
    }

    private func takeException(_ context: JSContext) -> String? {
        guard let exception = context.exception else { return nil }
        context.exception = nil
        return Self.describe(exception)
    }

    static func describe(_ value: JSValue) -> String {
        let message = value.toString() ?? "unknown error"
        guard let stack = value.objectForKeyedSubscript("stack"), stack.isString, let text = stack.toString(), !text.isEmpty else { return message }
        return "\(message)\n\(text.split(separator: "\n").prefix(6).joined(separator: "\n"))"
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in queue.async { continuation.resume(returning: work()) } }
    }
}

/// Resumes a continuation once, because a promise can settle after a timeout already ended the call.
private final class Once<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.withLock {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}

/// Moves a JavaScriptCore value to another task. Only the queue of its runtime touches it.
private struct Unchecked<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
