import AppKit

/// Holds registrations — event monitors, notification observers — and undoes
/// them when its owner is deallocated.
///
/// A separate object because `deinit` on a `@MainActor` type is itself
/// nonisolated and so cannot reach the isolated stored properties it would
/// need to clean up. Owning them here moves the teardown somewhere `deinit`
/// can legally reach.
///
/// These registrations are process-wide. Leaking a `.mouseMoved` monitor means
/// waking this process on every pointer movement anywhere on the system, for
/// as long as it runs.
final class RegistrationBag: @unchecked Sendable {
    // Only ever mutated from the main actor. `deinit` reads it once, after the
    // last reference is gone and nothing else can be touching it.
    private var handles: [Any] = []
    private let unregister: @Sendable @MainActor (Any) -> Void

    private init(unregister: @escaping @Sendable @MainActor (Any) -> Void) {
        self.unregister = unregister
    }

    static func eventMonitors() -> RegistrationBag {
        RegistrationBag { NSEvent.removeMonitor($0) }
    }

    static func observers(of center: NotificationCenter) -> RegistrationBag {
        RegistrationBag { center.removeObserver($0) }
    }

    func add(_ handle: Any?) {
        guard let handle else { return }
        handles.append(handle)
    }

    func removeAll() {
        let taken = handles
        handles = []
        guard !taken.isEmpty else { return }
        let unregister = self.unregister
        // Both `removeMonitor` and `removeObserver` want the main thread, and
        // `deinit` can run anywhere.
        Task { @MainActor in
            for handle in taken {
                unregister(handle)
            }
        }
    }

    deinit {
        removeAll()
    }
}
