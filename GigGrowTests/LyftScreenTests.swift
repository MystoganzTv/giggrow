//
//  LyftScreenTests.swift
//  GigGrowTests
//
//  Reproduces the actual Vision output from Lyft's weekly dashboard.
//

import XCTest
import CoreGraphics
@testable import GigGrow

final class LyftScreenTests: XCTestCase {

    private func line(_ text: String, x: CGFloat, width: CGFloat,
                      y: CGFloat, height: CGFloat = 0.016,
                      confidence: Float = 1) -> RecognisedLine {
        RecognisedLine(
            text: text,
            confidence: confidence,
            box: CGRect(x: x, y: 1 - y - height, width: width, height: height)
        )
    }

    /// Captured from the user's Lyft screenshot with Apple's own Vision OCR.
    /// It deliberately includes the three competing ride counts.
    private var weeklySummary: [RecognisedLine] {
        [
            line("Week", x: 0.347, width: 0.107, y: 0.131),
            line("Jul 20-26", x: 0.407, width: 0.177, y: 0.195),
            line("$998.31", x: 0.103, width: 0.774, y: 0.258, height: 0.081),
            line("See weekly breakdown", x: 0.281, width: 0.429, y: 0.548),
            line("Your weekly stats", x: 0.038, width: 0.467, y: 0.608),
            line("DRIVING STATS", x: 0.101, width: 0.249, y: 0.676),
            line("TIP STATS", x: 0.602, width: 0.161, y: 0.676),
            line("Rides completed", x: 0.041, width: 0.265, y: 0.712),
            line("60", x: 0.401, width: 0.047, y: 0.712),
            line("$89.67", x: 0.542, width: 0.247, y: 0.709, height: 0.035),
            line("Rides rejected", x: 0.041, width: 0.227, y: 0.741),
            line("117", x: 0.398, width: 0.051, y: 0.743),
            line("16 rides", x: 0.542, width: 0.123, y: 0.751),
            line("Online", x: 0.038, width: 0.107, y: 0.772),
            line("30 hr 23 min", x: 0.246, width: 0.202, y: 0.772),
            line("$998.31 balance", x: 0.038, width: 0.347, y: 0.905),
            line("Cash out", x: 0.688, width: 0.196, y: 0.905)
        ]
    }

    func testLyftWeeklySummaryReadsTheBusinessFigures() {
        let parsed = EarningsParser.parse(weeklySummary)

        XCTAssertEqual(parsed.platformName, "Lyft")
        XCTAssertEqual(parsed.best.amount, 998.31)
        XCTAssertEqual(parsed.best.units, 60,
                       "completed rides, not 117 rejected or 16 tipped rides")
        XCTAssertEqual(parsed.best.hours ?? 0, 30 + 23.0 / 60, accuracy: 0.001)
        XCTAssertEqual(parsed.tips ?? 0, 89.67, accuracy: 0.001)
        XCTAssertTrue(parsed.miles.isEmpty,
                      "`mi` inside `min` is minutes, not mileage")
    }

    func testRejectedRidesAreNotOfferedAsCompletedUnits() {
        let parsed = EarningsParser.parse(weeklySummary)
        XCTAssertFalse(parsed.units.contains { $0.value == 117 })
        XCTAssertEqual(parsed.units.map(\.value), [60],
                       "16 tipped rides is not an alternative completed count")
    }

    func testSingleLetterWeekdayRowStillProducesSevenDailyShares() throws {
        // Vision dropped Tuesday entirely in the real screenshot. The
        // detector must reconstruct all seven columns from the remaining
        // Monday-to-Sunday span.
        let labels = [
            line("M", x: 0.076, width: 0.044, y: 0.500),
            line("W", x: 0.344, width: 0.041, y: 0.502),
            line("T", x: 0.483, width: 0.028, y: 0.502),
            line("F", x: 0.622, width: 0.022, y: 0.502),
            line("S", x: 0.754, width: 0.025, y: 0.502),
            line("S", x: 0.886, width: 0.025, y: 0.502)
        ]
        let values = [5.0, 142, 300, 123, 273, 154, 0]
        let image = try XCTUnwrap(chartImage(values: values))
        let shares = try XCTUnwrap(
            ChartDayDetector.dailyShares(image: image, lines: labels)
        )

        XCTAssertEqual(shares.count, 7)
        XCTAssertEqual(shares[6], 0, accuracy: 0.01)
        XCTAssertEqual(shares[2], values[2] / values.reduce(0, +), accuracy: 0.025)
        XCTAssertEqual(shares[5], values[5] / values.reduce(0, +), accuracy: 0.025)
        XCTAssertEqual(ChartDayDetector.read(image: image, lines: labels), .aggregate)
    }

