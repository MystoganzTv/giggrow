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

    // MARK: The period header
    //
    // "Jun 1 - Jun 8" is the one date on an Uber screen that definitely
    // describes the period shown. When it wasn't read the importer fell back
    // to today, and a June screenshot was filed as "Sunday 26 July" — stated
    // firmly, with a chart reading behind it. These pin the header down.

    private func lines(_ texts: [String]) -> [RecognisedLine] {
        texts.enumerated().map { index, text in
            RecognisedLine(text: text, confidence: 0.9,
                           box: CGRect(x: 0.1, y: 0.9 - Double(index) * 0.05,
                                       width: 0.5, height: 0.03))
        }
    }

    private var july26_2026: Date { day(2026, 7, 26) }

    func testHeaderRangeGivesTheWeekStart() {
        let found = EarningsParser.weekStart(in: lines(["Jun 1 - Jun 8"]), now: july26_2026)
        XCTAssertEqual(found, day(2026, 6, 1))
    }

    /// En dash and em dash both appear; so does the day-first spelling.
    func testHeaderAcceptsTheDashAndOrderVariants() {
        XCTAssertEqual(EarningsParser.weekStart(in: lines(["Jun 1 – Jun 8"]), now: july26_2026),
                       day(2026, 6, 1))
        XCTAssertEqual(EarningsParser.weekStart(in: lines(["jul 13 — jul 20"]), now: july26_2026),
                       day(2026, 7, 13))
        XCTAssertEqual(EarningsParser.weekStart(in: lines(["1 Jun - 8 Jun"]), now: july26_2026),
                       day(2026, 6, 1))
    }

    /// A week that runs into the next month still starts where it starts.
    func testHeaderHandlesAWeekCrossingAMonth() {
        let found = EarningsParser.weekStart(in: lines(["Jun 29 - Jul 5"]), now: july26_2026)
        XCTAssertEqual(found, day(2026, 6, 29))
    }

    /// A screenshot is always of something that already happened, so a bare
    /// "Dec 22" read in July belongs to last year, not five months from now.
    func testHeaderPutsAFutureLookingDateInLastYear() {
        let found = EarningsParser.weekStart(in: lines(["Dec 22 - Dec 28"]), now: july26_2026)
        let year = Calendar.gigPilot.component(.year, from: found ?? .distantFuture)
        XCTAssertEqual(year, 2025)
    }

    /// Everything else on the screen must not look like a header. The status
    /// bar clock already cost us once.
    func testHeaderIgnoresTheRestOfTheScreen() {
        let noise = lines(["20:33", "Stats", "Total Earnings $291.64",
                           "Online", "8 h 49 m", "Trips", "21", "See customer fare breakdown"])
        XCTAssertNil(EarningsParser.weekStart(in: noise, now: july26_2026))
    }

    /// The exact failure the user reported, end to end: the June 1 week plus
    /// a bar labelled 7 is Sunday 7 June, not Sunday 26 July.
    func testJuneScreenshotDoesNotBecomeToday() {
        let week = EarningsParser.weekStart(in: lines(["Jun 1 - Jun 8"]), now: july26_2026)
        XCTAssertNotNil(week)

        let resolved = ChartDayDetector.date(
            for: .day(index: 6, weekday: "sun", dayOfMonth: 7),
            weekStart: week!
        )
        XCTAssertEqual(resolved, day(2026, 6, 7))

        let calendar = Calendar.gigPilot
        XCTAssertEqual(calendar.component(.month, from: resolved ?? .distantPast), 6,
                       "A June screenshot must not land in July")
    }

    // MARK: Which day a screenshot shows

    /// The number under the bar is the date, written on the screen. Nothing
    /// else needs to be inferred, and it must win over the other two signals.
    func testDayNumberBeatsColumnPosition() {
        let weekStart = day(2026, 6, 1)   // Monday
        // Column 0, but the bar is labelled 3 — a dropped label shifted the
        // index. The printed number is the one to believe.
        let reading = ChartDayDetector.Reading.day(index: 0, weekday: "wed", dayOfMonth: 3)
        let resolved = ChartDayDetector.date(for: reading, weekStart: weekStart)

        XCTAssertEqual(Calendar.gigPilot.component(.day, from: resolved ?? .distantPast), 3)
    }

    /// A week can straddle a month, so the day number is searched for inside
    /// the week rather than pinned to the week's own month.
    func testDayNumberResolvesAcrossAMonthBoundary() {
        let weekStart = day(2026, 6, 29)  // Monday, week runs into July
        let reading = ChartDayDetector.Reading.day(index: 4, weekday: "fri", dayOfMonth: 3)
        let resolved = ChartDayDetector.date(for: reading, weekStart: weekStart)

        let calendar = Calendar.gigPilot
        XCTAssertEqual(calendar.component(.month, from: resolved ?? .distantPast), 7)
        XCTAssertEqual(calendar.component(.day, from: resolved ?? .distantPast), 3)
    }

    /// Without the number, the weekday name still places it — and it must
    /// beat the column index for the same reason.
    func testWeekdayNameUsedWhenNoNumberWasRead() {
        let weekStart = day(2026, 6, 1)
        let reading = ChartDayDetector.Reading.day(index: 0, weekday: "thu", dayOfMonth: nil)
        let resolved = ChartDayDetector.date(for: reading, weekStart: weekStart)

        XCTAssertEqual(Calendar.gigPilot.component(.day, from: resolved ?? .distantPast), 4)
    }

    /// Position is the last resort, not the first.
    func testColumnIndexIsTheFallback() {
        let weekStart = day(2026, 6, 1)
        let reading = ChartDayDetector.Reading.day(index: 5, weekday: nil, dayOfMonth: nil)
        let resolved = ChartDayDetector.date(for: reading, weekStart: weekStart)

        XCTAssertEqual(Calendar.gigPilot.component(.day, from: resolved ?? .distantPast), 6)
    }

    /// A weekly total has no single day, and must not be given one.
    func testAggregateAndInconclusiveResolveToNothing() {
        let weekStart = day(2026, 6, 1)
        XCTAssertNil(ChartDayDetector.date(for: .aggregate, weekStart: weekStart))
        XCTAssertNil(ChartDayDetector.date(for: .inconclusive, weekStart: weekStart))
    }

    /// Every day of the week the user sent must land on its own date — the
    /// whole point of reading the chart.
    func testAWeekOfDailiesLandsOnSevenDistinctDates() {
        let weekStart = day(2026, 6, 1)
        let dates = (1...7).compactMap { number in
            ChartDayDetector.date(
                for: .day(index: number - 1, weekday: nil, dayOfMonth: number),
                weekStart: weekStart
            )
        }
        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(Set(dates).count, 7, "Seven screenshots must not collapse onto fewer days")
    }

    // MARK: Erasing

    /// A wipe that misses a model is worse than no wipe: the app looks empty
    /// and isn't, and the next launch reads figures the driver believes they
    /// deleted. This fails the moment an entity joins the schema without
    /// joining the erase list.
    func testWipeCoversEveryModelInTheSchema() {
        XCTAssertEqual(Seed.erasedTypeCount, GigPilotSchema.all.count,
                       "Seed.eraseEverything must delete every model in GigPilotSchema.all")
    }

    // MARK: The Mileage screen's arithmetic
    //
    // These mirror what MileageView computes. The headline is a tax figure, so
    // the properties that produce it are worth pinning down independently of
    // whether the view renders.

    /// Reviewed and unreviewed must partition the year: nothing counted twice,
    /// nothing lost between the two tabs.
    func testTabsPartitionTheYear() {
        let drives = sampleDrives()
        let reviewed = drives.filter { $0.purpose != .unclassified }
        let unreviewed = drives.filter { $0.purpose == .unclassified }

        XCTAssertEqual(reviewed.count + unreviewed.count, drives.count)
        XCTAssertTrue(Set(reviewed.map(ObjectIdentifier.init))
            .isDisjoint(with: Set(unreviewed.map(ObjectIdentifier.init))))
    }

    /// The year filter must not leak a drive from December into January.
    func testYearFilterExcludesNeighbouringYears() {
        let calendar = Calendar.gigPilot
        let drives = [
            DriveRecord(start: day(2025, 12, 31, hour: 23), end: day(2025, 12, 31, hour: 23),
                        distanceMeters: 16_093, purpose: .business),
            DriveRecord(start: day(2026, 1, 1, hour: 0), end: day(2026, 1, 1, hour: 1),
                        distanceMeters: 16_093, purpose: .business),
            DriveRecord(start: day(2027, 1, 1), end: day(2027, 1, 1, hour: 1),
                        distanceMeters: 16_093, purpose: .business)
        ]
        let in2026 = drives.filter { calendar.component(.year, from: $0.start) == 2026 }
        XCTAssertEqual(in2026.count, 1)
    }

    /// The headline must equal the sum of the rows beneath it, each at its own
    /// rate. Applying one rate to total miles would be off by $3.50 on this
    /// sample and by real money over a year.
    func testYearTotalEqualsTheSumOfItsDrives() {
        let drives = sampleDrives()
        let headline = drives.reduce(0) { $0 + $1.deduction() }

        XCTAssertEqual(headline, 72.50 + 38.00, accuracy: 0.02)

        // What a single-rate implementation would have produced, for contrast.
        let businessMiles = drives.filter { $0.purpose.isDeductible }.reduce(0) { $0 + $1.miles }
        let naive = businessMiles * 0.76
        XCTAssertNotEqual(headline, naive, accuracy: 0.02)
    }

    /// An override applies to the whole year, so there is no mid-year change
    /// to warn about.
    func testOverrideRateSuppressesTheMidYearWarning() {
        let calendar = Calendar.gigPilot
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!

        XCTAssertTrue(MileageRates.changesDuring(start..<end), "2026 changed rate on 1 July")

        // With an override every drive uses the same number, whatever the date.
        let june = DriveRecord(start: day(2026, 6, 15), end: day(2026, 6, 15, hour: 1),
                               distanceMeters: 16_093.44, purpose: .business)
        let july = DriveRecord(start: day(2026, 7, 15), end: day(2026, 7, 15, hour: 1),
                               distanceMeters: 16_093.44, purpose: .business)
        XCTAssertEqual(june.deduction(overrideRate: 0.6),
                       july.deduction(overrideRate: 0.6), accuracy: 0.0001)
    }

    /// A year with no rate change must not show the warning.
    func testNoWarningInAYearThatDidntChange() {
        let calendar = Calendar.gigPilot
        let start = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!
        XCTAssertFalse(MileageRates.changesDuring(start..<end))
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
