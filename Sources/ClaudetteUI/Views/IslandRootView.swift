import SwiftUI
import AppKit
import ClaudetteCore

struct IslandRootView: View {
    @ObservedObject var viewModel: IslandViewModel

    /// Read from the environment so SwiftUI invalidates the view when the
    /// user toggles Reduce Motion. Reading `NSWorkspace` directly created no
    /// dependency, so the setting only took effect after some unrelated
    /// republish happened to come along.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// No matching environment key exists, and Low Power Mode changing
    /// mid-hover is not worth an observer — it takes effect on the next
    /// republish, which the 1 Hz ticker guarantees is within a second.
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

    /// Continuous corners; a hand-built arc kinks against the real notch.
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
        // Clips the content too, so the full-bleed sparkline follows the
        // bottom corners instead of spilling past them.
        .clipShape(silhouette)
        // A hairline rim while open separates the panel from whatever is
        // behind it; collapsed it stays invisible so the bar reads as bezel.
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

    /// The one permitted glow: refresh in flight, never an idle animation.
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

/// Two tinted numerals flanking the notch. Nothing else at rest.
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

    /// Numeral only at rest — the countdown lives in the hover panel, which is
    /// what keeps the bar tight to the notch.
    private func pill(window: LimitWindow?, isStale: Bool) -> some View {
        let used = window?.fractionUsed ?? 0
        let tint = window == nil ? Theme.secondaryText : Theme.gaugeTint(used: used)
        return Text(Format.percentRemaining(window))
            .font(Theme.numeral())
            .foregroundStyle(isStale ? Theme.secondaryText : tint)
            .contentTransition(.numericText(value: window?.percentUsed ?? 0))
            // Frozen at the width of "100%" so geometry never moves.
            .frame(width: Layout.pillWidth)
    }
}
