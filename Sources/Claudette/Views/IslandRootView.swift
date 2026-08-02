import SwiftUI
import AppKit
import ClaudetteCore

struct IslandRootView: View {
    @ObservedObject var vm: IslandViewModel
    @Namespace private var ns

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var lowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var morphAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.15)
        }
        switch vm.mode {
        case .collapsed:
            return .spring(response: 0.26, dampingFraction: 0.92)
        case .peek:
            return .spring(response: 0.30, dampingFraction: 0.82)
        case .panel:
            return .spring(response: 0.38, dampingFraction: 0.86)
        }
    }

    private var cornerRadius: CGFloat {
        vm.mode == .collapsed ? Layout.cornerCollapsed : Layout.cornerExpanded
    }

    var body: some View {
        let size = vm.silhouetteSize
        ZStack(alignment: .top) {
            // Continuous corners: a hand-built arc path leaves a visible kink
            // at the tangent against the real notch; this shape does not.
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous)
                .fill(Tokens.void)
                .shadow(color: glowColor, radius: 8, x: 0, y: 2)

            content
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .animation(morphAnimation, value: vm.mode)
        .frame(
            width: Layout.windowSize.width,
            height: Layout.windowSize.height,
            alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// The one permitted glow: refresh in flight only, off under Low Power
    /// Mode and reduced motion. No idle animation, ever.
    private var glowColor: Color {
        guard vm.usage.isRefreshing, !lowPower, !reduceMotion else { return .clear }
        let used = vm.usage.snapshot?.fiveHour?.fractionUsed ?? 0
        return Tokens.gaugeTint(utilization: used).opacity(0.35)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.mode {
        case .collapsed:
            CollapsedView(vm: vm, ns: ns)
                .transition(.opacity)
        case .peek:
            PeekView(vm: vm, ns: ns)
                .transition(.opacity)
        case .panel:
            PanelView(vm: vm, settings: vm.settings, ns: ns)
                .transition(.opacity)
        }
    }
}

extension IslandViewModel {
    /// Row sources with plan-dependent fallbacks: no five_hour promotes the
    /// weekly window to primary; the model row prefers opus, then sonnet.
    var collapsedLeft: (label: String, window: UsageWindow?) {
        if let snapshot = usage.snapshot {
            if let session = snapshot.fiveHour { return ("SESSION", session) }
            if let week = snapshot.sevenDay { return ("WEEK", week) }
        }
        return ("SESSION", nil)
    }

    var collapsedRight: (label: String, window: UsageWindow?) {
        guard let snapshot = usage.snapshot else { return ("WEEK", nil) }
        if snapshot.fiveHour == nil, snapshot.sevenDay != nil {
            if let model = snapshot.modelWeekly { return (model.label, model.window) }
            return ("WEEK", nil)
        }
        return ("WEEK", snapshot.sevenDay)
    }
}

struct CollapsedView: View {
    @ObservedObject var vm: IslandViewModel
    let ns: Namespace.ID

    var body: some View {
        let left = vm.collapsedLeft
        let right = vm.collapsedRight
        HStack(spacing: 0) {
            pill(label: left.label, window: left.window, geometryID: "left-num")
            Color.clear
                .frame(width: vm.geometry.notchWidth)
            pill(label: right.label, window: right.window, geometryID: "right-num")
        }
        .frame(height: vm.geometry.notchHeight + Layout.collapsedDrop, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture { vm.clicked() }
    }

    private func pill(label: String, window: UsageWindow?, geometryID: String) -> some View {
        let used = window?.fractionUsed ?? 0
        return VStack(spacing: 2) {
            Spacer(minLength: 1)
            Text(Format.percent(window, remaining: vm.settings.displayRemaining))
                .font(Tokens.numeral(12))
                .foregroundStyle(vm.isStale ? Tokens.haze : Tokens.vapor)
                .contentTransition(.numericText(value: window?.utilization ?? 0))
                .matchedGeometryEffect(id: geometryID, in: ns)
            Capsule()
                .fill(window == nil ? Tokens.hairline : Tokens.gaugeTint(utilization: used))
                .frame(width: 34, height: 2)
                .animation(.easeInOut(duration: 0.6), value: used)
            Text(label)
                .font(Tokens.label())
                .tracking(0.6)
                .foregroundStyle(Tokens.haze.opacity(0.6))
            Spacer(minLength: 2)
        }
        // Fixed width sized for the widest content so digit changes never
        // resize the pill.
        .frame(width: Layout.pillWidth)
    }
}

struct PeekView: View {
    @ObservedObject var vm: IslandViewModel
    let ns: Namespace.ID

    var body: some View {
        VStack(spacing: 9) {
            Color.clear.frame(height: vm.geometry.notchHeight)
            GaugeBar(
                label: "SESSION",
                window: vm.usage.snapshot?.fiveHour,
                windowLength: 5 * 3600,
                displayRemaining: vm.settings.displayRemaining,
                now: vm.now,
                compact: true,
                dimmed: vm.isStale,
                geometryID: "left-num",
                ns: ns)
            GaugeBar(
                label: "WEEK",
                window: vm.usage.snapshot?.sevenDay,
                windowLength: 7 * 86_400,
                displayRemaining: vm.settings.displayRemaining,
                now: vm.now,
                compact: true,
                dimmed: vm.isStale,
                geometryID: "right-num",
                ns: ns)
            GaugeBar(
                label: vm.usage.snapshot?.modelWeekly.map { "\($0.label) · 7D" } ?? "MODEL · 7D",
                window: vm.usage.snapshot?.modelWeekly?.window,
                windowLength: 7 * 86_400,
                displayRemaining: vm.settings.displayRemaining,
                now: vm.now,
                compact: true,
                dimmed: vm.isStale)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 18)
        .frame(width: vm.size(for: .peek).width)
        .contentShape(Rectangle())
        .onTapGesture { vm.clicked() }
    }
}
