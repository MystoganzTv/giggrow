//
//  Charts.swift
//  GigPilot
//
//  Lightweight chart primitives. Each one takes coordinates in the design's
//  original SVG viewBox and rescales them to whatever frame it's given, so the
//  curves are identical to GigPilot.dc.html at any width.
//

import SwiftUI

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
                            colors: [GP.Palette.violet300.opacity(0.45), GP.Palette.violet300.opacity(0)],
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
    var fill: LinearGradient = GP.Gradients.bar
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
                    colors: [GP.Palette.sky300.opacity(0.42), GP.Palette.sky300.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            SeriesCurve(
                start: ChartData.monthlyCurveStart,
                segments: ChartData.monthlyCurve,
                box: ChartData.monthlyCurveBox
            )
            .stroke(GP.Palette.sky300, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
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
                    .font(GP.Typo.axis)
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
