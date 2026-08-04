import SwiftUI
import ClaudetteCore

struct CostPageView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        Group {
            if let presenter = viewModel.costPresenter {
                content(presenter)
            } else {
                scanningPlaceholder
            }
        }
        .padding(.horizontal, Layout.panelPadding)
        .padding(.top, Layout.panelTopPadding)
    }

    private var scanningPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCANNING SESSION LOGS")
                .font(Theme.label)
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryText)
            if let progress = viewModel.costProgress, progress.totalFiles > 0 {
                ProgressView(value: progress.completedFraction)
                    .tint(Theme.primaryText.opacity(0.7))
                Text("\(progress.completedFiles)/\(progress.totalFiles) FILES")
                    .font(Theme.countdown())
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
            } else {
                ProgressView(value: nil as Double?)
                    .tint(Theme.primaryText.opacity(0.7))
            }
        }
        .frame(height: Layout.estimatedPanelBodyHeight, alignment: .top)
    }

    private func content(_ presenter: CostPresenter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headline(presenter)
            dailySpendBars(presenter)
            // Fills whatever height the taller usage page dictates, so the
            // breakdown floats with equal space above and below it.
            modelBreakdown(presenter)
                .frame(maxHeight: .infinity)
            if let unpriced = presenter.unpricedNote {
                footnote(unpriced)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 4)
    }

    private func headline(_ presenter: CostPresenter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            caption(presenter.spanLabel)
            Text(presenter.totalText)
                .font(Theme.numeral(size: 20))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText(value: presenter.report.totalDollars))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.label)
            .tracking(0.6)
            .foregroundStyle(Theme.secondaryText.opacity(0.6))
    }

    private func dailySpendBars(_ presenter: CostPresenter) -> some View {
        let fractions = presenter.dailyFractions
        let lastDay = presenter.report.days.last?.key
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(presenter.report.days.enumerated()), id: \.element.id) { index, day in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(day.key == lastDay
                        ? Theme.primaryText.opacity(0.9)
                        : Theme.chartLine.opacity(Theme.chartDimOpacity))
                    .frame(height: max(2, (Layout.chartHeight - 2) * fractions[index]))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Layout.chartHeight, alignment: .bottom)
    }

    private func modelBreakdown(_ presenter: CostPresenter) -> some View {
        VStack(spacing: 4) {
            ForEach(presenter.modelRows) { row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.primaryText.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    Text(row.tokens)
                        .font(Theme.countdown())
                        .foregroundStyle(Theme.secondaryText)
                    Text(row.cost)
                        .font(Theme.numeral(size: 10.5))
                        .foregroundStyle(Theme.primaryText.opacity(0.9))
                        .frame(minWidth: 48, alignment: .trailing)
                }
            }
            if presenter.hiddenModelCount > 0 {
                HStack {
                    Text("+ \(presenter.hiddenModelCount) more")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryText.opacity(0.7))
                    Spacer()
                }
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5))
            .foregroundStyle(Theme.secondaryText.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }
}
