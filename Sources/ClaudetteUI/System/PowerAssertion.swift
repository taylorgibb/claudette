import Foundation
import IOKit.pwr_mgt

@MainActor
final class PowerAssertionManager {
    private var assertion: IOPMAssertionID?

    var isActive: Bool { assertion != nil }

    func setPreventsSleep(_ enabled: Bool) {
        guard enabled else { return release() }
        guard assertion == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Claudette: Caffeine Mode" as CFString,
            &id)
        if result == kIOReturnSuccess { assertion = id }
    }

    func renew(preventsSleep: Bool) {
        release()
        setPreventsSleep(preventsSleep)
    }

    func release() {
        guard let id = assertion else { return }
        IOPMAssertionRelease(id)
        assertion = nil
    }
}
