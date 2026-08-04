import Foundation
import ClaudetteCore

struct CostPresenter: Equatable {
    struct ModelRow: Equatable, Identifiable {
        let name: String
        let tokens: String
        let cost: String
        var id: String { name }
    }

    let report: CostReport
    let plan: PlanTier?

    private static let visibleModelRows = 4

    var totalText: String { Format.dollars(report.totalDollars) }

    var spanLabel: String { "ESTIMATED COST" }

    var dailyFractions: [Double] { report.dailyFractionOfPeak }

    var modelRows: [ModelRow] {
        report.models.prefix(Self.visibleModelRows).map { model in
            ModelRow(
                name: ModelNaming.displayName(for: model.model),
                tokens: Format.tokens(model.tally.total),
                cost: model.dollars.map(Format.dollars) ?? "—")
        }
    }

    var hiddenModelCount: Int {
        max(0, report.models.count - Self.visibleModelRows)
    }

    var unpricedNote: String? {
        guard !report.unpricedModels.isEmpty else { return nil }
        let names = report.unpricedModels.joined(separator: ", ")
        return "Unpriced models (tokens counted, excluded from total): \(names)"
    }
}
