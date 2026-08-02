import SwiftUI
import ClaudetteCore

/// One usage window as a gauge: percent, countdown, a 3pt track, and the
/// signature pace tick — a 1pt marker at the position usage would be if the
/// window were consumed evenly. Fill left of the tick: under budget. Fill
/// past it: on course to hit the wall early.
struct GaugeBar: View {
    let label: String
    let window: UsageWindow?
    let windowLength: TimeInterval
    let displayRemaining: Bool
    let now: Date
    var compact = false
    var dimmed = false
    var geometryID: String?
    var ns: Namespace.ID?

    @State private var tickOpacity: Double = 0.35

    private var usedFraction: Double { window?.fractionUsed ?? 0 }

    private var fillFraction: Double {
        displayRemaining ? 1 - usedFraction : usedFraction
    }

    /// pace = (now - windowStart) / (windowEnd - windowStart)
    private var paceUsed: Double? {
        guard let resetsAt = window?.resetsAt, windowLength > 0 else { return nil }
        let start = resetsAt.addingTimeInterval(-windowLength)
        let fraction = now.timeIntervalSince(start) / windowLength
        guard fraction > 0, fraction < 1 else { return nil }
        return fraction
    }

    private var tickPosition: Double? {
        paceUsed.map { displayRemaining ? 1 - $0 : $0 }
    }

    private var aheadOfPace: Bool {
        guard let paceUsed else { return false }
        return usedFraction >= paceUsed
    }

    private var isGhost: Bool { window == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(Tokens.label())
                    .tracking(0.6)
                    .foregroundStyle(Tokens.haze.opacity(0.6))
                Spacer(minLength: 4)
                if !compact, let resetsAt = window?.resetsAt {
                    Text(Format.countdown(to: resetsAt, from: now))
                        .font(Tokens.countdown())
                        .foregroundStyle(Tokens.haze)
                }
                numeral
            }
            track
        }
        .opacity(isGhost ? 0.4 : 1)
        .onChange(of: aheadOfPace) { _, crossed in
            // The tick punches to full opacity when fill crosses it, then
            // settles at 60%.
            if crossed {
                withAnimation(.easeIn(duration: 0.1)) { tickOpacity = 1.0 }
                withAnimation(.easeOut(duration: 0.3).delay(0.4)) { tickOpacity = 0.6 }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { tickOpacity = 0.35 }
            }
        }
        .onAppear {
            tickOpacity = aheadOfPace ? 0.6 : 0.35
        }
    }

    @ViewBuilder
    private var numeral: some View {
        let text = Text(Format.percent(window, remaining: displayRemaining))
            .font(Tokens.numeral(compact ? 11 : 13))
            .foregroundStyle(dimmed || isGhost ? Tokens.haze : Tokens.vapor)
            .contentTransition(.numericText(value: window?.utilization ?? 0))
        if let ns, let geometryID {
            text.matchedGeometryEffect(id: geometryID, in: ns)
        } else {
            text
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Tokens.hairline)
                    .frame(height: 3)
                if !isGhost {
                    Capsule()
                        .fill(Tokens.gaugeTint(utilization: usedFraction))
                        .frame(width: max(3, width * fillFraction), height: 3)
                        // Critically damped on purpose: overshoot on a
                        // percentage bar reads as a bug.
                        .animation(.spring(response: 0.55, dampingFraction: 1.0), value: fillFraction)
                        .animation(.easeInOut(duration: 0.6), value: usedFraction)
                }
                if let tickPosition {
                    Rectangle()
                        .fill(Tokens.vapor)
                        .frame(width: 1, height: 7)
                        .offset(x: min(max(width * tickPosition, 0), width - 1))
                        .opacity(tickOpacity)
                }
            }
            .frame(height: 7)
        }
        .frame(height: 7)
    }
}
