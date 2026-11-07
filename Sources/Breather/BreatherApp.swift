import AppKit
import SwiftUI

@main
struct BreatherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var scheduler = Scheduler.shared
    @StateObject private var stats = Stats.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(scheduler: scheduler, stats: stats)
        } label: {
            // Minimal: a filled leaf when Breather is looking after you, an outline when paused or off-hours.
            Image(systemName: scheduler.isActive ? "leaf.fill" : "leaf")
        }
        .menuBarExtraStyle(.menu)
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
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var scheduler: Scheduler
    @ObservedObject var stats: Stats

    var body: some View {
        Text(statusText)

        let today = stats.today
        Text(today.offered == 0 ? "No breaks yet today" : "Breaks today: \(today.taken) of \(today.offered)")
        if stats.streak >= 2 {
            Text("\(stats.streak)-day streak")
        }

        Divider()

        Menu("Take a break now") {
            ForEach(BreakKind.allCases, id: \.self) { kind in
                Button(kind.title) { scheduler.takeBreakNow(kind) }
            }
        }

        if case .paused = scheduler.status {
            Button("Resume") { scheduler.resume() }
        } else {
            Menu("Pause") {
                Button("For 30 minutes") { scheduler.pause(for: 30 * 60) }
                Button("For 1 hour") { scheduler.pause(for: 60 * 60) }
                Button("For 2 hours") { scheduler.pause(for: 2 * 60 * 60) }
                Button("Until tomorrow") { scheduler.pauseUntilTomorrow() }
            }
        }

        Divider()

        Button("Settings…") { SettingsWindow.show() }
            .keyboardShortcut(",")
        Button("Quit Breather") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        switch scheduler.status {
        case .running: "Breather is on"
        case .onBreak: "On a break"
        case .outsideHours: "Off — outside work hours"
        case .holding(let reason): "Waiting — \(reason)"
        case .paused(let until):
            "Paused until " + until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated,
                                              time: .shortened)
        }
    }
}
