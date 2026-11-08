import AppKit
import SwiftUI

/// Renders each screen to PNG without showing anything, for reviewing the UI:
/// `build/Breather.app/Contents/MacOS/Breather --snapshot <dir>`
@MainActor
enum Snapshots {
    static func run(into dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        func session(_ kinds: [BreakKind], strict: Bool = false, at t: TimeInterval, complete: Bool = false) -> BreakSession {
            let s = BreakSession(kinds: Set(kinds), pattern: .relaxed, strict: strict, sound: true)
            s.preview(elapsed: t, complete: complete)
            return s
        }

        func save<V: View>(_ name: String, _ view: V) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                print("failed: \(name)"); return
            }
            try? png.write(to: url.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }

        /// The island hanging from a fake menu bar, as on a MacBook.
        func island(_ s: BreakSession, reduceMotion: Bool = false) -> some View {
            let model = IslandModel(geometry: NotchGeometry(notchWidth: 200, barHeight: 32, hasNotch: true))
            model.expanded = true
            model.reduceMotion = reduceMotion
            let size = IslandMetrics.windowSize(nudge: s.isNudge)
            return ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.62, green: 0.70, blue: 0.75), Color(red: 0.40, green: 0.49, blue: 0.55)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.5)).frame(height: 32)
                IslandView(model: model, session: s)
            }
            .frame(width: size.width + 200, height: size.height + 40)
        }

        save("eyes", island(session([.eyes], at: 7)))
        save("breathe", island(session([.breathe], at: 22)))
        save("stretch", island(session([.stretch], at: 48)))
        save("hydrate-nudge", island(session([.hydrate], at: 3)))
        save("stretch-hydrate", island(session([.stretch, .hydrate], at: 30)))
        save("strict",island(session([.stretch], strict: true, at: 30)))
        save("eyes-breathe", island(session([.eyes, .breathe], at: 5)))
        save("eyes-water", island(session([.eyes, .hydrate], at: 5)))
        save("breathe-water", island(session([.breathe, .hydrate], at: 5)))
        save("stretch-breathe-water", island(session([.stretch, .breathe, .hydrate, .eyes], at: 30)))
        save("complete", island(session([.eyes], at: 0, complete: true)))
        save("reduce-motion", island(session([.eyes], at: 7), reduceMotion: true))
        // Native controls and scroll views only draw in a real window.
        func saveInWindow<V: View>(_ name: String, _ view: V, dark: Bool) {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = host.fittingSize
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }
        for dark in [false, true] {
            saveInWindow(dark ? "settings-dark" : "settings",
                         SettingsPage(prefs: .shared) {}.padding(18).frame(width: PopoverView.width).background(Theme.panel), dark: dark)
        }
        save("popover", PopoverView(scheduler: .shared, stats: .shared).padding(30).background(Color(white: 0.45)))
        save("popover-dark", PopoverView(scheduler: .shared, stats: .shared).padding(30).background(Color(white: 0.2))
            .environment(\.colorScheme, .dark))
    }
}
