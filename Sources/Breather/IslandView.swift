import SwiftUI

/// Colours for the black notch island.
enum Island {
    static let mint = Color(red: 0.56, green: 0.89, blue: 0.78)
    static let text2 = Color.white.opacity(0.72)
    static let ink = Color(red: 0.04, green: 0.08, blue: 0.09)
}

enum IslandMetrics {
    static let ear: CGFloat = 6           // the small concave fillets where the notch meets the top edge
    static let width: CGFloat = 640       // open island, including ears
    static let breakHeight: CGFloat = 68  // below the menu bar: one row
    static let doneHeight: CGFloat = 68
    static let nudgeWidth: CGFloat = 420  // water nudge: smaller and quieter
    static let nudgeHeight: CGFloat = 52
    static let glow: CGFloat = 30         // room around the island for its glow
    static func windowSize(nudge: Bool) -> CGSize {
        nudge ? CGSize(width: nudgeWidth + glow * 2, height: 40 + nudgeHeight + glow)
              : CGSize(width: width + glow * 2, height: 40 + breakHeight + glow)
    }
}

/// The island's outline: flush with the top of the screen, curving out into the
/// menu bar at the top corners like the notch does, rounded at the bottom.
struct NotchShape: Shape {
    var ear: CGFloat = IslandMetrics.ear
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in r: CGRect) -> Path {
        let br = max(0, min(bottomRadius, r.height - ear, (r.width - 2 * ear) / 2))
        let left = r.minX + ear, right = r.maxX - ear
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        // Circular fillets (true arcs, like the notch's), then the rounded bottom.
        p.addArc(tangent1End: CGPoint(x: left, y: r.minY), tangent2End: CGPoint(x: left, y: r.maxY), radius: ear)
        p.addArc(tangent1End: CGPoint(x: left, y: r.maxY), tangent2End: CGPoint(x: right, y: r.maxY), radius: br)
        p.addArc(tangent1End: CGPoint(x: right, y: r.maxY), tangent2End: CGPoint(x: right, y: r.minY), radius: br)
        p.addArc(tangent1End: CGPoint(x: right, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: ear)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var session: BreakSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || model.forceReduceMotion }

    var body: some View {
        let g = model.geometry
        let open = model.expanded
        let nudge = session.isNudge
        let openWidth = nudge ? IslandMetrics.nudgeWidth : IslandMetrics.width
        let openHeight = nudge ? IslandMetrics.nudgeHeight
            : session.isComplete ? IslandMetrics.doneHeight : IslandMetrics.breakHeight
        let width = open ? openWidth : g.notchWidth + IslandMetrics.ear * 2
        let height = g.barHeight + (open ? openHeight : 0)
        let shape = NotchShape(bottomRadius: open ? (nudge ? 20 : 24) : 9)
        let glow = IslandMetrics.glow

        TimelineView(.animation) { ctx in
            let t = max(0, ctx.date.timeIntervalSince(session.stepStart))
            // A slow glow that breathes in and out around the edge.
            // Reduce Motion: hold it still. A nudge glows more faintly.
            let pulse = (reduceMotion ? 0.6 : 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 2 * .pi / 4))
                * (nudge ? 0.6 : 1)

            ZStack(alignment: .top) {
                // Glow on the sides and bottom only: faded out across the menu bar,
                // so the top edge (where the island meets the screen) stays clean.
                ZStack {
                    shape
                        .stroke(Island.mint, lineWidth: 6)
                        .blur(radius: 9)
                        .opacity(0.5 + 0.45 * pulse)
                    shape
                        .fill(Island.mint.opacity(0.25 + 0.25 * pulse))
                        .blur(radius: 16)
                }
                .frame(width: width, height: height)
                .padding(glow)
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: glow + g.barHeight * 0.6)
                        LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom).frame(height: 18)
                        Color.white
                    }
                }
                .padding(-glow)
                .opacity(open ? 1 : 0)

                shape.fill(Color.black)
                shape
                    .stroke(Island.mint.opacity(0.3 + 0.3 * pulse), lineWidth: 1)
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: g.barHeight * 0.6)
                            LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom).frame(height: 18)
                            Color.white
                        }
                    }
                    .opacity(open ? 1 : 0)

                Group {
                    if nudge {
                        NudgeRow(session: session, now: ctx.date)
                    } else if session.isComplete {
                        CompleteRow(session: session, now: ctx.date)
                    } else {
                        BreakContent(session: session, t: t, now: ctx.date)
                    }
                }
                .padding(.top, g.barHeight + (nudge ? 2 : 4))
                .padding(.horizontal, IslandMetrics.ear + (nudge ? 12 : 16))
                .padding(.bottom, nudge ? 10 : 12)
                .frame(width: width, height: height, alignment: .top)
                .opacity(open ? 1 : 0)
                .animation(.easeOut(duration: 0.2).delay(open && !reduceMotion ? 0.15 : 0), value: open)
            }
            .frame(width: width, height: height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: Break

private struct BreakContent: View {
    @ObservedObject var session: BreakSession
    let t: TimeInterval
    let now: Date

    var body: some View {
        let step = session.step
        HStack(spacing: 12) {
            Orb(step: step, t: t, fraction: t / step.duration)
            VStack(alignment: .leading, spacing: 1) {
                Text(caption(step))
                    .font(Theme.font(9.5, .semibold))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Island.mint)
                Text(title(step))
                    .font(Theme.font(16, .medium))
                Text(detail(step))
                    .font(Theme.font(12))
                    .foregroundStyle(Island.text2)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            KeyBar(session: session, now: now)
        }
    }

    private func caption(_ step: BreakStep) -> String {
        let part = session.steps.count > 1 ? " · \(session.index + 1) of \(session.steps.count)" : ""
        switch step {
        case .eyes: return "Eyes · 20 seconds" + part
        case .breathe(let p): return "Breathe · breath \(min(p.breaths, Int(t / p.cycle) + 1)) of \(p.breaths)" + part
        case .stretch: return "Stretch · 2 minutes" + part
        case .hydrate: return "Water · a few sips" + part
        }
    }

    private func title(_ step: BreakStep) -> String {
        switch step {
        case .eyes: t < BreakStep.eyesLookAway ? "Look away now" : "Blink slowly"
        case .breathe(let p): Breath.phase(p, t: t).label
        case .stretch: "Time to stretch"
        case .hydrate: "Drink some water"
        }
    }

    private func detail(_ step: BreakStep) -> String {
        switch step {
        case .eyes:
            t < BreakStep.eyesLookAway
                ? (session.sound ? "About 6 m away. A chime means blink." : "Something about 6 m away.")
                : "Ten slow, gentle blinks."
        case .breathe(let p):
            p == .box ? "In 4, hold 4, out 4, hold 4." : "In for 4, out for 6."
        case .stretch:
            "Stand up, roll your shoulders."
        case .hydrate:
            "No glass nearby? Go fill one up."
        }
    }
}

/// Progress ring with the step's icon and time left, or a breathing disc.
private struct Orb: View {
    let step: BreakStep
    let t: TimeInterval
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.003, min(1, fraction)))
                .stroke(Island.mint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            switch step {
            case .breathe(let p):
                Circle()
                    .fill(RadialGradient(colors: [Island.mint.opacity(0.8), Island.mint.opacity(0.2)],
                                         center: .center, startRadius: 0, endRadius: 18))
                    .frame(width: 36, height: 36)
                    .scaleEffect(Breath.scale(p, t: t))
            default:
                VStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                    Text(timeLeft)
                        .font(Theme.font(10, .semibold).monospacedDigit())
                }
                .foregroundStyle(Island.mint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Island.mint.opacity(0.14)))
            }
        }
        .frame(width: 48, height: 48)
    }

    private var symbol: String {
        switch step {
        case .eyes: t < BreakStep.eyesLookAway ? "eye" : "eye.slash"
        case .stretch: "figure.stand"
        case .breathe: "wind"
        case .hydrate: "drop.fill"
        }
    }

    private var timeLeft: String {
        let s = Int(ceil(max(0, step.duration - t)))
        return s >= 60 ? String(format: "%d:%02d", s / 60, s % 60) : "\(s)s"
    }
}

