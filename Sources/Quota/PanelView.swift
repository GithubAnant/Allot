import SwiftUI

extension Color {
    static let panel = Color(red: 9/255, green: 9/255, blue: 9/255)
    static let line = Color(white: 28/255)
    static let muted = Color(white: 0.48)
    static func provider(_ driver: String) -> Color {
        switch driver {
        case "claude", "claudeAgent": Color(red: 217/255, green: 119/255, blue: 87/255)
        case "cursor": Color(white: 139/255)
        case "opencode": Color(red: 91/255, green: 155/255, blue: 189/255)
        case "antigravity": Color(red: 140/255, green: 123/255, blue: 209/255)
        default: Color(white: 0.83)
        }
    }
}
extension Font { static func quota(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Geist-Regular", size: size * 1.1).weight(weight) } }

enum T3Format {
    static func money(_ value: Double) -> String { value.formatted(.currency(code: "USD").locale(Locale.current)) }
    static func tokens(_ value: Double) -> String {
        if value.rounded() < 1000 { return value.rounded().formatted(.number.locale(Locale.current)) }
        var scaled = value / 1000, index = 0
        let suffix = ["K", "M", "B", "T"]
        func trim(_ number: Double) -> String {
            let digits = abs(number) >= 100 ? 0 : abs(number) >= 10 ? 1 : 2
            return number.formatted(.number.locale(Locale.current).grouping(.never).precision(.fractionLength(0...digits)))
        }
        while scaled.rounded() >= 1000 && index < suffix.count - 1 { scaled /= 1000; index += 1 }
        return trim(scaled) + suffix[index]
    }
    static func reset(_ timestamp: String?, now: Date) -> String? {
        guard let reset = T3Date.parse(timestamp) else { return nil }
        let seconds = reset.timeIntervalSince(now)
        if seconds <= 0 { return L.text("resets now") }
        if seconds < 60 { return L.text("Resets momentarily") }
        return "↻ " + L.duration(seconds)
    }
}

struct QuotaButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { inside in
                if inside && isEnabled { NSCursor.pointingHand.set() }
                else { NSCursor.arrow.set() }
            }
    }
}

struct ProviderLogo: View {
    let provider: T3Provider
    var body: some View {
        if let path = QuotaResources.bundle.url(forResource: provider.rawValue, withExtension: "png"), let logo = NSImage(contentsOf: path) {
            Image(nsImage: logo).resizable().renderingMode(.template).scaledToFit()
                .foregroundStyle(provider == .claude ? Color.provider("claude") : Color(white: 0.8))
        } else { Text(String(provider.label.prefix(1))).font(.quota(12)) }
    }
}

