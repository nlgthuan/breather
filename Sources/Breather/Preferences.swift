import AppKit
import Foundation

enum BreakKind: String, CaseIterable, Codable, Hashable, Comparable {
    case eyes, breathe, stretch, hydrate

    var title: String {
        switch self {
        case .eyes: "Rest your eyes"
        case .breathe: "Breathe"
        case .stretch: "Stretch"
        case .hydrate: "Drink water"
        }
    }

    var symbol: String {
        switch self {
        case .eyes: "eye"
        case .breathe: "wind"
        case .stretch: "figure.stand"
        case .hydrate: "drop"
        }
    }

    /// Order used when several breaks are combined into one session.
    static func < (a: BreakKind, b: BreakKind) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

enum BreathingPattern: String, CaseIterable, Identifiable {
    case relaxed   // 4 in, 6 out
    case box       // 4-4-4-4
    var id: String { rawValue }
    var label: String {
        switch self {
        case .relaxed: "Longer exhale (4 in, 6 out)"
        case .box: "Box breathing (4-4-4-4)"
        }
    }
}

/// How much the island moves: springing out of the notch and a breathing glow,
/// or a simple fade and a still glow.
enum MotionMode: String, CaseIterable, Identifiable {
    case system, full, reduced
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Match system"
        case .full: "Full"
        case .reduced: "Reduced"
        }
    }
}

/// Light or dark for the menu bar panel (the break island is always dark).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// User settings, persisted in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    @Published var eyesEnabled: Bool { didSet { d.set(eyesEnabled, forKey: "eyesEnabled") } }
    @Published var eyesInterval: Int { didSet { d.set(eyesInterval, forKey: "eyesInterval") } }
    @Published var breatheEnabled: Bool { didSet { d.set(breatheEnabled, forKey: "breatheEnabled") } }
    @Published var breatheInterval: Int { didSet { d.set(breatheInterval, forKey: "breatheInterval") } }
    @Published var stretchEnabled: Bool { didSet { d.set(stretchEnabled, forKey: "stretchEnabled") } }
    @Published var stretchInterval: Int { didSet { d.set(stretchInterval, forKey: "stretchInterval") } }
    @Published var hydrateEnabled: Bool { didSet { d.set(hydrateEnabled, forKey: "hydrateEnabled") } }
    @Published var hydrateInterval: Int { didSet { d.set(hydrateInterval, forKey: "hydrateInterval") } }
    @Published var breathingPattern: BreathingPattern { didSet { d.set(breathingPattern.rawValue, forKey: "breathingPattern") } }

    @Published var strictMode: Bool { didSet { d.set(strictMode, forKey: "strictMode") } }
    @Published var soundEnabled: Bool { didSet { d.set(soundEnabled, forKey: "soundEnabled") } }
    @Published var motion: MotionMode { didSet { d.set(motion.rawValue, forKey: "motion") } }
    @Published var appearance: AppearanceMode {
        didSet { d.set(appearance.rawValue, forKey: "appearance"); applyAppearance() }
    }

    /// Sets the whole app's appearance; nil follows the system.
    func applyAppearance() {
        NSApp.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Whether to use reduced motion right now (the system's Reduce Motion, unless overridden).
    var reduceMotion: Bool {
        switch motion {
        case .system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        case .full: false
        case .reduced: true
        }
    }

    @Published var workHoursOnly: Bool { didSet { d.set(workHoursOnly, forKey: "workHoursOnly") } }
    /// Minutes after midnight.
    @Published var workStart: Int { didSet { d.set(workStart, forKey: "workStart") } }
    @Published var workEnd: Int { didSet { d.set(workEnd, forKey: "workEnd") } }
    /// Calendar weekdays: 1 = Sunday … 7 = Saturday.
    @Published var workDays: Set<Int> { didSet { d.set(Array(workDays), forKey: "workDays") } }

    /// Debug aid: how many real seconds one "minute" of interval lasts.
    /// `defaults write com.thuanngo.Breather debugSecondsPerMinute -int 2` makes breaks come fast.
    var secondsPerMinute: Double {
        let v = d.double(forKey: "debugSecondsPerMinute")
        return v > 0 ? v : 60
    }

    private init() {
        let d = UserDefaults.standard
        func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
        func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
        eyesEnabled = bool("eyesEnabled", true)
        // Multiples of 25 min, so reminders fall on one rhythm and those that
        // land together share a card (e.g. stretch + water every 50 min).
        eyesInterval = int("eyesInterval", 25)
        breatheEnabled = bool("breatheEnabled", true)
        breatheInterval = int("breatheInterval", 75)
        stretchEnabled = bool("stretchEnabled", true)
        stretchInterval = int("stretchInterval", 50)
        hydrateEnabled = bool("hydrateEnabled", true)
        hydrateInterval = int("hydrateInterval", 50)
        breathingPattern = BreathingPattern(rawValue: d.string(forKey: "breathingPattern") ?? "") ?? .relaxed
        strictMode = bool("strictMode", false)
        soundEnabled = bool("soundEnabled", true)
        motion = MotionMode(rawValue: d.string(forKey: "motion") ?? "") ?? .system
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        workHoursOnly = bool("workHoursOnly", false)
        workStart = int("workStart", 9 * 60)
        workEnd = int("workEnd", 18 * 60)
        workDays = Set(d.array(forKey: "workDays") as? [Int] ?? [2, 3, 4, 5, 6])
    }

    func isEnabled(_ k: BreakKind) -> Bool {
        switch k {
        case .eyes: eyesEnabled
        case .breathe: breatheEnabled
        case .stretch: stretchEnabled
        case .hydrate: hydrateEnabled
        }
    }

    /// Interval in real seconds.
    func interval(_ k: BreakKind) -> TimeInterval {
        let minutes: Int
        switch k {
        case .eyes: minutes = eyesInterval
        case .breathe: minutes = breatheInterval
        case .stretch: minutes = stretchInterval
        case .hydrate: minutes = hydrateInterval
        }
        return Double(minutes) * secondsPerMinute
    }

    func isWithinWorkHours(_ date: Date = Date()) -> Bool {
        guard workHoursOnly else { return true }
        let cal = Calendar.current
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, workDays.contains(wd) else { return false }
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if workStart <= workEnd { return m >= workStart && m < workEnd }
        return m >= workStart || m < workEnd // overnight shift
    }
}
