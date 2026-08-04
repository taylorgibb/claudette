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

    var planLabel: String {
        plan.map { "SUBSCRIPTION · \($0.displayName.uppercased())" } ?? "SUBSCRIPTION"
    }

    var planPriceText: String {
        plan.map { Format.dollars($0.monthlyUSD) } ?? "—"
    }

    var spanLabel: String { "API EQUIVALENT · \(report.spanDays)D" }

    var dailyFractions: [Double] { report.dailyFractionOfPeak }

    var comparison: CostComparison? {
        plan.map { CostComparison(report: report, monthlyPrice: $0.monthlyUSD) }
    }

    var multipleText: String? {
        comparison?.subscriptionMultiple.map(Format.multiple)
    }

    var breakEvenText: String? {
        guard let day = comparison?.breakEvenDay else { return nil }
        return "· broke even on the \(Format.ordinalDay(day))"
    }

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

    var disclaimer: String {
        "Estimate at list API rates in USD. Excludes batch discounts, "
            + "long-context surcharges, and anything billed outside the "
            + "subscription."
    }

    var unpricedNote: String? {
        guard !report.unpricedModels.isEmpty else { return nil }
        let names = report.unpricedModels.joined(separator: ", ")
        return "Unpriced models (tokens counted, excluded from total): \(names)"
    }
}
