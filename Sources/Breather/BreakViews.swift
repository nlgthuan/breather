import SwiftUI

/// Soft, light, sage-green theme (menu bar popover and settings).
enum Theme {
    static let ink = Color(red: 0.12, green: 0.18, blue: 0.16)        // main text
    static let text2 = Color(red: 0.29, green: 0.35, blue: 0.33)      // body text
    static let text3 = Color(red: 0.36, green: 0.42, blue: 0.40)      // captions
    static let accent = Color(red: 0.23, green: 0.46, blue: 0.39)     // accent text
    static let soft = Color(red: 0.49, green: 0.72, blue: 0.64)       // progress, decoration
    static let panel = Color(red: 0.98, green: 0.984, blue: 0.976)

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
