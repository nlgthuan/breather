import AppKit
import SwiftUI

// MARK: Theme

enum Theme {
    static let accent = Color(red: 0.56, green: 0.89, blue: 0.78)
    static let ink = Color(red: 0.04, green: 0.08, blue: 0.09)
}

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True when rendering offscreen (ImageRenderer can't draw live blur).
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// Live blur of whatever is behind the window.
struct Backdrop: View {
    var material: NSVisualEffectView.Material
    @Environment(\.snapshotMode) private var snapshot

    var body: some View {
        if snapshot {
            LinearGradient(colors: [Color(white: 0.22), Color(red: 0.18, green: 0.22, blue: 0.26)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            BlurView(material: material)
        }
    }
}

private struct BlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// MARK: Full-screen break

/// Dimmed, lightly blurred desktop. macOS has no blur-strength setting, so the
/// blur layer is made partly transparent to let some of the sharp desktop through.
struct BreakBackground: View {
    static let blurAmount = 0.6   // 0 = no blur, 1 = full system blur
    static let dim = 0.62

    var body: some View {
        ZStack {
            Backdrop(material: .fullScreenUI).opacity(Self.blurAmount)
            Theme.ink.opacity(Self.dim)
        }
    }
}

struct BreakOverlayView: View {
    @ObservedObject var session: BreakSession

    var body: some View {
        ZStack {
            BreakBackground()

            TimelineView(.animation) { ctx in
                let t = max(0, ctx.date.timeIntervalSince(session.stepStart))
                VStack(spacing: 0) {
                    Spacer()
                    if session.isComplete {
                        CompleteContent()
                    } else {
                        StepContent(session: session, t: t)
                    }
                    Spacer()
                    HintBar(session: session, now: ctx.date)
                        .padding(.bottom, 56)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// A thin progress ring with content inside.
private struct Dial<Inner: View>: View {
    let progress: Double
    @ViewBuilder let inner: Inner

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.002, min(1, progress)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            inner
        }
        .frame(width: 196, height: 196)
    }
}

private struct StepContent: View {
    @ObservedObject var session: BreakSession
    let t: TimeInterval

    var body: some View {
        let step = session.step
        let remaining = max(0, step.duration - t)

        VStack(spacing: 36) {
            Dial(progress: t / step.duration) { dialInner(step, remaining: remaining) }

            VStack(spacing: 10) {
                Text(caption(step))
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accent.opacity(0.8))
                Text(title(step))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(detail(step, remaining: remaining))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.steps.count > 1 {
                StepDots(count: session.steps.count, current: session.index)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.index)
    }

    @ViewBuilder private func dialInner(_ step: BreakStep, remaining: TimeInterval) -> some View {
        switch step {
        case .breathe(let pattern):
            BreathingDisc(pattern: pattern, t: t)
        case .eyes:
            SymbolCountdown(symbol: t < BreakStep.eyesLookAway ? "eye" : "eye.slash", remaining: remaining)
        case .stretch(let s, _, _):
            SymbolCountdown(symbol: s.symbol, remaining: remaining)
        }
    }

    private func caption(_ step: BreakStep) -> String {
        switch step {
        case .eyes: "Eyes"
        case .breathe: "Breathe"
        case .stretch(_, let n, let total): "Stretch \(n) of \(total)"
        }
    }

    private func title(_ step: BreakStep) -> String {
        switch step {
        case .eyes: t < BreakStep.eyesLookAway ? "Look far away" : "Blink slowly"
        case .breathe(let p): BreathingDisc.phase(p, t: t).label
        case .stretch(let s, _, _): s.title
        }
    }

    private func detail(_ step: BreakStep, remaining: TimeInterval) -> String {
        switch step {
        case .eyes:
            t < BreakStep.eyesLookAway
                ? "Rest your eyes on something about 6 m (20 ft) away."
                : "Ten slow, gentle blinks."
        case .breathe:
            "Follow the circle · \(Int(ceil(remaining)))s"
        case .stretch(let s, _, _):
            s.instruction
        }
    }
}

private struct SymbolCountdown: View {
    let symbol: String
    let remaining: TimeInterval

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(height: 48)
                .contentTransition(.symbolEffect(.replace))
            Text("\(Int(ceil(remaining)))s")
                .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .contentTransition(.numericText(countsDown: true))
        }
    }
}

private struct BreathingDisc: View {
    let pattern: BreathingPattern
    let t: TimeInterval

    struct Phase { let label: String; let length: Double; let from: Double; let to: Double; let local: Double }

    static func phase(_ pattern: BreathingPattern, t: TimeInterval) -> Phase {
        let small = 0.38, big = 0.92
        let phases: [(String, Double, Double, Double)] = switch pattern {
        case .relaxed: [("Breathe in", 4, small, big), ("Breathe out", 6, big, small)]
        case .box: [("Breathe in", 4, small, big), ("Hold", 4, big, big),
                    ("Breathe out", 4, big, small), ("Hold", 4, small, small)]
        }
        let cycle = phases.reduce(0) { $0 + $1.1 }
        var local = t.truncatingRemainder(dividingBy: cycle)
        for p in phases {
            if local < p.1 { return Phase(label: p.0, length: p.1, from: p.2, to: p.3, local: local) }
            local -= p.1
        }
        let p = phases[0]
        return Phase(label: p.0, length: p.1, from: p.2, to: p.3, local: 0)
    }

    var body: some View {
        let p = Self.phase(pattern, t: t)
        let progress = min(1, p.local / p.length)
        let eased = 0.5 - 0.5 * cos(progress * .pi)
        let scale = p.from + (p.to - p.from) * eased
        Circle()
            .fill(RadialGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0.12)],
                                 center: .center, startRadius: 0, endRadius: 90))
            .overlay(Circle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
            .frame(width: 180, height: 180)
            .scaleEffect(scale)
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Theme.accent.opacity(i == current ? 1 : 0.5) : .white.opacity(0.15))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
    }
}

private struct CompleteContent: View {
    var body: some View {
        VStack(spacing: 36) {
            Dial(progress: 1) {
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.accent)
            }
            VStack(spacing: 10) {
                Text("Nice work")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Back to it, a little lighter.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: Key hints

/// Bottom bar showing what you can do, each with its key. Also clickable.
private struct HintBar: View {
    @ObservedObject var session: BreakSession
    let now: Date

    var body: some View {
        HStack(spacing: 2) {
            if session.isComplete {
                KeyHint(label: "Close", key: "↩", prominent: true, action: session.done)
            } else {
                if session.canSnooze {
                    KeyHint(label: "Later", key: "L", action: session.snooze)
                }
                if session.strict {
                    strictExit
                } else {
                    KeyHint(label: "Skip", key: "esc", action: session.skip)
                }
                if session.canFinishNow {
                    KeyHint(label: session.isLastStep ? "Done" : "Next", key: "↩", prominent: true,
                            action: session.next)
                }
            }
        }
        .padding(4)
        .background(Capsule().fill(.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }

    private var strictExit: some View {
        let held = session.escHoldStart.map { min(1, now.timeIntervalSince($0) / BreakPresenter.escHoldSeconds) } ?? 0
        return HStack(spacing: 8) {
            Text("Hold to exit")
                .font(.system(size: 13, weight: .medium))
            Keycap(key: "esc", prominent: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(.white.opacity(0.7))
        .background(alignment: .leading) {
            GeometryReader { g in
                Capsule().fill(.white.opacity(0.14)).frame(width: g.size.width * held)
            }
        }
        .clipShape(Capsule())
    }
}

private struct KeyHint: View {
    let label: String
    let key: String
    var prominent = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 13, weight: .medium))
                Keycap(key: key, prominent: prominent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? Theme.ink : .white.opacity(0.85))
            .background(Capsule().fill(prominent ? Theme.accent : .white.opacity(hover ? 0.1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct Keycap: View {
    let key: String
    let prominent: Bool

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(prominent ? Theme.ink.opacity(0.12) : .white.opacity(0.1)))
    }
}

// MARK: Nudge (gentle first reminder)

struct NudgeCardView: View {
    let kinds: [BreakKind]
    let canSnooze: Bool
    let canSkip: Bool
    let autoStartAt: Date
    let autoStartAfter: TimeInterval
    let onStart: () -> Void
    let onSnooze: () -> Void
    let onSkip: () -> Void

    private var title: String {
        switch kinds {
        case [.eyes]: "Rest your eyes"
        case [.breathe]: "Time to breathe"
        case [.stretch]: "Time to stretch"
        default: "Time for a short break"
        }
    }

    private var subtitle: String {
        switch kinds {
        case [.eyes]: "Look away for 20 seconds"
        case [.breathe]: "One minute of slow breathing"
        case [.stretch]: "Two minutes to move"
        default: kinds.map(\.title).joined(separator: " + ")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: kinds.count == 1 ? kinds[0].symbol : "leaf")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.accent.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)

                Spacer(minLength: 10)

                HStack(spacing: 2) {
                    if canSkip { SmallButton(title: "Skip", action: onSkip) }
                    if canSnooze { SmallButton(title: "Later", action: onSnooze) }
                    SmallButton(title: "Start", prominent: true, action: onStart)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)

            // Quietly shows when the break will start on its own.
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let left = max(0, autoStartAt.timeIntervalSince(ctx.date)) / autoStartAfter
                GeometryReader { g in
                    Rectangle().fill(Theme.accent.opacity(0.6)).frame(width: g.size.width * left)
                }
            }
            .frame(height: 2)
        }
        .frame(width: 400)
        .background(Backdrop(material: .hudWindow))
        .background(Theme.ink.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private struct SmallButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: prominent ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .foregroundStyle(prominent ? Theme.ink : .white.opacity(hover ? 0.95 : 0.65))
                .background(Capsule().fill(prominent ? Theme.accent : .white.opacity(hover ? 0.1 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// A faint pulse around the screen edge, alongside the nudge card.
struct EdgeGlowView: View {
    @State private var bright = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 2)
            .blur(radius: 6)
            .opacity(bright ? 0.5 : 0.1)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}
