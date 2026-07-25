//
//  Glass.swift
//  GigPilot
//
//  The translucent card surfaces every screen is built from.
//

import SwiftUI

// MARK: - Card

/// Standard frosted card: `rgba(255,255,255,0.05)` fill, hairline border,
/// large corner radius. Used for almost every block in the design.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = GP.Radius.card
    var padding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    var fill: Color = GP.Surface.glass
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(GP.Surface.stroke, lineWidth: 1)
            )
    }
}

/// Gradient "hero" card — the violet/blue washed panels at the top of
/// Dashboard, Apps, Vehicle and the GigPilot Pro row.
struct HeroCard<Content: View>: View {
    var radius: CGFloat = GP.Radius.hero
    var padding: EdgeInsets = EdgeInsets(top: 24, leading: 22, bottom: 20, trailing: 22)
    var gradient: LinearGradient = GP.Gradients.heroViolet
    /// Purple glow beneath the dashboard hero; off for the lighter panels.
    var glow: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(gradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(GP.Surface.strokeBright, lineWidth: 1)
            )
            .shadow(
                color: glow ? Color(hex: 0x5C3CDC, opacity: 0.60) : .clear,
                radius: glow ? 25 : 0,
                x: 0, y: glow ? 24 : 0
            )
    }
}

// MARK: - Small parts

/// Uppercase, wide-tracked label above a metric.
struct Eyebrow: View {
    let text: String
    var color: Color = GP.Ink.eyebrow

    var body: some View {
        Text(text.uppercased())
            .gpText(GP.Typo.eyebrow, tracking: GP.Typo.eyebrowTracking, color: color)
    }
}

/// A 2-up tile: eyebrow, big value, optional footnote or trailing content.
struct StatTile<Accessory: View>: View {
    let eyebrow: String
    let value: String
    var footnote: String? = nil
    var footnoteColor: Color = GP.Ink.secondary
    var valueFont: Font = GP.Typo.metric
    var valueTracking: CGFloat = GP.Typo.metricTracking
    var valueColor: Color = GP.Ink.primary
    var fill: Color = GP.Surface.glass
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: eyebrow)

            Text(value)
                .gpText(valueFont, tracking: valueTracking, color: valueColor)
                .padding(.top, 8)

            if let footnote {
                Text(footnote)
                    .gpText(.system(size: 12.5, weight: .medium), color: footnoteColor)
                    .padding(.top, 3)
            }

            accessory
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous)
                .strokeBorder(GP.Surface.stroke, lineWidth: 1)
        )
    }
}

extension StatTile where Accessory == EmptyView {
    init(
        eyebrow: String,
        value: String,
        footnote: String? = nil,
        footnoteColor: Color = GP.Ink.secondary,
        valueFont: Font = GP.Typo.metric,
        valueTracking: CGFloat = GP.Typo.metricTracking,
        valueColor: Color = GP.Ink.primary,
        fill: Color = GP.Surface.glass
    ) {
        self.init(
            eyebrow: eyebrow,
            value: value,
            footnote: footnote,
            footnoteColor: footnoteColor,
            valueFont: valueFont,
            valueTracking: valueTracking,
            valueColor: valueColor,
            fill: fill,
            accessory: { EmptyView() }
        )
    }
}

/// Rounded capsule badge — "+12.4%", "Due now", "Healthy".
struct Pill: View {
    let text: String
    var foreground: Color
    var background: Color
    var font: Font = .system(size: 12.5, weight: .semibold)
    var horizontalPadding: CGFloat = 11
    var verticalPadding: CGFloat = 5
    /// Optional upward arrow, as on the dashboard delta.
    var showsTrendArrow: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if showsTrendArrow {
                TrendArrow()
                    .stroke(foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 10, height: 10)
            }
            Text(text)
                .font(font)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(background, in: Capsule())
    }
}

/// The small "↑" glyph inside the delta pill (design viewBox 12×12).
private struct TrendArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 12
        var p = Path()
        p.move(to: CGPoint(x: 6 * s, y: 10 * s))
        p.addLine(to: CGPoint(x: 6 * s, y: 2 * s))
        p.move(to: CGPoint(x: 2.5 * s, y: 5.5 * s))
        p.addLine(to: CGPoint(x: 6 * s, y: 2 * s))
        p.addLine(to: CGPoint(x: 9.5 * s, y: 5.5 * s))
        return p
    }
}

