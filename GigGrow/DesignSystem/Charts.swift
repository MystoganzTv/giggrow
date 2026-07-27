//
//  Charts.swift
//  GigGrow
//
//  Lightweight chart primitives. Each one takes coordinates in the design's
//  original SVG viewBox and rescales them to whatever frame it's given, so the
//  curves are identical to GigGrow.dc.html at any width.
//

import SwiftUI

// MARK: - Normalising real values

extension Array where Element == Double {

    /// Turns raw values into points in a `box`-sized space, with y inverted so
    /// larger values sit higher. Used to feed `SeriesLine` / `SeriesArea` from
    /// live data rather than the design's hard-coded coordinates.
    ///
    /// - Parameter headroom: fraction of the box left empty above the peak,
    ///   so the maximum doesn't graze the top edge.
    func chartPoints(box: CGSize, headroom: Double = 0.10) -> [CGPoint] {
        guard count > 1 else { return [] }
        let peak = (self.max() ?? 0) * (1 + headroom)
        guard peak > 0 else {
            // Flat baseline rather than a division by zero.
            return enumerated().map { i, _ in
                CGPoint(x: CGFloat(i) / CGFloat(count - 1) * box.width, y: box.height)
            }
        }
        return enumerated().map { i, value in
            CGPoint(
                x: CGFloat(i) / CGFloat(count - 1) * box.width,
                y: box.height * CGFloat(1 - value / peak)
            )
        }
    }

    /// Bar heights plus the opacity ramp the design uses — taller bars are
    /// more opaque, so the eye lands on the best day without needing a label.
    func chartBars(minOpacity: Double = 0.45) -> [(height: CGFloat, opacity: Double)] {
        let peak = self.max() ?? 0
        guard peak > 0 else {
            return map { _ in (height: CGFloat(0), opacity: minOpacity) }
        }
        return map { value in
            let ratio = value / peak
            return (height: CGFloat(ratio),
                    opacity: minOpacity + (1 - minOpacity) * ratio)
        }
    }

    /// Same, tinted along a violet→indigo ramp for the hourly distribution.
    func chartColoredBars(palette: [Color]) -> [(height: CGFloat, color: Color, opacity: Double)] {
        let peak = self.max() ?? 0
        return enumerated().map { i, value in
            let ratio = peak > 0 ? value / peak : 0
            // Explicitly Swift.min / Swift.max — Array has its own min()/max().
            let colour = palette.isEmpty
                ? GG.Palette.violet400
                : palette[Swift.min(i * palette.count / Swift.max(count, 1), palette.count - 1)]
            return (height: CGFloat(ratio),
                    color: colour,
                    opacity: 0.40 + 0.60 * ratio)
        }
    }
}

// MARK: - Coordinate mapping

private func mapped(_ points: [CGPoint], box: CGSize, into rect: CGRect) -> [CGPoint] {
    guard box.width > 0, box.height > 0 else { return [] }
    return points.map {
        CGPoint(x: rect.minX + $0.x / box.width * rect.width,
                y: rect.minY + $0.y / box.height * rect.height)
    }
}

// MARK: - Line & area

/// A polyline through design-space points.
struct SeriesLine: Shape {
    let points: [CGPoint]
    let box: CGSize

    func path(in rect: CGRect) -> Path {
        let pts = mapped(points, box: box, into: rect)
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }
}

/// The same polyline closed down to the baseline, for the gradient fill.
struct SeriesArea: Shape {
    let points: [CGPoint]
    let box: CGSize

