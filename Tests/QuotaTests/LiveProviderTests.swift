import XCTest
@testable import Quota

final class LiveProviderTests: XCTestCase {
    private func check(_ provider: T3Provider) async throws {
        guard ProcessInfo.processInfo.environment["ALLOT_LIVE_PROVIDER_TESTS"] == "1" else {
            throw XCTSkip("Opt in to read-only live quota requests with ALLOT_LIVE_PROVIDER_TESTS=1.")
        }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = T3Source(directory: missing)
        guard let account = source.accounts().first(where: { $0.provider == provider }) else { throw XCTSkip("No local \(provider.label) installation available.") }
        let result = try await T3LimitReader(source: source).fetch(account)
        XCTAssertFalse(result.limits.windows.isEmpty)
        XCTAssertTrue(result.limits.windows.allSatisfy { (0...100).contains($0.usedPercent) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        print("Live \(provider.label): quota received without T3.")
    }
    func testCodexWithoutT3() async throws { try await check(.codex) }
    func testClaudeWithoutT3() async throws { try await check(.claude) }
    func testCursorWithoutT3() async throws { try await check(.cursor) }
}
