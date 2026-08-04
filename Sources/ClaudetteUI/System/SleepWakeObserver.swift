import AppKit

@MainActor
final class SleepWakeObserver {
    private let onSleep: @MainActor () -> Void
    private let onWake: @MainActor () -> Void
    private let workspaceObservers = RegistrationBag.observers(
        of: NSWorkspace.shared.notificationCenter)
    private let distributedObservers = RegistrationBag.observers(
        of: DistributedNotificationCenter.default())

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
            workspaceObservers.add(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onSleep() }
                })
        }
        for name in wakeNames {
            workspaceObservers.add(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onWake() }
                })
        }

        let distributed = DistributedNotificationCenter.default()
        distributedObservers.add(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSleep() }
        })
        distributedObservers.add(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake() }
        })
    }
}