struct PanelView: View {
    @Bindable var store: T3Store
    var close: () -> Void
    var manageAccounts: () -> Void = {}
    private var warnings: [(String, String)] {
        store.accounts.compactMap { account in
            guard account.provider != .opencode, let error = store.errors[account.id], error != "This account has no subscription limits.",
                  store.selectedProvider == nil || store.selectedProvider == account.provider else { return nil }
            return (account.name, error)
        }
    }
    private var height: CGFloat {
        if store.metric != .limits {
            let providers = store.summary?.providers.count ?? 3
            let models = min(store.summary?.models.count ?? 0, 8)
            return min(650, max(360, CGFloat(246 + providers * 51 + models * 28)))
        }
        let rows = store.pools.reduce(0) { $0 + $1.windows.reduce(0) { $0 + max(1, $1.segments.compactMap { $0 }.count) } }
        return min(740, max(220, CGFloat(110 + store.pools.count * 35 + rows * 90 + warnings.count * 40)))
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.line).frame(height: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    if store.metric == .limits { limits } else { usage }
                }.padding(.horizontal, 14).padding(.vertical, 14)
            }.frame(maxHeight: .infinity)
            Rectangle().fill(Color.line).frame(height: 0.5)
            footer
        }.frame(width: 400, height: height)
            .background(Color.panel).foregroundStyle(Color(white: 0.79))
            .preferredColorScheme(.dark).font(.quota(11)).buttonStyle(QuotaButtonStyle())
            .focusEffectDisabled()
    }
    private var header: some View {
        HStack(spacing: 9) {
            MetricPicker(selection: $store.metric).frame(width: 210, height: 28)
            Spacer(minLength: 4)
            Button(action: manageAccounts) { Image(systemName: "person.crop.circle").font(.system(size: 12)).frame(width: 22, height: 26) }
                .help(L.text("Accounts")).accessibilityLabel(L.text("Accounts"))
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11)).frame(width: 22, height: 26)
            }.disabled(store.refreshing).opacity(store.refreshing ? 0.35 : 0.8).help(L.text("Refresh usage")).accessibilityLabel(L.text("Refresh usage"))
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 18, height: 26) }.help(L.text("Close")).accessibilityLabel(L.text("Close panel"))
        }.padding(.horizontal, 14).frame(height: 40)
    }
    @ViewBuilder private var limits: some View {
        if store.pools.isEmpty && store.refreshing { Text(L.text("Reading subscription limits…")).foregroundStyle(Color.muted).padding(.vertical, 20) }
        if store.pools.isEmpty && !store.refreshing && warnings.isEmpty { Text(L.text("No limits reported.")).foregroundStyle(Color.muted).padding(.vertical, 20) }
        ForEach(store.pools) { pool in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let provider = T3Provider.from(driver: pool.driver) {
                        ProviderLogo(provider: provider).frame(width: 15, height: 15)
                        Text(provider.label).font(.quota(12, .medium))
                    }
                    Spacer()
                }
                ForEach(pool.windows) { window in LimitWindowRow(window: window, driver: pool.driver) }
            }
        }
        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 10))
                Text(warning.0 + ": " + L.text("Usage unavailable. Check the account sign-in.")).help(warning.1).font(.quota(10)).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(Color(red: 0.98, green: 0.73, blue: 0.15)).padding(.horizontal, 11).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.13, green: 0.085, blue: 0.01), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 0.35, green: 0.24, blue: 0.01), lineWidth: 0.5))
        }
    }
    @ViewBuilder private var usage: some View {
        if let summary = store.summary {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.text(store.metric == .cost ? "Total cost" : "Processed tokens")).font(.quota(11)).foregroundStyle(Color.muted)
                    Text(store.metric == .cost ? (summary.costQuality.unpricedShare >= 1 && summary.records > 0 ? L.text("Unpriced") : T3Format.money(summary.costUsd)) : T3Format.tokens(summary.totalTokens)).font(.quota(29, .medium)).monospacedDigit()
                    Text(L.text("Last %d days", store.days) + (store.metric == .cost ? " · " + L.text("API estimate") : ""))
                        .font(.quota(10)).foregroundStyle(Color.muted)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach([1, 7, 30, 90], id: \.self) { days in
                        Button { store.selectDays(days) } label: {
                            Text(L.days(days)).font(.quota(10)).padding(.horizontal, 6).padding(.vertical, 4)
                                .background(store.days == days ? Color(white: 0.12) : .clear, in: RoundedRectangle(cornerRadius: 3))
                        }.accessibilityLabel(L.text("Last %d days", days))
                    }
                }
            }
            if summary.costQuality.unpricedShare > 0 {
                Text(L.text("API estimate excludes %@%% unpriced usage.", (summary.costQuality.unpricedShare * 100).formatted(.number.precision(.fractionLength(1))))).font(.quota(10)).foregroundStyle(Color.muted)
            }
            VStack(spacing: 15) {
                ForEach(summary.providers.filter { store.selectedProvider == nil || $0.provider == store.selectedProvider?.rawValue }.sorted { store.metric == .cost ? $0.costUsd > $1.costUsd : $0.totalTokens > $1.totalTokens }) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            if let provider = T3Provider(rawValue: row.provider) { ProviderLogo(provider: provider).frame(width: 14, height: 14); Text(provider.label) }
                            Text(L.text("%d sessions", row.sessions)).font(.quota(9)).foregroundStyle(Color.muted)
                            Spacer()
                            Text(store.metric == .cost ? T3Format.money(row.costUsd) : T3Format.tokens(row.totalTokens)).monospacedDigit()
                        }
                        let share = store.metric == .cost ? row.costShare : row.tokenShare
                        Text(L.text(store.metric == .cost ? "%@%% of cost · %@ tokens" : "%@%% of tokens · %@", (share * 100).formatted(.number.precision(.fractionLength(1))), store.metric == .cost ? T3Format.tokens(row.totalTokens) : T3Format.money(row.costUsd)))
                            .font(.quota(10)).foregroundStyle(Color.muted)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(L.text("Breakdown")).font(.quota(11, .medium))
                HStack { Text(L.text("Model")); Spacer(); Text(L.text("Tokens")).frame(width: 72, alignment: .trailing); Text(L.text("Cost")).frame(width: 70, alignment: .trailing) }.font(.quota(9)).foregroundStyle(Color.muted)
                ForEach(summary.models.filter { store.selectedProvider == nil || $0.provider == store.selectedProvider?.rawValue }.sorted { store.metric == .cost ? $0.costUsd > $1.costUsd : $0.totalTokens > $1.totalTokens }) { model in
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            if let provider = T3Provider.from(driver: model.provider) {
                                ProviderLogo(provider: provider).frame(width: 13, height: 13).help(provider.label)
                            }
                            Text(model.model).lineLimit(1).truncationMode(.middle).help(model.model)
                        }.layoutPriority(1)
                        Spacer(minLength: 0)
                        Text(T3Format.tokens(model.totalTokens)).frame(width: 72, alignment: .trailing)
                        Text(model.records > 0 && model.unpricedRecords >= model.records ? L.text("Unpriced") : T3Format.money(model.costUsd)).frame(width: 70, alignment: .trailing)
                    }.font(.quota(10)).monospacedDigit().padding(.vertical, 4)
                    Rectangle().fill(Color.line).frame(height: 0.5)
                }
            }
            Text(L.text("API-equivalent cost is an estimate, not your subscription bill.")).font(.quota(9)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        } else { Text(L.text(store.historyLoading ? "Reading usage history…" : "No usage history available.")).foregroundStyle(Color.muted) }
        if let error = store.summaryError { Text(L.text("No usage history available.")).help(error).font(.quota(10)).foregroundStyle(Color.orange.opacity(0.8)) }
        ForEach(store.notices, id: \.self) { Text(L.text("Some history could not be refreshed.")).help($0).font(.quota(10)).foregroundStyle(Color.muted) }
    }
    private var footer: some View {
        HStack(spacing: 5) {
            Text(L.text(store.refreshing ? "Updating…" : "Refreshes every 5 min")).foregroundStyle(Color.muted)
            Spacer()
            if let date = store.historyDate, store.metric != .limits { Text(L.text("History %@", date.formatted(date: .omitted, time: .shortened))).foregroundStyle(Color.muted).help(L.text("Last updated %@", date.formatted())) }
            Button(L.text("Quit")) { NSApplication.shared.terminate(nil) }.foregroundStyle(Color.muted).padding(.leading, 10)
        }.font(.quota(9)).padding(.horizontal, 15).frame(height: 28)
    }
}

