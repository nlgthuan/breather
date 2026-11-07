import SwiftUI

/// Colours for the black notch island.
enum Island {
    static let mint = Color(red: 0.56, green: 0.89, blue: 0.78)
    static let text2 = Color.white.opacity(0.72)
    static let ink = Color(red: 0.04, green: 0.08, blue: 0.09)
}

enum IslandMetrics {
    static let ear: CGFloat = 14          // the concave curves where the island meets the top edge
    static let width: CGFloat = 460       // open island, including ears
    static let breakHeight: CGFloat = 132 // below the menu bar
    static let doneHeight: CGFloat = 70
    static let glow: CGFloat = 30         // room around the island for its glow
    static var windowSize: CGSize { CGSize(width: width + glow * 2, height: 40 + breakHeight + glow) }
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
        let br = min(bottomRadius, (r.height - ear) / 2, (r.width - 2 * ear) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + ear, y: r.minY + ear), control: CGPoint(x: r.minX + ear, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + ear, y: r.maxY - br))
        p.addQuadCurve(to: CGPoint(x: r.minX + ear + br, y: r.maxY), control: CGPoint(x: r.minX + ear, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - ear - br, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - ear, y: r.maxY - br), control: CGPoint(x: r.maxX - ear, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - ear, y: r.minY + ear))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - ear, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var session: BreakSession

    var body: some View {
        let g = model.geometry
        let open = model.expanded
        let width = open ? IslandMetrics.width : g.notchWidth + IslandMetrics.ear * 2
        let height = g.barHeight + (open ? (session.isComplete ? IslandMetrics.doneHeight : IslandMetrics.breakHeight) : 0)
        let shape = NotchShape(bottomRadius: open ? 26 : 10)
        let glow = IslandMetrics.glow

        TimelineView(.animation) { ctx in
            let t = max(0, ctx.date.timeIntervalSince(session.stepStart))
            // A slow glow that breathes in and out around the edge.
            let pulse = 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 2 * .pi / 4)

            ZStack(alignment: .top) {
                // Glow on the sides and bottom only: faded out across the menu bar,
                // so the top edge (where the island meets the screen) stays clean.
                ZStack {
                    shape
                        .stroke(Island.mint, lineWidth: 5)
                        .blur(radius: 10)
                        .opacity(0.4 + 0.45 * pulse)
                    shape
                        .fill(Island.mint.opacity(0.18 + 0.2 * pulse))
                        .blur(radius: 18)
                }
                .frame(width: width, height: height)
                .padding(glow)
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: glow + g.barHeight)
                        LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom).frame(height: 24)
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
                            Color.clear.frame(height: g.barHeight)
                            LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom).frame(height: 24)
                            Color.white
                        }
                    }
                    .opacity(open ? 1 : 0)

                Group {
                    if session.isComplete {
                        CompleteRow(session: session, now: ctx.date)
                    } else {
                        BreakContent(session: session, t: t, now: ctx.date)
                    }
                }
                .padding(.top, g.barHeight + 8)
                .padding(.horizontal, IslandMetrics.ear + 16)
                .padding(.bottom, 14)
                .frame(width: width, height: height, alignment: .top)
                .opacity(open ? 1 : 0)
                .animation(.easeOut(duration: 0.2).delay(open ? 0.15 : 0), value: open)
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
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Orb(step: step, t: t, fraction: t / step.duration)
                VStack(alignment: .leading, spacing: 3) {
                    Text(caption(step))
                        .font(Theme.font(10, .semibold))
                        .kerning(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(Island.mint)
                    Text(title(step))
                        .font(Theme.font(18, .medium))
                    Text(detail(step))
                        .font(Theme.font(12.5))
                        .foregroundStyle(Island.text2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            KeyBar(session: session, now: now)
        }
    }

    private func caption(_ step: BreakStep) -> String {
        let part = session.steps.count > 1 ? " · \(session.index + 1) of \(session.steps.count)" : ""
        switch step {
        case .eyes: return "Eyes · 20 seconds" + part
        case .breathe(let p): return "Breathe · breath \(min(p.breaths, Int(t / p.cycle) + 1)) of \(p.breaths)" + part
        case .stretch: return "Stretch · 2 minutes" + part
        }
    }

    private func title(_ step: BreakStep) -> String {
        switch step {
        case .eyes: t < BreakStep.eyesLookAway ? "Look away now" : "Blink slowly"
        case .breathe(let p): Breath.phase(p, t: t).label
        case .stretch: "Time to stretch"
        }
    }

    private func detail(_ step: BreakStep) -> String {
        switch step {
        case .eyes:
            t < BreakStep.eyesLookAway
                ? "Look at something about 6 m away." + (session.sound ? " A chime means blink." : "")
                : "Ten slow, gentle blinks."
        case .breathe(let p):
            p == .box ? "Follow the circle: in 4, hold 4, out 4, hold 4." : "Follow the circle: in for 4, out for 6."
        case .stretch:
            "Stand up, roll your shoulders, walk a little."
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
            Circle().stroke(.white.opacity(0.14), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.003, min(1, fraction)))
                .stroke(Island.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            switch step {
            case .breathe(let p):
                Circle()
                    .fill(RadialGradient(colors: [Island.mint.opacity(0.8), Island.mint.opacity(0.2)],
                                         center: .center, startRadius: 0, endRadius: 24))
                    .frame(width: 48, height: 48)
                    .scaleEffect(Breath.scale(p, t: t))
            default:
                VStack(spacing: 1) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .regular))
                        .contentTransition(.symbolEffect(.replace))
                    Text(timeLeft)
                        .font(Theme.font(11, .semibold).monospacedDigit())
                }
                .foregroundStyle(Island.mint)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Island.mint.opacity(0.14)))
            }
        }
        .frame(width: 66, height: 66)
    }

    private var symbol: String {
        switch step {
        case .eyes: t < BreakStep.eyesLookAway ? "eye" : "eye.slash"
        case .stretch: "figure.stand"
        case .breathe: "wind"
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Island.mint)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Island.mint.opacity(0.16)))
                .overlay(Circle().stroke(Island.mint, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 2) {
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
        HStack(spacing: 8) {
            if session.canSnooze {
                KeyButton(label: "Later", key: "L", action: session.snooze)
            }
            if session.strict {
                strictExit
            } else {
                KeyButton(label: "Skip", key: "esc", action: session.skip)
            }
            if session.canFinishNow {
                KeyButton(label: session.isLastStep ? "Done" : "Next", key: "↩", prominent: true, action: session.next)
            }
        }
    }

    private var strictExit: some View {
        let held = session.escHoldStart.map { min(1, now.timeIntervalSince($0) / BreakPresenter.escHoldSeconds) } ?? 0
        return HStack(spacing: 8) {
            Text("Hold to exit").font(Theme.font(13, .medium))
            Keycap(key: "esc", prominent: false)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
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
    let key: String
    var prominent = false
    var fill = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(Theme.font(13, prominent ? .semibold : .medium)).fixedSize()
                Keycap(key: key, prominent: prominent)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: 32)
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
