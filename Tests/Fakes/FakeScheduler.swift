import Foundation
@testable import ModernMac

/// A clock the test moves by hand.
@MainActor
final class FakeScheduler: HUDScheduling {
    private final class Entry: HUDCancellable {
        let fireTime: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false

        init(fireTime: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.fireTime = fireTime
            self.action = action
        }

        func cancel() { isCancelled = true }
    }

    private(set) var now: TimeInterval = 0
    private var entries: [Entry] = []

    /// Timers that are scheduled and not cancelled.
    var pendingCount: Int { entries.filter { !$0.isCancelled }.count }

    func schedule(
        after delay: TimeInterval, _ action: @escaping @MainActor () -> Void
    ) -> any HUDCancellable {
        let entry = Entry(fireTime: now + delay, action: action)
        entries.append(entry)
        return entry
    }

    /// Moves time forward, firing due timers in order.
    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let next = entries
            .filter({ !$0.isCancelled && $0.fireTime <= target + 1e-9 })
            .min(by: { $0.fireTime < $1.fireTime })
        {
            now = max(now, next.fireTime)
            entries.removeAll { $0 === next }
            next.action()
        }
        entries.removeAll { $0.isCancelled }
        now = target
    }
}
