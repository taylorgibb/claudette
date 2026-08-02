import SwiftUI

/// The panel footer: the report window's spend, bled to the silhouette's
/// edges and deliberately unlabelled.
///
/// `Equatable` only takes effect through `.equatable()` at the call site —
/// SwiftUI does not consult a view's conformance on its own. Without that the
/// Bézier path is rebuilt on every 1 Hz tick.
struct Sparkline: View, Equatable {
    /// Pre-normalized to 0...1 by `CostReport.dailyFractionOfPeak`.
    let values: [Double]

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
            GeometryReader { geo in
                let line = path(in: geo.size)
                ZStack {
                    closed(line, in: geo.size).fill(Theme.chartLine.opacity(0.14))
                    line.stroke(
                        Theme.chartLine,
                        style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: Layout.chartHeight)
            .opacity(0.75)
        }
        .padding(.top, Layout.chartTopMargin)
    }

    /// Headroom above the peak so the busiest day never touches the top edge.
    private let topInset: CGFloat = 9

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let usable = max(size.height - topInset, 1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height - usable * CGFloat(value))
        }
    }

    /// Quadratic smoothing through segment midpoints — enough to take the
    /// jaggedness off daily spend without inventing peaks that aren't there.
    private func path(in size: CGSize) -> Path {
        var path = Path()
        let pts = points(in: size)
        guard let first = pts.first, pts.count > 1 else { return path }
        path.move(to: first)
        for index in 1..<pts.count {
            let previous = pts[index - 1]
            let current = pts[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    /// Drops the stroke down to the baseline at both ends to make the fill.
    private func closed(_ line: Path, in size: CGSize) -> Path {
        guard !line.isEmpty, let end = line.currentPoint else { return line }
        var filled = line
        filled.addLine(to: CGPoint(x: end.x, y: size.height))
        filled.addLine(to: CGPoint(x: 0, y: size.height))
        filled.closeSubpath()
        return filled
    }
}
