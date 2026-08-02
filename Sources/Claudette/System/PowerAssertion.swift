import Foundation
import IOKit.pwr_mgt

/// IOPMAssertion wrapper for the two keep-awake modes. Assertion IDs are
/// held so they can be released on toggle-off and at termination, and
/// re-asserted after wake.
@MainActor
final class PowerAssertionManager {
    private var systemAssertion: IOPMAssertionID?
    private var displayAssertion: IOPMAssertionID?

    var isAnyActive: Bool {
        systemAssertion != nil || displayAssertion != nil
    }

    func apply(preventSystemSleep: Bool, preventDisplaySleep: Bool) {
        setAssertion(
            &systemAssertion,
            enabled: preventSystemSleep,
            type: kIOPMAssertionTypePreventUserIdleSystemSleep,
            reason: "Claudette: prevent system sleep")
        setAssertion(
            &displayAssertion,
            enabled: preventDisplaySleep,
            type: kIOPMAssertionTypeNoDisplaySleep,
            reason: "Claudette: prevent display sleep")
    }

    func releaseAll() {
        apply(preventSystemSleep: false, preventDisplaySleep: false)
    }

    private func setAssertion(
        _ slot: inout IOPMAssertionID?,
        enabled: Bool,
        type: String,
        reason: String
    ) {
        if enabled {
            guard slot == nil else { return }
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id)
            if result == kIOReturnSuccess {
                slot = id
            }
        } else if let id = slot {
            IOPMAssertionRelease(id)
            slot = nil
        }
    }
}
