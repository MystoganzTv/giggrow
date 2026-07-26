//
//  MileageTests.swift
//  GigPilotTests
//
//  The mileage deduction is the largest number in this app that a driver will
//  put on a tax return. It is worth more than every other figure combined for
//  most gig drivers, and it is the one an auditor asks about first. So the
//  tests here are about being wrong in ways that cost money:
//
//  - the wrong rate applied to a drive on the wrong side of a rate change
//  - an unclassified drive quietly counted as business
//  - metres-to-miles drift, which compounds across a year of drives
//

import XCTest
@testable import GigPilot

final class MileageTests: XCTestCase {

    // MARK: Rates

    /// 2026 changed mid-year: 72.5¢ through June, 76¢ from 1 July. A single
    /// annual rate would misstate a full-time driver's deduction by hundreds.
    func testRateFollowsTheDatedSchedule() {
        XCTAssertEqual(MileageRates.rate(on: day(2026, 6, 30)), 0.725, accuracy: 0.0001)
        XCTAssertEqual(MileageRates.rate(on: day(2026, 7, 1)),  0.76,  accuracy: 0.0001)
        XCTAssertEqual(MileageRates.rate(on: day(2025, 3, 15)), 0.70,  accuracy: 0.0001)
        XCTAssertEqual(MileageRates.rate(on: day(2024, 12, 31)), 0.67, accuracy: 0.0001)
    }

