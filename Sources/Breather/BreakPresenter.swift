import AppKit
import SwiftUI

/// Borderless window that can take keyboard focus (for Esc / Return).
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the reminder windows: the gentle nudge (edge glow + card) and the
/// full-screen break overlay.
@MainActor
final class BreakPresenter {
    static let escHoldSeconds: TimeInterval = 3

    private var glowWindow: NSWindow?
    private var cardPanel: NSPanel?
    private var overlayWindows: [NSWindow] = []
    private var session: BreakSession?
    private var keyMonitor: Any?
    private var escTimer: Timer?
    private var previousApp: NSRunningApplication?

    private static var activeScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// A hosting view that fills exactly `size` and never resizes its window to fit
    /// its content (by default NSHostingView grows the window, which pushed the
    /// bottom of the break screen off the display).
    private static func fixedHost<V: View>(_ view: V, size: CGSize) -> NSView {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        return host
    }

    // MARK: Nudge

    func showNudge(kinds: [BreakKind], canSnooze: Bool, canSkip: Bool, autoStartAfter: TimeInterval,
                   onStart: @escaping () -> Void, onSnooze: @escaping () -> Void, onSkip: @escaping () -> Void) {
        dismissNudge()

        // Soft glow around the screen edge. Click-through.
        let glow = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        glow.isOpaque = false
        glow.backgroundColor = .clear
        glow.hasShadow = false
        glow.ignoresMouseEvents = true
        glow.level = .statusBar
        glow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        glowWindow = glow

        // Small card in the top-right corner. Non-activating, so it never steals focus.
        let card = NudgeCardView(kinds: kinds, canSnooze: canSnooze, canSkip: canSkip,
                                 autoStartAt: Date().addingTimeInterval(autoStartAfter), autoStartAfter: autoStartAfter,
                                 onStart: onStart, onSnooze: onSnooze, onSkip: onSkip)
        let host = NSHostingView(rootView: card)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.alphaValue = 0
        cardPanel = panel

        nudgeDisplay = Self.displayID(Self.activeScreen)
        placeNudge()
        glow.orderFrontRegardless()
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.4; panel.animator().alphaValue = 1 }
    }

    /// Puts the glow and card on the nudge's display, or on the mouse's display if that one is gone.
    private func placeNudge() {
        guard let panel = cardPanel, !NSScreen.screens.isEmpty else { return }
        let screen = NSScreen.screens.first { Self.displayID($0) == nudgeDisplay } ?? Self.activeScreen
        nudgeDisplay = Self.displayID(screen)

        if let glow = glowWindow {
            glow.contentView = Self.fixedHost(EdgeGlowView(), size: screen.frame.size)
            glow.setFrame(screen.frame, display: true)
        }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 12))
    }

    func dismissNudge() {
        glowWindow?.orderOut(nil)
        glowWindow = nil
        nudgeDisplay = nil
        if let panel = cardPanel {
            cardPanel = nil
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil) })
        }
    }

    // MARK: Full-screen break

    func showBreak(kinds: [BreakKind], pattern: BreathingPattern, strict: Bool, canSnooze: Bool, sound: Bool,
                   onDone: @escaping () -> Void, onSnooze: @escaping () -> Void, onSkip: @escaping () -> Void) {
        dismissBreak()

        let session = BreakSession(kinds: kinds, pattern: pattern, strict: strict, canSnooze: canSnooze, sound: sound)
        session.onDone = onDone
        session.onSnooze = onSnooze
        session.onSkip = onSkip
        self.session = session

        breakDisplay = Self.displayID(Self.activeScreen)
        layoutOverlay(fadeIn: true)

        // Take keyboard focus so Esc / Return work; give it back afterwards.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != getpid() { previousApp = front }
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
        session.start()
    }

    /// Creates one window per connected display: the exercise on `breakDisplay`,
    /// a dimmed background on the others. Replaces any existing overlay windows.
    private func layoutOverlay(fadeIn: Bool) {
        guard let session else { return }
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows = []

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        // Keep the exercise where it was; if that display is gone, move it to where the mouse is.
        let main = screens.first { Self.displayID($0) == breakDisplay } ?? Self.activeScreen
        breakDisplay = Self.displayID(main)

        for screen in screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isReleasedWhenClosed = false
            if screen == main {
                w.contentView = Self.fixedHost(BreakOverlayView(session: session), size: screen.frame.size)
            } else {
                w.contentView = Self.fixedHost(BreakBackground().ignoresSafeArea(), size: screen.frame.size)
            }
            w.setFrame(screen.frame, display: false)
            w.alphaValue = fadeIn ? 0 : 1
            w.orderFrontRegardless()
            overlayWindows.append(w)
            if fadeIn {
                NSAnimationContext.runAnimationGroup { $0.duration = 0.6; w.animator().alphaValue = 1 }
            }
            if screen == main { w.makeKey() }
        }
    }

    // MARK: Display changes

    private var breakDisplay: CGDirectDisplayID?
    private var nudgeDisplay: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    /// A display was connected, disconnected, rearranged or changed resolution.
    func screensChanged() {
        if session != nil { layoutOverlay(fadeIn: false) }
        if cardPanel != nil { placeNudge() }
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    func dismissBreak() {
        session?.stop()
        session = nil
        breakDisplay = nil
        escTimer?.invalidate()
        escTimer = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        let windows = overlayWindows
        overlayWindows = []
        guard !windows.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            for w in windows { w.animator().alphaValue = 0 }
        }, completionHandler: {
            for w in windows { w.orderOut(nil) }
        })
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: Keys

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let code = event.keyCode
            let isDown = event.type == .keyDown
            let isRepeat = isDown && event.isARepeat
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let session = self.session else { return false }
                switch code {
                case 53: // Esc
                    if isDown, !isRepeat { self.escPressed(session) }
                    if !isDown { self.escReleased(session) }
                case 36, 76: // Return, Enter: done
                    if isDown, !isRepeat, session.canFinishNow { session.next() }
                case 37: // L: later
                    if isDown, !isRepeat, session.canSnooze, !session.isComplete { session.snooze() }
                default:
                    break // swallow typing while on a break
                }
                return true
            }
            return handled ? nil : event
        }
    }

    private func escPressed(_ session: BreakSession) {
        if session.isComplete { session.done(); return }
        if !session.strict { session.skip(); return }
        // Strict mode: emergency exit needs Esc held down.
        session.escHoldStart = Date()
        escTimer?.invalidate()
        let t = Timer(timeInterval: Self.escHoldSeconds, repeats: false) { [weak session] _ in
            MainActor.assumeIsolated { session?.skip() }
        }
        RunLoop.main.add(t, forMode: .common)
        escTimer = t
    }

    private func escReleased(_ session: BreakSession) {
        escTimer?.invalidate()
        escTimer = nil
        session.escHoldStart = nil
    }
}