// MARK: - Progress

/// A rounded track with a gradient fill — used for platform shares,
/// the maintenance fund, and the active/idle hours split.
struct ProgressBar: View {
    /// 0…1
    let progress: Double
    var height: CGFloat = 6
    var fill: LinearGradient
    var track: Color = GP.Surface.track

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(0, min(progress, 1)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Two-segment bar: active hours in gradient, idle in flat white.
struct SplitBar: View {
    /// Share of the bar taken by the active segment, 0…1.
    let activeShare: Double
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(GP.Gradients.activeHours)
                    .frame(width: max(0, min(activeShare, 1)) * geo.size.width)
                Rectangle()
                    .fill(GP.Surface.trackFill)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// Concentric progress rings for the "Set aside this year" card.
/// The design draws two arcs of radius 45 and 31 inside a 106pt box.
struct DonutRings: View {
    /// Outer ring completion, 0…1.
    let outer: Double
    /// Inner ring completion, 0…1.
    let inner: Double
    var outerColor: Color = GP.Palette.violet400
    var innerColor: Color = GP.Palette.blue400
    var size: CGFloat = 106

    var body: some View {
        ZStack {
            ring(radius: 45, lineWidth: 11, progress: outer, color: outerColor)
            ring(radius: 31, lineWidth: 9,  progress: inner, color: innerColor)
        }
        .frame(width: size, height: size)
    }

    private func ring(radius: CGFloat, lineWidth: CGFloat, progress: Double, color: Color) -> some View {
        let diameter = radius * 2
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Coloured dot + label used in the donut legend.
struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .gpText(.system(size: 12.5, weight: .medium), color: GP.Ink.secondary)
        }
    }
}

// MARK: - Chevron

/// Trailing disclosure chevron.
struct Chevron: View {
    var size: CGFloat = 16
    var color: Color = Color.white.opacity(0.28)

    var body: some View {
        ChevronShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var p = Path()
        p.move(to: CGPoint(x: 9 * s, y: 5 * s))
        p.addLine(to: CGPoint(x: 16 * s, y: 12 * s))
        p.addLine(to: CGPoint(x: 9 * s, y: 19 * s))
        return p
    }
}

// MARK: - Pro gating

/// Small "PRO" tag on a locked card.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(GP.Gradients.brandMark, in: Capsule())
    }
}

/// Wraps a Pro-only card for free users.
///
/// The content stays legible rather than being blurred out. Hiding the
/// maintenance reserve entirely would hide the only reason to subscribe —
/// the driver has to see the number they're not getting.
struct ProLock<Content: View>: View {
    let isLocked: Bool
    var action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        if !isLocked {
            content
        } else {
            Button(action: action) {
                VStack(spacing: 0) {
                    content
                        .allowsHitTesting(false)

                    HStack(spacing: 8) {
                        LockGlyph()
                            .stroke(GP.Palette.violet300,
                                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 13, height: 13)

                        Text("Unlock with Pro")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(GP.Palette.violet300)

                        Spacer(minLength: 0)

                        Chevron(size: 14, color: GP.Palette.violet300.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(GP.Palette.violet500.opacity(0.14))
                }
                .clipShape(RoundedRectangle(cornerRadius: GP.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GP.Radius.card, style: .continuous)
                        .strokeBorder(GP.Palette.violet400.opacity(0.30), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Padlock outline.
struct LockGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: 4 * s, y: 10 * s, width: 16 * s, height: 11 * s),
            cornerSize: CGSize(width: 3 * s, height: 3 * s),
            style: .continuous
        )
        // Shackle
        p.move(to: CGPoint(x: 8 * s, y: 10 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 7 * s))
        p.addCurve(
            to: CGPoint(x: 16 * s, y: 7 * s),
            control1: CGPoint(x: 8 * s, y: 2.5 * s),
            control2: CGPoint(x: 16 * s, y: 2.5 * s)
        )
        p.addLine(to: CGPoint(x: 16 * s, y: 10 * s))
        return p
    }
}

// MARK: - Divider

/// Hairline used between rows inside a grouped card. Omitted after the last row.
struct RowDivider: View {
    var color: Color = GP.Surface.divider
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}
