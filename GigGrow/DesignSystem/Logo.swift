//
//  Logo.swift
//  GigGrow
//
//  Vector rebuild of the GigGrow brand mark: a gauge that closes into a map
//  pin, three ascending bars, and a needle that breaks out of the dial as a
//  rising arrow. Drawn rather than bitmapped so it stays crisp at 20pt and
//  1024pt alike; the raster original ships as the app icon.
//
//  All geometry is authored in a 100 × 120 box and scaled to fit.
//

import SwiftUI

// MARK: - Public view

/// The GigGrow mark. Set `glow` for the neon bloom used on dark surfaces.
struct GigGrowLogo: View {
    var size: CGFloat = 44
    var glow: Bool = true

    private var box: CGSize { CGSize(width: size * (100.0 / 120.0), height: size) }

    var body: some View {
        LogoMark()
            .frame(width: box.width, height: box.height)
            .shadow(color: glow ? Color(hex: 0xA855F7, opacity: 0.55) : .clear,
                    radius: glow ? size * 0.22 : 0)
    }
}

/// Rounded-square app-icon treatment — the mark on its bloom, for use in
/// settings rows, launch screens and About panes.
struct GigGrowIconTile: View {
    var size: CGFloat = 54
    var corner: CGFloat { size * 0.28 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(hex: 0x0A0A12))
            RadialGradient(
                colors: [Color(hex: 0x6D28D9, opacity: 0.55), .clear],
                center: .center, startRadius: 0, endRadius: size * 0.62
            )
            GigGrowLogo(size: size * 0.68, glow: false)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Mark

private struct LogoMark: View {

    /// Neon sweep: cyan at the lower left → violet through the middle →
    /// magenta at the arrow tip, matching the source artwork.
    private var sweep: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x22C0FF), location: 0.00),
                .init(color: Color(hex: 0x3B82F6), location: 0.28),
                .init(color: Color(hex: 0x7C3AED), location: 0.55),
                .init(color: Color(hex: 0xC026D3), location: 0.80),
                .init(color: Color(hex: 0xF056E8), location: 1.00)
            ],
            startPoint: .bottomLeading, endPoint: .topTrailing
        )
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Geo.box.width, geo.size.height / Geo.box.height)

            ZStack {
                // Dial + pin outline, broken where the arrow escapes.
                PinOutline()
                    .stroke(sweep, style: StrokeStyle(lineWidth: Geo.ringWidth * s,
                                                      lineCap: .round, lineJoin: .round))

                // Gauge ticks along the inner left of the dial.
                DialTicks()
                    .stroke(sweep, style: StrokeStyle(lineWidth: Geo.tickWidth * s, lineCap: .round))
                    .opacity(0.95)

                // Three ascending bars sitting in the belly of the pin.
                Bars()
                    .fill(sweep)

                // Needle hub.
                Circle()
                    .fill(sweep)
                    .frame(width: Geo.hubRadius * 2 * s, height: Geo.hubRadius * 2 * s)
                    .position(x: Geo.hub.x * s, y: Geo.hub.y * s)

                // Needle shaft, breaking out of the dial.
                Needle()
                    .stroke(sweep, style: StrokeStyle(lineWidth: Geo.needleWidth * s, lineCap: .round))

                // Arrowhead.
                ArrowHead()
                    .fill(sweep)
            }
            .frame(width: Geo.box.width * s, height: Geo.box.height * s)
        }
        .aspectRatio(Geo.box.width / Geo.box.height, contentMode: .fit)
    }
}

// MARK: - Geometry constants

private enum Geo {
    static let box = CGSize(width: 100, height: 120)

    /// Dial circle.
    static let center = CGPoint(x: 50, y: 45)
    static let radius: CGFloat = 38
    /// Point of the pin.
    static let tip = CGPoint(x: 50, y: 116)

    static let ringWidth: CGFloat = 8.5
    static let tickWidth: CGFloat = 2.6
    static let needleWidth: CGFloat = 5.0

    static let hub = CGPoint(x: 46.5, y: 56.5)
    static let hubRadius: CGFloat = 5.0

    /// Where the needle's arrowhead lands, outside the dial.
    static let arrowTip = CGPoint(x: 90, y: 13)

    /// Tangent points where the straight sides of the pin meet the dial.
    /// cos⁻¹(r / |C→tip|) either side of the downward vertical.
    static var tangentSpread: CGFloat {
        let dx = Double(tip.x - center.x)
        let dy = Double(tip.y - center.y)
        let d = (dx * dx + dy * dy).squareRoot()
        return CGFloat(acos(Double(radius) / d) * 180 / Double.pi)   // ≈ 57.6°
    }
    /// Screen-space angles (0° = +x, growing clockwise because y points down).
    static var leftTangentAngle: CGFloat { 90 + tangentSpread }   // ≈ 147.6°
    static var rightTangentAngle: CGFloat { 90 - tangentSpread }  // ≈ 32.4°

    /// The dial is interrupted between these angles so the needle can escape.
    static let gapStart: CGFloat = 297   // upper right, roughly 1 o'clock
    static let gapEnd: CGFloat = 340     // roughly 2 o'clock

    static func point(_ angleDegrees: CGFloat, radius r: CGFloat) -> CGPoint {
        let a = Double(angleDegrees) * Double.pi / 180
        return CGPoint(x: center.x + CGFloat(cos(a)) * r,
                       y: center.y + CGFloat(sin(a)) * r)
    }

    /// Arcs are sampled rather than built with `addArc` so the sweep direction
    /// is unambiguous in SwiftUI's flipped coordinate space.
    static func arc(from a0: CGFloat, to a1: CGFloat, radius r: CGFloat, steps: Int = 48) -> [CGPoint] {
        (0...steps).map { i in
            point(a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps), radius: r)
        }
    }
}