    func path(in rect: CGRect) -> Path {
        let pts = mapped(points, box: box, into: rect)
        var p = Path()
        guard let first = pts.first, let last = pts.last else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        p.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A smooth cubic path — used for the monthly income curve.
struct SeriesCurve: Shape {
    let start: CGPoint
    let segments: [(c1: CGPoint, c2: CGPoint, end: CGPoint)]
    let box: CGSize
    var closed: Bool = false

    func path(in rect: CGRect) -> Path {
        func m(_ pt: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + pt.x / box.width * rect.width,
                    y: rect.minY + pt.y / box.height * rect.height)
        }
        var p = Path()
        p.move(to: m(start))
        for seg in segments {
            p.addCurve(to: m(seg.end), control1: m(seg.c1), control2: m(seg.c2))
        }
        if closed, let last = segments.last {
            p.addLine(to: CGPoint(x: m(last.end).x, y: rect.maxY))
            p.addLine(to: CGPoint(x: m(start).x, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Composite chart views

/// Hero area chart on the Dashboard: soft violet fill, white stroke, end dot.
struct HeroAreaChart: View {
    let points: [CGPoint]
    let box: CGSize
    var height: CGFloat = 72

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let mappedEnd = points.last.map {
                CGPoint(x: $0.x / box.width * geo.size.width,
                        y: $0.y / box.height * geo.size.height)
            }

            ZStack {
                SeriesArea(points: points, box: box)
                    .fill(
                        LinearGradient(
                            colors: [GG.Palette.violet300.opacity(0.45), GG.Palette.violet300.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                SeriesLine(points: points, box: box)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                if let end = mappedEnd {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8.4, height: 8.4)
                        .position(end)
                }
            }
            .frame(width: rect.width, height: rect.height)
        }
        .frame(height: height)
    }
}

/// Tiny two-tone sparkline used in the trend tiles.
struct Sparkline: View {
    let points: [CGPoint]
    var box: CGSize = ChartData.sparklineBox
    var color: Color
    var height: CGFloat = 30
    var lineWidth: CGFloat = 2
    /// Adds a soft gradient beneath the line (analytics tiles do, dashboard doesn't).
    var filled: Bool = false

    var body: some View {
        ZStack {
            if filled {
                SeriesArea(points: points, box: box)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.40), color.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            SeriesLine(points: points, box: box)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .frame(height: height)
    }
}

/// Vertical bars with individually varying opacity — the weekly income chart.
struct BarChart: View {
    /// Bar heights in design units, plus the opacity each was drawn at.
    let bars: [(height: CGFloat, opacity: Double)]
    let maxHeight: CGFloat
    var fill: LinearGradient = GG.Gradients.bar
    var height: CGFloat = 100
    var cornerRadius: CGFloat = 9
    var spacing: CGFloat = 12

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .opacity(bar.opacity)
                    .frame(height: max(bar.height / maxHeight * height, 4))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// Bars with per-bar colour — the hourly earnings distribution.
struct ColoredBarChart: View {
    let bars: [(height: CGFloat, color: Color, opacity: Double)]
    let maxHeight: CGFloat
    var height: CGFloat = 78
    var cornerRadius: CGFloat = 7
    var spacing: CGFloat = 5

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(bar.color)
                    .opacity(bar.opacity)
                    .frame(height: max(bar.height / maxHeight * height, 4))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// Filled curve with a sky-blue stroke — the monthly income chart.
struct MonthlyCurveChart: View {
    var height: CGFloat = 104

    var body: some View {
        ZStack {
            SeriesCurve(
                start: ChartData.monthlyCurveStart,
                segments: ChartData.monthlyCurve,
                box: ChartData.monthlyCurveBox,
                closed: true
            )
            .fill(
                LinearGradient(
                    colors: [GG.Palette.sky300.opacity(0.42), GG.Palette.sky300.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            SeriesCurve(
                start: ChartData.monthlyCurveStart,
                segments: ChartData.monthlyCurve,
                box: ChartData.monthlyCurveBox
            )
            .stroke(GG.Palette.sky300, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        .frame(height: height)
    }
}

// MARK: - Axis

/// Evenly distributed axis captions beneath a chart.
struct AxisLabels: View {
    let labels: [String]
    var color: Color = Color.white.opacity(0.40)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(GG.Typo.axis)
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity,
                           alignment: alignment(for: index))
            }
        }
    }

    private func alignment(for index: Int) -> Alignment {
        if labels.count == 1 { return .center }
        if index == 0 { return .leading }
        if index == labels.count - 1 { return .trailing }
        return .center
    }
}
