import Foundation
import CryptoKit

struct T3Source: Sendable {
    var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3/userdata")
    func settings() -> [String: Any] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("settings.json")), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
    func accounts() -> [T3Account] {
        let settings = settings()
        let instances = settings["providerInstances"] as? [String: [String: Any]] ?? [:]
        var result: [T3Account] = []
        for (id, value) in instances.sorted(by: { $0.key < $1.key }) {
            guard value["enabled"] as? Bool != false, let driver = value["driver"] as? String, let provider = T3Provider.from(driver: driver) else { continue }
            let config = (value["config"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            var environment = value["environment"] as? [String: String] ?? [:]
            let variables = value["environment"] as? [[String: Any]] ?? []
            for variable in variables {
                if let name = variable["name"] as? String, let text = variable["value"] as? String { environment[name] = text }
            }
            let unavailable = variables.contains { $0["secret"] != nil || $0["valueRedacted"] as? Bool == true }
            let home = environment[provider == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"]
            result.append(T3Account(id: id, provider: provider, name: value["displayName"] as? String ?? provider.label, home: home, environment: environment, environmentUnavailable: unavailable, configuration: config))
        }
        for (provider, executable) in [(T3Provider.codex, "codex"), (.claude, "claude"), (.grok, "grok")] {
            if !instances.values.contains(where: { $0["driver"] as? String == provider.driver }), Command.executable(executable) != nil {
                result.append(T3Account(id: provider.driver, provider: provider, name: provider.label))
            }
        }
        return result
    }
    func cursorKey(instance: String) throws -> String {
        let hash = SHA256.hash(data: Data("6:cursor\(instance)".utf8)).map { String(format: "%02x", $0) }.joined()
        let path = directory.appendingPathComponent("secrets/provider-auth-\(hash).bin")
        guard let data = try? Data(contentsOf: path),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], value["version"] as? Int == 1,
              let key = value["apiKey"] as? String, !key.isEmpty else { throw UsageFailure("Cursor is not signed in to T3 Code.") }
        if let expiry = value["apiKeyExpiresAtMs"] as? Double, expiry <= Date().timeIntervalSince1970 * 1000 { throw UsageFailure("Cursor sign-in expired. Reconnect Cursor in T3 Code.") }
        return key
    }
}

private final class T3NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum T3HTTP {
    static func json(_ url: URL, token: String, post: Bool = false) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if post {
            request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
            request.setValue("cli", forHTTPHeaderField: "x-cursor-client-type")
        }
        let session = URLSession(configuration: .ephemeral, delegate: T3NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count < 8_000_000,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageFailure("Provider could not read usage.") }
        return body
    }
}

/// Swift transport port of T3's usage-only Claude capabilities probe: no user message is sent.
enum T3ClaudeProbe {
    static func run(account: T3Account) async throws -> Data {
        try await Task.detached(priority: .utility) {
            guard let binary = account.configuration["binaryPath"].flatMap({ $0.isEmpty ? nil : $0 }) ?? Command.executable("claude") else { throw UsageFailure("Claude Code is not installed.") }
            let process = Process(), input = Pipe(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--no-session-persistence", "--allowedTools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--settings", "{\"disableAllHooks\":true}"]
            process.environment = ProcessInfo.processInfo.environment.merging(account.environment) { _, value in value }.merging(["ENABLE_CLAUDEAI_MCP_SERVERS": "false", "CLAUDE_CODE_AUTO_CONNECT_IDE": "0", "CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL": "1"]) { _, value in value }
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: deadline)
            defer { deadline.cancel(); if process.isRunning { process.terminate() }; try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
            func send(_ id: String, _ request: [String: Any]) throws {
                var data = try JSONSerialization.data(withJSONObject: ["type": "control_request", "request_id": id, "request": request]); data.append(10)
                try input.fileHandleForWriting.write(contentsOf: data)
            }
            try send("initialize", ["subtype": "initialize", "hooks": [:], "sdkMcpServers": []])
            var line = Data()
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                for byte in chunk {
                    if byte == 10 {
                        defer { line.removeAll(keepingCapacity: true) }
                        guard let envelope = try? JSONSerialization.jsonObject(with: line) as? [String: Any], envelope["type"] as? String == "control_response", let response = envelope["response"] as? [String: Any], response["subtype"] as? String == "success" else { continue }
                        if response["request_id"] as? String == "initialize" { try send("usage", ["subtype": "get_usage", "skip_behaviors": true]) }
                        if response["request_id"] as? String == "usage", let result = response["response"] as? [String: Any] { return try JSONSerialization.data(withJSONObject: result) }
                    } else { line.append(byte) }
                    guard line.count < 8_000_000 else { throw UsageFailure("Claude usage response was too large.") }
                }
            }
            throw UsageFailure("Claude could not read usage limits.")
        }.value
    }
}

