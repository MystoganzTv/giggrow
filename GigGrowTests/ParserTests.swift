//
//  ParserTests.swift
//  GigGrowTests
//
//  The screenshot parser, driven by synthetic lines rather than real images.
//
//  Testing the extraction rules without needing screenshots is the point:
//  when a gig app redesigns its earnings screen and the parser stops finding
//  the total, adding the new layout's lines here reproduces it in seconds.
//

import XCTest
@testable import GigGrow

final class ParserTests: XCTestCase {

    /// Builds recognised lines with plausible positions, top of screen first.
    private func lines(_ texts: [String], confidence: Float = 0.95) -> [RecognisedLine] {
        texts.enumerated().map { index, text in
            let y = 1 - (CGFloat(index + 1) * 0.06)
            return RecognisedLine(
                text: text,
                confidence: confidence,
                box: CGRect(x: 0.1, y: y, width: 0.8, height: 0.04)
            )
        }
    }

    // MARK: Currency

    func testCurrencyFormats() {
        XCTAssertEqual(EarningsParser.currencyAmounts(in: "$1,482.60"), [1482.60])
        XCTAssertEqual(EarningsParser.currencyAmounts(in: "$47"), [47])
        XCTAssertEqual(EarningsParser.currencyAmounts(in: "Total $ 89.60"), [89.60])
        XCTAssertEqual(EarningsParser.currencyAmounts(in: "1,482.60"), [1482.60])
        XCTAssertEqual(EarningsParser.currencyAmounts(in: "$0.70"), [0.70])
    }

    /// Regression: an ungrouped four-digit figure came back missing its
    /// leading digit — $1,482.60 read as $482.60, and nothing downstream
    /// would have questioned it.
    func testUngroupedThousandsKeepTheirLeadingDigit() {
        XCTAssertEqual(EarningsParser.currencyAmounts(in: "1482.60"), [1482.60])
        XCTAssertEqual(EarningsParser.currencyAmounts(in: "$1482.60"), [1482.60])
    }

    /// Hours and clock times must never be read as money.
    func testDurationsAreNotReadAsMoney() {
        XCTAssertTrue(EarningsParser.currencyAmounts(in: "6.5 hrs").isEmpty)
        XCTAssertTrue(EarningsParser.currencyAmounts(in: "Active time 7:45").isEmpty)
    }

    /// Bare counts must not be read as money, or "12 trips" becomes $12.
    func testBareIntegersAreNotMoney() {
        XCTAssertTrue(EarningsParser.currencyAmounts(in: "12 trips").isEmpty)
        XCTAssertTrue(EarningsParser.currencyAmounts(in: "104 mi").isEmpty)
    }

    // MARK: Platform

    func testPlatformDetection() {
        let cases: [(String, String)] = [
            ("Uber", "Uber"), ("UBER EATS", "Uber"), ("Lyft Driver", "Lyft"),
            ("DoorDash", "DoorDash"), ("Dasher earnings", "DoorDash"),
            ("Instacart Shopper", "Instacart"), ("Amazon Flex", "Amazon Flex"),
            ("Spark Driver", "Walmart Spark")
        ]
        for (text, expected) in cases {
            let parsed = EarningsParser.parse(lines([text, "Total $100.00"]))
            XCTAssertEqual(parsed.platformName, expected, "failed on \(text)")
        }
    }

    func testUnknownPlatformIsNilRatherThanGuessed() {
        let parsed = EarningsParser.parse(lines(["Weekly summary", "Total $100.00"]))
        XCTAssertNil(parsed.platformName, "better to ask than to guess wrong")
    }

    // MARK: Ranking

    /// A figure labelled "Total" should outrank an incidental amount, even
    /// when the incidental one is larger.
    func testLabelledTotalOutranksAnUnlabelledAmount() {
        let parsed = EarningsParser.parse(lines([
            "Uber",
            "Trip fare $9,999.00",
            "Total earnings",
            "$342.18"
        ]))
        XCTAssertEqual(parsed.amounts.first?.value, 342.18)
    }

    func testAllAmountsAreOfferedAsAlternatives() {
        let parsed = EarningsParser.parse(lines([
            "Uber", "Total $342.18", "Tips $48.00", "Promotions $12.50"
        ]))
        let values = parsed.amounts.map(\.value)
        XCTAssertTrue(values.contains(342.18))
        XCTAssertTrue(values.contains(48.00))
        XCTAssertTrue(values.contains(12.50))
    }

    func testDuplicateAmountsAreCollapsed() {
        let parsed = EarningsParser.parse(lines([
            "Uber", "Total $100.00", "Balance $100.00"
        ]))
        XCTAssertEqual(parsed.amounts.filter { $0.value == 100 }.count, 1)
    }

