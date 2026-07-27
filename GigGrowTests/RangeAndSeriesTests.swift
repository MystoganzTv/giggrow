//
//  RangeAndSeriesTests.swift
//  GigGrowTests
//
//  Bucketing and chart series. The risk here is silent: a month view that
//  compares itself to last week, or a bar chart that quietly drops the
//  31st of the month, looks perfectly fine on screen.
//

import XCTest
import SwiftData
@testable import GigGrow

@MainActor
final class RangeAndSeriesTests: XCTestCase {

    // MARK: Bucket geometry

    func testBucketCountsMatchLabelCounts() {
        for range in AnalyticsRange.allCases {
            XCTAssertEqual(range.labels.count, range.bucketCount,
                           "\(range.rawValue) draws \(range.bucketCount) bars but has \(range.labels.count) labels")
        }
    }

    func testComparisonUnitMatchesTheRange() {
        XCTAssertEqual(AnalyticsRange.week.comparisonUnit, .weekOfYear)
        XCTAssertEqual(AnalyticsRange.month.comparisonUnit, .month)
        XCTAssertEqual(AnalyticsRange.year.comparisonUnit, .year)
    }

    /// Weeks of the month, counted from the 1st. Day 29–31 all land in W5.
    func testMonthBucketEdges() {
        let cal = Calendar.gigGrow
        let start = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

        let expected: [(day: Int, bucket: Int)] = [
            (1, 0), (7, 0), (8, 1), (14, 1), (15, 2),
            (21, 2), (22, 3), (28, 3), (29, 4), (31, 4)
        ]
        for (day, bucket) in expected {
            let date = cal.date(from: DateComponents(year: 2026, month: 7, day: day))!
            XCTAssertEqual(
                AnalyticsRange.month.bucketIndex(for: date, windowStart: start),
                bucket,
                "day \(day) should be in W\(bucket + 1)"
            )
        }
    }

    func testYearBucketsAreMonths() {
        let cal = Calendar.gigGrow
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        for month in 1...12 {
            let date = cal.date(from: DateComponents(year: 2026, month: month, day: 15))!
            XCTAssertEqual(
                AnalyticsRange.year.bucketIndex(for: date, windowStart: start),
                month - 1
            )
        }
    }

    func testDatesOutsideTheWindowGetNoBucket() {
        let cal = Calendar.gigGrow
        let start = Fixture.weekStart()
        let wayLater = cal.date(byAdding: .day, value: 30, to: start)!
        XCTAssertNil(AnalyticsRange.week.bucketIndex(for: wayLater, windowStart: start))
    }

    // MARK: Conservation

    /// Every shift in the window must land in exactly one bar, so the bars
    /// sum back to the window's gross.
    func testWeekBucketsConserveGross() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")

