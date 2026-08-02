import Foundation
import IOKit.pwr_mgt

/// `IOPMAssertion` wrapper for Caffeine Mode; the display may still sleep.
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

    /// Drops any existing assertion and takes a fresh one.
    ///
    /// Assertions do not reliably survive sleep. Calling `setPreventsSleep(true)`
    /// on wake looks like it re-applies but hits the `assertion == nil` guard
    /// and returns immediately, so a stale ID left the machine free to sleep
    /// with Caffeine Mode still showing as on.
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
