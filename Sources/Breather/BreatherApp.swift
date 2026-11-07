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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
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