    // MARK: Units, hours, miles

    func testUnitCounts() {
        for text in ["12 trips", "12 deliveries", "12 orders", "12 batches"] {
            let parsed = EarningsParser.parse(lines(["Uber", text]))
            XCTAssertEqual(parsed.units.first?.value, 12, "failed on \(text)")
        }
    }

    func testDurationFormats() {
        let cases: [(String, Double)] = [
            ("6:30", 6.5),
            ("6h 30m", 6.5),
            ("6.5 hrs", 6.5),
            ("8 h", 8)
        ]
        for (text, expected) in cases {
            let parsed = EarningsParser.parse(lines(["Uber", "Online \(text)"]))
            XCTAssertEqual(parsed.hours.first?.value ?? -1, expected, accuracy: 0.01,
                           "failed on \(text)")
        }
    }

    func testMileage() {
        let parsed = EarningsParser.parse(lines(["Uber", "104 miles"]))
        XCTAssertEqual(parsed.miles.first?.value ?? -1, 104, accuracy: 0.01)
    }

    /// A dollar figure on a line mentioning miles is money, not a distance.
    func testMoneyOnAMileageLineIsNotReadAsMiles() {
        let parsed = EarningsParser.parse(lines(["Uber", "Per mile $2.42"]))
        XCTAssertTrue(parsed.miles.isEmpty)
        XCTAssertEqual(parsed.amounts.first?.value, 2.42)
    }

    // MARK: Dates

    func testDateFormats() {
        for text in ["Jul 24, 2026", "24 Jul 2026", "07/24/2026", "2026-07-24"] {
            XCTAssertNotNil(EarningsParser.date(in: text), "failed on \(text)")
        }
    }

    func testDayAndMonthWithoutAYearAssumesThisYear() throws {
        let date = try XCTUnwrap(EarningsParser.date(in: "Jul 24"))
        let year = Calendar.gigGrow.component(.year, from: date)
        XCTAssertEqual(year, Calendar.gigGrow.component(.year, from: .now))
    }

    // MARK: Whole screens

    /// A plausible Uber weekly summary.
    func testRealisticUberScreen() {
        let parsed = EarningsParser.parse(lines([
            "Uber",
            "This week",
            "Total earnings",
            "$342.18",
            "Jul 20 - Jul 26",
            "Trips 27",
            "Online 14h 20m",
            "Distance 186 miles"
        ]))

        XCTAssertEqual(parsed.platformName, "Uber")
        XCTAssertEqual(parsed.best.amount, 342.18)
        XCTAssertEqual(parsed.best.units, 27)
        XCTAssertEqual(parsed.best.hours ?? -1, 14.333, accuracy: 0.01)
        XCTAssertEqual(parsed.best.miles ?? -1, 186, accuracy: 0.01)
    }

    func testRealisticDoorDashScreen() {
        let parsed = EarningsParser.parse(lines([
            "DoorDash",
            "Earnings",
            "$188.45",
            "31 deliveries",
            "Active time 7:45"
        ]))

        XCTAssertEqual(parsed.platformName, "DoorDash")
        XCTAssertEqual(parsed.best.amount, 188.45)
        XCTAssertEqual(parsed.best.units, 31)
        XCTAssertEqual(parsed.best.hours ?? -1, 7.75, accuracy: 0.01)
    }

    // MARK: Degenerate input

    func testEmptyInputFindsNothingAndDoesNotCrash() {
        let parsed = EarningsParser.parse([])
        XCTAssertFalse(parsed.foundAnything)
        XCTAssertNil(parsed.platformName)
        XCTAssertNil(parsed.best.amount)
    }

    func testGarbageInputFindsNothing() {
        let parsed = EarningsParser.parse(lines(["...", "▲▲▲", "%%%"]))
        XCTAssertFalse(parsed.foundAnything)
    }

    /// Low OCR confidence must lower the candidate's confidence, so a blurry
    /// screenshot doesn't present a shaky reading as certain.
    func testLowOCRConfidenceLowersCandidateConfidence() {
        let sharp = EarningsParser.parse(lines(["Uber", "Total $100.00"], confidence: 0.99))
        let blurry = EarningsParser.parse(lines(["Uber", "Total $100.00"], confidence: 0.30))
        let sharpScore = sharp.amounts.first?.confidence ?? 0
        let blurryScore = blurry.amounts.first?.confidence ?? 0
        XCTAssertGreaterThan(sharpScore, blurryScore)
    }
}
