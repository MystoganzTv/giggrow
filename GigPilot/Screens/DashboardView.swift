//
//  DashboardView.swift
//  GigPilot
//
//  Screen 01 — the week at a glance.
//

import SwiftUI

struct DashboardView: View {
    let snapshot: EarningsSnapshot

    var body: some View {
        ScreenScaffold {
            GP.Gradients.dashboardWash()
        } content: {
            header
            heroCard
            setAsideTiles
            earningsByApp
            rateTiles
            hoursCard
            trendTiles
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("This week")
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)
            Spacer()
            Monogram(letter: snapshot.driver.initial)
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Total earnings".uppercased())
                    .gpText(GP.Typo.heroEyebrow,
                            tracking: GP.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                HStack(alignment: .bottom, spacing: 10) {
                    Text(Money.cents(snapshot.weeklyTotal))
                        .gpText(GP.Typo.heroAmount, tracking: GP.Typo.heroAmountTracking)

                    Pill(text: snapshot.weeklyChange.replacingOccurrences(of: "+", with: ""),
                         foreground: GP.Palette.mint,
                         background: Color(hex: 0x34D399, opacity: 0.16),
                         font: .system(size: 13, weight: .semibold),
                         horizontalPadding: 9,
                         showsTrendArrow: true)
                        .padding(.bottom, 7)
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    HeroAreaChart(
                        points: snapshot.series.cumulative
                            .chartPoints(box: ChartData.weekTrendBox),
                        box: ChartData.weekTrendBox
                    )
                    AxisLabels(labels: ChartData.weekdayNames, color: Color.white.opacity(0.42))
                }
                .padding(.top, 18)
            }
        }
    }

    // MARK: Tax / maintenance

    private var setAsideTiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Taxes to save",
                value: Money.whole(snapshot.taxesToSave),
                footnote: "\(Int(snapshot.taxRate))% set aside",
                footnoteColor: GP.Palette.violet300.opacity(0.85),
                fill: GP.Surface.glassBright
            )
        } right: {
            StatTile(
                eyebrow: "Maintenance",
                value: Money.whole(snapshot.maintenanceThisWeek),
                footnote: "Fund \(Money.whole(snapshot.maintenanceFund))",
                footnoteColor: GP.Palette.blue300.opacity(0.85),
                fill: GP.Surface.glassBright
            )
        }
    }

    // MARK: Earnings by app

    private var earningsByApp: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Earnings by app")
                        .gpText(GP.Typo.cardTitle, tracking: GP.Typo.cardTitleTracking)
                    Spacer()
                    Text("\(snapshot.platforms.count) connected")
                        .gpText(GP.Typo.captionMuted, color: Color.white.opacity(0.40))
                }

                ForEach(snapshot.platforms) { platform in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(platform.name)
                                .gpText(GP.Typo.body, color: GP.Ink.body)
                            Spacer()
                            Text(Money.cents(snapshot.amount(for: platform)))
                                .gpText(.system(size: 14.5, weight: .semibold), tracking: -0.15)
                        }
                        ProgressBar(
                            progress: snapshot.normalisedShare(for: platform),
                            height: 6,
                            fill: platform.barGradient
                        )
                    }
                }
            }
        }
    }

    // MARK: Rates

    private var rateTiles: some View {
        TilePair {
            StatTile(eyebrow: "Per hour", value: Money.cents(snapshot.perHour))
        } right: {
            StatTile(eyebrow: "Per mile", value: Money.cents(snapshot.perMile))
        }
    }

    // MARK: Hours & mileage

    private var hoursCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Online hours")
                        unitValue(String(format: "%.1f", snapshot.onlineHours), unit: " hrs")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Eyebrow(text: "Mileage")
                        unitValue(Num.grouped(snapshot.mileage), unit: " mi")
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    SplitBar(activeShare: snapshot.activeShare)
                    HStack {
                        Text("Active \(String(format: "%.1f", snapshot.activeHours)) hrs")
                            .gpText(.system(size: 13, weight: .medium),
                                    color: GP.Palette.violet300.opacity(0.9))
                        Spacer()
                        Text("Idle \(String(format: "%.1f", snapshot.idleHours)) hrs")
                            .gpText(.system(size: 13, weight: .medium), color: GP.Ink.tertiary)
                    }
                }
            }
        }
    }

    /// Big figure with a smaller, dimmer unit suffix.
    private func unitValue(_ value: String, unit: String) -> some View {
        (
            Text(value)
                .font(GP.Typo.metricLarge)
                .foregroundColor(.white)
            + Text(unit)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color.white.opacity(0.45))
        )
        .tracking(GP.Typo.metricLargeTracking)
    }

    // MARK: Trends

    private var trendTiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Weekly trend",
                value: snapshot.weeklyChange,
                valueFont: GP.Typo.headline,
                valueTracking: GP.Typo.headlineTracking,
                valueColor: GP.Palette.mint
            ) {
                Sparkline(points: snapshot.series.daily
                            .chartPoints(box: ChartData.sparklineBox),
                          color: GP.Palette.mint.opacity(0.8))
                    .padding(.top, 8)
            }
        } right: {
            StatTile(
                eyebrow: "Monthly trend",
                value: snapshot.monthlyChange,
                valueFont: GP.Typo.headline,
                valueTracking: GP.Typo.headlineTracking,
                valueColor: GP.Palette.blue300
            ) {
                Sparkline(points: snapshot.series.monthly
                            .chartPoints(box: ChartData.sparklineBox),
                          color: GP.Palette.blue300.opacity(0.8))
                    .padding(.top, 8)
            }
        }
    }
}

#Preview("Dashboard") {
    DashboardView(snapshot: .mock)
        .preferredColorScheme(.dark)
}
