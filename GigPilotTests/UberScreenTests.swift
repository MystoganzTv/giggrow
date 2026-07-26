//
//  UberScreenTests.swift
//  GigPilotTests
//
//  The parser against real Uber layouts, reproduced as positioned lines.
//
//  These came from actual screenshots during testing and each one caught a
//  bug. When Uber redesigns and the parser stops finding the total, adding
//  the new layout here reproduces it without needing the phone.
//

import XCTest
@testable import GigPilot

final class UberScreenTests: XCTestCase {

    /// Builds a line with real geometry. Vision's origin is bottom-left, so
    /// `y` here is the top-down position and gets flipped.
    private func line(_ text: String, x: CGFloat, width: CGFloat,
                      y: CGFloat, height: CGFloat = 0.018,
                      confidence: Float = 0.95) -> RecognisedLine {
        RecognisedLine(
            text: text,
            confidence: confidence,
            box: CGRect(x: x, y: 1 - y - height, width: width, height: height)
        )
    }

    // MARK: Weekly summary

    /// The screen that actually has everything: total, online time, trips.
    /// "Online" and "Trips" sit side by side, which is what broke the old
    /// reading-order matching.
    private var weeklySummary: [RecognisedLine] {
        [
            line("Jul 13 - Jul 20", x: 0.32, width: 0.36, y: 0.08),
            line("$829.41",         x: 0.33, width: 0.34, y: 0.12, height: 0.040),
            line("$321.48",         x: 0.02, width: 0.14, y: 0.15, height: 0.012),
            line("Stats",           x: 0.04, width: 0.16, y: 0.34, height: 0.022),
            line("Online",          x: 0.04, width: 0.16, y: 0.38, height: 0.016),
            line("Trips",           x: 0.52, width: 0.12, y: 0.38, height: 0.016),
            line("20 h 21 m",       x: 0.04, width: 0.28, y: 0.41, height: 0.022),
            line("47",              x: 0.52, width: 0.08, y: 0.41, height: 0.022),
            line("Points",          x: 0.04, width: 0.16, y: 0.44, height: 0.016),
            line("89",              x: 0.04, width: 0.08, y: 0.47, height: 0.022),
            line("Net Fare",        x: 0.04, width: 0.18, y: 0.59, height: 0.016),
            line("$610.92",         x: 0.74, width: 0.16, y: 0.59, height: 0.016),
            line("Promotions",      x: 0.04, width: 0.22, y: 0.63, height: 0.016),
            line("$94.95",          x: 0.76, width: 0.14, y: 0.63, height: 0.016),
            line("Tip",             x: 0.04, width: 0.08, y: 0.66, height: 0.016),
            line("$123.54",         x: 0.74, width: 0.16, y: 0.66, height: 0.016)
        ]
    }

    func testWeeklySummaryReadsTheHeadlineTotal() {
        let parsed = EarningsParser.parse(weeklySummary)
        XCTAssertEqual(parsed.best.amount, 829.41,
                       "the headline total, not the net fare or a chart label")
    }

    /// The regression that started this: "Online" and "Trips" are side by
    /// side, so reading order puts "20 h 21 m" directly before "47" and the
    /// trip count came out as 20.
    func testTripCountComesFromItsOwnColumn() {
        let parsed = EarningsParser.parse(weeklySummary)
        XCTAssertEqual(parsed.best.units, 47,
                       "20 is the hours in the neighbouring column, not the trips")
    }

    func testOnlineTimeParsesTheSpacedHourMinuteForm() {
        let parsed = EarningsParser.parse(weeklySummary)
        XCTAssertEqual(parsed.best.hours ?? 0, 20.35, accuracy: 0.01)
    }

    /// A chart's axis label sits as high on screen as the total and in the
    /// same colour. Only its size tells them apart.
    func testChartAxisLabelLosesToTheHeadline() {
        let parsed = EarningsParser.parse(weeklySummary)
        let top = parsed.amounts.first
        XCTAssertEqual(top?.value, 829.41)
        XCTAssertNotEqual(top?.value, 321.48)
    }

    func testDateRangeYieldsBothEnds() {
        let dates = EarningsParser.dates(in: "Jul 13 - Jul 20")
        XCTAssertEqual(dates.count, 2, "a range is two dates, not zero")
    }

    func testNoMileageIsClaimedWhenTheScreenHasNone() {
        let parsed = EarningsParser.parse(weeklySummary)
        XCTAssertTrue(parsed.miles.isEmpty,
                      "better to leave it blank than invent a distance")
    }

    // MARK: Fare breakdown

    /// The wrong screen to import from — money but no denominators — and it
    /// lists four deductions. Dropping the sign offered every one of them as
    /// income.
    private var fareBreakdown: [RecognisedLine] {
        [
            line("Customer fare breakdown", x: 0.20, width: 0.60, y: 0.08, height: 0.022),
            line("Total customer fare",     x: 0.04, width: 0.34, y: 0.30),
            line("$1,091.87",               x: 0.70, width: 0.20, y: 0.30, height: 0.020),
            line("Government taxes",        x: 0.04, width: 0.34, y: 0.36),
            line("-$68.51",                 x: 0.72, width: 0.18, y: 0.36),
            line("Customer promotions",     x: 0.04, width: 0.36, y: 0.44),
            line("-$15.11",                 x: 0.72, width: 0.18, y: 0.44),
            line("Amount Uber kept",        x: 0.04, width: 0.32, y: 0.50),
            line("-$206.19",                x: 0.70, width: 0.20, y: 0.50),
            line("Earnings from fares",     x: 0.04, width: 0.34, y: 0.56),
            line("$705.87",                 x: 0.72, width: 0.18, y: 0.56),
            line("Your total earnings",     x: 0.04, width: 0.34, y: 0.66, height: 0.020),
            line("$829.41",                 x: 0.66, width: 0.24, y: 0.66, height: 0.030)
        ]
    }

    func testDeductionsAreNeverOfferedAsIncome() {
        let parsed = EarningsParser.parse(fareBreakdown)
        let values = parsed.amounts.map(\.value)

        for deduction in [68.51, 15.11, 206.19] {
            XCTAssertFalse(values.contains(deduction),
                           "\(deduction) is money taken off, not money earned")
        }
    }

    func testLabelledTotalStillWinsOnTheBreakdownScreen() {
        let parsed = EarningsParser.parse(fareBreakdown)
        XCTAssertEqual(parsed.best.amount, 829.41,
                       "'Your total earnings', not the customer fare above it")
    }

    /// This screen genuinely has no hours or trips on it, and the importer
    /// must not pretend otherwise — an invented denominator is what turned
    /// $185.27 into $185.27 per hour.
    func testFareBreakdownYieldsNoHours() {
        let parsed = EarningsParser.parse(fareBreakdown)
        XCTAssertTrue(parsed.hours.isEmpty)
    }
}
