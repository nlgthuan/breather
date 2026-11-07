import Foundation

struct Stretch: Identifiable, Hashable {
    let id: String
    let title: String
    let instruction: String
    let symbol: String

    static let all: [Stretch] = [
        .init(id: "neck-tilt", title: "Neck tilt",
              instruction: "Tilt your right ear toward your right shoulder and hold. Breathe. Switch sides halfway.",
              symbol: "figure.mind.and.body"),
        .init(id: "neck-turn", title: "Look over your shoulder",
              instruction: "Slowly turn your head to look over your right shoulder, then your left. Go gently.",
              symbol: "person.fill.turn.right"),
        .init(id: "shoulder-roll", title: "Shoulder rolls",
              instruction: "Roll your shoulders backwards in big, slow circles. Then a few forwards.",
              symbol: "figure.arms.open"),
        .init(id: "shrug", title: "Shrug and drop",
              instruction: "Lift your shoulders up to your ears, hold for 3 seconds, then let them drop. Repeat.",
              symbol: "figure.stand"),
        .init(id: "chest", title: "Chest opener",
              instruction: "Clasp your hands behind your back, straighten your arms and gently lift your chest.",
              symbol: "figure.cooldown"),
        .init(id: "wrist", title: "Wrist stretch",
              instruction: "Hold one arm out, palm up. With the other hand, gently pull the fingers back. Switch halfway.",
              symbol: "hand.raised"),
        .init(id: "fingers", title: "Open your hands",
              instruction: "Make a soft fist, then spread your fingers as wide as you can. Repeat slowly.",
              symbol: "hand.raised.fingers.spread"),
        .init(id: "reach", title: "Stand and reach",
              instruction: "Stand up, reach both arms overhead and stretch tall. Breathe in deeply.",
              symbol: "figure.stand"),
        .init(id: "side-bend", title: "Side bend",
              instruction: "Arms overhead, lean slowly to one side, then the other. Feel the stretch along your sides.",
              symbol: "figure.flexibility"),
        .init(id: "twist", title: "Seated twist",
              instruction: "Sit tall and turn your upper body toward the back of your chair. Hold, then switch sides.",
              symbol: "figure.core.training"),
        .init(id: "calf", title: "Calf raises",
              instruction: "Stand up, rise slowly onto your toes, then lower down. Repeat about 10 times.",
              symbol: "figure.walk"),
        .init(id: "walk", title: "Take a short walk",
              instruction: "Walk around the room, or go get a glass of water.",
              symbol: "figure.walk"),
    ]

    /// Picks `count` stretches, avoiding the ones used last time so breaks stay fresh.
    static func pick(_ count: Int) -> [Stretch] {
        let key = "lastStretches"
        let last = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        var pool = all.filter { !last.contains($0.id) }.shuffled()
        if pool.count < count { pool += all.filter { last.contains($0.id) }.shuffled() }
        let chosen = Array(pool.prefix(count))
        UserDefaults.standard.set(chosen.map(\.id), forKey: key)
        return chosen
    }
}

enum BreakStep {
    case eyes
    case breathe(BreathingPattern)
    case stretch(Stretch, number: Int, of: Int)

    static let eyesLookAway: TimeInterval = 20
    static let eyesBlink: TimeInterval = 10

    var duration: TimeInterval {
        switch self {
        case .eyes: Self.eyesLookAway + Self.eyesBlink
        case .breathe(let p): p == .box ? 64 : 60
        case .stretch: 40
        }
    }

    static func steps(for kinds: [BreakKind], pattern: BreathingPattern) -> [BreakStep] {
        kinds.flatMap { kind -> [BreakStep] in
            switch kind {
            case .eyes: return [.eyes]
            case .breathe: return [.breathe(pattern)]
            case .stretch:
                let s = Stretch.pick(3)
                return s.enumerated().map { .stretch($0.element, number: $0.offset + 1, of: s.count) }
            }
        }
    }
}

/// Drives one break overlay: which step is showing and when it's finished.
@MainActor
final class BreakSession: ObservableObject {
    let kinds: [BreakKind]
    let steps: [BreakStep]
    let strict: Bool
    let canSnooze: Bool
    let sound: Bool

    @Published private(set) var index = 0
    @Published private(set) var stepStart = Date()
    @Published private(set) var isComplete = false
    /// Set while Esc is held in strict mode.
    @Published var escHoldStart: Date?

    var onDone: () -> Void = {}
    var onSnooze: () -> Void = {}
    var onSkip: () -> Void = {}

    private var timer: Timer?
    private var blinkCuePlayed = false
    private var completedAt: Date?
    static let autoCloseAfter: TimeInterval = 4

    /// Return marks the break done early; strict mode only allows it at the end.
    var canFinishNow: Bool { isComplete || !strict }

    /// Snapshot/testing aid: jump to a step, `elapsed` seconds in.
    func preview(step: Int, elapsed: TimeInterval, complete: Bool = false) {
        index = min(step, steps.count - 1)
        stepStart = Date().addingTimeInterval(-elapsed)
        isComplete = complete
    }

    init(kinds: [BreakKind], pattern: BreathingPattern, strict: Bool, canSnooze: Bool, sound: Bool) {
        self.kinds = kinds
        self.steps = BreakStep.steps(for: kinds, pattern: pattern)
        self.strict = strict
        self.canSnooze = canSnooze
        self.sound = sound
    }

    var step: BreakStep { steps[index] }

    var title: String {
        kinds.count == 1 ? kinds[0].title : kinds.map(\.title).joined(separator: " · ")
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
        advance(now)
    }

    private func advance(_ now: Date) {
        if index + 1 < steps.count {
            index += 1
            stepStart = now
            blinkCuePlayed = false
            if sound { Sounds.step() }
        } else {
            isComplete = true
            completedAt = now
            if sound { Sounds.done() }
        }
    }

    var isLastStep: Bool { index + 1 >= steps.count }

    /// Return key: go to the next step, or finish on the last one.
    func next() {
        if isComplete || isLastStep { done() } else { advance(Date()) }
    }

    func done() { stop(); onDone() }
    func skip() { stop(); onSkip() }
    func snooze() { stop(); onSnooze() }
}