        for day in 0..<7 {
            Fixture.shift(context, day: day, splits: [(account, Double(100 + day * 10), 5)])
        }

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile,
            vehicle: nil,
            range: AnalyticsRange.week.window(containing: .now),
            rangeKind: .week
        )

        XCTAssertEqual(snapshot.series.primary.count, 7)
        XCTAssertMoneyEqual(snapshot.series.primary.reduce(0, +), snapshot.weeklyTotal)
        XCTAssertMoneyEqual(snapshot.series.daily.reduce(0, +), snapshot.weeklyTotal)
    }

    /// The dashboard's weekly series must not change when Analytics is set
    /// to the year — they're deliberately separate projections.
    func testDailySeriesStaysWeeklyRegardlessOfRange() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")
        Fixture.shift(context, day: 0, splits: [(account, 200, 10)])

        let shifts = try context.fetch(FetchDescriptor<Shift>())
        let accounts = try context.fetch(FetchDescriptor<PlatformAccount>())

        let yearly = EarningsSnapshot.build(
            shifts: shifts, expenses: [], accounts: accounts,
            profile: profile, vehicle: nil,
            range: AnalyticsRange.year.window(containing: .now),
            rangeKind: .year
        )

        XCTAssertEqual(yearly.series.daily.count, 7, "daily is always the week")
        XCTAssertEqual(yearly.series.primary.count, 12, "primary follows the selected range")
        XCTAssertMoneyEqual(yearly.series.daily.reduce(0, +), 200)
    }

    /// The dashboard's rising line is a running total, so it never dips.
    func testCumulativeSeriesIsMonotonic() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")
        for day in 0..<7 {
            Fixture.shift(context, day: day, splits: [(account, 50, 3)])
        }

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile, vehicle: nil
        )

        for (a, b) in zip(snapshot.series.cumulative, snapshot.series.cumulative.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b, a)
        }
        XCTAssertMoneyEqual(snapshot.series.cumulative.last ?? 0, 350)
    }

    func testHourlyBaselineExcludesSelectedPeriod() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")
        let previousWeek = Calendar.gigGrow.date(
            byAdding: .weekOfYear, value: -1, to: Date.now
        )!

        Fixture.shift(
            context, from: 9, to: 19,
            splits: [(account, 100, 5)],
            weekOf: previousWeek
        )
        Fixture.shift(
            context, from: 9, to: 14,
            splits: [(account, 200, 8)]
        )

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: [account],
            profile: profile,
            vehicle: nil
        )

        XCTAssertEqual(snapshot.perHour, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.lifetimePerHour, 10, accuracy: 0.001,
                       "the current week must not be included in its own baseline")
    }

    // MARK: Hourly spread

    /// A shift's gross is spread across the buckets it actually spans, and
    /// none of it leaks: the buckets sum back to the week's gross.
    func testHourlyBucketsConserveGross() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, day: 0, from: 15, to: 21.5, splits: [(account, 260, 12)])
        Fixture.shift(context, day: 1, from: 8, to: 13, splits: [(account, 140, 8)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile, vehicle: nil
        )

        XCTAssertEqual(snapshot.series.hourly.count, 12)
        XCTAssertMoneyEqual(snapshot.series.hourly.reduce(0, +), 400)
    }

    /// An evening block must feed the evening buckets, not the one it started in.
    func testEveningShiftSpreadsAcrossItsBuckets() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")

        // 18:00–22:00 spans the 18h and 20h buckets (buckets start at 06:00).
        Fixture.shift(context, day: 0, from: 18, to: 22, splits: [(account, 200, 10)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile, vehicle: nil
        )

        let hourly = snapshot.series.hourly
        // Bucket index = (hour − 6) / 2 → 18h is 6, 20h is 7.
        XCTAssertMoneyEqual(hourly[6], 100)
        XCTAssertMoneyEqual(hourly[7], 100)
        XCTAssertMoneyEqual(hourly[0], 0, "nothing should land in the 06:00 bucket")
    }

    func testPeakWindowLabelFollowsTheBusiestBucket() throws {
        var series = ChartSeries.empty
        series.hourly = Array(repeating: 0, count: 12)
        series.hourly[6] = 500          // 18:00–20:00
        XCTAssertEqual(series.peakWindowLabel, "Peak 6pm–8pm")

        series.hourly = Array(repeating: 0, count: 12)
        series.hourly[0] = 10           // 06:00–08:00
        XCTAssertEqual(series.peakWindowLabel, "Peak 6am–8am")
    }

    func testPeakWindowLabelWithNoData() {
        XCTAssertEqual(ChartSeries.empty.peakWindowLabel, "No data yet")
    }

    // MARK: Normalisation

    func testChartPointsOnAFlatZeroSeriesDoNotDivideByZero() {
        let points = [Double](repeating: 0, count: 7)
            .chartPoints(box: CGSize(width: 300, height: 72))
        XCTAssertEqual(points.count, 7)
        for point in points {
            XCTAssertFinite(point.x, "x")
            XCTAssertFinite(point.y, "y")
        }
    }

    func testChartBarsOnAFlatZeroSeriesDoNotDivideByZero() {
        let bars = [Double](repeating: 0, count: 7).chartBars()
        XCTAssertEqual(bars.count, 7)
        for bar in bars {
            XCTAssertFinite(Double(bar.height), "bar height")
            XCTAssertFinite(bar.opacity, "bar opacity")
        }
    }

    /// The tallest bar is fully opaque and full height; the ramp is relative.
    func testChartBarsScaleAgainstThePeak() {
        let bars = [50.0, 100.0, 25.0].chartBars()
        XCTAssertEqual(Double(bars[1].height), 1, accuracy: 0.0001)
        XCTAssertEqual(bars[1].opacity, 1, accuracy: 0.0001)
        XCTAssertEqual(Double(bars[0].height), 0.5, accuracy: 0.0001)
    }
}
