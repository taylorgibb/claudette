import XCTest
@testable import ClaudetteCore

final class CostReportTests: XCTestCase {
    private let prices = PriceTable(models: ["m": ModelPrice(inputPerMillion: 1_000_000, outputPerMillion: 1_000_000)])

    private func dayKey(daysAgo: Int, from now: Date) -> DayKey {
        DayKey(Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!)
    }

    func testWindowExcludesOldDaysAndZeroFills() {
        let now = Date()
        let days: [DayKey: [ModelID: TokenTally]] = [
            dayKey(daysAgo: 0, from: now): ["m": TokenTally(input: 3)],
            dayKey(daysAgo: 29, from: now): ["m": TokenTally(input: 2)],
            dayKey(daysAgo: 40, from: now): ["m": TokenTally(input: 500)],
        ]
        let report = CostReport.build(dailyTallies: days, prices: prices, spanDays: 30, now: now)
        XCTAssertEqual(report.days.count, 30)
        XCTAssertEqual(report.totalDollars, 5, accuracy: 1e-9)
        XCTAssertEqual(report.days.last?.dollars ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(report.days.first?.dollars ?? 0, 2, accuracy: 1e-9)
        // Zero-filled middle.
        XCTAssertEqual(report.days[10].dollars, 0)
    }

    func testModelSharesSumToOne() {
        let now = Date()
        let table = PriceTable(models: [
            "a": ModelPrice(inputPerMillion: 1_000_000, outputPerMillion: 0),
            "b": ModelPrice(inputPerMillion: 1_000_000, outputPerMillion: 0),
        ])
        let days = [dayKey(daysAgo: 1, from: now): [
            "a": TokenTally(input: 75),
            "b": TokenTally(input: 25),
        ]]
        let report = CostReport.build(dailyTallies: days, prices: table, now: now)
        XCTAssertEqual(report.models[0].model, "a")
        XCTAssertEqual(report.models[0].costShare, 0.75, accuracy: 1e-9)
        XCTAssertEqual(report.models.map(\.costShare).reduce(0, +), 1.0, accuracy: 1e-9)
    }

    func testComparisonMultipleAndBreakEven() {
        let now = Date()
        // $10/day for 30 days against a $100 subscription.
        var days: [DayKey: [ModelID: TokenTally]] = [:]
        for back in 0..<30 {
            days[dayKey(daysAgo: back, from: now)] = ["m": TokenTally(input: 10)]
        }
        let report = CostReport.build(dailyTallies: days, prices: prices, now: now)
        XCTAssertEqual(report.totalDollars, 300, accuracy: 1e-6)

        let comparison = CostComparison(report: report, monthlyPrice: 100)
        XCTAssertEqual(comparison.subscriptionMultiple ?? 0, 3.0, accuracy: 1e-9)
        // Crosses $100 on the 10th day of the window.
        XCTAssertEqual(comparison.breakEvenDay, report.days[9].key)
    }

    func testComparisonNeverCrossing() {
        let now = Date()
        let days = [dayKey(daysAgo: 0, from: now): ["m": TokenTally(input: 5)]]
        let report = CostReport.build(dailyTallies: days, prices: prices, now: now)
        let comparison = CostComparison(report: report, monthlyPrice: 100)
        XCTAssertNil(comparison.breakEvenDay)
        XCTAssertEqual(comparison.subscriptionMultiple ?? 0, 0.05, accuracy: 1e-9)
    }

    func testEffectiveTierPrefersExplicitOverrideThenAccount() {
        XCTAssertEqual(PlanTier.effective(override: "pro", detected: "default_claude_max_20x")?.id, "pro")
        XCTAssertEqual(
            PlanTier.effective(override: PlanTier.automaticID, detected: "default_claude_max_20x")?.id,
            "max_20x")
        XCTAssertNil(PlanTier.effective(override: PlanTier.automaticID, detected: nil))
        // An override naming a tier that no longer exists falls back, it
        // doesn't strand the user on no tier at all.
        XCTAssertEqual(PlanTier.effective(override: "retired_plan", detected: "pro")?.id, "pro")
    }

    func testPlanTierResolution() {
        XCTAssertEqual(PlanTier.resolve("default_claude_max_5x")?.id, "max_5x")
        XCTAssertEqual(PlanTier.resolve("default_claude_max_20x")?.id, "max_20x")
        XCTAssertEqual(PlanTier.resolve("max")?.id, "max_5x")
        XCTAssertEqual(PlanTier.resolve("pro")?.id, "pro")
        XCTAssertEqual(PlanTier.resolve("default_claude_pro")?.id, "pro")
        XCTAssertNil(PlanTier.resolve(nil))
        XCTAssertNil(PlanTier.resolve("enterprise_weird"))
    }
}
