import AppKit

/// Polling is suspended while the screen is locked or asleep and refreshed
/// immediately on wake/unlock.
@MainActor
final class SleepWakeObserver {
    private let onSleep: @MainActor () -> Void
    private let onWake: @MainActor () -> Void
    private var tokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []

    init(onSleep: @escaping @MainActor () -> Void, onWake: @escaping @MainActor () -> Void) {
        self.onSleep = onSleep
        self.onWake = onWake

        let workspace = NSWorkspace.shared.notificationCenter
        let sleepNames: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
        ]
        let wakeNames: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
        ]
        for name in sleepNames {
            tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onSleep() }
            })
        }
        for name in wakeNames {
            tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onWake() }
            })
        }

        let distributed = DistributedNotificationCenter.default()
        distributedTokens.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSleep() }
        })
        distributedTokens.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake() }
        })
    }
}
