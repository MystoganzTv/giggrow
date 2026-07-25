//
//  AnalyticsView.swift
//  GigPilot
//
//  Screen 03 — trends, comparisons and the year's set-asides.
//

import SwiftUI

struct AnalyticsView: View {
    let snapshot: EarningsSnapshot

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    @State private var range: Range = .week
    @Namespace private var segmentNamespace

    var body: some View {
        ScreenScaffold {
            GP.Gradients.analyticsWash()
        } content: {
            Text("Analytics")
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)

            segmentedControl
            weeklyIncomeCard
            monthlyIncomeCard
            comparisonCard
            hourlyCard
            tiles
            setAsideCard
        }
    }

    // MARK: Range picker

    private var segmentedControl: some View {
        HStack(spacing: 7) {
            ForEach(Range.allCases) { option in
                let isSelected = option == range
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        range = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : Color.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(GP.Gradients.segment)
                                    .matchedGeometryEffect(id: "segment", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Weekly income

    private var weeklyIncomeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Weekly income")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Spacer()
                    Text(Money.cents(snapshot.weeklyTotal))
                        .gpText(.system(size: 15, weight: .semibold))
                }

                BarChart(bars: ChartData.weeklyBars,
                         maxHeight: ChartData.weeklyBarsMax,
                         height: 100)
                    .padding(.top, 16)

                AxisLabels(labels: ChartData.weekdayInitials)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: Monthly income

    private var monthlyIncomeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Monthly income")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Spacer()
                    Text(Money.whole(snapshot.monthlyIncome))
                        .gpText(.system(size: 15, weight: .semibold))
                }

                MonthlyCurveChart()
                    .padding(.top, 16)

                AxisLabels(labels: ChartData.monthLabels)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: App comparison

    private var comparisonCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("App comparison")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                ForEach(snapshot.platforms) { platform in
                    HStack(spacing: 12) {
                        Text(platform.short)
                            .gpText(.system(size: 12.5, weight: .medium), color: GP.Ink.secondary)
                            .frame(width: 64, alignment: .leading)

                        ProgressBar(
                            progress: snapshot.normalisedShare(for: platform),
                            height: 9,
                            fill: platform.barGradient
                        )

                        Text(platform.hourly)
                            .gpText(.system(size: 12.5, weight: .semibold))
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: Hourly distribution

    private var hourlyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hourly earnings")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Spacer()
                    Text("Peak 6–8pm")
                        .gpText(GP.Typo.captionMuted, color: GP.Ink.tertiary)
                }

                ColoredBarChart(bars: ChartData.hourlyBars,
                                maxHeight: ChartData.hourlyBarsMax,
                                height: 78)
                    .padding(.top, 16)

                AxisLabels(labels: ChartData.hourLabels)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: Mileage / profit

    private var tiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Mileage",
                value: "\(Num.grouped(snapshot.mileage)) mi",
                valueFont: GP.Typo.metricSmall,
                valueTracking: GP.Typo.metricSmallTracking
            ) {
                Sparkline(points: ChartData.mileageSpark,
                          box: ChartData.tileSparkBox,
                          color: GP.Palette.violet400,
                          height: 40,
                          filled: true)
                    .padding(.top, 10)
            }
        } right: {
            StatTile(
                eyebrow: "Net profit",
                value: Money.whole(snapshot.netProfit),
                valueFont: GP.Typo.metricSmall,
                valueTracking: GP.Typo.metricSmallTracking
            ) {
                Sparkline(points: ChartData.profitSpark,
                          box: ChartData.tileSparkBox,
                          color: GP.Palette.mint,
                          height: 40,
                          filled: true)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: Set aside this year

    private var setAsideCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Set aside this year")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                HStack(spacing: 22) {
                    // Design draws dasharray 283 / offset 82 → ≈71% complete,
                    // and dasharray 195 / offset 88 → ≈55%.
                    DonutRings(outer: 0.71, inner: 0.55)

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            LegendDot(color: GP.Palette.violet400, label: "Tax savings")
                            Text(Money.whole(snapshot.taxSavingsYTD))
                                .gpText(GP.Typo.metricTiny, tracking: GP.Typo.metricTinyTracking)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            LegendDot(color: GP.Palette.blue400, label: "Maintenance")
                            Text(Money.whole(snapshot.maintenanceFund))
                                .gpText(GP.Typo.metricTiny, tracking: GP.Typo.metricTinyTracking)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }
}

#Preview("Analytics") {
    AnalyticsView(snapshot: .mock)
        .preferredColorScheme(.dark)
}
