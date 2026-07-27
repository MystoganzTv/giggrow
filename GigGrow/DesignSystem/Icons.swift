//
//  Icons.swift
//  GigGrow
//
//  The five tab glyphs, traced from the SVG paths in GigGrow.dc.html.
//  Drawn rather than mapped onto SF Symbols so the stroke weight and corner
//  radii match the design exactly. All authored in a 24 × 24 box.
//

import SwiftUI

/// Shared stroke treatment: `stroke-width:1.9; linecap:round; linejoin:round`.
private let iconStroke = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)

enum GGIcon: String, CaseIterable, Identifiable {
    // Apps came out and Taxes went in. The per-platform split it showed
    // already lives inside Analytics, whereas "what do I owe" is the question
    // that brings drivers to an app like this and had no home at all.
    case dashboard, taxes, analytics, vehicle, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .taxes:     return "Taxes"
        case .analytics: return "Analytics"
        case .vehicle:   return "Vehicle"
        case .settings:  return "Settings"
        }
    }
}

/// Renders a tab glyph at the given point size.
struct GGIconView: View {
    let icon: GGIcon
    var size: CGFloat = 24

    var body: some View {
        Group {
            switch icon {
            case .dashboard: DashboardGlyph().stroke(style: scaled)
            case .taxes:     TaxGlyph().stroke(style: scaled)
            case .analytics: AnalyticsGlyph().stroke(style: scaled)
            case .vehicle:   VehicleGlyph().stroke(style: scaled)
            case .settings:  SettingsGlyph().stroke(style: scaled)
            }
        }
        .frame(width: size, height: size)
    }

    private var scaled: StrokeStyle {
        StrokeStyle(lineWidth: 1.9 * size / 24, lineCap: .round, lineJoin: .round)
    }
}

// MARK: - Glyphs

private func unit(_ rect: CGRect) -> CGFloat { min(rect.width, rect.height) / 24 }

/// Four rounded squares — `<rect … rx="2.4">` × 4.
struct DashboardGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unit(rect)
        var p = Path()
        for origin in [CGPoint(x: 3, y: 3), CGPoint(x: 13.5, y: 3),
                       CGPoint(x: 3, y: 13.5), CGPoint(x: 13.5, y: 13.5)] {
            p.addRoundedRect(
                in: CGRect(x: origin.x * s, y: origin.y * s, width: 7.5 * s, height: 7.5 * s),
                cornerSize: CGSize(width: 2.4 * s, height: 2.4 * s),
                style: .continuous
            )
        }
        return p
    }
}

/// Four circles in a 2 × 2 grid.
/// A receipt with a torn edge — the one document every driver recognises.
struct TaxGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()

        // Body, with a zigzag along the bottom.
        path.move(to: CGPoint(x: w * 0.22, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.88))
        let teeth = 4
        for tooth in 0..<teeth {
            let step = 0.56 / Double(teeth)
            let x = 0.78 - step * (Double(tooth) + 0.5)
            path.addLine(to: CGPoint(x: w * x, y: h * (tooth % 2 == 0 ? 0.74 : 0.88)))
        }
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.88))
        path.closeSubpath()

        // Two lines of figures.
        path.move(to: CGPoint(x: w * 0.34, y: h * 0.32))
        path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.32))
        path.move(to: CGPoint(x: w * 0.34, y: h * 0.50))
        path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.50))
        return path
    }
}

struct AppsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unit(rect)
        var p = Path()
        for c in [CGPoint(x: 7, y: 7), CGPoint(x: 17, y: 7),
                  CGPoint(x: 7, y: 17), CGPoint(x: 17, y: 17)] {
            p.addEllipse(in: CGRect(x: (c.x - 4) * s, y: (c.y - 4) * s,
                                    width: 8 * s, height: 8 * s))
        }
        return p
    }
}

/// Three bars on a baseline.
struct AnalyticsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unit(rect)
        var p = Path()
        // M4 19V11
        p.move(to: CGPoint(x: 4 * s, y: 19 * s));  p.addLine(to: CGPoint(x: 4 * s, y: 11 * s))
        // M10 19V5
        p.move(to: CGPoint(x: 10 * s, y: 19 * s)); p.addLine(to: CGPoint(x: 10 * s, y: 5 * s))
        // M16 19v-6
        p.move(to: CGPoint(x: 16 * s, y: 19 * s)); p.addLine(to: CGPoint(x: 16 * s, y: 13 * s))
        // M21 19H3
        p.move(to: CGPoint(x: 21 * s, y: 19 * s)); p.addLine(to: CGPoint(x: 3 * s, y: 19 * s))
        return p
    }
}

