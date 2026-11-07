import AppKit
import SwiftUI

// MARK: Theme

/// Soft, light, sage-green theme.
enum Theme {
    static let ink = Color(red: 0.12, green: 0.18, blue: 0.16)        // main text
    static let text2 = Color(red: 0.29, green: 0.35, blue: 0.33)      // body text
    static let text3 = Color(red: 0.36, green: 0.42, blue: 0.40)      // captions
    static let control = Color(red: 0.18, green: 0.25, blue: 0.23)    // secondary button text
    static let accent = Color(red: 0.23, green: 0.46, blue: 0.39)     // buttons, accent text
    static let soft = Color(red: 0.49, green: 0.72, blue: 0.64)       // progress, decoration
    static let frostTop = Color(red: 0.965, green: 0.976, blue: 0.961)
    static let frostBottom = Color(red: 0.933, green: 0.953, blue: 0.937)
    static let panel = Color(red: 0.98, green: 0.984, blue: 0.976)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True when rendering offscreen (ImageRenderer can't draw live blur).
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// Live blur of whatever is behind the window, always in the light appearance.
struct Backdrop: View {
    var material: NSVisualEffectView.Material
    @Environment(\.snapshotMode) private var snapshot

    var body: some View {
        if snapshot {
            LinearGradient(colors: [Color(red: 0.62, green: 0.69, blue: 0.72), Color(red: 0.45, green: 0.53, blue: 0.58)],
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
        v.appearance = NSAppearance(named: .aqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Your desktop at full blur under a light frosted tint: visible, but never readable
/// through the break's text.
struct BreakBackground: View {
    static let tint = 0.6   // 0 = plain blur, 1 = solid frost

    var body: some View {
        ZStack {
            Backdrop(material: .fullScreenUI)
            LinearGradient(colors: [Theme.frostTop.opacity(Self.tint), Theme.frostBottom.opacity(Self.tint + 0.06)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: Full-screen break

struct BreakOverlayView: View {
    @ObservedObject var session: BreakSession

    var body: some View {
        ZStack {
            BreakBackground()

            TimelineView(.animation) { ctx in
                let t = max(0, ctx.date.timeIntervalSince(session.stepStart))
                VStack(spacing: 0) {
                    if !session.isComplete {
                        TopBar(session: session, t: t)
                            .padding(.horizontal, 56)
                            .padding(.top, 40)
                    }
                    Spacer()
                    if session.isComplete {
                        CompleteContent(session: session, now: ctx.date)
                    } else {
                        StepContent(session: session, t: t)
                    }
                    Spacer()
                    HintBar(session: session, now: ctx.date)
                        .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
    }
}

private struct TopBar: View {
    @ObservedObject var session: BreakSession
    let t: TimeInterval

    var body: some View {
        HStack {
            Text(caption)
                .font(Theme.font(14, .semibold))
                .kerning(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            Spacer()
            Text(info)
                .font(Theme.font(14))
                .foregroundStyle(Theme.text3)
        }
    }

    private var caption: String {
        switch session.step {
        case .eyes: "Eyes · 20 seconds"
        case .breathe(let p): p == .box ? "Breathe · box breathing" : "Breathe · longer exhale"
        case .stretch: "Stretch · 2 minutes"
        }
    }

    private var info: String {
        if session.steps.count > 1 { return "Part \(session.index + 1) of \(session.steps.count)" }
        switch session.step {
        case .eyes: return t < BreakStep.eyesLookAway ? "Then 10 slow blinks" : "Almost done"
        case .breathe(let p): return "Breath \(min(p.breaths, Int(t / p.cycle) + 1)) of \(p.breaths)"
        case .stretch: return "Any movement counts"
        }
    }
}

private struct StepContent: View {
    @ObservedObject var session: BreakSession
    let t: TimeInterval

    var body: some View {
        let step = session.step
        let remaining = max(0, step.duration - t)

        Group {
            switch step {
            case .eyes:
                let lookingAway = t < BreakStep.eyesLookAway
                FocusMessage(
                    symbol: lookingAway ? "eye" : "eye.slash",
                    title: lookingAway ? "Look away now" : "Blink slowly",
                    detail: lookingAway
                        ? "Find something about 6 metres away, like a window or a far wall. "
                          + (session.sound ? "You'll hear a soft chime when it's time to blink." : "Come back in 20 seconds.")
                        : "Close your eyes gently, then open them. Ten slow blinks.",
                    fraction: t / step.duration,
                    timeLabel: "\(Int(ceil(remaining)))s")
            case .stretch:
                FocusMessage(
                    symbol: "figure.stand",
                    title: "Time to stretch",
                    detail: "Stand up, roll your shoulders, take a short walk. Whatever feels good.",
                    fraction: t / step.duration,
                    timeLabel: Self.minutes(remaining))
            case .breathe(let pattern):
                BreathingView(pattern: pattern, t: t)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: session.index)
    }

    static func minutes(_ s: TimeInterval) -> String {
        let total = Int(ceil(s))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Icon, title, one line of guidance and a quiet progress bar.
private struct FocusMessage: View {
    let symbol: String
    let title: String
    let detail: String
    let fraction: Double
    let timeLabel: String

    var body: some View {
        VStack(spacing: 28) {
            IconBadge(symbol: symbol, size: 148, iconSize: 60)
            Text(title)
                .font(Theme.font(54, .medium))
            Text(detail)
                .font(Theme.font(21))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 580)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                LinearProgress(fraction: fraction).frame(width: 360)
                Text(timeLabel)
                    .font(Theme.font(16, .medium).monospacedDigit())
                    .foregroundStyle(Theme.text2)
                    .frame(minWidth: 44, alignment: .leading)
            }
            .padding(.top, 12)
        }
    }
}

struct IconBadge: View {
    let symbol: String
    var size: CGFloat = 42
    var iconSize: CGFloat = 18

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: iconSize, weight: .light))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.soft.opacity(0.2)))
            .contentTransition(.symbolEffect(.replace))
    }
}

struct LinearProgress: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.1))
                Capsule().fill(Theme.soft)
                    .frame(width: max(6, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

private struct BreathingView: View {
    let pattern: BreathingPattern
    let t: TimeInterval

    private struct Phase { let label: String; let hint: String; let length: Double; let from: Double; let to: Double }

    private var phases: [Phase] {
        let small = 0.55, big = 1.0
        switch pattern {
        case .relaxed:
            return [.init(label: "Breathe in", hint: "through your nose", length: 4, from: small, to: big),
                    .init(label: "Breathe out", hint: "slowly, all the way", length: 6, from: big, to: small)]
        case .box:
            return [.init(label: "Breathe in", hint: "through your nose", length: 4, from: small, to: big),
                    .init(label: "Hold", hint: "gently", length: 4, from: big, to: big),
                    .init(label: "Breathe out", hint: "slowly", length: 4, from: big, to: small),
                    .init(label: "Hold", hint: "gently", length: 4, from: small, to: small)]
        }
    }

    var body: some View {
        var local = t.truncatingRemainder(dividingBy: pattern.cycle)
        var current = phases[0]
        for p in phases {
            if local < p.length { current = p; break }
            local -= p.length
        }
        let progress = min(1, local / current.length)
        let eased = 0.5 - 0.5 * cos(progress * .pi)
        let scale = current.from + (current.to - current.from) * eased
        let breath = min(pattern.breaths, Int(t / pattern.cycle) + 1)

        return VStack(spacing: 40) {
            ZStack {
                Circle().strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
                    .frame(width: 420, height: 420)
                Circle().strokeBorder(Theme.accent.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .frame(width: 280, height: 280)
                Circle()
                    .fill(RadialGradient(colors: [Theme.soft.opacity(0.5), Theme.soft.opacity(0.14)],
                                         center: .center, startRadius: 0, endRadius: 170))
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
                    .frame(width: 340, height: 340)
                    .scaleEffect(scale)
                VStack(spacing: 8) {
                    Text(current.label).font(Theme.font(36, .medium))
                    Text(current.hint).font(Theme.font(16)).foregroundStyle(Theme.text2)
                }
            }
            .frame(width: 420, height: 420)

            HStack(spacing: 10) {
                ForEach(1...pattern.breaths, id: \.self) { i in
                    Circle()
                        .fill(i < breath ? Theme.accent.opacity(0.45) : i == breath ? Theme.accent : Theme.ink.opacity(0.15))
                        .frame(width: 10, height: 10)
                        .background(Circle().fill(Theme.accent.opacity(i == breath ? 0.18 : 0)).padding(-4))
                }
            }
            .accessibilityLabel("Breath \(breath) of \(pattern.breaths)")

            Text(pattern == .box ? "In 4, hold 4, out 4, hold 4." : "In for 4, out for 6. Let your shoulders drop on each exhale.")
                .font(Theme.font(17))
                .foregroundStyle(Theme.text2)
        }
    }
}

private struct CompleteContent: View {
    @ObservedObject var session: BreakSession
    @ObservedObject private var stats = Stats.shared
    let now: Date

    var body: some View {
        // This break is recorded when the screen closes, so count it in now.
        let today = stats.today
        VStack(spacing: 26) {
            IconBadge(symbol: "checkmark", size: 120, iconSize: 48)
            Text("Nice work").font(Theme.font(48, .medium))
            Text("That's \(today.taken + 1) of \(today.offered + 1) breaks today.")
                .font(Theme.font(19))
                .foregroundStyle(Theme.text2)
        }
    }
}

// MARK: Key hints

/// Bottom bar showing what you can do, each with its key. Also clickable.
private struct HintBar: View {
    @ObservedObject var session: BreakSession
    let now: Date

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                if session.isComplete {
                    KeyHint(label: "Back to work", key: "↩", prominent: true, action: session.done)
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
            .padding(5)
            .background(Capsule().fill(.white.opacity(0.78)))
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.08)))
            .shadow(color: Theme.ink.opacity(0.06), radius: 10, y: 6)

            if session.isComplete, let c = session.completedAt {
                let left = max(1, Int(ceil(BreakSession.autoCloseAfter - now.timeIntervalSince(c))))
                Text("Closes on its own in \(left) second\(left == 1 ? "" : "s")")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.text3)
            }
        }
    }

    private var strictExit: some View {
        let held = session.escHoldStart.map { min(1, now.timeIntervalSince($0) / BreakPresenter.escHoldSeconds) } ?? 0
        return HStack(spacing: 10) {
            Text("Hold to exit").font(Theme.font(15, .medium))
            Keycap(key: "esc", prominent: false)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .foregroundStyle(Theme.control)
        .background(alignment: .leading) {
            GeometryReader { g in
                Capsule().fill(Theme.ink.opacity(0.1)).frame(width: g.size.width * held)
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
            HStack(spacing: 10) {
                Text(label).font(Theme.font(15, prominent ? .semibold : .medium))
                Keycap(key: key, prominent: prominent)
            }
            .padding(.horizontal, prominent ? 20 : 18)
            .frame(minHeight: 44)
            .foregroundStyle(prominent ? Color.white : Theme.control)
            .background(Capsule().fill(prominent ? Theme.accent : Theme.ink.opacity(hover ? 0.06 : 0)))
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
            .font(Theme.font(11, .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(prominent ? Color.white : Theme.text2)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(prominent ? Color.white.opacity(0.2) : Theme.ink.opacity(0.07)))
    }
}

// MARK: Nudge (gentle first reminder)

/// Live state of the reminder card: when it starts on its own, and whether the
/// pointer is over it (which holds the countdown).
@MainActor
final class NudgeModel: ObservableObject {
    @Published var autoStartAt: Date
    @Published var hovered = false
    let total: TimeInterval

    init(autoStartAfter: TimeInterval) {
        total = autoStartAfter
        autoStartAt = Date().addingTimeInterval(autoStartAfter)
    }
}

struct NudgeCardView: View {
    let kinds: [BreakKind]
    let canSnooze: Bool
    let canSkip: Bool
    @ObservedObject var model: NudgeModel
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

    private var length: String {
        let seconds = BreakStep.steps(for: kinds, pattern: Preferences.shared.breathingPattern)
            .reduce(0) { $0 + $1.duration }
        return seconds < 60 ? "\(Int(seconds)) seconds" : seconds < 90 ? "1 minute" : "About \(Int((seconds / 60).rounded())) minutes"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let left = max(0, model.autoStartAt.timeIntervalSince(ctx.date))
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    IconBadge(symbol: kinds.count == 1 ? kinds[0].symbol : "leaf")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(Theme.font(15, .semibold))
                        Text(model.hovered ? "Waiting for you · won't start on its own"
                                           : "\(length) · starts in \(Int(ceil(left)))s")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.text3)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

                HStack(spacing: 6) {
                    if canSkip { CardButton(title: "Skip", action: onSkip) }
                    if canSnooze { CardButton(title: "In 5 min", action: onSnooze) }
                    CardButton(title: "Start now", prominent: true, action: onStart)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

                GeometryReader { g in
                    Rectangle()
                        .fill(Theme.soft.opacity(model.hovered ? 0.35 : 1))
                        .frame(width: model.hovered ? g.size.width : g.size.width * left / model.total)
                }
                .frame(height: 3)
            }
        }
        .frame(width: 420)
        .background(Theme.panel.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(model.hovered ? Theme.accent.opacity(0.45) : Theme.ink.opacity(0.08)))
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
        .onHover { model.hovered = $0 }
    }
}

private struct CardButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(14, prominent ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(prominent ? Color.white : Theme.control)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(prominent ? Theme.accent : Theme.ink.opacity(hover ? 0.11 : 0.06)))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .strokeBorder(Theme.soft, lineWidth: 2)
            .blur(radius: 6)
            .opacity(bright ? 0.55 : 0.1)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}
