import AppKit
import SwiftUI

/// Borderless window that can take keyboard focus, so shortcuts work right away.
private final class IslandWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Where the island hangs: around the camera notch on MacBooks, otherwise
/// from the top centre of the screen.
struct NotchGeometry {
    let notchWidth: CGFloat
    let barHeight: CGFloat
    let hasNotch: Bool

    static func of(_ screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return .init(notchWidth: screen.frame.width - left.width - right.width, barHeight: top, hasNotch: true)
        }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        return .init(notchWidth: 180, barHeight: max(bar, 24), hasNotch: false)
    }
}

/// Animation state of the island: collapsed (notch-sized) or open.
@MainActor
final class IslandModel: ObservableObject {
    @Published var expanded = false
    @Published var geometry: NotchGeometry
    init(geometry: NotchGeometry) { self.geometry = geometry }
}

/// Shows breaks in an island that grows out of the notch.
@MainActor
final class BreakPresenter {
    static let escHoldSeconds: TimeInterval = 3

    private var window: NSWindow?
    private var model: IslandModel?
    private var session: BreakSession?
    private var keyMonitor: Any?
    private var escTimer: Timer?
    private var previousApp: NSRunningApplication?
    private var islandDisplay: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    private static var activeScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    // MARK: Show / dismiss

    func showBreak(kinds: [BreakKind], pattern: BreathingPattern, strict: Bool, canSnooze: Bool, sound: Bool,
                   onDone: @escaping () -> Void, onSnooze: @escaping () -> Void, onSkip: @escaping () -> Void) {
        dismissBreak(animated: false)

        let session = BreakSession(kinds: kinds, pattern: pattern, strict: strict, canSnooze: canSnooze, sound: sound)
        session.onDone = onDone
        session.onSnooze = onSnooze
        session.onSkip = onSkip
        self.session = session

        let screen = Self.activeScreen
        islandDisplay = Self.displayID(screen)
        let model = IslandModel(geometry: .of(screen))
        self.model = model

        let w = IslandWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .popUpMenu   // above the menu bar, so it can sit around the notch
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: IslandView(model: model, session: session))
        host.sizingOptions = []
        w.contentView = host
        place(w, on: screen)
        window = w

        // Take keyboard focus so Esc / Return / L work straight away; give it back afterwards.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != getpid() { previousApp = front }
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKey()
        installKeyMonitor()
        session.start()

        // Grow out of the notch on the next frame.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { model.expanded = true }
        }
    }

    func dismissBreak() { dismissBreak(animated: true) }

    private func dismissBreak(animated: Bool) {
        session?.stop()
        session = nil
        escTimer?.invalidate()
        escTimer = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        islandDisplay = nil

        guard let w = window else { return }
        window = nil
        let model = self.model
        self.model = nil
        if animated, let model {
            // Shrink back into the notch, then go.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { model.expanded = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { w.orderOut(nil) }
        } else {
            w.orderOut(nil)
        }
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: Placement

    /// The window is big enough for the open island plus room for its glow,
    /// pinned to the top centre of the screen.
    private func place(_ w: NSWindow, on screen: NSScreen) {
        let size = IslandMetrics.windowSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        w.setFrame(frame, display: true)
        w.contentView?.frame = NSRect(origin: .zero, size: size)
    }

    /// A display was connected, disconnected or changed: keep the island on its
    /// display, or move it to where the mouse is if that display is gone.
    private func screensChanged() {
        guard let w = window, let model, !NSScreen.screens.isEmpty else { return }
        let screen = NSScreen.screens.first { Self.displayID($0) == islandDisplay } ?? Self.activeScreen
        islandDisplay = Self.displayID(screen)
        model.geometry = .of(screen)
        place(w, on: screen)
        w.makeKey()
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
                case 53: // Esc: skip (strict mode: hold it)
                    if isDown, !isRepeat { self.escPressed(session) }
                    if !isDown { self.escReleased(session) }
                case 36, 76: // Return, Enter: done / next
                    if isDown, !isRepeat, session.canFinishNow { session.next() }
                case 37: // L: later
                    if isDown, !isRepeat, session.canSnooze, !session.isComplete { session.snooze() }
                default:
                    return false
                }
                return true
            }
            return handled ? nil : event
        }
    }

    private func escPressed(_ session: BreakSession) {
        if session.isComplete { session.done(); return }
        if !session.strict { session.skip(); return }
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
