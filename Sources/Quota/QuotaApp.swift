import AppKit
import SwiftUI
import CoreText

@main struct RationApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = T3Store()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let font = QuotaResources.bundle.url(forResource: "Geist-Regular", withExtension: "ttf") { CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil) }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--probe") || arguments.contains("--render") {
            Task {
                await store.refresh()
                for account in store.limitAccounts.values.sorted(by: { $0.key < $1.key }) {
                    print("\(account.displayName ?? account.driver): " + account.limits.windows.map { "\($0.label): \(Int((100 - $0.usedPercent).rounded()))% left" }.joined(separator: "; "))
                }
                if let summary = store.summary { print("T3 last \(store.days) days: \(T3Format.money(summary.costUsd)) API estimate, \(T3Format.tokens(summary.totalTokens)) tokens") }
                for (id, error) in store.errors { print("\(id): \(error)") }
                if let error = store.summaryError { print(error) }
                if let index = arguments.firstIndex(of: "--render"), arguments.indices.contains(index + 1) {
                    if arguments.contains("--cost") { store.metric = .cost }
                    if arguments.contains("--tokens") { store.metric = .tokens }
                    let host = NSHostingView(rootView: PanelView(store: store, close: {}))
                    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
                    window.contentView = host; host.frame = NSRect(origin: .zero, size: host.fittingSize)
                    host.layoutSubtreeIfNeeded(); window.display()
                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[index + 1]))
                    }
                }
                fflush(stdout); NSApplication.shared.terminate(nil)
            }
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Ration · T3 usage")
        item.button?.image?.isTemplate = true
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.toolTip = "Ration · T3 usage"
        popover.behavior = .transient; popover.animates = false
        let controller = NSHostingController(rootView: PanelView(store: store, close: { [weak self] in self?.popover.performClose(nil) }))
        controller.sizingOptions = [.preferredContentSize]; popover.contentViewController = controller
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        store.start()
        if arguments.contains("--show") || !UserDefaults.standard.bool(forKey: "t3-port-launched") { UserDefaults.standard.set(true, forKey: "t3-port-launched"); toggle() }
    }
    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func wake() { Task { await store.refresh() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !popover.isShown { toggle() }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