struct LimitWindowRow: View {
    let window: T3PoolWindow
    let driver: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    if !window.label.isEmpty { Text(L.window(window.label)).font(.quota(11)) }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(window.remaining))%").font(.quota(25, .medium)).monospacedDigit()
                        Text(L.text("left")).font(.quota(10)).foregroundStyle(Color.muted)
                        if let pace = window.pace { Image(systemName: pace == "ahead" ? "arrow.up.right" : pace == "under" ? "arrow.down.right" : "gauge.with.dots.needle.50percent").font(.system(size: 9)).foregroundStyle(Color.muted).help(L.text(pace == "ahead" ? "Spending faster than the window elapses" : pace == "under" ? "Headroom left for this window" : "On pace")) }
                    }
                }.frame(width: 100, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(window.segments.enumerated()), id: \.offset) { _, segment in
                        if let segment {
                            VStack(alignment: .leading, spacing: 4) {
                                if window.segments.count > 1 {
                                    HStack {
                                        Text(segment.name).lineLimit(1).truncationMode(.middle).help(segment.name)
                                        Spacer(minLength: 4)
                                        Text("\(Int(segment.remaining))% " + L.text("left")).monospacedDigit()
                                    }.font(.quota(9))
                                }
                                LimitSegment(segment: segment, driver: driver, multiple: false)
                            }
                        } else { Text(L.text("No limits reported.")).font(.quota(9)).foregroundStyle(Color.muted) }
                    }
                }
            }
            if let description = window.description, !(driver == "cursor" && window.id == "apiPercentUsed") { Text(L.text(description)).font(.quota(9)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true) }
        }.padding(.horizontal, 12).padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.line.opacity(0.8), lineWidth: 0.5))
    }
}
struct LimitSegment: View {
    let segment: T3Segment
    let driver: String
    let multiple: Bool
    private var resetHelp: String {
        let remaining = segment.name + ": \(Int(segment.remaining))% " + L.text("left")
        guard let date = T3Date.parse(segment.reset) else { return remaining }
        return remaining + " · " + L.text("Resets %@", date.formatted(date: .complete, time: .standard))
    }
    var body: some View {
        GeometryReader { geometry in
            let fill = geometry.size.width * segment.remaining / 100
            let hatch = geometry.size.width * min(100 - segment.remaining, segment.refill) / 100
            ZStack(alignment: .leading) {
                Color(white: 0.075)
                Color.provider(driver).opacity(0.35).frame(width: fill)
                HStack { Spacer(minLength: 0); Canvas { context, size in
                    var path = Path()
                    for x in stride(from: -size.height, through: size.width + size.height, by: 5) {
                        path.move(to: CGPoint(x: x, y: size.height)); path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    }
                    context.stroke(path, with: .color(Color.provider(driver).opacity(0.25)), lineWidth: 0.6)
                }.frame(width: max(0, hatch)) }
                if let pace = segment.pace {
                    let x = min(max(3, geometry.size.width * pace / 100), geometry.size.width - 3)
                    Rectangle().fill(Color.panel).frame(width: 6).offset(x: x - 3)
                    Rectangle().fill(Color(white: 0.7)).frame(width: 1, height: 20).offset(x: x)
                }
                HStack(spacing: 3) {
                    if multiple { Text(segment.name).lineLimit(1).font(.quota(8)) }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        HStack(spacing: 4) {
                            if let label = T3Format.reset(segment.reset, now: context.date) { Text(label) }
                            if segment.credits > 0 { Image(systemName: "ticket"); Text("\(segment.credits)") }
                        }.font(.quota(10, .medium)).monospacedDigit().foregroundStyle(Color(white: 0.88))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 3))
                    }
                }.padding(.horizontal, 4)
            }.clipShape(RoundedRectangle(cornerRadius: 3))
        }.frame(height: 24)
            .help(resetHelp)
            .accessibilityLabel(L.text("%@, %d percent remaining", segment.name, Int(segment.remaining)))
    }
}