enum Breath {
    struct Phase { let label: String; let length: Double; let from: Double; let to: Double; let local: Double }

    static func phase(_ pattern: BreathingPattern, t: TimeInterval) -> Phase {
        let small = 0.5, big = 1.0
        let phases: [(String, Double, Double, Double)] = switch pattern {
        case .relaxed: [("Breathe in", 4, small, big), ("Breathe out", 6, big, small)]
        case .box: [("Breathe in", 4, small, big), ("Hold", 4, big, big),
                    ("Breathe out", 4, big, small), ("Hold", 4, small, small)]
        }
        var local = t.truncatingRemainder(dividingBy: pattern.cycle)
        for p in phases {
            if local < p.1 { return Phase(label: p.0, length: p.1, from: p.2, to: p.3, local: local) }
            local -= p.1
        }
        let p = phases[0]
        return Phase(label: p.0, length: p.1, from: p.2, to: p.3, local: 0)
    }

    static func scale(_ pattern: BreathingPattern, t: TimeInterval) -> Double {
        let p = phase(pattern, t: t)
        let eased = 0.5 - 0.5 * cos(min(1, p.local / p.length) * .pi)
        return p.from + (p.to - p.from) * eased
    }
}

// MARK: Water nudge

/// One quiet row: no keyboard focus, closes by itself.
private struct NudgeRow: View {
    @ObservedObject var session: BreakSession
    let now: Date

