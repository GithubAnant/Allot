import XCTest
import AppKit
@testable import Quota

final class StandaloneTests: XCTestCase {
    func testThreeClaudeAndThreeCodexAccountsWithoutT3() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalAccounts(directory: root.appendingPathComponent("Allot"))
        let source = T3Source(directory: root.appendingPathComponent("no-t3"), localAccounts: local, cursorDatabase: root.appendingPathComponent("no-cursor"), homeDirectory: root)
        let binary = root.appendingPathComponent("fixture-cli")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // These CLIs return different quotas from each isolated environment, with no network or login.
        let script = #"""
        #!/bin/sh
        if [ "$1" = app-server ]; then
          while IFS= read -r line; do
            case "$line" in
              *account/rateLimits/read*) printf '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":%s,"windowDurationMins":10080}}}}\n' "$FIXTURE_USED" ;;
            esac
          done
        else
          IFS= read -r line
          printf '{"type":"control_response","response":{"subtype":"success","request_id":"initialize","response":{}}}\n'
          IFS= read -r line
          printf '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":true,"rate_limits":{"seven_day":{"utilization":%s}}}}}\n' "$FIXTURE_USED"
        fi
        """#
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        var snapshots: [T3LimitAccount] = []
        var homes = Set<String>()
        for provider in [T3Provider.codex, .claude] {
            for index in 1...3 {
                var account = try local.add(provider: provider, name: "\(provider.label) \(index)")
                homes.insert(try XCTUnwrap(account.home))
                account.configuration["binaryPath"] = binary.path
                account.environment["FIXTURE_USED"] = String(index * 20)
                let result = try await T3LimitReader(source: source).fetch(account)
                XCTAssertEqual(result.limits.windows.first?.usedPercent, Double(index * 20))
                XCTAssertNil(result.limits.windows.first?.resetsAt)
                snapshots.append(result)
            }
        }
        XCTAssertEqual(homes.count, 6)
        for account in source.accounts().filter({ $0.id.hasPrefix("allot-") && $0.provider == .codex }) {
            let config = URL(fileURLWithPath: account.home!).appendingPathComponent("config.toml")
            XCTAssertEqual(try String(contentsOf: config), "cli_auth_credentials_store = \"keyring\"\n")
        }
        XCTAssertEqual(source.accounts().filter { $0.id.hasPrefix("allot-") }.count, 6)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.directory.path))
        let accounts = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshots))
        let data = try T3Engine().call("poolJSON", object: ["accounts": accounts, "now": Date().timeIntervalSince1970 * 1000])
        let pools = try JSONDecoder().decode([T3Pool].self, from: data)
        XCTAssertEqual(pools.count, 2)
        for pool in pools {
            let window = try XCTUnwrap(pool.windows.first)
            XCTAssertEqual(window.remaining, 60)
            XCTAssertEqual(Set(window.segments.compactMap { $0?.remaining }), [80, 60, 40])
            XCTAssertEqual(Set(window.segments.compactMap { $0?.name }).count, 3)
        }
        let first = try XCTUnwrap(source.accounts().first { $0.id.hasPrefix("allot-") })
        try local.remove(first)
        XCTAssertFalse(source.accounts().contains { $0.id == first.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.home!))
        XCTAssertEqual(try local.load().accounts.count, 5)
    }
    func testCursorSafeStorageDecryptionAndUnknownFormats() throws {
        let hex = "763130acad4e51485fdc0aebc576149c0b4d2b8201ae3d0e8cb3486ac54fd73c1eefb8"
        let bytes = stride(from: 0, to: hex.count, by: 2).map { index -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: index)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        XCTAssertEqual(try CursorCredentials.decrypt(Data(bytes), password: Data("fixture-key".utf8)), "header.payload.signature")
        XCTAssertThrowsError(try CursorCredentials.decrypt(Data(bytes), password: Data("wrong".utf8)))
        XCTAssertThrowsError(try CursorCredentials.decrypt(Data("v99unsupported".utf8), password: Data()))
        XCTAssertThrowsError(try CursorCredentials.decrypt(Data("v10short".utf8), password: Data()))
    }
    func testAccountFileValidationAndAtomicPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalAccounts(directory: root)
        XCTAssertThrowsError(try local.add(provider: .cursor, name: "Unsupported"))
        XCTAssertThrowsError(try local.add(provider: .claude, name: "  "))
        let account = try local.add(provider: .claude, name: "Work ' $(echo nope)")
        XCTAssertEqual(try local.load().accounts.first?.name, account.name)
        XCTAssertTrue(account.home!.hasPrefix(root.path))
        XCTAssertFalse(account.home!.contains("echo"))
        let file = root.appendingPathComponent("accounts.json")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        try Data("broken".utf8).write(to: file)
        XCTAssertThrowsError(try local.add(provider: .codex, name: "Personal"))
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8))
    }
    func testLanguageMatchingFallbackAndCompleteFormatPlaceholders() throws {
        let expected = ["en": "Limits", "es": "Límites", "fr": "Limites", "de": "Limits", "hi": "सीमाएँ", "ja": "上限", "zh-Hans": "限额"]
        let english = L.languageBundle(preferences: ["en"])
        let englishFile = try XCTUnwrap(english.url(forResource: "Localizable", withExtension: "strings"))
        let entries = try XCTUnwrap(NSDictionary(contentsOf: englishFile) as? [String: String])
        let pattern = try NSRegularExpression(pattern: "%[@d]")
        func placeholders(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
        }
        for (language, title) in expected {
            let bundle = L.languageBundle(preferences: [language])
            XCTAssertEqual(bundle.localizedString(forKey: "Limits", value: nil, table: nil), title)
            let table = try XCTUnwrap(NSDictionary(contentsOf: bundle.url(forResource: "Localizable", withExtension: "strings")!) as? [String: String])
            XCTAssertEqual(Set(table.keys), Set(entries.keys))
            for (key, value) in table { XCTAssertEqual(placeholders(value), placeholders(key), "\(language): \(key)") }
        }
        XCTAssertEqual(L.languageBundle(preferences: ["es-MX"]).localizedString(forKey: "Quit", value: nil, table: nil), "Salir")
        XCTAssertEqual(L.languageBundle(preferences: ["xx-YY"]).localizedString(forKey: "Quit", value: nil, table: nil), "Quit")
        XCTAssertEqual(L.window("Weekly · Fable"), L.text("Weekly") + " · Fable")
    }
    func testLocalHistoryAndPricingWithNoT3Installation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalAccounts(directory: root.appendingPathComponent("Allot"))
        let account = try local.add(provider: .claude, name: "Personal")
        let projects = URL(fileURLWithPath: account.home!).appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let record: [String: Any] = ["type": "assistant", "timestamp": T3Date.iso(), "sessionId": "standalone", "requestId": "standalone", "message": ["id": "standalone", "model": "claude-sonnet-4-5", "usage": ["input_tokens": 100, "output_tokens": 50]]]
        var data = try JSONSerialization.data(withJSONObject: record); data.append(10)
        try data.write(to: projects.appendingPathComponent("session.jsonl"))
        let source = T3Source(directory: root.appendingPathComponent("missing-t3"), localAccounts: local, cursorDatabase: root.appendingPathComponent("no-cursor"), homeDirectory: root)
        let summary = try await T3History(source: source).summary(days: 30, scan: true)
        XCTAssertTrue(summary.0.models.contains { $0.model == "claude-sonnet-4-5" && $0.costUsd > 0 && $0.totalTokens >= 150 })
        XCTAssertNotNil(summary.1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.directory.path))
    }
}
