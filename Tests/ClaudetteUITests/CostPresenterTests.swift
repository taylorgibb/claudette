import XCTest
import ClaudetteCore
@testable import ClaudetteUI

final class CostPresenterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(
        totalDollars: Double = 0,
        models: [CostReport.ModelCost] = [],
        unpriced: [ModelID] = [],
        dailyDollars: [Double] = []
    ) -> CostReport {
        let days = dailyDollars.enumerated().map { index, dollars in
            CostReport.Day(
                key: DayKey(now.addingTimeInterval(Double(index - dailyDollars.count) * 86_400)),
                dollars: dollars)
        }
        return CostReport(
            spanDays: 30,
            days: days,
            totalDollars: totalDollars,
            models: models,
            unpricedModels: unpriced,
            generatedAt: now,
            scanDurationMs: 0,
            filesDiscovered: 0)
    }

    private func model(_ name: ModelID, tokens: Int64, dollars: Double?) -> CostReport.ModelCost {
        CostReport.ModelCost(
            model: name,
            tally: TokenTally(input: tokens),
            dollars: dollars,
            costShare: 0)
    }

    func testHeadline() {
        let presenter = CostPresenter(
            report: report(totalDollars: 42.5),
            plan: PlanTier.known.first { $0.id == "max_20x" })
        XCTAssertEqual(presenter.totalText, "$42.50")
        XCTAssertEqual(presenter.spanLabel, "ESTIMATED COST")
    }

    func testUnpricedModelRendersADashAndIsNamedInTheFootnote() {
        let presenter = CostPresenter(
            report: report(
                models: [
                    model("claude-opus-5", tokens: 2_000_000, dollars: 12),
                    model("totally-future-model", tokens: 999, dollars: nil),
                ],
                unpriced: ["totally-future-model"]),
            plan: nil)

        XCTAssertEqual(presenter.modelRows.map(\.name), ["Opus 5", "totally-future-model"])
        XCTAssertEqual(presenter.modelRows[0].cost, "$12.00")
        XCTAssertEqual(presenter.modelRows[1].cost, "—")
        XCTAssertEqual(presenter.modelRows[0].tokens, "2.0M")
        XCTAssertEqual(
            presenter.unpricedNote,
            "Unpriced models (tokens counted, excluded from total): totally-future-model")
    }

    func testNoUnpricedModelsMeansNoFootnote() {
        let presenter = CostPresenter(report: report(), plan: nil)
        XCTAssertNil(presenter.unpricedNote)
    }

    func testModelListIsCappedAndTheRemainderCounted() {
        let models = (0..<7).map { model("claude-model-\($0)", tokens: 10, dollars: 1) }
        let presenter = CostPresenter(report: report(models: models), plan: nil)
        XCTAssertEqual(presenter.modelRows.count, 4)
        XCTAssertEqual(presenter.hiddenModelCount, 3)
    }
}
