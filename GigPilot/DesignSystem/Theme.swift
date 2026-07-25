//
//  Theme.swift
//  GigPilot
//
//  Design tokens extracted from GigPilot.dc.html.
//  Every colour, radius and type ramp here maps 1:1 to a value in the design doc.
//

import SwiftUI

// MARK: - Colour

extension Color {
    /// Creates a colour from a hex integer, e.g. `Color(hex: 0x8B5CF6)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum GP {

    // MARK: Palette

    enum Palette {
        /// Screen base — `#08080D`
        static let screen = Color(hex: 0x08080D)
        /// Canvas base behind the device — `#06060A`
        static let canvas = Color(hex: 0x06060A)

        static let violet300 = Color(hex: 0xC4B5FD)
        static let violet400 = Color(hex: 0xA78BFA)
        static let violet500 = Color(hex: 0x8B5CF6)
        static let violet600 = Color(hex: 0x7C5CF6)

        static let indigo400 = Color(hex: 0x818CF8)
        static let indigo500 = Color(hex: 0x6366F1)
        static let indigo600 = Color(hex: 0x4F76F6)

        static let blue300 = Color(hex: 0x93C5FD)
        static let blue400 = Color(hex: 0x60A5FA)
        static let blue500 = Color(hex: 0x3B82F6)

        static let sky300 = Color(hex: 0x7DD3FC)
        static let sky400 = Color(hex: 0x38BDF8)

        static let fuchsia400 = Color(hex: 0xC084FC)

        /// Positive delta green — `#5EEAB0`
        static let mint = Color(hex: 0x5EEAB0)
        /// Warning amber — `#FDBA74`
        static let amber = Color(hex: 0xFDBA74)
    }

    // MARK: Semantic colours

    enum Ink {
        static let primary = Color.white
        /// Section subtitles, secondary values.
        static let secondary = Color.white.opacity(0.50)
        /// Card eyebrow labels.
        static let eyebrow = Color.white.opacity(0.45)
        /// Row metadata.
        static let tertiary = Color.white.opacity(0.42)
        /// Muted counts and secondary captions.
        static let muted = Color.white.opacity(0.35)
        /// Inactive tab bar items. Deliberately brighter than the design's
        /// 0.35 — a tab bar has to stay legible over whatever scrolls behind
        /// it, and in sunlight.
        static let tabInactive = Color.white.opacity(0.58)
        /// Footer text.
        static let faint = Color.white.opacity(0.28)
        /// Body text inside list rows.
        static let body = Color.white.opacity(0.85)
    }

    enum Surface {
        /// Standard glass card fill — `rgba(255,255,255,0.05)`
        static let glass = Color.white.opacity(0.05)
        /// Slightly brighter glass used by the dashboard stat pair.
        static let glassBright = Color.white.opacity(0.055)
        /// Dashed "connect another platform" affordance.
        static let glassFaint = Color.white.opacity(0.035)
        /// Hairline border on glass cards.
        static let stroke = Color.white.opacity(0.09)
        /// Brighter border used by hero (gradient) cards.
        static let strokeBright = Color.white.opacity(0.12)
        /// Dashed border colour.
        static let strokeDashed = Color.white.opacity(0.14)
        /// Divider between rows inside a grouped card.
        static let divider = Color.white.opacity(0.06)
        /// Divider inside settings groups (very slightly lighter).
        static let dividerSoft = Color.white.opacity(0.055)
        /// Empty track behind progress bars.
        static let track = Color.white.opacity(0.07)
        /// Idle segment of the hours bar.
        static let trackFill = Color.white.opacity(0.16)
    }

    // MARK: Gradients

    enum Gradients {

        /// Ambient wash behind the Dashboard screen.
        static func dashboardWash() -> some View {
            ZStack {
                RadialWash(color: Color(hex: 0x8B5CF6, opacity: 0.30),
                           center: .init(x: 0.82, y: -0.06),
                           size: .init(width: 340, height: 300))
                RadialWash(color: Color(hex: 0x3B82F6, opacity: 0.18),
                           center: .init(x: 0.05, y: 0.12),
                           size: .init(width: 300, height: 280))
            }
        }

        static func appsWash() -> some View {
            ZStack {
                RadialWash(color: Color(hex: 0x3B82F6, opacity: 0.26),
                           center: .init(x: 0.15, y: -0.04),
                           size: .init(width: 320, height: 280))
                RadialWash(color: Color(hex: 0x8B5CF6, opacity: 0.16),
                           center: .init(x: 0.95, y: 0.30),
                           size: .init(width: 280, height: 260))
            }
        }

        static func analyticsWash() -> some View {
            ZStack {
                RadialWash(color: Color(hex: 0x6366F1, opacity: 0.28),
                           center: .init(x: 0.78, y: -0.06),
                           size: .init(width: 340, height: 300))
                RadialWash(color: Color(hex: 0x8B5CF6, opacity: 0.14),
                           center: .init(x: 0.0, y: 0.40),
                           size: .init(width: 300, height: 300))
            }
        }

