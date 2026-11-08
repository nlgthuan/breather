import AppKit
import SwiftUI

/// What opens when you click the leaf in the menu bar.
struct PopoverView: View {
    @ObservedObject var scheduler: Scheduler
    @ObservedObject var stats: Stats
    @State private var showingSettings = false
    static let width: CGFloat = 352

    var body: some View {
        Group {
            if showingSettings {
                SettingsPage(prefs: .shared) { show(settings: false) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                // Refresh the "in N min" times while it's open.
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        today
                        comingUp
                        actions
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(18)
        .frame(width: PopoverView.width)
        .clipped()
        .background(Theme.panel)
        // Open on the main page next time.
        .onDisappear { showingSettings = false }
        .foregroundStyle(Theme.ink)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(scheduler.isActive ? Theme.soft : Theme.ink.opacity(0.25))
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(Theme.font(15, .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                show(settings: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var today: some View {
        let d = stats.today
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today").font(Theme.font(14)).foregroundStyle(Theme.text2)
                Spacer()
                Text(d.offered == 0 ? "No breaks yet" : "\(d.taken) of \(d.offered) breaks")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.text2)
            }
            LinearProgress(fraction: d.offered == 0 ? 0 : Double(d.taken) / Double(d.offered))
            if stats.streak >= 2 {
                Text("\(stats.streak)-day streak")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.soft.opacity(0.14)))
    }

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Coming up")
                .font(Theme.font(12, .semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            ForEach(BreakKind.allCases, id: \.self) { kind in
                if let left = scheduler.timeUntil(kind) {
                    BreakRow(kind: kind, when: whenText(left)) {
                        closePopover()
                        scheduler.takeBreakNow(kind)
                    }
                }
            }
            Text("Click a row to take that break now.")
                .font(Theme.font(12))
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 6)
                .padding(.top, 6)
        }
    }

    private var actions: some View {
        VStack(spacing: 6) {
            if case .paused = scheduler.status {
                PanelButton(title: "Resume") { scheduler.resume() }
            } else {
                HStack(spacing: 8) {
                    PanelButton(title: "Pause 1 hour") { scheduler.pause(for: 60 * 60) }
                    PanelButton(title: "Pause for today") { scheduler.pauseUntilTomorrow() }
                }
            }
            Button("Quit Breather") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.font(13, .medium))
                .foregroundStyle(Theme.text3)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
    }

    // MARK: Helpers

    private var statusText: String {
        switch scheduler.status {
        case .running: "Breather is on"
        case .onBreak: "On a break"
        case .outsideHours: "Off · outside work hours"
        case .holding(let reason): "Waiting · \(reason)"
        case .paused(let until):
            "Paused until " + until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated,
                                              time: .shortened)
        }
    }

    private func whenText(_ seconds: TimeInterval) -> String {
        if !scheduler.isActive { return "paused" }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes <= 0 ? "now" : "in \(minutes) min"
    }

    private func show(settings: Bool) {
        let reduce = Preferences.shared.reduceMotion
        withAnimation(reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9)) {
            showingSettings = settings
        }
    }

    /// The popover is the key window while you click in it.
    private func closePopover() {
        NSApp.keyWindow?.close()
    }
}

private struct BreakRow: View {
    let kind: BreakKind
    let when: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                Text(kind.title).font(Theme.font(15, .medium))
                Spacer()
                Text(when).font(Theme.font(14)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.ink.opacity(hover ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct PanelButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(14, .medium))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(Theme.ink)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.ink.opacity(hover ? 0.1 : 0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
