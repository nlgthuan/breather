import AppKit
import SwiftUI

/// Renders each screen to PNG without showing anything, for reviewing the UI:
/// `build/Breather.app/Contents/MacOS/Breather --snapshot <dir>`
@MainActor
enum Snapshots {
    static func run(into dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let screen = CGSize(width: 1440, height: 900)

        func session(_ kinds: [BreakKind], strict: Bool = false, step: Int = 0, at t: TimeInterval,
                     complete: Bool = false) -> BreakSession {
            let s = BreakSession(kinds: kinds, pattern: .relaxed, strict: strict, canSnooze: true, sound: false)
            s.preview(step: step, elapsed: t, complete: complete)
            return s
        }

        func save<V: View>(_ name: String, _ view: V, size: CGSize? = nil) {
            let content = view.environment(\.snapshotMode, true)
            let renderer: ImageRenderer<AnyView>
            if let size {
                renderer = ImageRenderer(content: AnyView(content.frame(width: size.width, height: size.height)))
            } else {
                renderer = ImageRenderer(content: AnyView(content.padding(40).background(Color(white: 0.3))))
            }
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                print("failed: \(name)"); return
            }
            try? png.write(to: url.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }

        save("eyes", BreakOverlayView(session: session([.eyes], at: 7)), size: screen)
        save("eyes-blink", BreakOverlayView(session: session([.eyes], at: 24)), size: screen)
        save("breathe", BreakOverlayView(session: session([.breathe], at: 2.5)), size: screen)
        save("stretch", BreakOverlayView(session: session([.stretch], step: 1, at: 14)), size: screen)
        save("stretch-strict", BreakOverlayView(session: session([.stretch], strict: true, at: 30)), size: screen)
        save("complete", BreakOverlayView(session: session([.eyes], at: 0, complete: true)), size: screen)
        save("nudge", NudgeCardView(kinds: [.eyes], canSnooze: true, canSkip: true,
                                    autoStartAt: Date().addingTimeInterval(30), autoStartAfter: 45,
                                    onStart: {}, onSnooze: {}, onSkip: {}))
        save("nudge-combined", NudgeCardView(kinds: [.eyes, .breathe], canSnooze: false, canSkip: true,
                                             autoStartAt: Date().addingTimeInterval(10), autoStartAfter: 45,
                                             onStart: {}, onSnooze: {}, onSkip: {}))
    }
}