private extension Path {
    /// Appends sampled points, starting a new subpath at the first one.
    mutating func addSampled(_ points: [CGPoint], scale s: CGFloat, startNew: Bool = true) {
        guard let first = points.first else { return }
        if startNew { move(to: CGPoint(x: first.x * s, y: first.y * s)) }
        for p in points.dropFirst() { addLine(to: CGPoint(x: p.x * s, y: p.y * s)) }
    }
}

private func unitScale(_ rect: CGRect) -> CGFloat {
    min(rect.width / Geo.box.width, rect.height / Geo.box.height)
}

// MARK: - Shapes

/// The pin: tip → left flank → around the dial → right flank → tip,
/// with a gap at the upper right for the needle.
private struct PinOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unitScale(rect)
        var p = Path()

        // Left flank, then up and over the top, stopping before the gap.
        p.move(to: CGPoint(x: Geo.tip.x * s, y: Geo.tip.y * s))
        let leftArc = Geo.arc(from: Geo.leftTangentAngle, to: Geo.gapStart, radius: Geo.radius)
        p.addSampled(leftArc, scale: s, startNew: false)

        // Resume after the gap, come down the right flank into the tip.
        let rightArc = Geo.arc(from: Geo.gapEnd, to: 360 + Geo.rightTangentAngle, radius: Geo.radius)
        p.addSampled(rightArc, scale: s)
        p.addLine(to: CGPoint(x: Geo.tip.x * s, y: Geo.tip.y * s))

        return p
    }
}

/// Six graduation marks on the inner edge of the dial, lower left → top.
private struct DialTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unitScale(rect)
        var p = Path()
        let inner: CGFloat = 24
        let outer: CGFloat = 30

        for i in 0..<6 {
            let angle = 172 + CGFloat(i) * 22          // 172° … 282°
            let a = Geo.point(angle, radius: inner)
            let b = Geo.point(angle, radius: outer)
            p.move(to: CGPoint(x: a.x * s, y: a.y * s))
            p.addLine(to: CGPoint(x: b.x * s, y: b.y * s))
        }
        return p
    }
}

/// Three ascending bars. Each leans very slightly right, and their baselines
/// follow the V of the pin, exactly as in the artwork.
private struct Bars: Shape {
    /// (topLeft x, width, top y, bottom-left y, bottom-right y)
    private static let bars: [(x: CGFloat, w: CGFloat, top: CGFloat, bl: CGFloat, br: CGFloat)] = [
        (23.0, 17.5, 58.5, 84.0, 88.0),
        (45.0, 17.5, 47.5, 93.5, 90.0),
        (67.0, 16.0, 31.5, 82.0, 78.0)
    ]

    func path(in rect: CGRect) -> Path {
        let s = unitScale(rect)
        var p = Path()
        let r: CGFloat = 2.2 * s

        for b in Self.bars {
            let lean: CGFloat = 1.4        // subtle rightward skew at the top
            let tl = CGPoint(x: (b.x + lean) * s, y: b.top * s)
            let tr = CGPoint(x: (b.x + b.w + lean) * s, y: b.top * s)
            let brp = CGPoint(x: (b.x + b.w) * s, y: b.br * s)
            let blp = CGPoint(x: b.x * s, y: b.bl * s)

            var sub = Path()
            sub.move(to: tl)
            sub.addLine(to: tr)
            sub.addLine(to: brp)
            sub.addLine(to: blp)
            sub.closeSubpath()

            // Soften the corners without losing the skew.
            p.addPath(sub.strokedPath(StrokeStyle(lineWidth: r, lineJoin: .round)))
            p.addPath(sub)
        }
        return p
    }
}

/// The needle: hub → out past the dial toward the arrowhead.
private struct Needle: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unitScale(rect)
        var p = Path()
        // Stop a little short so the arrowhead caps the line cleanly.
        let end = CGPoint(
            x: Geo.hub.x + (Geo.arrowTip.x - Geo.hub.x) * 0.82,
            y: Geo.hub.y + (Geo.arrowTip.y - Geo.hub.y) * 0.82
        )
        p.move(to: CGPoint(x: Geo.hub.x * s, y: Geo.hub.y * s))
        p.addLine(to: CGPoint(x: end.x * s, y: end.y * s))
        return p
    }
}

/// Filled triangle at the end of the needle, aligned to the shaft.
private struct ArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unitScale(rect)

        let dx = Geo.arrowTip.x - Geo.hub.x
        let dy = Geo.arrowTip.y - Geo.hub.y
        let len = max(CGFloat((Double(dx * dx + dy * dy)).squareRoot()), 0.0001)
        let ux = dx / len, uy = dy / len          // along the shaft
        let px = -uy, py = ux                     // perpendicular

        let headLength: CGFloat = 20
        let halfWidth: CGFloat = 10

        let tip = Geo.arrowTip
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        let a = CGPoint(x: base.x + px * halfWidth, y: base.y + py * halfWidth)
        let b = CGPoint(x: base.x - px * halfWidth, y: base.y - py * halfWidth)

        var p = Path()
        p.move(to: CGPoint(x: tip.x * s, y: tip.y * s))
        p.addLine(to: CGPoint(x: a.x * s, y: a.y * s))
        p.addLine(to: CGPoint(x: b.x * s, y: b.y * s))
        p.closeSubpath()
        return p
    }
}

// MARK: - Preview

#Preview("Brand mark") {
    ZStack {
        Color(hex: 0x08080D).ignoresSafeArea()
        VStack(spacing: 40) {
            GigGrowLogo(size: 160)
            HStack(spacing: 24) {
                GigGrowLogo(size: 44)
                GigGrowLogo(size: 28)
                GigGrowIconTile(size: 60)
            }
        }
    }
}
