import XCTest
import AppKit
import ClaudetteCore
@testable import ClaudetteUI

@MainActor
final class IslandLayoutTests: XCTestCase {
    private func geometry(notchWidth: CGFloat = 180, notchHeight: CGFloat = 32) -> NotchGeometry {
        NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchMinX: 666,
            notchWidth: notchWidth,
            notchHeight: notchHeight)
    }

    func testCollapsedBarStraddlesTheNotch() {
        let layout = IslandLayout(geometry: geometry())
        XCTAssertEqual(layout.collapsedSize.width, 180 + Layout.pillWidth * 2)
        XCTAssertEqual(layout.collapsedSize.height, Layout.collapsedHeight)
        XCTAssertEqual(
            IslandLayout(geometry: geometry(notchHeight: 24)).collapsedSize.height,
            Layout.collapsedHeight)
    }

    func testExpandedHeightPrefersWhatThePanelMeasured() {
        let estimated = IslandLayout(geometry: geometry())
        XCTAssertEqual(estimated.expandedSize.height, 32 + Layout.estimatedPanelBodyHeight)

        let measured = IslandLayout(geometry: geometry(), measuredPanelHeight: 217)
        XCTAssertEqual(measured.expandedSize.height, 217)
    }

    func testExpandedWidthNeverDropsBelowThePanelWidth() {
        let layout = IslandLayout(geometry: geometry(notchWidth: 40))
        XCTAssertEqual(layout.expandedSize.width, Layout.panelWidth)
    }

    func testSizeForModeMatchesTheNamedSizes() {
        let layout = IslandLayout(geometry: geometry(), measuredPanelHeight: 200)
        XCTAssertEqual(layout.size(for: .collapsed), layout.collapsedSize)
        XCTAssertEqual(layout.size(for: .panel), layout.expandedSize)
    }
}

final class FormatTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPercentIsAlwaysRemaining() {
        XCTAssertEqual(Format.percentRemaining(LimitWindow(percentUsed: 17, resetsAt: nil)), "83%")
        XCTAssertEqual(Format.percentRemaining(LimitWindow(percentUsed: 0, resetsAt: nil)), "100%")
        XCTAssertEqual(Format.percentRemaining(LimitWindow(percentUsed: 100, resetsAt: nil)), "0%")
        XCTAssertEqual(Format.percentRemaining(nil), "–")
    }

    func testCountdownShrinksItsUnitsAsItCloses() {
        func countdown(_ seconds: TimeInterval) -> String {
            Format.compactCountdown(to: now.addingTimeInterval(seconds), from: now)
        }
        XCTAssertEqual(countdown(2 * 86_400 + 21 * 3600), "2D21H")
        XCTAssertEqual(countdown(3600 + 50 * 60), "1H50M")
        XCTAssertEqual(countdown(45 * 60), "45M")
        XCTAssertEqual(countdown(-5), "NOW")
        XCTAssertEqual(Format.compactCountdown(to: nil, from: now), "")
    }

    func testCountdownSpacingIsOptional() {
        let date = now.addingTimeInterval(3600 + 50 * 60)
        XCTAssertEqual(Format.compactCountdown(to: date, from: now, spaced: false), "1H50M")
        XCTAssertEqual(Format.compactCountdown(to: date, from: now, spaced: true), "1H 50M")
    }

    func testAgo() {
        XCTAssertEqual(Format.ago(nil, from: now), "Never synced")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-30), from: now), "Synced just now")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-600), from: now), "Synced 10m ago")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-7200), from: now), "Synced 2h ago")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-5 * 86_400), from: now), "Synced 5d ago")
    }

    func testTokenAbbreviations() {
        XCTAssertEqual(Format.tokens(999), "999")
        XCTAssertEqual(Format.tokens(1_500), "1.5K")
        XCTAssertEqual(Format.tokens(2_000_000), "2.0M")
        XCTAssertEqual(Format.tokens(3_500_000_000), "3.50B")
    }

    func testOrdinalDaysIncludingTheTeens() {
        func ordinal(_ day: Int) -> String {
            Format.ordinalDay(DayKey(year: 2026, month: 8, day: day))
        }
        XCTAssertEqual(ordinal(1), "1st")
        XCTAssertEqual(ordinal(2), "2nd")
        XCTAssertEqual(ordinal(3), "3rd")
        XCTAssertEqual(ordinal(4), "4th")
        XCTAssertEqual(ordinal(11), "11th")
        XCTAssertEqual(ordinal(12), "12th")
        XCTAssertEqual(ordinal(13), "13th")
        XCTAssertEqual(ordinal(21), "21st")
        XCTAssertEqual(ordinal(22), "22nd")
    }

    func testModelLabelRaisesTheFirstLetterOnlyWhenItNeedsIt() {
        XCTAssertEqual(Format.modelLabel("Fable"), "Fable")
        XCTAssertEqual(Format.modelLabel("opus"), "Opus")
        XCTAssertEqual(Format.modelLabel(""), "")
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1", than: "1.2"), "missing components are zero")
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1.9", than: "1.2.0"))
    }

    func testDevBuildsAreNeverBehind() {
        XCTAssertFalse(UpdateChecker.isNewer("99.0.0", than: "dev"))
    }
}