struct T3LimitReader: Sendable {
    let source: T3Source
    func fetch(_ account: T3Account) async throws -> T3LimitAccount {
        guard !account.environmentUnavailable else { throw UsageFailure("This T3 account uses protected environment references; quota access is unavailable.") }
        let limits: T3Limits
        switch account.provider {
        case .codex:
            guard let binary = account.configuration["binaryPath"].flatMap({ $0.isEmpty ? nil : (Command.executable($0) ?? (FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil)) }) ?? Command.executable("codex") else { throw UsageFailure("Codex is not installed.") }
            let lines = ["{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"ration\",\"version\":\"2.0\"}}}", "{\"method\":\"initialized\"}", "{\"id\":2,\"method\":\"account/rateLimits/read\"}"].joined(separator: "\n") + "\n"
            let data = try await Command.run(binary, ["app-server"], input: lines, environment: account.environment, responseID: 2)
            limits = try Self.codex(data)
        case .claude: limits = try Self.claude(await T3ClaudeProbe.run(account: account))
        case .cursor:
            let apiKey = try source.cursorKey(instance: account.id)
            let exchanged = try await T3HTTP.json(URL(string: "https://api2.cursor.sh/auth/exchange_user_api_key")!, token: apiKey, post: true)
            guard let access = exchanged["accessToken"] as? String else { throw UsageFailure("Cursor sign-in could not be exchanged.") }
            let body = try await T3HTTP.json(URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!, token: access, post: true)
            limits = try Self.cursor(body)
        case .opencode: limits = try await openCode(account)
        default: throw UsageFailure("This account has no subscription limits.")
        }
        return T3LimitAccount(key: account.id, driver: account.provider.driver, displayName: account.name, limits: limits)
    }
    static func clamp(_ percent: Double) -> Double { min(100, max(0, percent)) }
    static func codex(_ data: Data) throws -> T3Limits {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = envelope["result"] as? [String: Any], let snapshot = result["rateLimits"] as? [String: Any] else { throw UsageFailure("Codex could not read usage limits.") }
        var windows: [T3Window] = []
        let monthly = ["free", "go"].contains(snapshot["planType"] as? String ?? "")
        for (id, fallback) in [("primary", monthly ? 43200 : 300), ("secondary", 10080)] {
            guard let window = snapshot[id] as? [String: Any], let used = window["usedPercent"] as? Double, used.isFinite else { continue }
            let duration = window["windowDurationMins"] as? Int ?? fallback
            let kind = duration >= 43200 ? "monthly" : duration >= 10080 ? "weekly" : "session"
            let label = kind == "monthly" ? "Monthly" : kind == "weekly" ? "Weekly" : "Session"
            let reset = (window["resetsAt"] as? Double).flatMap { $0 > 0 ? T3Date.iso(Date(timeIntervalSince1970: $0)) : nil }
            windows.append(T3Window(id: id, kind: kind, label: label, usedPercent: clamp(used), resetsAt: reset, windowDurationMins: duration))
        }
        if let member = snapshot["individualLimit"] as? [String: Any], let remaining = member["remainingPercent"] as? Double {
            windows.append(T3Window(id: "individual", kind: "monthly", label: "Monthly credit limit", usedPercent: clamp(100 - remaining), resetsAt: (member["resetsAt"] as? Double).map { T3Date.iso(Date(timeIntervalSince1970: $0)) }))
        }
        let credits = (result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int
        return T3Limits(checkedAt: T3Date.iso(), windows: windows, resetCredits: credits.map { T3Credits(availableCount: max(0, $0)) })
    }
    static func claude(_ data: Data) throws -> T3Limits {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any], body["rate_limits_available"] as? Bool == true, let rates = body["rate_limits"] as? [String: Any] else { throw UsageFailure("Claude could not read usage limits.") }
        var windows: [T3Window] = []
        for (id, kind, label, duration) in [("five_hour", "session", "Session", 300), ("seven_day", "weekly", "Weekly", 10080)] {
            guard let row = rates[id] as? [String: Any], let used = row["utilization"] as? Double, used.isFinite else { continue }
            windows.append(T3Window(id: id, kind: kind, label: label, usedPercent: clamp(used), resetsAt: row["resets_at"] as? String, windowDurationMins: duration))
        }
        for row in rates["model_scoped"] as? [[String: Any]] ?? [] {
            guard let name = row["display_name"] as? String, let used = row["utilization"] as? Double, used.isFinite else { continue }
            let id = "seven_day_" + name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            windows.append(T3Window(id: id, kind: "weekly", label: "Weekly · " + name, usedPercent: clamp(used), resetsAt: row["resets_at"] as? String, windowDurationMins: 10080))
        }
        if let spend = rates["spend"] as? [String: Any], spend["enabled"] as? Bool == true,
           let used = spend["used"] as? [String: Any], let limit = spend["limit"] as? [String: Any],
           let a = used["amount_minor"] as? Double, let b = limit["amount_minor"] as? Double, a >= 0, b > 0,
           used["currency"] as? String == limit["currency"] as? String, used["exponent"] as? Int == limit["exponent"] as? Int {
            windows.append(T3Window(id: "monthly_spend", kind: "monthly", label: "Monthly spend", usedPercent: clamp(a / b * 100)))
        }
        return T3Limits(checkedAt: T3Date.iso(), windows: windows)
    }
    static func cursor(_ body: [String: Any]) throws -> T3Limits {
        guard let plan = body["planUsage"] as? [String: Any] else { throw UsageFailure("Cursor could not read usage limits.") }
        func number(_ key: String) -> Double? { (body[key] as? Double) ?? (body[key] as? String).flatMap(Double.init) }
        let end = number("billingCycleEnd"), start = number("billingCycleStart")
        let reset = end.flatMap { $0 > 0 ? T3Date.iso(Date(timeIntervalSince1970: $0 / 1000)) : nil }
        let duration = end.flatMap { end in start.flatMap { start in end > start && start > 0 ? Int(((end - start) / 60000).rounded()) : nil } }
        let names = [("totalPercentUsed", "Overall"), ("autoPercentUsed", "Cursor Models"), ("apiPercentUsed", "Other Models")]
        let windows = names.compactMap { id, label -> T3Window? in
            guard let used = plan[id] as? Double, used.isFinite else { return nil }
            return T3Window(id: id, kind: "monthly", label: label, usedPercent: clamp(used), resetsAt: reset, windowDurationMins: duration)
        }
        return T3Limits(checkedAt: T3Date.iso(), windows: windows)
    }
    private func openCode(_ account: T3Account) async throws -> T3Limits {
        if let endpoint = account.configuration["serverUrl"], !endpoint.isEmpty { throw UsageFailure("OpenCode Go could not read usage.") }
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode")
        var keys: [String] = []
        if let data = try? Data(contentsOf: base.appendingPathComponent("auth.json")), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let row = root["opencode-go"] as? [String: Any], row["type"] as? String == "api", let key = row["key"] as? String { keys.append(key) }
        let database = base.appendingPathComponent("opencode.db")
        if FileManager.default.fileExists(atPath: database.path) {
            for integration in ["opencode", "opencode-go"] {
                let query = "SELECT value FROM credential WHERE integration_id = '\(integration)' AND active IS NOT 0 ORDER BY active DESC, time_created DESC, id DESC LIMIT 1"
                if let data = try? await Command.run("/usr/bin/sqlite3", ["-readonly", database.path, query]), let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any], row["type"] as? String == "key", let key = row["key"] as? String { keys.append(key) }
            }
        }
        guard let key = keys.first, !key.isEmpty else { throw UsageFailure("OpenCode Go could not read usage.") }
        let body = try await T3HTTP.json(URL(string: "https://opencode.ai/zen/go/v1/usage")!, token: key)
        guard let usage = body["usage"] as? [String: Any] else { throw UsageFailure("OpenCode Go could not read usage.") }
        let windows = [("rolling", "session", "Session", 300), ("weekly", "weekly", "Weekly", 10080), ("monthly", "monthly", "Monthly", 0)].compactMap { id, kind, label, duration -> T3Window? in
            guard let row = usage[id] as? [String: Any], let percent = row["percent"] as? Double else { return nil }
            return T3Window(id: "go_" + id, kind: kind, label: "Go · " + label, usedPercent: Self.clamp(percent), resetsAt: row["resetsAt"] as? String, windowDurationMins: duration > 0 ? duration : nil)
        }
        return T3Limits(checkedAt: T3Date.iso(), windows: windows)
    }
}
