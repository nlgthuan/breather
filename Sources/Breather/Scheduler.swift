import AppKit

/// The heart of the app: counts active work time per break kind and decides
/// when to start a break.
///
/// Flow for a due break:
///   counting → waiting (for a call / full screen to end, and a pause in typing)
///            → in break (the notch island opens and takes keyboard focus).
/// There is no "start?" step: the break simply begins, and Later is always one key away.
@MainActor
final class Scheduler: ObservableObject {
    static let shared = Scheduler()

    enum Status: Equatable {
        case running
        case paused(until: Date)
        case outsideHours
        case holding(String)
        case onBreak
    }

    @Published private(set) var status: Status = .running

    // Tunables (seconds).
    static let pauseIdle: TimeInterval = 120      // idle this long: stop counting
    static let resetIdle: TimeInterval = 300      // idle/away this long: counts as a natural break
    static let typingPause: TimeInterval = 2      // the island takes focus, so wait for a pause in typing…
    static let maxWaitForPause: TimeInterval = 90 // …but not forever
    static let snoozeLength: TimeInterval = 300
    static let maxSnoozes = 2
    static let mergeWindow: TimeInterval = 300    // breaks due within 5 min are combined

    private enum Phase {
        case counting
        case waiting(Set<BreakKind>, since: Date)
        case inBreak(Set<BreakKind>)
    }

    private var phase: Phase = .counting
    private var elapsed: [BreakKind: TimeInterval] = [:]
    private var pausedUntil: Date?
    private var snoozeUntil: Date?
    private var snoozeCount = 0
    private var lastTick = Date()
    private var timer: Timer?

    private let prefs = Preferences.shared
    private let activity = ActivityMonitor()
    private let presenter = BreakPresenter()

    private init() {}

    /// Whether the app is actively looking after you (shown by the menu bar icon).
    var isActive: Bool {
        switch status {
        case .paused, .outsideHours: false
        default: true
        }
    }

    /// Time until the next break of this kind is due, or nil if it's turned off.
    func timeUntil(_ kind: BreakKind) -> TimeInterval? {
        guard prefs.isEnabled(kind) else { return nil }
        return max(0, prefs.interval(kind) - elapsed[kind, default: 0])
    }

    func start() {
        activity.onReturn = { [weak self] awayFor in
            if awayFor >= Self.resetIdle { self?.naturalBreak() }
        }
        lastTick = Date()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Menu actions

    func takeBreakNow(_ kind: BreakKind) {
        if case .inBreak = phase { return }
        begin([kind], automatic: false)
    }

    /// Testing aid: start a break exactly as the schedule would.
    func startScheduledBreakNow(_ kind: BreakKind) {
        if case .inBreak = phase { return }
        begin([kind], automatic: true)
    }

    func pause(for duration: TimeInterval) {
        pause(until: Date().addingTimeInterval(duration))
    }

    func pauseUntilTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!)
        pause(until: tomorrow)
    }

    private func pause(until date: Date) {
        pausedUntil = date
        if case .inBreak = phase {} else { phase = .counting }
        setStatus(.paused(until: date))
    }

    func resume() {
        pausedUntil = nil
        lastTick = Date()
        setStatus(.running)
    }

    // MARK: Main loop

    private func tick() {
        let now = Date()
        let dt = min(max(now.timeIntervalSince(lastTick), 0), 5)
        lastTick = now

        if case .inBreak = phase { setStatus(.onBreak); return }

        if let until = pausedUntil {
            if until > now { setStatus(.paused(until: until)); return }
            pausedUntil = nil
        }

        if !prefs.isWithinWorkHours(now) {
            phase = .counting
            setStatus(.outsideHours)
            return
        }

        if activity.isAway { return }

        let idle = activity.idleSeconds()
        if idle >= Self.resetIdle {
            naturalBreak()
            setStatus(.running)
            return
        }
        if idle >= Self.pauseIdle { return }

        switch phase {
        case .counting:
            setStatus(.running)
            for k in BreakKind.allCases where prefs.isEnabled(k) {
                elapsed[k, default: 0] += dt
            }
            if let s = snoozeUntil, now < s { return }
            let due = BreakKind.allCases.filter { prefs.isEnabled($0) && elapsed[$0, default: 0] >= prefs.interval($0) }
            if !due.isEmpty { phase = .waiting(Set(due), since: now) }

        case .waiting(let kinds, let since):
            if prefs.holdDuringCalls, let reason = BusyDetector.busyReason() {
                phase = .waiting(kinds, since: now)
                setStatus(.holding(reason))
                return
            }
            setStatus(.running)
            if idle >= Self.typingPause || now.timeIntervalSince(since) >= Self.maxWaitForPause {
                begin(merge(kinds), automatic: true)
            }

        case .inBreak:
            break
        }
    }

    private func setStatus(_ s: Status) {
        if status != s { status = s }
    }

    /// Adds breaks that are almost due, so two reminders don't arrive minutes apart.
    private func merge(_ due: Set<BreakKind>) -> Set<BreakKind> {
        var set = due
        for k in BreakKind.allCases where prefs.isEnabled(k) && !set.contains(k) {
            if prefs.interval(k) - elapsed[k, default: 0] <= Self.mergeWindow { set.insert(k) }
        }
        // Stretching away from the screen rests the eyes too.
        if set.contains(.stretch) { set.remove(.eyes) }
        return set
    }

    // MARK: Break lifecycle

    /// `automatic`: started by the schedule (Later is offered, a soft chime plays),
    /// as opposed to taken by hand from the menu.
    private func begin(_ kinds: Set<BreakKind>, automatic: Bool) {
        phase = .inBreak(kinds)
        setStatus(.onBreak)
        if automatic && prefs.soundEnabled { Sounds.start() }
        presenter.showBreak(
            kinds: kinds.sorted(),
            pattern: prefs.breathingPattern,
            strict: prefs.strictMode,
            canSnooze: automatic && snoozeCount < Self.maxSnoozes,
            sound: prefs.soundEnabled,
            onDone: { [weak self] in self?.finish(kinds, taken: true) },
            onSnooze: { [weak self] in self?.snooze() },
            onSkip: { [weak self] in self?.finish(kinds, taken: false) })
    }

    private func finish(_ kinds: Set<BreakKind>, taken: Bool) {
        presenter.dismissBreak()
        var reset = kinds
        if kinds.contains(.stretch) { reset.insert(.eyes) }
        for k in reset { elapsed[k] = 0 }
        snoozeCount = 0
        snoozeUntil = nil
        Stats.shared.record(taken: taken)
        phase = .counting
        lastTick = Date()
        setStatus(pausedUntil.map { .paused(until: $0) } ?? .running)
    }

    private func snooze() {
        presenter.dismissBreak()
        snoozeCount += 1
        snoozeUntil = Date().addingTimeInterval(Self.snoozeLength)
        phase = .counting
        lastTick = Date()
        setStatus(.running)
    }

    /// The user was away long enough to have rested: start every timer over.
    private func naturalBreak() {
        if case .inBreak = phase { return }
        elapsed = [:]
        snoozeUntil = nil
        snoozeCount = 0
        phase = .counting
        lastTick = Date()
    }
}

enum Sounds {
    @MainActor static func start() { play("Glass", volume: 0.25) }
    @MainActor static func step() { play("Tink", volume: 0.3) }
    @MainActor static func done() { play("Purr", volume: 0.35) }

    @MainActor private static func play(_ name: String, volume: Float) {
        guard let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        s.volume = volume
        s.play()
    }
}