    /// The boundary is the day itself, not the day after.
    func testRateChangesOnTheEffectiveDayNotTheNext() {
        let before = MileageRates.rate(on: day(2026, 6, 30, hour: 23))
        let after  = MileageRates.rate(on: day(2026, 7, 1, hour: 0))
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after, 0.76, accuracy: 0.0001)
    }

    /// A date before anything in the schedule must still return a usable rate
    /// rather than zero — a zero would silently erase a deduction.
    func testRateBeforeTheScheduleFallsBackRatherThanZero() {
        XCTAssertGreaterThan(MileageRates.rate(on: day(2019, 1, 1)), 0)
    }

    // MARK: Conversion

    func testMilesUseTheStatuteMile() {
        let drive = DriveRecord(start: .now, end: .now, distanceMeters: 1_609.344)
        XCTAssertEqual(drive.miles, 1.0, accuracy: 0.000_001)
    }

    /// A marathon's worth of metres shouldn't drift at the second decimal.
    func testConversionHoldsOverLongDistances() {
        let drive = DriveRecord(start: .now, end: .now, distanceMeters: 160_934.4)
        XCTAssertEqual(drive.miles, 100.0, accuracy: 0.001)
    }

    // MARK: Deduction

    func testUnclassifiedDrivesAreWorthNothing() {
        let drive = DriveRecord(start: day(2026, 3, 1), end: day(2026, 3, 1, hour: 1),
                                distanceMeters: 80_467.2) // 50 mi
        XCTAssertEqual(drive.purpose, .unclassified)
        XCTAssertEqual(drive.deduction(), 0, accuracy: 0.0001)
    }

    func testPersonalDrivesAreWorthNothing() {
        let drive = DriveRecord(start: day(2026, 3, 1), end: day(2026, 3, 1, hour: 1),
                                distanceMeters: 80_467.2, purpose: .personal)
        XCTAssertEqual(drive.deduction(), 0, accuracy: 0.0001)
    }

    func testBusinessDriveUsesTheRateFromItsOwnDate() {
        let june = DriveRecord(start: day(2026, 6, 15), end: day(2026, 6, 15, hour: 1),
                               distanceMeters: 160_934.4, purpose: .business) // 100 mi
        let july = DriveRecord(start: day(2026, 7, 15), end: day(2026, 7, 15, hour: 1),
                               distanceMeters: 160_934.4, purpose: .business)

        XCTAssertEqual(june.deduction(), 72.50, accuracy: 0.01)
        XCTAssertEqual(july.deduction(), 76.00, accuracy: 0.01)
    }

    /// A driver who sets their own rate overrides the schedule entirely.
    func testOverrideRateWins() {
        let drive = DriveRecord(start: day(2026, 6, 15), end: day(2026, 6, 15, hour: 1),
                                distanceMeters: 160_934.4, purpose: .business)
        XCTAssertEqual(drive.deduction(overrideRate: 0.50), 50.00, accuracy: 0.01)
    }

    /// Zero means "no override", not "a rate of zero". Getting this backwards
    /// would wipe out every deduction for anyone who never set a rate.
    func testZeroOverrideMeansFollowTheSchedule() {
        let drive = DriveRecord(start: day(2026, 7, 15), end: day(2026, 7, 15, hour: 1),
                                distanceMeters: 160_934.4, purpose: .business)
        XCTAssertEqual(drive.deduction(overrideRate: 0), 76.00, accuracy: 0.01)
    }

    // MARK: Duration

    func testDurationNeverGoesNegative() {
        let backwards = DriveRecord(start: day(2026, 3, 1, hour: 10),
                                    end: day(2026, 3, 1, hour: 9),
                                    distanceMeters: 1_000)
        XCTAssertEqual(backwards.duration, 0, accuracy: 0.0001)
    }

    // MARK: Export

    func testDriveExportHasOneRowPerDrivePlusHeader() {
        let csv = CSVExport.drives(sampleDrives())
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].hasPrefix("date,start,end,minutes,miles,purpose"))
    }

    /// Rows are written per drive with their own rate, so a year spanning a
    /// rate change exports two different rates — the whole point of the column.
    func testDriveExportWritesTheRateThatAppliedToEachRow() {
        let csv = CSVExport.drives(sampleDrives())
        XCTAssertTrue(csv.contains("0.725"), "June drive should carry the pre-July rate")
        XCTAssertTrue(csv.contains("0.760"), "July drive should carry the post-July rate")
    }

    func testDriveExportKeepsUnclassifiedRowsAtZero() {
        let csv = CSVExport.drives(sampleDrives())
        let unclassified = csv.split(separator: "\n").first { $0.contains("unclassified") }
        XCTAssertNotNil(unclassified)
        XCTAssertTrue(unclassified!.hasSuffix(",0.00"),
                      "An unclassified drive must export a zero deduction")
    }

    /// The exported deductions must sum to what the app shows, or the driver
    /// files one number and sees another.
    func testExportedDeductionsMatchTheModel() {
        let drives = sampleDrives()
        let fromModel = drives.reduce(0) { $0 + $1.deduction() }

        let fromCSV = CSVExport.drives(drives)
            .split(separator: "\n")
            .dropFirst()
            .compactMap { Double($0.split(separator: ",").last ?? "") }
            .reduce(0, +)

        XCTAssertEqual(fromCSV, fromModel, accuracy: 0.02)
    }

    /// Dates are exported ascending regardless of the order handed in.
    func testExportSortsByDate() {
        let csv = CSVExport.drives(sampleDrives().reversed())
        let dates = csv.split(separator: "\n").dropFirst()
            .map { String($0.split(separator: ",")[0]) }
        XCTAssertEqual(dates, dates.sorted())
    }

    // MARK: Tracker configuration

    /// Location must be off until the driver asks for it. A default of "on"
    /// would mean the app starts reading someone's position before they have
    /// been told it does.
    func testTrackingIsOffByDefault() {
        let profile = DriverProfile(name: "Test")
        XCTAssertFalse(profile.autoMileageTracking)
    }

    // MARK: Helpers

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = y; components.month = m; components.day = d; components.hour = hour
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    /// Three drives that straddle the July rate change, one of each purpose.
    private func sampleDrives() -> [DriveRecord] {
        [
            DriveRecord(start: day(2026, 6, 15), end: day(2026, 6, 15, hour: 13),
                        distanceMeters: 160_934.4, purpose: .business),   // 100 mi @ .725
            DriveRecord(start: day(2026, 7, 15), end: day(2026, 7, 15, hour: 13),
                        distanceMeters: 80_467.2, purpose: .business),    // 50 mi @ .76
            DriveRecord(start: day(2026, 7, 20), end: day(2026, 7, 20, hour: 13),
                        distanceMeters: 16_093.44)                        // 10 mi, unsorted
        ]
    }
}
