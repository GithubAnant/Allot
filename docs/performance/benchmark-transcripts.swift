import Foundation
import Dispatch
struct UsageFailure: Error { init(_ message: String) {} }
func readBefore(path: String, provider: String) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var pending = Data(), lines: [String] = []
        let markers = provider == "claude" ? ["\"usage\""] : ["\"token_count\"", "\"token_usage_record\"", "\"turn_context\"", "\"thread_settings_applied\"", "\"session_meta\""]
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            guard pending.count <= 32 * 1024 * 1024 else { throw UsageFailure("A transcript record exceeded the reader's memory bound.") }
            while let end = pending.firstIndex(of: 10) {
                let data = pending.prefix(upTo: end)
                pending.removeSubrange(...end)
                guard let text = String(data: data, encoding: .utf8), markers.contains(where: text.contains),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                var projected = object.filter { ["type", "timestamp", "requestId", "sessionId", "costUSD"].contains($0.key) }
                if provider == "claude", let message = object["message"] as? [String: Any] {
                    projected["message"] = message.filter { ["id", "model", "usage"].contains($0.key) }
                } else if let payload = object["payload"] as? [String: Any] {
                    projected["payload"] = payload.filter { ["type", "id", "session_id", "model_provider", "turn_id", "response_id", "model", "thread_settings", "forked_from_id", "source", "info", "usage"].contains($0.key) }
                }
                lines.append(String(decoding: try JSONSerialization.data(withJSONObject: projected), as: UTF8.self))
            }
        }
        // Keep the prior snapshot while an active transcript has an unfinished record.
        guard pending.isEmpty else { throw UsageFailure("Transcript writer has an unfinished record.") }
        return lines
    }
func readAfter(path: String, provider: String) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var pending = Data(), lines: [String] = []
        let markers = (provider == "claude" ? ["\"usage\""] : ["\"token_count\"", "\"token_usage_record\"", "\"turn_context\"", "\"thread_settings_applied\"", "\"session_meta\""]).map { Data($0.utf8) }
        let newline = Data([10])
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try autoreleasepool {
            pending.append(chunk)
            guard pending.count <= 32 * 1024 * 1024 else { throw UsageFailure("A transcript record exceeded the reader's memory bound.") }
            var cursor = pending.startIndex
            while let separator = pending.range(of: newline, in: cursor..<pending.endIndex) {
                let data = pending[cursor..<separator.lowerBound]
                cursor = separator.upperBound
                guard markers.contains(where: { data.range(of: $0) != nil }),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                var projected = object.filter { ["type", "timestamp", "requestId", "sessionId", "costUSD"].contains($0.key) }
                if provider == "claude", let message = object["message"] as? [String: Any] {
                    projected["message"] = message.filter { ["id", "model", "usage"].contains($0.key) }
                } else if let payload = object["payload"] as? [String: Any] {
                    projected["payload"] = payload.filter { ["type", "id", "session_id", "model_provider", "turn_id", "response_id", "model", "thread_settings", "forked_from_id", "source", "info", "usage"].contains($0.key) }
                }
                lines.append(String(decoding: try JSONSerialization.data(withJSONObject: projected), as: UTF8.self))
            }
            pending.removeSubrange(..<cursor)
            }
        }
        // Keep the prior snapshot while an active transcript has an unfinished record.
        guard pending.isEmpty else { throw UsageFailure("Transcript writer has an unfinished record.") }
        return lines
    }

let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: path) }
let ignored: [String:Any] = ["type":"event_msg", "payload":["type":"agent_message", "text":String(repeating:"日本語のログ abc def ", count:24)]]
let usage: [String:Any] = ["type":"event_msg", "timestamp":"2026-11-13T00:00:00Z", "payload":["type":"token_count", "info":["last_token_usage":["input_tokens":10,"output_tokens":5]]]]
var ignoredLine=try JSONSerialization.data(withJSONObject:ignored); ignoredLine.append(10)
var usageLine=try JSONSerialization.data(withJSONObject:usage); usageLine.append(10)
var fixture=Data()
for index in 0..<12000 { fixture.append(ignoredLine); if index % 20 == 0 { fixture.append(usageLine) } }
try fixture.write(to:path)
func canonical(_ lines:[String]) throws -> Data {
 var result=Data()
 for line in lines { let object=try JSONSerialization.jsonObject(with:Data(line.utf8));result.append(try JSONSerialization.data(withJSONObject:object,options:.sortedKeys));result.append(10) }
 return result
}
let expected=try autoreleasepool { try canonical(readBefore(path:path.path,provider:"codex")) }
let actual=try autoreleasepool { try canonical(readAfter(path:path.path,provider:"codex")) }
precondition(actual == expected)
var samples:[String:[Double]]=["before":[],"after":[]]
var counts:[String:Int]=[:]
for _ in 0..<5 {
 for variant in ["before","after"] {
  try autoreleasepool {
   let start=DispatchTime.now().uptimeNanoseconds
   let result=try variant == "before" ? readBefore(path:path.path,provider:"codex") : readAfter(path:path.path,provider:"codex")
   let milliseconds=Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
   precondition(result.count == 600)
   let canonicalResult=try canonical(result)
   precondition(canonicalResult == expected)
   samples[variant]!.append(milliseconds);counts[variant]=result.count
  }
 }
}
let output:[String:Any]=["fixtureBytes":fixture.count,"inputLines":12600,"outputLines":counts,"milliseconds":samples,"errors":0,"equivalentCanonicalOutput":true]
print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
