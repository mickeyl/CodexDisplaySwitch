import Foundation
import IOKit.pwr_mgt

@MainActor
final class SleepAssertions {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0

    func acquire() -> Bool {
        guard systemID == 0, displayID == 0 else { return true }
        let reason = "External monitors are dark while computer use continues" as CFString
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        let systemResult = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, level, reason, &systemID)
        let displayResult = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, level, reason, &displayID)
        guard systemResult == kIOReturnSuccess, displayResult == kIOReturnSuccess else {
            release()
            return false
        }
        return true
    }

    func release() {
        if systemID != 0 { IOPMAssertionRelease(systemID); systemID = 0 }
        if displayID != 0 { IOPMAssertionRelease(displayID); displayID = 0 }
    }
}
