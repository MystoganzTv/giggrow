//
//  AnalyticsView.swift
//  GigGrow
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
            GG.Gradients.analyticsWash()
        } content: {
            Text("Analytics")
                .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)

            // The picker stays put whether or not this period has data —
            // an empty week shouldn't trap you out of checking the month.
            segmentedControl
            ownAverageCard

            if snapshot.hasData {
                weeklyIncomeCard
                monthlyIncomeCard
                comparisonCard
                if range == .week { dailyByAppCard }
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
    /// number in their app and the one thing GigGrow can't copy: it needs
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
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                            Text("\(Money.cents(mine))/hr")
                                .ggText(.system(size: 17, weight: .semibold), tracking: -0.3,
                                        color: GG.Ink.tertiary)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(selection.title)
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                            Text("\(Money.cents(now))/hr")
                                .ggText(.system(size: 17, weight: .semibold), tracking: -0.3)
                        }
                    }

                    // Where this period sits against the average, on a bar
                    // whose midpoint is the average.
                    GeometryReader { geo in
                        let ratio = min(max(now / (mine * 2), 0.02), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(GG.Surface.glassFaint)
                            Capsule()
                                .fill(ahead ? AnyShapeStyle(GG.Palette.mint)
                                            : AnyShapeStyle(GG.Gradients.brandMark))
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
                        .ggText(GG.Typo.footnote,
                                color: ahead ? GG.Palette.mint : GG.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if snapshot.perHour > 0 {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your baseline starts here")
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                    Text("\(selection.title) is your first period of data at \(Money.cents(snapshot.perHour))/hr. After another period, GigGrow can compare it with your real history.")
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
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
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                    Spacer()
                    Text(Money.cents(snapshot.weeklyTotal))
                        .ggText(.system(size: 15, weight: .semibold))
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
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                    Spacer()
                    Text(Money.whole(snapshot.monthlyIncome))
                        .ggText(.system(size: 15, weight: .semibold))
                }

                if snapshot.series.hasMonthlyHistory {
                    Sparkline(points: snapshot.series.monthly
                                .chartPoints(box: ChartData.monthlyCurveBox),
                              box: ChartData.monthlyCurveBox,
                              color: GG.Palette.sky300,
                              height: 104,
                              lineWidth: 2.4,
                              filled: true)
                        .padding(.top, 16)

                    AxisLabels(labels: monthLabels)
                        .padding(.top, 6)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Not enough history yet")
                            .ggText(.system(size: 14, weight: .semibold),
                                    color: GG.Ink.secondary)
                        Text("The month-to-month chart appears after two months with earnings.")
                            .ggText(GG.Typo.footnote, color: GG.Ink.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 18)
                }
            }
        }
    }

    // MARK: App comparison

    private var comparisonCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("App comparison")
                    .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

                ForEach(snapshot.platforms) { platform in
                    HStack(spacing: 12) {
                        Text(platform.short)
                            .ggText(.system(size: 12.5, weight: .medium), color: GG.Ink.secondary)
                            .frame(width: 64, alignment: .leading)

                        ProgressBar(
                            progress: snapshot.normalisedShare(for: platform),
                            height: 9,
                            fill: platform.barGradient
                        )

                        Text(platform.hourly)
                            .ggText(.system(size: 12.5, weight: .semibold))
                            .frame(width: 58, alignment: .trailing)
                    }
                }

                if snapshot.platforms.count == 1, let only = snapshot.platforms.first {
                    Text("Only \(only.name) has earnings in \(selection.title). Choose Month or Year to compare apps imported in different weeks.")
                        .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Daily earnings by app

    /// The weekly import turns Lyft and Uber chart columns into dated
    /// earnings. This is the visible audit trail: the driver can see exactly
    /// which app contributed money on each day after the import sheet closes.
    private var dailyByAppCard: some View {
        let sharedPeak = max(
            snapshot.platforms
                .flatMap(\.daily)
                .max() ?? 0,
            1
        )

        return GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily earnings by app")
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                    Text("Weekly totals are exact. Daily bars and whole-dollar amounts are estimates read from each app's chart.")
                        .ggText(GG.Typo.footnote, color: GG.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(snapshot.platforms.enumerated()), id: \.element.id) { index, platform in
                    if index > 0 { RowDivider(color: GG.Surface.dividerSoft) }
                    dailyPlatform(platform, sharedPeak: sharedPeak)
                }
            }
        }
    }

    private func dailyPlatform(_ platform: Platform, sharedPeak: Double) -> some View {
        let values = platform.daily.count == 7
            ? platform.daily
            : Array(repeating: 0, count: 7)
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(platform.brandGradient)
                        .frame(width: 8, height: 8)
                    Text(platform.name)
                        .ggText(.system(size: 14, weight: .semibold))
                }
                Spacer()
                Text(Money.cents(values.reduce(0, +)))
                    .ggText(.system(size: 13.5, weight: .semibold),
                            color: GG.Ink.secondary)
            }

            ForEach(values.indices, id: \.self) { day in
                HStack(spacing: 10) {
                    Text(labels[day])
                        .ggText(.system(size: 11.5, weight: .medium),
                                color: GG.Ink.tertiary)
                        .frame(width: 30, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(GG.Surface.glassFaint)
                            if values[day] > 0 {
                                Capsule()
                                    .fill(platform.barGradient)
                                    .frame(width: max(geo.size.width * values[day] / sharedPeak, 4))
                            }
                        }
                    }
                    .frame(height: 6)

                    Text(values[day] > 0 ? "~\(Money.whole(values[day]))" : "—")
                        .ggText(.system(size: 11.5, weight: .semibold),
                                color: values[day] > 0 ? GG.Ink.secondary : GG.Ink.muted)
                        .frame(width: 62, alignment: .trailing)
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
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                    Spacer()
                    Text(snapshot.series.peakWindowLabel)
                        .ggText(GG.Typo.captionMuted, color: GG.Ink.tertiary)
                }

                if snapshot.series.hourly.contains(where: { $0 > 0 }) {
                    ColoredBarChart(bars: snapshot.series.hourly
                                        .chartColoredBars(palette: Self.hourPalette),
                                    maxHeight: 1,
                                    height: 78)
                        .padding(.top, 16)

                    AxisLabels(labels: ChartSeries.hourLabels)
                        .padding(.top, 6)
                } else {
                    Text("Weekly summaries include total online time, but not the time of day. Log a shift with start and end times to unlock hourly earnings.")
                        .ggText(.system(size: 12.5, weight: .regular), color: GG.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 13)
                }
            }
        }
    }

    // MARK: Mileage / profit

    private var tiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Mileage",
                value: "\(Num.grouped(snapshot.mileage)) mi",
                valueFont: GG.Typo.metricSmall,
                valueTracking: GG.Typo.metricSmallTracking
            ) {
                Sparkline(points: snapshot.series.dailyMiles
                            .chartPoints(box: ChartData.tileSparkBox),
                          box: ChartData.tileSparkBox,
                          color: GG.Palette.violet400,
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
                    footnoteColor: GG.Ink.tertiary,
                    valueFont: GG.Typo.metricSmall,
                    valueTracking: GG.Typo.metricSmallTracking
                ) {
                    Sparkline(points: snapshot.series.dailyNet
                                .chartPoints(box: ChartData.tileSparkBox),
                              box: ChartData.tileSparkBox,
                              color: GG.Palette.mint,
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
        let cal = Calendar.gigGrow
        return (0..<4).reversed().compactMap { offset in
            cal.date(byAdding: .month, value: -offset, to: .now).map(f.string(from:))
        }
    }

    // MARK: Set aside this year

    private var setAsideCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Set aside this year")
                    .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

                HStack(spacing: 22) {
                    // Design draws dasharray 283 / offset 82 → ≈71% complete,
                    // and dasharray 195 / offset 88 → ≈55%.
                    DonutRings(outer: 0.71, inner: 0.55)

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            LegendDot(color: GG.Palette.violet400, label: "Tax savings")
                            Text(Money.whole(snapshot.taxSavingsYTD))
                                .ggText(GG.Typo.metricTiny, tracking: GG.Typo.metricTinyTracking)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            LegendDot(color: GG.Palette.blue400, label: "Maintenance")
                            Text(Money.whole(snapshot.maintenanceFund))
                                .ggText(GG.Typo.metricTiny, tracking: GG.Typo.metricTinyTracking)
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
