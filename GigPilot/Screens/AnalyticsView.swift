//
//  AnalyticsView.swift
//  GigPilot
//
//  Screen 03 — trends, comparisons and the year's set-asides.
//

import SwiftUI

struct AnalyticsView: View {
    /// Built for whatever `range` is set to, so every figure on this screen
    /// belongs to the selected period rather than always to the week.
    let snapshot: EarningsSnapshot
    @Binding var selection: RangeSelection


    private var range: AnalyticsRange { selection.range }
    var onShowExpenses: () -> Void = {}


    var body: some View {
        ScreenScaffold {
            GP.Gradients.analyticsWash()
        } content: {
            Text("Analytics")
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)

            // The picker stays put whether or not this period has data —
            // an empty week shouldn't trap you out of checking the month.
            segmentedControl
            ownAverageCard

            if snapshot.hasData {
                weeklyIncomeCard
                monthlyIncomeCard
                comparisonCard
                hourlyCard
                tiles
                setAsideCard
            } else {
                EmptyStateCard(
                    title: "Nothing logged \(range.possessive.lowercased())",
                    message: "Analytics needs a few shifts before the patterns mean anything — which hours pay best, which app earns most per hour, where the miles go."
                )
            }
        }
    }

    /// This period against your own history.
    ///
    /// Solo compares you to your city's average, which is the most motivating
    /// number in their app and the one thing GigPilot can't copy: it needs
    /// aggregated data from other drivers, which means a server, which would
    /// break the promise on the privacy screen. Comparing you to yourself
    /// needs nobody else's data and answers the more useful question anyway —
    /// not "am I better than strangers" but "is this week better than mine
    /// usually are".
    @ViewBuilder
    private var ownAverageCard: some View {
        if snapshot.perHour > 0, snapshot.lifetimePerHour > 0 {
            let mine = snapshot.lifetimePerHour
            let now = snapshot.perHour
            let ahead = now >= mine
            let change = mine > 0 ? (now - mine) / mine * 100 : 0

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your usual")
                                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                            Text("\(Money.cents(mine))/hr")
                                .gpText(.system(size: 17, weight: .semibold), tracking: -0.3,
                                        color: GP.Ink.tertiary)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(selection.title)
                                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                            Text("\(Money.cents(now))/hr")
                                .gpText(.system(size: 17, weight: .semibold), tracking: -0.3)
                        }
                    }

                    // Where this period sits against the average, on a bar
                    // whose midpoint is the average.
                    GeometryReader { geo in
                        let ratio = min(max(now / (mine * 2), 0.02), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(GP.Surface.glassFaint)
                            Capsule()
                                .fill(ahead ? AnyShapeStyle(GP.Palette.mint)
                                            : AnyShapeStyle(GP.Gradients.brandMark))
                                .frame(width: geo.size.width * ratio)
                            // The midpoint marker *is* the average.
                            Rectangle()
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 2)
                                .offset(x: geo.size.width / 2 - 1)
                        }
                    }
                    .frame(height: 8)

                    Text(ahead
                         ? String(format: "%.0f%% above your average. Whatever you did here, it worked.", change)
                         : String(format: "%.0f%% below your average — worth a look at which hours you drove.", abs(change)))
                        .gpText(GP.Typo.footnote,
                                color: ahead ? GP.Palette.mint : GP.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Range picker

    private var segmentedControl: some View {
        // Size and which-one in one control. The picker alone could only ever
        // mean "the current week", which is why importing June showed nothing.
        RangeBar(selection: $selection)
    }

    // MARK: Weekly income

    private var weeklyIncomeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(range.possessive)'s income")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Spacer()
                    Text(Money.cents(snapshot.weeklyTotal))
                        .gpText(.system(size: 15, weight: .semibold))
                }

                BarChart(bars: snapshot.series.primary.chartBars(),
                         maxHeight: 1,
                         height: 100,
                         spacing: range == .year ? 5 : 12)
                    .padding(.top, 16)

                AxisLabels(labels: snapshot.series.primaryLabels)
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

                // A brand-new account has no month-over-month history, so the
                // design's smooth curve stands in until there are two months
                // worth of shifts to draw a real one from.
                Group {
                    if snapshot.series.hasMonthlyHistory {
                        Sparkline(points: snapshot.series.monthly
                                    .chartPoints(box: ChartData.monthlyCurveBox),
                                  box: ChartData.monthlyCurveBox,
                                  color: GP.Palette.sky300,
                                  height: 104,
                                  lineWidth: 2.4,
                                  filled: true)
                    } else {
                        MonthlyCurveChart()
                    }
                }
                .padding(.top, 16)

                AxisLabels(labels: monthLabels)
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
                    Text(snapshot.series.peakWindowLabel)
                        .gpText(GP.Typo.captionMuted, color: GP.Ink.tertiary)
                }

                ColoredBarChart(bars: snapshot.series.hourly
                                    .chartColoredBars(palette: Self.hourPalette),
                                maxHeight: 1,
                                height: 78)
                    .padding(.top, 16)

                AxisLabels(labels: ChartSeries.hourLabels)
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
                Sparkline(points: snapshot.series.dailyMiles
                            .chartPoints(box: ChartData.tileSparkBox),
                          box: ChartData.tileSparkBox,
                          color: GP.Palette.violet400,
                          height: 40,
                          filled: true)
                    .padding(.top, 10)
            }
        } right: {
            // Tapping through to the expenses list — net profit is the number
            // expenses move, so this is where a driver goes looking for them.
            Button(action: onShowExpenses) {
                StatTile(
                    eyebrow: "Net profit",
                    value: Money.whole(snapshot.netProfit),
                    footnote: expenseFootnote,
                    footnoteColor: GP.Ink.tertiary,
                    valueFont: GP.Typo.metricSmall,
                    valueTracking: GP.Typo.metricSmallTracking
                ) {
                    Sparkline(points: snapshot.series.dailyNet
                                .chartPoints(box: ChartData.tileSparkBox),
                              box: ChartData.tileSparkBox,
                              color: GP.Palette.mint,
                              height: 40,
                              filled: true)
                        .padding(.top, 10)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Names the out-of-pocket figure, not the gross spend — the reserve draw
    /// doesn't touch net profit and saying otherwise would be misleading.
    private var expenseFootnote: String {
        let pocket = snapshot.expensesTotal - snapshot.reserveDraw
        guard snapshot.expensesTotal > 0 else { return "Add expenses" }
        if snapshot.reserveDraw > 0 {
            return "\(Money.whole(pocket)) costs · \(Money.whole(snapshot.reserveDraw)) from reserve"
        }
        return "After \(Money.whole(pocket)) of costs"
    }

    // MARK: Chart support

    /// Violet through indigo, walked across the day so the peak reads warm.
    private static let hourPalette: [Color] = [
        Color(hex: 0x6366F1), Color(hex: 0x7C6CF6), Color(hex: 0x8B5CF6),
        Color(hex: 0x9B6CFA), Color(hex: 0xA78BFA), Color(hex: 0x818CF8)
    ]

    /// Month abbreviations for the last four months, ending with this one.
    private var monthLabels: [String] {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        let cal = Calendar.gigPilot
        return (0..<4).reversed().compactMap { offset in
            cal.date(byAdding: .month, value: -offset, to: .now).map(f.string(from:))
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
    AnalyticsView(snapshot: .mock, selection: .constant(RangeSelection()))
        .preferredColorScheme(.dark)
}

#Preview("Analytics — empty") {
    AnalyticsView(snapshot: .empty, selection: .constant(RangeSelection()))
        .preferredColorScheme(.dark)
}
