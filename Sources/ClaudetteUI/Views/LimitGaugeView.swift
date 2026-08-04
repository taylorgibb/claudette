import SwiftUI
import ClaudetteCore

struct LimitGaugeView: View {
    let gauge: UsagePresenter.Gauge
    let now: Date
    var isStale = false

    @State private var tickOpacity: Double = Theme.tickIdleOpacity

    private var window: LimitWindow? { gauge.window }

    private var usedFraction: Double { window?.fractionUsed ?? 0 }

    private var fillFraction: Double { 1 - usedFraction }

    private var paceUsed: Double? {
        guard let resetsAt = window?.resetsAt, gauge.duration > 0 else { return nil }
        let start = resetsAt.addingTimeInterval(-gauge.duration)
        let fraction = now.timeIntervalSince(start) / gauge.duration
        guard fraction > 0, fraction < 1 else { return nil }
        return fraction
    }

    private var tickPosition: Double? { paceUsed.map { 1 - $0 } }

    private var aheadOfPace: Bool {
        guard let paceUsed else { return false }
        return usedFraction >= paceUsed
    }

    private var isUnavailable: Bool { gauge.isUnavailable }

    var body: some View {
        let tint = Theme.gaugeTint(used: usedFraction)
        return VStack(alignment: .leading, spacing: Layout.rowInnerGap) {
            HStack(alignment: .firstTextBaseline, spacing: 6.5) {
                Text(gauge.label)
                    .font(Theme.label)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                if !isUnavailable, let resetsAt = window?.resetsAt {
                    Text(Format.compactCountdown(to: resetsAt, from: now))
                        .font(Theme.countdown())
                        .tracking(0.3)
                        .foregroundStyle(Theme.secondaryText.opacity(0.65))
                }
                Spacer(minLength: 4)
                numeral(tint: tint)
            }
            track(tint: tint)
        }
        .opacity(isUnavailable ? 0.34 : 1)
        .onChange(of: aheadOfPace) { _, crossed in
            guard crossed else {
                withAnimation(.easeOut(duration: 0.3)) { tickOpacity = Theme.tickIdleOpacity }
                return
            }
            withAnimation(.easeIn(duration: 0.1)) { tickOpacity = Theme.tickPunchOpacity }
            withAnimation(.easeOut(duration: 0.3).delay(0.4)) { tickOpacity = Theme.tickIdleOpacity }
        }
    }

    @ViewBuilder
    private func numeral(tint: Color) -> some View {
        if isUnavailable {
            Text("NOT ON THIS PLAN")
                .font(Theme.unavailableLabel)
                .foregroundStyle(Theme.secondaryText)
        } else {
            Text(Format.percentRemaining(window))
                .font(Theme.numeral())
                .foregroundStyle(isStale ? Theme.secondaryText : tint)
                .contentTransition(.numericText(value: window?.percentUsed ?? 0))
        }
    }

    @ViewBuilder
    private func track(tint: Color) -> some View {
        if isUnavailable {
            HorizontalRule()
                .stroke(
                    Theme.hairline,
                    style: StrokeStyle(lineWidth: Layout.trackHeight, dash: [3, 3]))
                .frame(height: Layout.tickHeight)
        } else {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.hairline)
                        .frame(height: Layout.trackHeight)
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: max(Layout.trackHeight, width * fillFraction),
                            height: Layout.trackHeight)
                        .animation(.spring(response: 0.55, dampingFraction: 1.0), value: fillFraction)
                    if let tickPosition {
                        Capsule()
                            .fill(Theme.primaryText)
                            .frame(width: Layout.tickWidth, height: Layout.tickHeight)
                            .offset(
                                x: min(
                                    max(width * tickPosition - Layout.tickWidth / 2, 0),
                                    width - Layout.tickWidth))
                            .opacity(tickOpacity)
                    }
                }
                .frame(width: width, height: geo.size.height)
            }
            .frame(height: Layout.tickHeight)
        }
    }
}

private struct HorizontalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}
