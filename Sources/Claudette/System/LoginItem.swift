import Foundation
import ServiceManagement

enum LoginItem {
    /// `SMAppService` returns `.requiresApproval` when the user must confirm
    /// in System Settings; silently ignoring that is a common bug, so the
    /// settings UI surfaces it with a deep link.
    @MainActor
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @MainActor
    static func set(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Dev builds outside an app bundle can't register; nothing to do.
            NSLog("Claudette: login item change failed: \(error.localizedDescription)")
        }
    }
}
