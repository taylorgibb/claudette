import AppKit

final class RegistrationBag: @unchecked Sendable {
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