    var body: some View {
        let fraction = min(1, max(0, now.timeIntervalSince(session.stepStart) / BreakSession.nudgeDuration))
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Island.mint.opacity(0.14))
                // Time until it slides away.
                Circle()
                    .trim(from: 0, to: 1 - fraction)
                    .stroke(Island.mint.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Island.mint)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("Time for some water").font(Theme.font(14, .medium))
                Text("A few sips")
                    .font(Theme.font(11.5))
                    .foregroundStyle(Island.text2)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            KeyButton(label: "Done", key: nil, prominent: true, fill: false, action: session.done)
        }
    }
}

// MARK: Finished

private struct CompleteRow: View {
    @ObservedObject var session: BreakSession
    @ObservedObject private var stats = Stats.shared
    let now: Date

    var body: some View {
        // This break is recorded when the island closes, so count it in now.
        let today = stats.today
        let left = session.completedAt.map { max(1, Int(ceil(BreakSession.autoCloseAfter - now.timeIntervalSince($0)))) } ?? 0
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Island.mint)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Island.mint.opacity(0.16)))
                .overlay(Circle().stroke(Island.mint, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 1) {
                Text("Nice work").font(Theme.font(16, .medium))
                Text("\(today.taken + 1) of \(today.offered + 1) today · closing in \(left)s")
                    .font(Theme.font(12))
                    .foregroundStyle(Island.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            KeyButton(label: "Back to work", key: "↩", prominent: true, fill: false, action: session.done)
        }
    }
}

// MARK: Keys

private struct KeyBar: View {
    @ObservedObject var session: BreakSession
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            if session.canSnooze {
                KeyButton(label: "Later", key: "L", fill: false, action: session.snooze)
            }
            if session.strict {
                strictExit
            } else {
                KeyButton(label: "Skip", key: "esc", fill: false, action: session.skip)
            }
            if session.canFinishNow {
                KeyButton(label: session.isLastStep ? "Done" : "Next", key: "↩", prominent: true, fill: false,
                          action: session.next)
            }
        }
        .fixedSize()
    }

    private var strictExit: some View {
        let held = session.escHoldStart.map { min(1, now.timeIntervalSince($0) / BreakPresenter.escHoldSeconds) } ?? 0
        return HStack(spacing: 8) {
            Text("Hold to exit").font(Theme.font(13, .medium))
            Keycap(key: "esc", prominent: false)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 32)
        .foregroundStyle(.white.opacity(0.85))
        .background(Capsule().fill(.white.opacity(0.1)))
        .background(alignment: .leading) {
            GeometryReader { g in Capsule().fill(.white.opacity(0.16)).frame(width: g.size.width * held) }
        }
        .clipShape(Capsule())
    }
}

private struct KeyButton: View {
    let label: String
    let key: String?
    var prominent = false
    var fill = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(Theme.font(13, prominent ? .semibold : .medium)).fixedSize()
                if let key { Keycap(key: key, prominent: prominent) }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: key == nil ? 28 : 32)
            .foregroundStyle(prominent ? Island.ink : .white)
            .background(Capsule().fill(prominent ? Island.mint : .white.opacity(hover ? 0.16 : 0.1)))
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
            .font(Theme.font(10, .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(prominent ? Island.ink.opacity(0.12) : .white.opacity(0.12)))
    }
}
