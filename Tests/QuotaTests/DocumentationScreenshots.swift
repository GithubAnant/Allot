import XCTest
import AppKit
import SwiftUI
import CoreText
@testable import Quota

final class DocumentationScreenshots: XCTestCase {
    @MainActor func testRenderPublicScreenshots() throws {
        guard let destination = ProcessInfo.processInfo.environment["QUOTA_SCREENSHOT_DIRECTORY"] else {
            throw XCTSkip("Set QUOTA_SCREENSHOT_DIRECTORY to render documentation fixtures.")
        }
        _ = NSApplication.shared
        if let font = QuotaResources.bundle.url(forResource: "Geist-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
        let directory = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = T3Store(source: T3Source(directory: source))
        store.accounts = []; store.limitAccounts = [:]; store.errors = [:]; store.notices = []
        store.historyDate = nil; store.summaryError = nil
        let now = Date()
        func window(_ id: String, _ label: String, _ remaining: Double, _ hours: Double, _ pace: Double, credits: Int = 0, description: String? = nil) -> T3PoolWindow {
            let segment = T3Segment(key: "sample", name: "Example account", remaining: remaining, used: 100 - remaining, pace: pace,
                reset: T3Date.iso(now.addingTimeInterval(hours * 3600 + 30)), resetLabel: nil, refill: 100 - remaining, credits: credits)
            return T3PoolWindow(id: id, label: label, description: description, remaining: remaining, pace: nil, segments: [segment])
        }
        store.pools = [
            T3Pool(driver: "codex", windows: [window("secondary", "Weekly", 86, 151, 81, credits: 2)]),
            T3Pool(driver: "claudeAgent", windows: [window("seven_day", "Weekly", 72, 148, 76), window("seven_day_opus", "Weekly · Opus", 61, 148, 76)]),
            T3Pool(driver: "cursor", windows: [window("autoPercentUsed", "Cursor Models", 93, 477, 69, description: "Grok, Composer, and Auto use this allowance."), window("apiPercentUsed", "Other Models", 0, 477, 69)])
        ]
        let cost = 138.42, tokens = 12_800_000.0
        store.summary = T3Summary(costUsd: cost, totalTokens: tokens, records: 1200, sessions: 45, providers: [
            T3ProviderTotals(provider: "codex", costUsd: 55.4, totalTokens: 4_200_000, records: 400, sessions: 14, costShare: 55.4 / cost, tokenShare: 4_200_000 / tokens),
            T3ProviderTotals(provider: "claude", costUsd: 77.42, totalTokens: 7_900_000, records: 650, sessions: 22, costShare: 77.42 / cost, tokenShare: 7_900_000 / tokens),
            T3ProviderTotals(provider: "cursor", costUsd: 5.6, totalTokens: 700_000, records: 150, sessions: 9, costShare: 5.6 / cost, tokenShare: 700_000 / tokens)
        ], models: [
            T3ModelTotals(model: "gpt-5.1-codex", provider: "codex", costUsd: 55.4, totalTokens: 4_200_000, unpricedRecords: 0, records: 400),
            T3ModelTotals(model: "claude-sonnet-4-5", provider: "claude", costUsd: 64.27, totalTokens: 6_100_000, unpricedRecords: 0, records: 500),
            T3ModelTotals(model: "claude-haiku-4-5", provider: "claude", costUsd: 13.15, totalTokens: 1_800_000, unpricedRecords: 0, records: 150),
            T3ModelTotals(model: "composer-1", provider: "cursor", costUsd: 5.6, totalTokens: 700_000, unpricedRecords: 0, records: 150)
        ], costQuality: T3CostQuality(providerReportedShare: 0.08, modelPricedShare: 0.92, unpricedShare: 0, cacheSavingsUsd: 12.8))
        for metric in T3Metric.allCases {
            store.metric = metric
            let host = NSHostingView(rootView: PanelView(store: store, close: {}))
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded(); window.display()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent(metric.rawValue.lowercased() + ".png"))
        }
    }
}
