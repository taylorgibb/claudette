import SwiftUI
import ClaudetteCore

/// API-equivalent cost over the last 30 days, priced from local session
/// logs at list rates, against the subscription price.
struct CostView: View {
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            if let report = vm.costReport {
                content(report)
            } else {
                scanningPlaceholder
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var scanningPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCANNING SESSION LOGS")
                .font(Tokens.label())
                .tracking(0.6)
                .foregroundStyle(Tokens.haze)
            if let progress = vm.costProgress, progress.filesTotal > 0 {
                ProgressView(value: progress.fraction)
                    .tint(Tokens.vapor.opacity(0.7))
                Text("\(progress.filesDone)/\(progress.filesTotal) FILES")
                    .font(Tokens.countdown())
                    .foregroundStyle(Tokens.haze.opacity(0.7))
            } else {
                ProgressView(value: nil as Double?)
                    .tint(Tokens.vapor.opacity(0.7))
            }
            Spacer()
        }
    }

    private func content(_ report: CostReport) -> some View {
        let plan = settings.monthlyPrice(autoDetectedTier: vm.usage.planTier)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("API EQUIVALENT · 30D")
                        .font(Tokens.label())
                        .tracking(0.6)
                        .foregroundStyle(Tokens.haze.opacity(0.6))
                    Text(Format.dollars(report.totalDollars))
                        .font(Tokens.numeral(20))
                        .foregroundStyle(Tokens.vapor)
                        .contentTransition(.numericText(value: report.totalDollars))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.map { "SUBSCRIPTION · \($0.label.uppercased())" } ?? "SUBSCRIPTION")
                        .font(Tokens.label())
                        .tracking(0.6)
                        .foregroundStyle(Tokens.haze.opacity(0.6))
                    Text(plan.map { Format.dollars($0.usd) } ?? "—")
                        .font(Tokens.numeral(20))
                        .foregroundStyle(Tokens.vapor)
                }
            }

            chart(report)

            comparisonLine(report, plan: plan)

            modelBreakdown(report)

            Spacer(minLength: 2)

            footnote(report)
        }
    }

    private func chart(_ report: CostReport) -> some View {
        let maxDay = max(report.days.map(\.dollars).max() ?? 0, 0.01)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(report.days) { day in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(day.dayKey == report.days.last?.dayKey
                        ? Tokens.vapor.opacity(0.9)
                        : Color(hex: 0x3D6BE5).opacity(0.75))
                    .frame(height: max(2, 36 * day.dollars / maxDay))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 38, alignment: .bottom)
    }

    @ViewBuilder
    private func comparisonLine(_ report: CostReport, plan: (label: String, usd: Double)?) -> some View {
        if let plan {
            let comparison = CostComparison(report: report, monthlyPrice: plan.usd)
            HStack(spacing: 4) {
                if let multiple = comparison.effectiveMultiple {
                    Text(Format.multiple(multiple))
                        .font(Tokens.numeral(12))
                        .foregroundStyle(Tokens.vapor)
                    Text("the subscription price")
                        .font(.system(size: 10))
                        .foregroundStyle(Tokens.haze)
                }
                if let breakEven = comparison.breakEvenDayKey,
                   let ordinal = Format.ordinalDay(breakEven) {
                    Text("· broke even on the \(ordinal)")
                        .font(.system(size: 10))
                        .foregroundStyle(Tokens.haze)
                }
            }
        } else {
            Text("Set your plan in Settings → Data for the comparison.")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.haze)
        }
    }

    private func modelBreakdown(_ report: CostReport) -> some View {
        VStack(spacing: 4) {
            ForEach(report.models.prefix(4)) { line in
                HStack(spacing: 8) {
                    Text(Format.modelDisplayName(line.model))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Tokens.vapor.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    Text(Format.tokens(line.tally.total))
                        .font(Tokens.countdown())
                        .foregroundStyle(Tokens.haze)
                    Text(line.dollars.map(Format.dollars) ?? "—")
                        .font(Tokens.numeral(10.5))
                        .foregroundStyle(Tokens.vapor.opacity(0.9))
                        .frame(minWidth: 48, alignment: .trailing)
                }
            }
            if report.models.count > 4 {
                HStack {
                    Text("+ \(report.models.count - 4) more")
                        .font(.system(size: 9))
                        .foregroundStyle(Tokens.haze.opacity(0.7))
                    Spacer()
                }
            }
        }
    }

    private func footnote(_ report: CostReport) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Estimate at list API rates (USD). Excludes batch discounts, long-context surcharges, and anything billed outside the subscription.")
            if !report.unknownModels.isEmpty {
                Text("Unpriced models (tokens counted, excluded from total): \(report.unknownModels.joined(separator: ", "))")
            }
        }
        .font(.system(size: 8.5))
        .foregroundStyle(Tokens.haze.opacity(0.7))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 10)
    }
}
