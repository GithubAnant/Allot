import Foundation

enum T3Provider: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex, claude, cursor, grok, opencode, antigravity, pi, muse
    var id: String { rawValue }
    var driver: String { self == .claude ? "claudeAgent" : rawValue }
    var label: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .grok: "Grok Build"
        case .opencode: "OpenCode"
        case .antigravity: "Antigravity"
        case .pi: "Pi"
        case .muse: "Muse Code"
        }
    }
    static func from(driver: String) -> T3Provider? { driver == "claudeAgent" ? .claude : T3Provider(rawValue: driver) }
}
enum T3Metric: String, CaseIterable, Identifiable { case cost = "Cost", tokens = "Tokens", limits = "Limits"; var id: String { rawValue } }
struct T3Account: Identifiable, Sendable {
    var id: String
    var provider: T3Provider
    var name: String
    var home: String?
    var environment: [String: String] = [:]
    var environmentUnavailable = false
    var configuration: [String: String] = [:]
}
struct T3Window: Codable, Sendable {
    var id: String
    var kind: String
    var label: String
    var usedPercent: Double
    var resetsAt: String?
    var windowDurationMins: Int?
}
struct T3Credits: Codable, Sendable { var availableCount: Int }
struct T3Limits: Codable, Sendable {
    var checkedAt: String
    var windows: [T3Window]
    var resetCredits: T3Credits?
}
struct T3LimitAccount: Codable, Sendable {
    var key: String
    var driver: String
    var displayName: String?
    var email: String?
    var plan: String?
    var environments: [T3Environment] = []
    var sourceLabel: String? = nil
    var limits: T3Limits
}
struct T3Environment: Codable, Sendable { var environmentId: String; var label: String }
struct T3Pool: Codable, Identifiable, Sendable {
    var driver: String
    var windows: [T3PoolWindow]
    var id: String { driver }
}
struct T3PoolWindow: Codable, Identifiable, Sendable {
    var id: String
    var label: String
    var description: String?
    var remaining: Double
    var pace: String?
    var segments: [T3Segment?]
}
struct T3Segment: Codable, Sendable {
    var key: String
    var name: String
    var remaining: Double
    var used: Double
    var pace: Double?
    var reset: String?
    var resetLabel: String?
    var refill: Double
    var credits: Int
}
struct T3TokenTotals: Codable, Sendable {
    var uncachedInputTokens: Double
    var cachedInputTokens: Double
    var cacheCreationTokens: Double
    var outputTokens: Double
    var reasoningTokens: Double
}
struct T3ProviderTotals: Codable, Identifiable, Sendable {
    var provider: String
    var costUsd: Double
    var totalTokens: Double
    var records: Int
    var sessions: Int
    var costShare: Double
    var tokenShare: Double
    var id: String { provider }
}
struct T3ModelTotals: Codable, Identifiable, Sendable {
    var model: String
    var provider: String
    var costUsd: Double
    var totalTokens: Double
    var unpricedRecords: Int
    var records: Int
    var id: String { provider + ":" + model }
}
struct T3CostQuality: Codable, Sendable {
    var providerReportedShare: Double
    var modelPricedShare: Double
    var unpricedShare: Double
    var cacheSavingsUsd: Double
}
struct T3Summary: Codable, Sendable {
    var costUsd: Double
    var totalTokens: Double
    var records: Int
    var sessions: Int
    var providers: [T3ProviderTotals]
    var models: [T3ModelTotals]
    var costQuality: T3CostQuality
}
struct UsageFailure: LocalizedError, Sendable {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
enum T3Date {
    static func iso(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text)
    }
}
enum QuotaResources {
    static var bundle: Bundle {
        Bundle.main.url(forResource: "Quota_Quota", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? .module
    }
}
