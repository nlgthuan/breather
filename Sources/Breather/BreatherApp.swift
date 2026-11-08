import AppKit
import SwiftUI

@main
struct BreatherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var scheduler = Scheduler.shared
    @StateObject private var stats = Stats.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(scheduler: scheduler, stats: stats)
        } label: {
            // Minimal: a filled leaf when Breather is looking after you, an outline when paused or off-hours.
            Image(systemName: scheduler.isActive ? "leaf.fill" : "leaf")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opening Breather again (Launchpad, Spotlight, Finder) while it's already running
    /// opens its menu bar panel, so the click visibly does something. Left alone during a break.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            if Scheduler.shared.status != .onBreak { Self.openMenuBarPanel() }
        }
        return false
    }

    /// Clicks Breather's own menu bar icon.
    @MainActor private static func openMenuBarPanel() {
        func button(in view: NSView?) -> NSStatusBarButton? {
            guard let view else { return nil }
            if let b = view as? NSStatusBarButton { return b }
            return view.subviews.lazy.compactMap { button(in: $0) }.first
        }
        for w in NSApp.windows where w.className.contains("StatusBar") {
            if let b = button(in: w.contentView) { b.performClick(nil); return }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            Preferences.shared.applyAppearance()
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
                Snapshots.run(into: args[i + 1])
                exit(0)
            }
            Scheduler.shared.start()
            // Testing aid: `open Breather.app --args --break breathe` shows a break immediately.
            if let i = args.firstIndex(of: "--break"), i + 1 < args.count, let kind = BreakKind(rawValue: args[i + 1]) {
                Scheduler.shared.takeBreakNow(kind)
            }
            // Testing aid: `--auto-break eyes` starts a break as if the schedule had (so Later is offered).
            if let i = args.firstIndex(of: "--auto-break"), i + 1 < args.count, let kind = BreakKind(rawValue: args[i + 1]) {
                Scheduler.shared.startScheduledBreakNow(kind)
            }
            // Testing aid: pretend a display was plugged in or out 3 seconds after launch.
            if args.contains("--simulate-display-change") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
                }
            }
        }
    }
}
