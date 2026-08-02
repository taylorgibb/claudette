import Foundation
import ClaudetteCore

/// Turns a `CostReport` into the strings and ratios the cost page renders.
///
/// Pure, so the money formatting, the subscription comparison and the
/// "unpriced models" disclosure can be tested without a view.
struct CostPresenter: Equatable {
    struct ModelRow: Equatable, Identifiable {
        let name: String
        let tokens: String
        /// "—" when the model has no price, never "$0.00".
        let cost: String
        var id: String { name }
    }

    let report: CostReport
    /// Nil when neither the account nor the user has named a plan.
    let plan: PlanTier?

    /// How many models get their own row before the rest are summarised.
    private static let visibleModelRows = 4

    var totalText: String { Format.dollars(report.totalDollars) }

    var planLabel: String {
        plan.map { "SUBSCRIPTION · \($0.displayName.uppercased())" } ?? "SUBSCRIPTION"
    }

    var planPriceText: String {
        plan.map { Format.dollars($0.monthlyUSD) } ?? "—"
    }

    var spanLabel: String { "API EQUIVALENT · \(report.spanDays)D" }

    /// Bar heights as fractions of the tallest day, so this chart and the
    /// collapsed sparkline scale identically.
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

    /// Named so the user can see exactly what the total is missing, rather
    /// than wondering why it looks low.
    var unpricedNote: String? {
        guard !report.unpricedModels.isEmpty else { return nil }
        let names = report.unpricedModels.joined(separator: ", ")
        return "Unpriced models (tokens counted, excluded from total): \(names)"
    }
}
