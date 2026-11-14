import XCTest
import AppKit
import SwiftUI
@testable import Quota

final class T3Tests: XCTestCase {
    func call(_ name: String, _ object: [String: Any]) throws -> Any {
        let data = try T3Engine().call(name, object: object)
        return try JSONSerialization.jsonObject(with: data)
    }
    func testSourcePoolKeepsCursorModelsAndHidesOverall() throws {
        let limits = try T3LimitReader.cursor(["planUsage": ["autoPercentUsed": 3.011, "apiPercentUsed": 99.955, "totalPercentUsed": 11.824], "billingCycleEnd": "1796291532000"])
        let account = T3LimitAccount(key: "cursor", driver: "cursor", displayName: "Cursor", limits: limits)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode([account]))
        let data = try T3Engine().call("poolJSON", object: ["accounts": object, "now": 1794600000000.0])
        let pools = try JSONDecoder().decode([T3Pool].self, from: data)
        XCTAssertEqual(pools.count, 1)
        XCTAssertEqual(pools[0].windows.count, 2)
        XCTAssertEqual(pools[0].windows.map(\.remaining), [97, 0])
        XCTAssertEqual(pools[0].windows.map(\.label), ["Cursor Models", "Other Models"])
        XCTAssertEqual(T3Date.parse(limits.windows[0].resetsAt)?.timeIntervalSince1970, 1796291532)
    }
    func testClaudeNullSessionAndModelScopedWeekly() throws {
        let data = try JSONSerialization.data(withJSONObject: ["rate_limits_available": true, "rate_limits": ["five_hour": NSNull(), "seven_day": ["utilization": 17, "resets_at": "2026-11-19T18:59:59.873433+00:00"], "model_scoped": [["display_name": "Fable", "utilization": 24]]]])
        let limits = try T3LimitReader.claude(data)
        XCTAssertEqual(limits.windows.map(\.usedPercent), [17, 24])
        XCTAssertEqual(limits.windows.map(\.label), ["Weekly", "Weekly · Fable"])
        XCTAssertNotNil(T3Date.parse(limits.windows[0].resetsAt))
        XCTAssertNil(limits.windows[1].resetsAt)
    }
    func testActualClaudeParserSkipsSyntheticAndPreservesDedupe() throws {
        let record: [String: Any] = ["type": "assistant", "timestamp": "2026-11-13T00:00:00Z", "sessionId": "session", "requestId": "request", "message": ["id": "message", "model": "claude-test", "usage": ["input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 200]]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: record), as: UTF8.self)
        let result = try XCTUnwrap(try call("parseTranscriptJSON", ["provider": "claude", "lines": [line, line.replacingOccurrences(of: "claude-test", with: "<synthetic>"), "broken"]]) as? [[String: Any]])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0]["dedupeKey"] as? String, "message:request")
        XCTAssertEqual((result[0]["totals"] as? [String: Any])?["cachedInputTokens"] as? Int, 200)
    }
    func testActualAggregatorDedupesAndDoesNotAddReasoningTwice() throws {
        let totals: [String: Any] = ["uncachedInputTokens": 100, "cachedInputTokens": 200, "cacheCreationTokens": 0, "outputTokens": 50, "reasoningTokens": 20]
        let record: [String: Any] = ["provider": "codex", "timestampMs": 1794528000000.0, "model": "test", "sessionId": "session", "totals": totals, "reportedCostUsd": 0.25, "speed": "standard", "dedupeKey": "same"]
        var input: [String: Any] = ["files": [["records": [record, record]]], "rates": [:], "settings": ["usageModelFilter": NSNull()], "timeZone": "UTC", "sinceDay": "2026-11-13", "untilDay": "2026-11-13", "now": 1794560000000.0]
        let result = try XCTUnwrap(try call("summaryJSON", input) as? [String: Any])
        XCTAssertEqual(result["totalTokens"] as? Int, 350)
        XCTAssertEqual(result["costUsd"] as? Double, 0.25)
        XCTAssertEqual(result["records"] as? Int, 1)
        input["provider"] = "claude"
        let filtered = try XCTUnwrap(try call("summaryJSON", input) as? [String: Any])
        XCTAssertEqual(filtered["totalTokens"] as? Int, 0)
    }
    func testUnpricedUsageAndHourWindowRemainHonest() throws {
        let record: [String: Any] = ["provider": "claude", "timestampMs": 1794528000000.0, "model": "unknown", "sessionId": "s", "totals": ["uncachedInputTokens": 5, "cachedInputTokens": 0, "cacheCreationTokens": 0, "outputTokens": 2, "reasoningTokens": 0], "reportedCostUsd": NSNull(), "speed": "standard", "dedupeKey": NSNull()]
        var input: [String: Any] = ["files": [["records": [record]]], "rates": [:], "timeZone": "UTC", "sinceDay": "2026-11-13", "untilDay": "2026-11-13", "now": 1794560000000.0]
        let result = try XCTUnwrap(try call("summaryJSON", input) as? [String: Any])
        XCTAssertEqual((result["costQuality"] as? [String: Any])?["unpricedShare"] as? Double, 1)
        input["sinceTimeMs"] = 1794528000001.0
        let filtered = try XCTUnwrap(try call("summaryJSON", input) as? [String: Any])
        XCTAssertEqual(filtered["totalTokens"] as? Int, 0)
    }
    func testCacheDecoderRejectsCorruptFileAndPreservesUnknownCost() throws {
        let row: [Any] = [1794528000000.0, 0, 0, 100, 20, 0, 50, 10, "key", NSNull(), 0]
        let result = try XCTUnwrap(try call("decodeCacheJSON", ["version": 11, "models": ["test"], "sessions": ["session"], "files": ["path": ["p": "codex", "s": 300, "m": 1794528000000.0, "r": [row], "t": []]]]) as? [[String: Any]])
        XCTAssertEqual(result.count, 1)
        let records = try XCTUnwrap(result[0]["records"] as? [[String: Any]])
        XCTAssertTrue(records[0]["reportedCostUsd"] is NSNull)
        XCTAssertThrowsError(try call("decodeCacheJSON", ["version": 99, "models": [], "sessions": []]))
    }
    func testActualCodexParserUsesSessionModelAndRejectsInvalidCounts() throws {
        func line(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
        let meta = try line(["type": "session_meta", "timestamp": "2026-11-13T00:00:00Z", "payload": ["id": "session"]])
        let context = try line(["type": "turn_context", "timestamp": "2026-11-13T00:00:01Z", "payload": ["model": "gpt-test"]])
        let event = try line(["type": "event_msg", "timestamp": "2026-11-13T00:00:02Z", "payload": ["type": "token_count", "info": ["last_token_usage": ["input_tokens": 100, "cached_input_tokens": 40, "output_tokens": 20, "reasoning_output_tokens": 5]]]])
        let result = try XCTUnwrap(try call("parseTranscriptJSON", ["provider": "codex", "lines": [meta, context, event, event]]) as? [[String: Any]])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0]["model"] as? String, "gpt-test")
        XCTAssertEqual(result[0]["sessionId"] as? String, "session")
        XCTAssertEqual((result[0]["totals"] as? [String: Any])?["uncachedInputTokens"] as? Int, 60)
    }
    func testT3AccountEnvironmentArrayAndProtectedReference() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let object: [String: Any] = ["providerInstances": ["work": ["driver": "codex", "environment": [["name": "CODEX_HOME", "value": "/tmp/account", "sensitive": false]], "config": ["binaryPath": "/tmp/codex", "customModels": []]], "private": ["driver": "claudeAgent", "environment": [["name": "TOKEN", "value": "", "secret": ["id": "secret"]]]]]]
        try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent("settings.json"))
        let accounts = T3Source(directory: directory).accounts()
        let work = try XCTUnwrap(accounts.first { $0.id == "work" })
        XCTAssertEqual(work.home, "/tmp/account")
        XCTAssertEqual(work.configuration["binaryPath"], "/tmp/codex")
        XCTAssertFalse(work.environmentUnavailable)
        XCTAssertTrue(try XCTUnwrap(accounts.first { $0.id == "private" }).environmentUnavailable)
        XCTAssertFalse(accounts.contains { $0.id == "codex" })
    }
    func testChangingWindowReusesHistoryUntilExplicitRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("usage-scan-cache-v11.json")
        let now = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        let row: [Any] = [now, 0, 0, 2, 0, 0, 1, 0, "key", NSNull(), 0]
        let cache: [String: Any] = ["version": 11, "models": ["test"], "sessions": ["s"], "files": ["missing-transcript": ["p": "codex", "s": 1, "m": now, "r": [row], "t": []]]]
        try JSONSerialization.data(withJSONObject: cache).write(to: url)
        let history = T3History(source: T3Source(directory: directory))
        let first = try await history.summary(days: 1)
        XCTAssertEqual(first.0.totalTokens, 3)
        try Data("{}".utf8).write(to: url)
        let next = try await history.summary(days: 7)
        XCTAssertEqual(next.0.totalTokens, 3)
        do { _ = try await history.summary(days: 7, scan: true); XCTFail("Refresh must read and validate the changed source") }
        catch { XCTAssertTrue(error is UsageFailure) }
    }
    @MainActor func testMetricChangeRedrawsNativeNumbers() async throws {
        _ = NSApplication.shared
        let store = T3Store(source: T3Source(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        store.summary = T3Summary(costUsd: 12.34, totalTokens: 1234567, records: 1, sessions: 1, providers: [], models: [], costQuality: T3CostQuality(providerReportedShare: 1, modelPricedShare: 0, unpricedShare: 0, cacheSavingsUsd: 0))
        store.metric = .cost
        let host = NSHostingView(rootView: PanelView(store: store, close: {}))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 360), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        func capture() throws -> Data {
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded(); window.display()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let numberArea = try XCTUnwrap(bitmap.cgImage?.cropping(to: CGRect(x: 14 * scale, y: 75 * scale, width: 260 * scale, height: 45 * scale)))
            return try XCTUnwrap(NSBitmapImageRep(cgImage: numberArea).representation(using: .png, properties: [:]))
        }
        let cost = try capture()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/quota-metric-style.png"))
        }
        let control = MetricControl(frame: NSRect(x: 0, y: 0, width: 174, height: 28))
        control.onSelection = { store.metric = $0 }
        control.selectedSegment = 1
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
        XCTAssertEqual(store.metric, .tokens)
        XCTAssertEqual(control.focusRingType, .none)
        try await Task.sleep(for: .milliseconds(50))
        let tokens = try capture()
        XCTAssertNotEqual(cost, tokens, "Native toggle action must redraw the number region, not only the selection")
        control.selectedSegment = 0
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
        XCTAssertEqual(store.metric, .cost)
        control.selectedSegment = 2
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
        XCTAssertEqual(store.metric, .limits)
    }
    func testTranscriptReaderHandlesChunkBoundariesUnicodeAndPartialWrites() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let record: [String: Any] = ["type": "assistant", "timestamp": "2026-11-13T00:00:00Z", "sessionId": "s", "message": ["id": "m", "model": "test", "content": "private content must not enter usage", "usage": ["input_tokens": 7, "output_tokens": 3]]]
        let data = try JSONSerialization.data(withJSONObject: record)
        var input = Data((String(repeating: "日", count: 349520) + "\n").utf8)
        input.append(data); input.append(10)
        input.append(Data("{broken \"usage\"}\n".utf8))
        input.append(Data([0xff, 0x22, 0x75, 0x73, 0x61, 0x67, 0x65, 0x22, 10]))
        try input.write(to: url)
        let lines = try T3History.projectedLines(path: url.path, provider: "claude")
        XCTAssertEqual(lines.count, 1)
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertNil((parsed["message"] as? [String: Any])?["content"])
        let records = try XCTUnwrap(try call("parseTranscriptJSON", ["provider": "claude", "lines": lines]) as? [[String: Any]])
        XCTAssertEqual((records[0]["totals"] as? [String: Any])?["uncachedInputTokens"] as? Int, 7)
        input.append(data.prefix(20)); try input.write(to: url)
        XCTAssertThrowsError(try T3History.projectedLines(path: url.path, provider: "claude"))
    }
    func testHistoryEngineReturnsMetadataAndPreservesNewerLocalRecords() throws {
        let engine = try T3Engine()
        let row: [Any] = [1794528000000.0, 0, 0, 2, 0, 0, 1, 0, "key", NSNull(), 0]
        let cache: [String: Any] = ["version": 11, "models": ["test"], "sessions": ["s"], "files": ["path": ["p": "codex", "s": 1, "m": 1, "r": [row], "t": []]]]
        let metadata = try engine.call("loadHistoryCacheJSON", object: cache)
        let files = try XCTUnwrap(try JSONSerialization.jsonObject(with: metadata) as? [[String: Any]])
        XCTAssertNil(files[0]["records"], "Usage records must stay in the engine instead of being copied into Swift")
        let query: [String: Any] = ["rates": [:], "timeZone": "UTC", "sinceDay": "2026-11-13", "untilDay": "2026-11-13", "now": 1794560000000.0]
        func total(_ engine: T3Engine) throws -> Double { try JSONDecoder().decode(T3Summary.self, from: engine.call("summaryJSON", object: query)).totalTokens }
        XCTAssertEqual(try total(engine), 3)
        let line: [String: Any] = ["type": "assistant", "timestamp": "2026-11-13T00:00:00Z", "sessionId": "s", "message": ["id": "m", "model": "test", "usage": ["input_tokens": 7, "output_tokens": 3]]]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: line), as: UTF8.self)
        _ = try engine.call("updateHistoryTranscriptJSON", object: ["path": "path", "provider": "claude", "size": 2, "mtimeMs": 2, "lines": [text]])
        XCTAssertEqual(try total(engine), 10)
        _ = try engine.call("loadHistoryCacheJSON", object: cache)
        XCTAssertEqual(try total(engine), 10, "An older disk cache must not replace freshly parsed records")
        XCTAssertEqual(try total(engine), 10, "Repeated summaries must not mutate or double-count cached records")
        XCTAssertEqual(try total(T3Engine()), 0, "History must remain private to its engine")
    }
    @MainActor func testAllotCurveKeepsItsPeakShelfAndMenuBarTemplate() {
        let path = AllotMark.path(in: NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(path.contains(NSPoint(x: 56, y: 65)), "Graph peak remains filled")
        XCTAssertTrue(path.contains(NSPoint(x: 90, y: 48)), "Flat shelf remains filled")
        XCTAssertTrue(path.contains(NSPoint(x: 12, y: 31)))
        XCTAssertFalse(path.contains(NSPoint(x: 50, y: 18)), "Space beneath the curve stays open")
        XCTAssertFalse(path.contains(NSPoint(x: 10, y: 75)))
        XCTAssertFalse(path.contains(NSPoint(x: -1, y: 50)))
        let menu = AllotMark.menuBarImage()
        XCTAssertTrue(menu.isTemplate)
        XCTAssertEqual(menu.size, NSSize(width: 18, height: 18))
    }
    func testTokenFormattingCarriesAndUnknownResetStaysAbsent() {
        XCTAssertEqual(T3Format.tokens(999999), "1M")
        XCTAssertEqual(T3Format.tokens(0), "0")
        XCTAssertNil(T3Format.reset(nil, now: Date()))
        XCTAssertNil(T3Format.reset("invalid", now: Date()))
    }
}
