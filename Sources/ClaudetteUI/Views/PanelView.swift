import SwiftUI
import ClaudetteCore

struct PanelView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                settingsButton
            }
            .frame(height: viewModel.geometry.notchHeight)

            // Both pages stay mounted so the ZStack always sizes to the taller
            // one — switching pages must never change the island's height.
            ZStack(alignment: .top) {
                usagePage
                    .opacity(viewModel.page == .usage ? 1 : 0)
                    .offset(x: viewModel.page == .usage ? 0 : -24)
                    .allowsHitTesting(viewModel.page == .usage)
                    .accessibilityHidden(viewModel.page != .usage)
                CostPageView(viewModel: viewModel)
                    .opacity(viewModel.page == .cost ? 1 : 0)
                    .offset(x: viewModel.page == .cost ? 0 : 24)
                    .allowsHitTesting(viewModel.page == .cost)
                    .accessibilityHidden(viewModel.page != .cost)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: viewModel.page)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.showPage(viewModel.page == .usage ? .cost : .usage)
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < -40 {
                            viewModel.showPage(.cost)
                        } else if value.translation.width > 40 {
                            viewModel.showPage(.usage)
                        }
                    })

            pageDots
        }
        .frame(width: viewModel.layout.expandedSize.width)
        .measuredHeight { viewModel.measuredPanelHeight = $0 }
    }

    private var pageDots: some View {
        HStack(spacing: Layout.pageDotGap) {
            pageDot(for: .usage)
            pageDot(for: .cost)
        }
        .padding(.vertical, Layout.pageDotVerticalPadding)
    }

    private func pageDot(for page: IslandViewModel.Page) -> some View {
        let isActive = viewModel.page == page
        return Circle()
            .fill(Theme.primaryText.opacity(
                isActive ? Theme.pageDotActiveOpacity : Theme.pageDotIdleOpacity))
            .frame(width: Layout.pageDotSize, height: Layout.pageDotSize)
            .frame(width: Layout.pageDotHitSize, height: Layout.pageDotHitSize)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.showPage(page) }
            .animation(.easeOut(duration: 0.2), value: isActive)
            .accessibilityLabel(page == .usage ? "Usage page" : "Cost page")
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
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

            Sparkline(values: viewModel.costReport?.dailyFractionOfPeak ?? [])
                .equatable()
        }
    }

}

private extension View {
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
