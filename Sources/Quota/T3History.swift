import Foundation

actor T3History {
    private var files: [String: [String: Any]] = [:]
    private let source: T3Source
    private var latest: Date?
    private var engine: T3Engine?
    private var cacheSignature: String?
    private var bundledRates: [String: Any]?
    init(source: T3Source) { self.source = source }
    func summary(days: Int, provider: String? = nil, scan: Bool = false) throws -> (T3Summary, Date?, [String]) {
        let engine = try self.engine ?? T3Engine()
        self.engine = engine
        var notices: [String] = []
        let root = source.directory
        let candidates = (4...15).reversed().map { "usage-scan-cache-v\($0).json" } + ["usage-scan-cache.json"]
        if (scan || files.isEmpty), let name = candidates.first(where: { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) {
            let url = root.appendingPathComponent(name)
            let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let signature = "\(url.path):\(attributes.contentModificationDate?.timeIntervalSince1970 ?? 0):\(attributes.fileSize ?? 0)"
            if signature != cacheSignature {
                let decoded = try engine.call("loadHistoryCacheJSON", json: Data(contentsOf: url))
                guard let list = try JSONSerialization.jsonObject(with: decoded) as? [[String: Any]] else { throw UsageFailure("T3 history could not be decoded.") }
                for file in list {
                    guard let path = file["path"] as? String else { continue }
                    files[path] = file
                }
                cacheSignature = signature
            }
            latest = attributes.contentModificationDate
        }
        if scan {
            let cutoff = Date().addingTimeInterval(-Double(days + 2) * 86400).timeIntervalSince1970 * 1000
            let userHome = source.homeDirectory
            var roots: [(String, URL)] = [("codex", userHome.appendingPathComponent(".codex/sessions")), ("codex", userHome.appendingPathComponent(".codex/archived_sessions")), ("claude", userHome.appendingPathComponent(".claude/projects"))]
            for account in source.accounts() {
                if let home = account.home, [T3Provider.codex, .claude].contains(account.provider) {
                    roots.append((account.provider.rawValue, URL(fileURLWithPath: home).appendingPathComponent(account.provider == .claude ? "projects" : "sessions")))
                }
            }
            for (provider, root) in roots {
                guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
                for case let url as URL in iterator where url.pathExtension == "jsonl" && files[url.path] == nil {
                    guard let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), info.isRegularFile == true,
                          let modified = info.contentModificationDate, modified.timeIntervalSince1970 * 1000 >= cutoff else { continue }
                    files[url.path] = ["path": url.path, "provider": provider, "size": -1, "mtimeMs": 0.0]
                }
            }
            for (path, cached) in files {
                guard let provider = cached["provider"] as? String, ["claude", "codex"].contains(provider),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      let modified = attributes[.modificationDate] as? Date, modified.timeIntervalSince1970 * 1000 >= cutoff,
                      let size = attributes[.size] as? Int else { continue }
                let stamp = modified.timeIntervalSince1970 * 1000
                guard abs(stamp - (cached["mtimeMs"] as? Double ?? 0)) > 1 || size != cached["size"] as? Int else { continue }
                do {
                    let lines = try Self.projectedLines(path: path, provider: provider)
                    _ = try engine.call("updateHistoryTranscriptJSON", object: ["path": path, "provider": provider, "lines": lines, "size": size, "mtimeMs": stamp])
                    files[path] = ["path": path, "provider": provider, "size": size, "mtimeMs": stamp]
                } catch { notices.append("Some current history could not be refreshed; saved T3 records were retained.") }
            }
        }
        let settings = source.settings()
        let ratesURL = root.appendingPathComponent("usage-model-rates.json")
        if bundledRates == nil { bundledRates = QuotaResources.bundle.url(forResource: "ModelRates", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:] }
        let importedRates = (try? Data(contentsOf: ratesURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["document"] as? [String: Any] ?? [:]
        let document = (bundledRates ?? [:]).merging(importedRates) { _, imported in imported }
        let cursorURL = root.appendingPathComponent("usage-cursor-account-cache-v1.json")
        let cursor = (try? Data(contentsOf: cursorURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
        guard !files.isEmpty || !(cursor is NSNull) else { throw UsageFailure("No usage history found on this Mac.") }
        let now = Date(), calendar = Calendar.current
        let start = days == 1 ? now.addingTimeInterval(-86400) : calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_CA"); formatter.dateFormat = "yyyy-MM-dd"
        var input: [String: Any] = ["rates": document, "cursorCache": cursor,
            "settings": ["usagePriceOverrides": settings["usagePriceOverrides"] ?? [:], "usageModelAliases": settings["usageModelAliases"] ?? [:], "usageModelFilter": settings["usageModelFilter"] ?? NSNull()],
            "timeZone": TimeZone.current.identifier, "sinceDay": formatter.string(from: start), "untilDay": formatter.string(from: now), "now": now.timeIntervalSince1970 * 1000]
        if days == 1 { input["sinceTimeMs"] = start.timeIntervalSince1970 * 1000 }
        if let provider { input["provider"] = provider }
        let data = try engine.call("summaryJSON", object: input)
        return (try JSONDecoder().decode(T3Summary.self, from: data), latest ?? Date(), Array(Set(notices)))
    }
    nonisolated static func projectedLines(path: String, provider: String) throws -> [String] {
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
}
