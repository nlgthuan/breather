import AppKit
import ServiceManagement
import SwiftUI

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(prefs: .shared)))
            w.title = "Breather Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Breaks") {
                breakRow(.eyes, enabled: $prefs.eyesEnabled, minutes: $prefs.eyesInterval, options: [15, 20, 25, 30, 40])
                breakRow(.breathe, enabled: $prefs.breatheEnabled, minutes: $prefs.breatheInterval, options: [30, 45, 60, 75, 90])
                breakRow(.stretch, enabled: $prefs.stretchEnabled, minutes: $prefs.stretchInterval, options: [45, 60, 75, 90, 120])
                breakRow(.hydrate, enabled: $prefs.hydrateEnabled, minutes: $prefs.hydrateInterval, options: [30, 40, 50, 60, 90])
                Picker("Breathing style", selection: $prefs.breathingPattern) {
                    ForEach(BreathingPattern.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                Toggle("Strict mode", isOn: $prefs.strictMode)
                Toggle("Wait until calls and full-screen apps end", isOn: $prefs.holdDuringCalls)
                Toggle("Play soft sounds", isOn: $prefs.soundEnabled)
            } header: {
                Text("Reminders")
            } footer: {
                Text("Strict mode hides Skip. You can still postpone twice, and holding Esc for 3 seconds always gets you out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Schedule") {
                Toggle("Only during work hours", isOn: $prefs.workHoursOnly)
                if prefs.workHoursOnly {
                    HStack {
                        DatePicker("From", selection: minutesBinding($prefs.workStart), displayedComponents: .hourAndMinute)
                        DatePicker("to", selection: minutesBinding($prefs.workEnd), displayedComponents: .hourAndMinute)
                    }
                    WeekdayPicker(days: $prefs.workDays)
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private func breakRow(_ kind: BreakKind, enabled: Binding<Bool>, minutes: Binding<Int>, options: [Int]) -> some View {
        HStack {
            Toggle(isOn: enabled) {
                Label(kind.title, systemImage: kind.symbol)
            }
            Spacer()
            Picker("", selection: minutes) {
                ForEach(Set(options + [minutes.wrappedValue]).sorted(), id: \.self) { Text("every \($0) min").tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!enabled.wrappedValue)
        }
    }

    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(minutes.wrappedValue) * 60) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription). Move Breather to the Applications folder and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols // index 0 = Sunday
        let first = Calendar.current.firstWeekday             // 1 = Sunday, 2 = Monday
        let order = (0..<7).map { (first - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            Text("Days")
            Spacer()
            ForEach(order, id: \.self) { day in
                let on = days.contains(day)
                Button(symbols[day - 1]) {
                    if on { days.remove(day) } else { days.insert(day) }
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .background(Circle().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(on ? .white : .primary)
            }
        }
    }
}
