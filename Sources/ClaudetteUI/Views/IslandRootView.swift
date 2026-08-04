import SwiftUI
import AppKit
import ClaudetteCore

struct IslandRootView: View {
    @ObservedObject var viewModel: IslandViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var morphAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.15)
        }
        switch viewModel.mode {
        case .collapsed:
            return .spring(response: 0.26, dampingFraction: 0.92)
        case .panel:
            return .spring(response: 0.38, dampingFraction: 0.86)
        }
    }

    private var silhouette: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: Layout.cornerRadius,
            bottomTrailingRadius: Layout.cornerRadius,
            topTrailingRadius: 0,
            style: .continuous)
    }

    var body: some View {
        let size = viewModel.silhouetteSize
        ZStack(alignment: .top) {
            Theme.surface
            content
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(silhouette)
        .overlay(
            silhouette.strokeBorder(
                .white.opacity(viewModel.mode == .panel ? 0.12 : 0),
                lineWidth: 0.5))
        .shadow(color: glowColor, radius: 8, x: 0, y: 2)
        .shadow(
            color: viewModel.mode == .panel ? .black.opacity(0.5) : .clear,
            radius: 20, y: 10)
        .animation(morphAnimation, value: viewModel.mode)
        .frame(
            width: Layout.hostWindowSize.width,
            height: Layout.hostWindowSize.height,
            alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var glowColor: Color {
        guard viewModel.usage.isRefreshing, !isLowPower, !reduceMotion else { return .clear }
        let used = viewModel.usage.snapshot?.session?.fractionUsed ?? 0
        return Theme.gaugeTint(used: used).opacity(0.35)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.mode {
        case .collapsed:
            CollapsedBar(viewModel: viewModel)
                .transition(.opacity)
        case .panel:
            PanelView(viewModel: viewModel)
                .transition(.opacity)
        }
    }
}

struct CollapsedBar: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        let presenter = viewModel.usagePresenter
        return HStack(spacing: 0) {
            pill(window: presenter.leadingPillWindow, isStale: presenter.isStale)
            Color.clear
                .frame(width: viewModel.geometry.notchWidth)
            pill(window: presenter.trailingPillWindow, isStale: presenter.isStale)
        }
        .frame(height: viewModel.layout.collapsedSize.height)
        .contentShape(Rectangle())
    }

    private func pill(window: LimitWindow?, isStale: Bool) -> some View {
        let used = window?.fractionUsed ?? 0
        let tint = window == nil ? Theme.secondaryText : Theme.gaugeTint(used: used)
        return Text(Format.percentRemaining(window))
            .font(Theme.numeral())
            .foregroundStyle(isStale ? Theme.secondaryText : tint)
            .contentTransition(.numericText(value: window?.percentUsed ?? 0))
            .frame(width: Layout.pillWidth)
    }
}
