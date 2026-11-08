import AppKit
import SwiftUI

/// Soft sage-green theme (menu bar popover and settings), light or dark with the system.
enum Theme {
    static let ink = adaptive(light: (0.12, 0.18, 0.16), dark: (0.91, 0.95, 0.93))    // main text
    static let text2 = adaptive(light: (0.29, 0.35, 0.33), dark: (0.74, 0.80, 0.77))  // body text
    static let text3 = adaptive(light: (0.36, 0.42, 0.40), dark: (0.60, 0.67, 0.64))  // captions
    static let accent = adaptive(light: (0.23, 0.46, 0.39), dark: (0.56, 0.86, 0.75)) // accent text
    static let soft = adaptive(light: (0.49, 0.72, 0.64), dark: (0.42, 0.70, 0.61))   // progress, decoration
    static let panel = adaptive(light: (0.98, 0.984, 0.976), dark: (0.11, 0.135, 0.125))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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