    func testPrintedLyftAmountsBeatTheMinimumHeightDot() throws {
        var lines = [
            line("M", x: 0.076, width: 0.044, y: 0.500),
            line("W", x: 0.344, width: 0.041, y: 0.502),
            line("T", x: 0.483, width: 0.028, y: 0.502),
            line("F", x: 0.622, width: 0.022, y: 0.502),
            line("S", x: 0.754, width: 0.025, y: 0.502),
            line("S", x: 0.886, width: 0.025, y: 0.502)
        ]
        // Exactly what Vision retained: Saturday's $154 label was omitted.
        lines += [
            line("$5", x: 0.073, width: 0.047, y: 0.452),
            line("$142", x: 0.192, width: 0.082, y: 0.423),
            line("$300", x: 0.319, width: 0.088, y: 0.379),
            line("$123", x: 0.460, width: 0.080, y: 0.430),
            line("$273", x: 0.590, width: 0.086, y: 0.385)
        ]

        let values = [5.0, 142, 300, 123, 273, 154, 0]
        let image = try XCTUnwrap(chartImage(values: values))
        let total = 998.31
        let shares = try XCTUnwrap(
            ChartDayDetector.dailyShares(image: image, lines: lines, total: total)
        )

        XCTAssertEqual(shares[0] * total, 5, accuracy: 0.01,
                       "the $5 label must beat Lyft's oversized minimum dot")
        XCTAssertEqual(shares[2] * total, 300, accuracy: 0.01)
        XCTAssertEqual(shares[5] * total, 155.31, accuracy: 0.02,
                       "the exact weekly remainder belongs to the missing Saturday label")
        XCTAssertEqual(shares[6], 0, accuracy: 0.001)
    }

    func testUberMergedWeekdayTextStillHasSevenColumns() throws {
        let labels = [
            line("1", x: 0.091, width: 0.029, y: 0.199),
            line("2", x: 0.224, width: 0.025, y: 0.198),
            line("3", x: 0.350, width: 0.028, y: 0.198),
            line("4", x: 0.483, width: 0.028, y: 0.199),
            line("5", x: 0.618, width: 0.022, y: 0.198),
            line("6", x: 0.745, width: 0.025, y: 0.199),
            line("7", x: 0.877, width: 0.025, y: 0.198),
            line("Mon", x: 0.069, width: 0.085, y: 0.217),
            line("Tue", x: 0.189, width: 0.107, y: 0.217),
            line("Wed Thu", x: 0.331, width: 0.202, y: 0.217),
            line("Fri", x: 0.606, width: 0.051, y: 0.215),
            line("Sat", x: 0.732, width: 0.057, y: 0.217),
            line("Sun", x: 0.855, width: 0.066, y: 0.217)
        ]
        let image = try XCTUnwrap(chartImage(
            values: [180, 0, 200, 95, 200, 200, 200],
            baseline: 0.192
        ))
        let shares = try XCTUnwrap(
            ChartDayDetector.dailyShares(image: image, lines: labels)
        )

        XCTAssertEqual(shares.count, 7)
        XCTAssertGreaterThan(shares[2], 0)
        XCTAssertGreaterThan(shares[3], 0)
    }

    private func chartImage(values: [Double], baseline: Double = 0.495) -> CGImage? {
        let width = 700
        let height = 1_000
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.90, green: 0.43, blue: 0.96, alpha: 1))

        let left = 0.098
        let right = 0.899
        let spacing = (right - left) / 6
        for (index, value) in values.enumerated() where value > 0 {
            let centre = left + Double(index) * spacing
            let barHeight = 0.11 * value / 300
            context.fill(
                CGRect(
                    x: (centre - 0.018) * Double(width),
                    y: (1 - baseline) * Double(height),
                    width: 0.036 * Double(width),
                    height: barHeight * Double(height)
                )
            )
        }
        return context.makeImage()
    }
}
