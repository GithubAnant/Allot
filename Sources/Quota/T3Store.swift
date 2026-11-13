import Foundation
import Observation

@MainActor @Observable
final class T3Store {
    var accounts: [T3Account] = []
    var limitAccounts: [String: T3LimitAccount] = [:]
    var pools: [T3Pool] = []
    var errors: [String: String] = [:]
    var summary: T3Summary?
    var summaryError: String?
    var historyDate: Date?
    var refreshing = false
    var historyLoading = false
    var days = 30
    var metric = T3Metric.limits
    var selectedProvider: T3Provider?
    var notices: [String] = []
    private let source: T3Source
    private let history: T3History
    private var timer: Task<Void, Never>?
    private var lastRefresh = Date.distantPast
    init(source: T3Source = T3Source()) {
        self.source = source; history = T3History(source: source)
        accounts = source.accounts()
        if let data = UserDefaults.standard.data(forKey: "t3-port-summary"), let cached = try? JSONDecoder().decode(T3Summary.self, from: data) { summary = cached }
        if let data = UserDefaults.standard.data(forKey: "t3-port-limits"), let cached = try? JSONDecoder().decode([String: T3LimitAccount].self, from: data) { limitAccounts = cached; rebuildPools() }
    }
    func start() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }
    func refresh() async {
        guard !refreshing, Date().timeIntervalSince(lastRefresh) > 5 else { return }
        refreshing = true; lastRefresh = Date(); accounts = source.accounts()
        let activeIDs = Set(accounts.map(\.id))
        limitAccounts = limitAccounts.filter { activeIDs.contains($0.key) }; errors = errors.filter { activeIDs.contains($0.key) }
        let reader = T3LimitReader(source: source)
        async let historyRefresh: () = refreshHistory(scan: true)
        await withTaskGroup(of: (String, Result<T3LimitAccount, Error>).self) { group in
            for account in accounts {
                group.addTask {
                    do { return (account.id, .success(try await reader.fetch(account))) }
                    catch { return (account.id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let snapshot): limitAccounts[id] = snapshot; errors[id] = nil
                case .failure(let error): errors[id] = (error as? UsageFailure)?.message ?? "Could not read limits."
                }
                rebuildPools()
            }
        }
        await historyRefresh
        if let data = try? JSONEncoder().encode(limitAccounts) { UserDefaults.standard.set(data, forKey: "t3-port-limits") }
        refreshing = false
    }
    func refreshHistory(scan: Bool = false) async {
        guard !historyLoading else { return }
        historyLoading = true
        let requestedDays = days, requestedProvider = selectedProvider
        do {
            let result = try await history.summary(days: requestedDays, provider: requestedProvider?.rawValue, scan: scan)
            summary = result.0; historyDate = result.1; notices = result.2; summaryError = nil
            if let data = try? JSONEncoder().encode(result.0) { UserDefaults.standard.set(data, forKey: "t3-port-summary") }
        } catch { summaryError = (error as? UsageFailure)?.message ?? "Could not read T3 usage history." }
        historyLoading = false
        if days != requestedDays || selectedProvider != requestedProvider { await refreshHistory() }
    }
    func selectDays(_ value: Int) { days = value; Task { await refreshHistory() } }
    func selectProvider(_ provider: T3Provider?) { selectedProvider = provider; rebuildPools(); Task { await refreshHistory() } }
    private func rebuildPools() {
        do {
            let selected = limitAccounts.values.filter { selectedProvider == nil || T3Provider.from(driver: $0.driver) == selectedProvider }
            let accountData = try JSONEncoder().encode(Array(selected))
            let accounts = try JSONSerialization.jsonObject(with: accountData)
            let engine = try T3Engine()
            let data = try engine.call("poolJSON", object: ["accounts": accounts, "now": Date().timeIntervalSince1970 * 1000])
            let decoded = try JSONDecoder().decode([T3Pool].self, from: data)
            pools = T3Provider.allCases.compactMap { provider in decoded.first { $0.driver == provider.driver } }
        } catch { summaryError = "T3 limit pooling failed." }
    }
}
