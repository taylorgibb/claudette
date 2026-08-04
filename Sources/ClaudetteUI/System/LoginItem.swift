import Foundation
import ServiceManagement

enum LoginItem {
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
            NSLog("Claudette: login item change failed: \(error.localizedDescription)")
        }
    }
}
