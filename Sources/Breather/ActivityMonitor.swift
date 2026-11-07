import AppKit
import IOKit

/// Tracks whether the user is at the computer: keyboard/mouse idle time,
/// screen lock and sleep.
@MainActor
final class ActivityMonitor {
    /// Set while the screen is locked or the Mac is asleep.
    private(set) var awaySince: Date?
    /// Called when the user comes back, with how long they were away.
    var onReturn: ((TimeInterval) -> Void)?

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let dnc = DistributedNotificationCenter.default()
        let wnc = NSWorkspace.shared.notificationCenter

        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ away: Bool) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { away ? self?.wentAway() : self?.cameBack() }
            }
            observers.append((center, token))
        }
        observe(dnc, .init("com.apple.screenIsLocked"), true)
        observe(dnc, .init("com.apple.screenIsUnlocked"), false)
        observe(wnc, NSWorkspace.willSleepNotification, true)
        observe(wnc, NSWorkspace.didWakeNotification, false)
        observe(wnc, NSWorkspace.screensDidSleepNotification, true)
        observe(wnc, NSWorkspace.screensDidWakeNotification, false)
    }

    var isAway: Bool { awaySince != nil }

    private func wentAway() {
        if awaySince == nil { awaySince = Date() }
    }

    private func cameBack() {
        guard let since = awaySince else { return }
        awaySince = nil
        onReturn?(Date().timeIntervalSince(since))
    }

    /// Seconds since the last keyboard, mouse or trackpad event (system-wide).
    /// Reads IOKit's HIDIdleTime, which needs no special permission.
    func idleSeconds() -> TimeInterval {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return 0 }
        return value.doubleValue / 1_000_000_000
    }
}
