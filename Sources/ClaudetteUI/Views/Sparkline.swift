import SwiftUI

struct Sparkline: View, Equatable {
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
            .opacity(Theme.chartDimOpacity)
        }
        .padding(.top, Layout.chartTopMargin)
    }

    private let topInset: CGFloat = 9

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let usable = max(size.height - topInset, 1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height - usable * CGFloat(value))
        }
    }

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

    private func closed(_ line: Path, in size: CGSize) -> Path {
        guard !line.isEmpty, let end = line.currentPoint else { return line }
        var filled = line
        filled.addLine(to: CGPoint(x: end.x, y: size.height))
        filled.addLine(to: CGPoint(x: 0, y: size.height))
        filled.closeSubpath()
        return filled
    }
}
