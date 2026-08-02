import SwiftUI
import ClaudetteCore

/// The hover state: three gauge rows over the spend sparkline, with a gear in
/// the notch band. Refresh, the cost page and quit live on the context menu.
struct PanelView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            // The notch band is dead space anyway, so the one control the
            // panel needs sits beside the camera rather than costing a row.
            HStack(spacing: 0) {
                Spacer()
                settingsButton
            }
            .frame(height: viewModel.geometry.notchHeight)

            ZStack {
                if viewModel.page == .usage {
                    usagePage
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    CostPageView(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: viewModel.page)
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < -40 {
                            viewModel.showPage(.cost)
                        } else if value.translation.width > 40 {
                            viewModel.showPage(.usage)
                        }
                    })
        }
        .frame(width: viewModel.layout.expandedSize.width)
        .measuredHeight { viewModel.measuredPanelHeight = $0 }
    }

    private var settingsButton: some View {
        SymbolButton(
            symbolName: "gearshape.fill",
            pointSize: 11,
            tint: Theme.secondaryText,
            help: "Settings",
            action: { viewModel.openSettings() })
            .frame(width: 22, height: 22)
            .padding(.trailing, Layout.panelPadding - 6)
    }

    private var usagePage: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Layout.rowGap) {
                let presenter = viewModel.usagePresenter
                // A row the plan doesn't have is rendered unavailable rather
                // than dropped, holding the height steady so the island never
                // resizes under the pointer.
                ForEach(presenter.gauges) { gauge in
                    LimitGaugeView(
                        gauge: gauge,
                        now: viewModel.displayTime,
                        isStale: presenter.isStale)
                }

                if let problem = presenter.problemText {
                    Text(problem)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let update = viewModel.availableUpdateVersion {
                    Link(destination: Endpoints.releases) {
                        Text("UPDATE V\(update) AVAILABLE")
                            .font(Theme.label)
                            .tracking(0.6)
                            .foregroundStyle(Theme.primaryText.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, Layout.panelPadding)
            .padding(.top, Layout.panelTopPadding)

            // Bled to the silhouette's edges, under a hairline.
            Sparkline(values: viewModel.costReport?.dailyFractionOfPeak ?? [])
                .equatable()
        }
    }

}

private extension View {
    /// Reports this view's laid-out height.
    ///
    /// `onChange`'s action is not `@Sendable`, so it is main-actor-isolated by
    /// construction. The `PreferenceKey` this replaced handed its value to an
    /// `@Sendable` closure — SwiftUI explicitly reserving the right to call it
    /// off the main actor — which the old code answered with
    /// `MainActor.assumeIsolated`, i.e. a `fatalError` in a shipping app.
    func measuredHeight(_ report: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                    report(height)
                }
            }
        }
    }
}
