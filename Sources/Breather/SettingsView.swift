import AppKit
import ServiceManagement
import SwiftUI

/// Settings, shown inside the menu bar panel in place of its main page.
struct SettingsPage: View {
    @ObservedObject var prefs: Preferences
    let onBack: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    breaks
                    reminders
                    schedule
                    general
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
            .frame(height: 470)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Back")
            Text("Settings").font(Theme.font(15, .semibold))
            Spacer()
        }
        .padding(.leading, -6)
    }

    private var breaks: some View {
        Group_(title: "Breaks",
               note: "Always at least \(Int(Scheduler.gapMinutes)) min apart; breaks due together share one reminder.") {
            breakRow(.eyes, enabled: $prefs.eyesEnabled, minutes: $prefs.eyesInterval, options: [25, 30, 40, 50, 60])
            breakRow(.hydrate, enabled: $prefs.hydrateEnabled, minutes: $prefs.hydrateInterval, options: [50, 60, 75, 90, 120])
            breakRow(.stretch, enabled: $prefs.stretchEnabled, minutes: $prefs.stretchInterval, options: [50, 60, 75, 90, 120])
            breakRow(.breathe, enabled: $prefs.breatheEnabled, minutes: $prefs.breatheInterval, options: [50, 60, 75, 90, 120])
            Row("Breathing") {
                Picker("", selection: $prefs.breathingPattern) {
                    ForEach(BreathingPattern.allCases) { Text($0.shortLabel).tag($0) }
                }
                .compactMenu()
            }
        }
    }

    private var reminders: some View {
        Group_(title: "Reminders",
               note: "Strict mode hides Skip; holding Esc for 3 s always gets you out. Reduced motion fades reminders in and keeps the glow still.") {
            Row("Strict mode") { Toggle("", isOn: $prefs.strictMode).themedSwitch() }
            Row("Wait for calls & full screen") { Toggle("", isOn: $prefs.holdDuringCalls).themedSwitch() }
            Row("Soft sounds") { Toggle("", isOn: $prefs.soundEnabled).themedSwitch() }
            Row("Motion") {
                Picker("", selection: $prefs.motion) {
                    ForEach(MotionMode.allCases) { Text($0.label).tag($0) }
                }
                .compactMenu()
            }
        }
    }

    private var schedule: some View {
        Group_(title: "Schedule") {
            Row("Only during work hours") { Toggle("", isOn: $prefs.workHoursOnly).themedSwitch() }
            if prefs.workHoursOnly {
                Row("Hours") {
                    HStack(spacing: 4) {
                        timePicker($prefs.workStart)
                        Text("–").foregroundStyle(Theme.text3)
                        timePicker($prefs.workEnd)
                    }
                }
                WeekdayPicker(days: $prefs.workDays)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
    }

    private var general: some View {
        Group_(title: "General", note: loginError) {
            Row("Appearance") {
                Picker("", selection: $prefs.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .compactMenu()
            }
            Row("Open at login") {
                Toggle("", isOn: $launchAtLogin)
                    .themedSwitch()
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            }
        }
    }

    // MARK: Rows

    private func breakRow(_ kind: BreakKind, enabled: Binding<Bool>, minutes: Binding<Int>, options: [Int]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbol)
                .font(.system(size: 13))
                .foregroundStyle(enabled.wrappedValue ? Theme.accent : Theme.text3)
                .frame(width: 18)
            Text(kind.title)
                .font(Theme.font(13, .medium))
                .foregroundStyle(enabled.wrappedValue ? Theme.ink : Theme.text3)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Picker("", selection: minutes) {
                ForEach(Set(options + [minutes.wrappedValue]).sorted(), id: \.self) { Text("\($0) min").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 78)
            .disabled(!enabled.wrappedValue)
            .opacity(enabled.wrappedValue ? 1 : 0.4)
            Toggle("", isOn: enabled).themedSwitch()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
    }

    private func timePicker(_ minutes: Binding<Int>) -> some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(minutes.wrappedValue) * 60) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.small)
            .fixedSize()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription). Move Breather to Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// A titled card of rows, with an optional note under it.
private struct Group_<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.font(12, .semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink.opacity(0.045)))
            if let note {
                Text(note)
                    .font(Theme.font(11.5))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

private struct Row<Control: View>: View {
    let label: String
    let control: Control
    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.font(13, .medium)).lineLimit(1)
            Spacer(minLength: 4)
            control
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
    }
}

private extension View {
    func themedSwitch() -> some View {
        labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Theme.soft)
    }

    func compactMenu() -> some View {
        labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
    }
}

private struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols // index 0 = Sunday
        let first = Calendar.current.firstWeekday             // 1 = Sunday, 2 = Monday
        let order = (0..<7).map { (first - 1 + $0) % 7 + 1 }
        HStack(spacing: 0) {
            ForEach(order, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(Theme.font(12, .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(on ? Theme.soft : Theme.ink.opacity(0.07)))
                        .foregroundStyle(on ? Color.white : Theme.text2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

extension BreathingPattern {
    var shortLabel: String {
        switch self {
        case .relaxed: "Longer exhale"
        case .box: "Box (4-4-4-4)"
        }
    }
}