/// Car silhouette with two wheels.
struct VehicleGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unit(rect)
        var p = Path()
        // M4 16v-3.2L6 7h12l2 5.8V16
        p.move(to: CGPoint(x: 4 * s, y: 16 * s))
        p.addLine(to: CGPoint(x: 4 * s, y: 12.8 * s))
        p.addLine(to: CGPoint(x: 6 * s, y: 7 * s))
        p.addLine(to: CGPoint(x: 18 * s, y: 7 * s))
        p.addLine(to: CGPoint(x: 20 * s, y: 12.8 * s))
        p.addLine(to: CGPoint(x: 20 * s, y: 16 * s))
        // M4 16h16
        p.move(to: CGPoint(x: 4 * s, y: 16 * s))
        p.addLine(to: CGPoint(x: 20 * s, y: 16 * s))
        // Wheels
        p.addEllipse(in: CGRect(x: (7.5 - 1.6) * s, y: (16.5 - 1.6) * s,
                                width: 3.2 * s, height: 3.2 * s))
        p.addEllipse(in: CGRect(x: (16.5 - 1.6) * s, y: (16.5 - 1.6) * s,
                                width: 3.2 * s, height: 3.2 * s))
        return p
    }
}

/// Hub with eight rays.
struct SettingsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unit(rect)
        var p = Path()
        p.addEllipse(in: CGRect(x: (12 - 3.2) * s, y: (12 - 3.2) * s,
                                width: 6.4 * s, height: 6.4 * s))

        // Cardinal rays: M12 3v2.4  M12 18.6V21  M3 12h2.4  M18.6 12H21
        let cardinals: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 12, y: 3),    CGPoint(x: 12, y: 5.4)),
            (CGPoint(x: 12, y: 18.6), CGPoint(x: 12, y: 21)),
            (CGPoint(x: 3, y: 12),    CGPoint(x: 5.4, y: 12)),
            (CGPoint(x: 18.6, y: 12), CGPoint(x: 21, y: 12))
        ]
        // Diagonal rays: M5.6 5.6l1.7 1.7 … etc.
        let diagonals: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 5.6, y: 5.6),   CGPoint(x: 7.3, y: 7.3)),
            (CGPoint(x: 16.7, y: 16.7), CGPoint(x: 18.4, y: 18.4)),
            (CGPoint(x: 18.4, y: 5.6),  CGPoint(x: 16.7, y: 7.3)),
            (CGPoint(x: 7.3, y: 16.7),  CGPoint(x: 5.6, y: 18.4))
        ]

        for (a, b) in cardinals + diagonals {
            p.move(to: CGPoint(x: a.x * s, y: a.y * s))
            p.addLine(to: CGPoint(x: b.x * s, y: b.y * s))
        }
        return p
    }
}

// MARK: - Small utility glyphs

/// Circular-arrow "synced" mark on the Apps hero card.
struct RefreshGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unit(rect)
        var p = Path()
        // M20 12a8 8 0 1 1-2.6-5.9  — an open circle, gap at the top right.
        let c = CGPoint(x: 12 * s, y: 12 * s)
        let r = 8 * s
        let start: CGFloat = 0        // 3 o'clock
        let end: CGFloat = -48        // stops short, leaving the notch
        let steps = 60
        for i in 0...steps {
            let deg = start + (360 + end - start) * CGFloat(i) / CGFloat(steps)
            let a = deg * .pi / 180
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 {
                p.move(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        // M20 4v4.5h-4.5 — the tick that closes the notch.
        p.move(to: CGPoint(x: 20 * s, y: 4 * s))
        p.addLine(to: CGPoint(x: 20 * s, y: 8.5 * s))
        p.addLine(to: CGPoint(x: 15.5 * s, y: 8.5 * s))
        return p
    }
}

/// Plus sign for the "Connect another platform" affordance.
struct PlusGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = unit(rect)
        var p = Path()
        p.move(to: CGPoint(x: 12 * s, y: 5 * s));  p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
        p.move(to: CGPoint(x: 5 * s, y: 12 * s));  p.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
        return p
    }
}

#Preview("Icons") {
    ZStack {
        Color(hex: 0x08080D).ignoresSafeArea()
        HStack(spacing: 22) {
            ForEach(GGIcon.allCases) { icon in
                GGIconView(icon: icon, size: 28)
                    .foregroundStyle(GG.Palette.violet400)
            }
        }
    }
}
