import Foundation

enum BreakStep {
    case eyes
    case breathe(BreathingPattern)
    case stretch
    case hydrate

    static let eyesLookAway: TimeInterval = 20
    static let eyesBlink: TimeInterval = 10

    var duration: TimeInterval {
        switch self {
        case .eyes: Self.eyesLookAway + Self.eyesBlink
        case .breathe(let p): Double(p.breaths) * p.cycle
        case .stretch: 120
        case .hydrate: 20
        }
    }

    /// Breaks that land together become one card. The main activity is the
    /// biggest one; the rest (a few sips, resting the eyes) ride along with it.
    static func primary(of kinds: Set<BreakKind>) -> BreakKind {
        [.stretch, .breathe, .eyes, .hydrate].first { kinds.contains($0) } ?? .hydrate
    }

    init(_ kind: BreakKind, pattern: BreathingPattern) {
        switch kind {
        case .eyes: self = .eyes
        case .breathe: self = .breathe(pattern)
        case .stretch: self = .stretch
        case .hydrate: self = .hydrate
        }
    }
}

extension BreathingPattern {
    /// Seconds per breath.
    var cycle: TimeInterval { self == .box ? 16 : 10 }
    var breaths: Int { self == .box ? 4 : 6 }
}

/// Drives one break card: its timer, and when it's finished.
@MainActor
final class BreakSession: ObservableObject {
    let kinds: Set<BreakKind>
    let step: BreakStep
    /// Bundled in with the main activity, e.g. water alongside a stretch.
    let extras: Set<BreakKind>
    let strict: Bool
    let canSnooze: Bool
    let sound: Bool

    @Published private(set) var stepStart = Date()
    @Published private(set) var isComplete = false
    @Published private(set) var completedAt: Date?
    /// Set while Esc is held in strict mode.
    @Published var escHoldStart: Date?

    var onDone: () -> Void = {}
    var onSnooze: () -> Void = {}
    var onSkip: () -> Void = {}
    /// A nudge closed on its own without being clicked.
    var onTimeout: () -> Void = {}

    /// Water on its own is a quiet nudge: it doesn't take keyboard focus and
    /// slides away by itself after a few seconds.
    var isNudge: Bool { kinds == [.hydrate] }
    static let nudgeDuration: TimeInterval = 8

    private var timer: Timer?
    private var blinkCuePlayed = false
    static let autoCloseAfter: TimeInterval = 4

    /// Return marks the break done early; strict mode only allows it at the end.
    var canFinishNow: Bool { isComplete || !strict }

    /// Snapshot/testing aid: show the card `elapsed` seconds in.
    func preview(elapsed: TimeInterval, complete: Bool = false) {
        stepStart = Date().addingTimeInterval(-elapsed)
        isComplete = complete
        completedAt = complete ? Date().addingTimeInterval(-1) : nil
    }

    init(kinds: Set<BreakKind>, pattern: BreathingPattern, strict: Bool, canSnooze: Bool, sound: Bool) {
        self.kinds = kinds
        let main = BreakStep.primary(of: kinds)
        self.step = BreakStep(main, pattern: pattern)
        self.extras = kinds.subtracting([main])
        self.strict = strict
        self.canSnooze = canSnooze
        self.sound = sound
    }

    func start() {
        stepStart = Date()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        if isNudge {
            if now.timeIntervalSince(stepStart) >= Self.nudgeDuration { stop(); onTimeout() }
            return
        }
        if isComplete {
            if let c = completedAt, now.timeIntervalSince(c) >= Self.autoCloseAfter { done() }
            return
        }
        let t = now.timeIntervalSince(stepStart)
        if case .eyes = step, !blinkCuePlayed, t >= BreakStep.eyesLookAway {
            blinkCuePlayed = true
            if sound { Sounds.step() } // they're looking away: a sound tells them to look back
        }
        guard t >= step.duration else { return }
        isComplete = true
        completedAt = now
        if sound { Sounds.done() }
    }

    /// Return key: finish.
    func next() { done() }

    func done() { stop(); onDone() }
    func skip() { stop(); onSkip() }
    func snooze() { stop(); onSnooze() }
}