        static func vehicleWash() -> some View {
            ZStack {
                RadialWash(color: Color(hex: 0x7C5CF6, opacity: 0.30),
                           center: .init(x: 0.50, y: -0.08),
                           size: .init(width: 360, height: 320))
                RadialWash(color: Color(hex: 0x3B82F6, opacity: 0.14),
                           center: .init(x: 1.0, y: 0.55),
                           size: .init(width: 300, height: 300))
            }
        }

        static func settingsWash() -> some View {
            ZStack {
                RadialWash(color: Color(hex: 0x8B5CF6, opacity: 0.24),
                           center: .init(x: 0.20, y: -0.05),
                           size: .init(width: 340, height: 300))
                RadialWash(color: Color(hex: 0x3B82F6, opacity: 0.14),
                           center: .init(x: 0.95, y: 0.45),
                           size: .init(width: 300, height: 280))
            }
        }

        /// Violet → blue hero card fill.
        /// `linear-gradient(150deg, rgba(139,92,246,.30), rgba(59,130,246,.16) 60%, rgba(255,255,255,.03))`
        static let heroViolet = LinearGradient(
            stops: [
                .init(color: Color(hex: 0x8B5CF6, opacity: 0.30), location: 0.0),
                .init(color: Color(hex: 0x3B82F6, opacity: 0.16), location: 0.60),
                .init(color: Color.white.opacity(0.03), location: 1.0)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Blue-led variant used by the Apps "combined week" card.
        static let heroBlue = LinearGradient(
            stops: [
                .init(color: Color(hex: 0x3B82F6, opacity: 0.26), location: 0.0),
                .init(color: Color(hex: 0x8B5CF6, opacity: 0.14), location: 0.70),
                .init(color: Color.white.opacity(0.03), location: 1.0)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Vehicle header card.
        static let heroVehicle = LinearGradient(
            stops: [
                .init(color: Color(hex: 0x8B5CF6, opacity: 0.26), location: 0.0),
                .init(color: Color(hex: 0x3B82F6, opacity: 0.14), location: 0.65),
                .init(color: Color.white.opacity(0.03), location: 1.0)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// GigPilot Pro card.
        static let heroPro = LinearGradient(
            stops: [
                .init(color: Color(hex: 0x8B5CF6, opacity: 0.28), location: 0.0),
                .init(color: Color(hex: 0x3B82F6, opacity: 0.15), location: 0.70),
                .init(color: Color.white.opacity(0.03), location: 1.0)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Selected pill in the analytics segmented control.
        static let segment = LinearGradient(
            colors: [Palette.violet500, Palette.indigo600],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Active portion of the online-hours bar.
        static let activeHours = LinearGradient(
            colors: [Palette.violet500, Palette.indigo500],
            startPoint: .leading, endPoint: .trailing
        )

        /// Maintenance fund progress.
        static let maintenance = LinearGradient(
            colors: [Palette.violet500, Palette.blue400],
            startPoint: .leading, endPoint: .trailing
        )

        /// App icon / avatar mark.
        static let brandMark = LinearGradient(
            colors: [Palette.violet500, Palette.blue500],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Vertical bar fill used by the weekly income chart.
        static let bar = LinearGradient(
            colors: [Palette.violet400, Palette.indigo600],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Radii

    enum Radius {
        static let hero: CGFloat = 30
        static let card: CGFloat = 28
        static let tile: CGFloat = 26
        static let badge: CGFloat = 15
        static let pill: CGFloat = 999
    }

    // MARK: Layout

    enum Layout {
        /// Horizontal inset of every screen's scroll content.
        static let screenInset: CGFloat = 20
        /// Vertical rhythm between top-level cards.
        static let stackSpacing: CGFloat = 14
        /// Gap between the two tiles of a 2-up grid.
        static let gridGap: CGFloat = 12
        /// Height of the custom tab bar, excluding the home-indicator inset.
        static let tabBarHeight: CGFloat = 62
        /// Clearance below the last card. Has to cover the floating Log
        /// button as well as the bar, or the final card hides behind it.
        static let scrollBottomPadding: CGFloat = 66
    }

    // MARK: Typography
    //
    // The design uses SF Pro Display with variable weights (680, 640, 560, …).
    // Those are mapped onto the nearest system weight, and `tracking` is
    // computed from the design's `letter-spacing` em value × font size.

    enum Typo {
        /// 30px / 680 / -0.035em — screen titles ("This week", "Apps", "Vehicle").
        static let screenTitle = Font.system(size: 30, weight: .bold)
        static let screenTitleTracking: CGFloat = -1.05

        /// 54px / 700 / -0.045em — dashboard hero amount.
        static let heroAmount = Font.system(size: 54, weight: .bold)
        static let heroAmountTracking: CGFloat = -2.43

        /// 44px / 700 / -0.04em — maintenance fund total.
        static let bigAmount = Font.system(size: 44, weight: .bold)
        static let bigAmountTracking: CGFloat = -1.76

        /// 38px / 700 / -0.04em — combined week amount.
        static let heroAmountSmall = Font.system(size: 38, weight: .bold)
        static let heroAmountSmallTracking: CGFloat = -1.52

        /// 34px / 680 / -0.035em — online hours / mileage figures.
        static let metricLarge = Font.system(size: 34, weight: .bold)
        static let metricLargeTracking: CGFloat = -1.19

        /// 27px / 660 / -0.03em — stat tile values.
        static let metric = Font.system(size: 27, weight: .semibold)
        static let metricTracking: CGFloat = -0.81

        /// 26px / 660 / -0.03em — vehicle & analytics tile values.
        static let metricSmall = Font.system(size: 26, weight: .semibold)
        static let metricSmallTracking: CGFloat = -0.78

        /// 23px / 660 / -0.025em — donut legend values.
        static let metricTiny = Font.system(size: 23, weight: .semibold)
        static let metricTinyTracking: CGFloat = -0.58

        /// 22px / 660 / -0.025em — trend percentages, vehicle name.
        static let headline = Font.system(size: 22, weight: .semibold)
        static let headlineTracking: CGFloat = -0.55

        /// 18px / 600 / -0.02em — profile name.
        static let title3 = Font.system(size: 18, weight: .semibold)
        static let title3Tracking: CGFloat = -0.36

        /// 17px / 600 / -0.015em — card titles.
        static let cardTitle = Font.system(size: 17, weight: .semibold)
        static let cardTitleTracking: CGFloat = -0.26

        /// 16.5px / 580 / -0.012em — platform names, section headers.
        static let rowTitle = Font.system(size: 16.5, weight: .semibold)
        static let rowTitleTracking: CGFloat = -0.20

        /// 15.5px / 540 / 0 — service + settings row labels.
        static let rowLabel = Font.system(size: 15.5, weight: .medium)

        /// 15px / 440 — screen subtitle.
        static let subtitle = Font.system(size: 15, weight: .regular)

        /// 14.5px / 540 — earnings-by-app row.
        static let body = Font.system(size: 14.5, weight: .medium)

        /// 13.5px / 500 — card metadata.
        static let caption = Font.system(size: 13.5, weight: .regular)

        /// 13px / 520 — muted counts, "6 connected".
        static let captionMuted = Font.system(size: 13, weight: .medium)

        /// 12.5px / 480 — row metadata, legend labels.
        static let footnote = Font.system(size: 12.5, weight: .regular)

        /// 12px / 600 / 0.12em uppercase — group titles.
        static let groupLabel = Font.system(size: 12, weight: .semibold)
        static let groupLabelTracking: CGFloat = 1.44

        /// 11.5px / 600 / 0.1em uppercase — tile eyebrows.
        static let eyebrow = Font.system(size: 11.5, weight: .semibold)
        static let eyebrowTracking: CGFloat = 1.15

        /// 12px / 600 / 0.13em uppercase — hero card eyebrow.
        static let heroEyebrow = Font.system(size: 12, weight: .semibold)
        static let heroEyebrowTracking: CGFloat = 1.56

        /// 11px / 540 — chart axis labels.
        static let axis = Font.system(size: 11, weight: .medium)

        /// 10.5px — tab bar labels.
        static let tabLabel = Font.system(size: 10.5, weight: .medium)
        static let tabLabelActive = Font.system(size: 10.5, weight: .semibold)
    }
}

// MARK: - Radial wash

/// A soft elliptical glow, matching CSS `radial-gradient(<w> <h> at <x> <y>, color, transparent 70%)`.
struct RadialWash: View {
    let color: Color
    /// Centre expressed as a unit point of the containing view.
    let center: UnitPoint
    /// Ellipse size in points (design values are authored against a 393pt-wide frame).
    let size: CGSize

    var body: some View {
        GeometryReader { geo in
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: color, location: 0),
                    .init(color: color.opacity(0), location: 0.70),
                    .init(color: color.opacity(0), location: 1.0)
                ]),
                center: .center,
                startRadius: 0,
                endRadius: size.width / 2
            )
            // Drawn square, then squashed on Y so the falloff is elliptical,
            // matching the CSS `radial-gradient(<w> <h> at …)` form.
            .frame(width: size.width, height: size.width)
            .scaleEffect(x: 1, y: size.height / size.width, anchor: .center)
            .position(
                x: geo.size.width * center.x,
                y: geo.size.height * center.y
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Convenience

extension View {
    /// Applies a font together with its design-specified tracking in one call.
    func gpText(_ font: Font, tracking: CGFloat = 0, color: Color = GP.Ink.primary) -> some View {
        self.font(font)
            .tracking(tracking)
            .foregroundStyle(color)
    }
}
