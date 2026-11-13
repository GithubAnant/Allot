import Foundation
import JavaScriptCore

/// Runs the extracted upstream arithmetic in macOS JavaScriptCore, with no browser or Node runtime.
final class T3Engine {
    private let context: JSContext
    private var exception: String?
    init() throws {
        guard let context = JSContext(), let source = QuotaResources.bundle.url(forResource: "T3Usage", withExtension: "js") else { throw UsageFailure("T3 usage engine is missing.") }
        self.context = context
        context.exceptionHandler = { [weak self] _, error in self?.exception = error?.toString() }
        context.evaluateScript(try String(contentsOf: source, encoding: .utf8))
        if exception != nil { throw UsageFailure("T3 usage engine could not initialize.") }
    }
    func call(_ method: String, json: Data) throws -> Data {
        exception = nil
        guard let input = String(data: json, encoding: .utf8),
              let result = context.objectForKeyedSubscript("T3Usage")?.invokeMethod(method, withArguments: [input])?.toString(), exception == nil,
              let data = result.data(using: .utf8) else { throw UsageFailure("T3 usage calculation failed.") }
        return data
    }
    func call(_ method: String, object: [String: Any]) throws -> Data { try call(method, json: JSONSerialization.data(withJSONObject: object)) }
}
