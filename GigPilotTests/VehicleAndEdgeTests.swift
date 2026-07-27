//
//  VehicleAndEdgeTests.swift
//  GigPilotTests
//
//  The service schedule, the odometer, and the state a brand-new install is
//  in. The zero case matters because every rate on the dashboard divides by
//  something that starts at zero.
//

import XCTest
import SwiftData
@testable import GigPilot

@MainActor
final class VehicleAndEdgeTests: XCTestCase {

    // MARK: Service schedule

    /// Being late must not shorten the next interval. Measuring from the old
    /// due date instead of from today would do exactly that.
    func testMarkDoneMeasuresFromTodayNotFromTheOldDueDate() {
        let record = ServiceRecord(name: "Oil change",
                                   dueAtMileage: 90_000,
                                   intervalMiles: 5_000)

        record.markDone(currentMileage: 90_800)   // 800 miles late

        XCTAssertEqual(record.dueAtMileage, 95_800,
                       "a full interval from today, not 95,000 from when it was due")
        XCTAssertEqual(record.lastDoneAtMileage, 90_800)
        XCTAssertNotNil(record.lastDoneOn)
    }

    func testMarkDoneEarlyStillGivesAFullInterval() {
        let record = ServiceRecord(name: "Tire rotation",
                                   dueAtMileage: 90_000,
                                   intervalMiles: 6_000)
        record.markDone(currentMileage: 88_000)
        XCTAssertEqual(record.dueAtMileage, 94_000)
    }

    func testMarkDoneClearsTheStaleDueNote() {
        let record = ServiceRecord(name: "Oil change",
                                   dueAtMileage: 90_000,
                                   dueNote: "Sep 2026",
                                   intervalMiles: 5_000)
        record.markDone(currentMileage: 90_000)
        XCTAssertNil(record.dueNote, "the old date no longer applies once it's done")
    }

    func testDateDrivenItemRollsForwardByItsInterval() {
        let cal = Calendar.gigPilot
        let due = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let record = ServiceRecord(name: "Registration", dueOn: due, intervalMonths: 12)

        let doneOn = cal.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        record.markDone(currentMileage: 0, on: doneOn)

        let next = try? XCTUnwrap(record.dueOn)
        XCTAssertEqual(cal.component(.year, from: next ?? .now), 2027)
        XCTAssertEqual(cal.component(.month, from: next ?? .now), 3)
    }

    func testRecurringDetection() {
        XCTAssertTrue(ServiceRecord(name: "Oil", intervalMiles: 5_000).isRecurring)
        XCTAssertTrue(ServiceRecord(name: "Reg", intervalMonths: 12).isRecurring)
        XCTAssertFalse(ServiceRecord(name: "One-off").isRecurring)
    }

    // MARK: Status

    func testStatusReflectsRemainingMileage() {
        let record = ServiceRecord(name: "Oil change", dueAtMileage: 90_000, intervalMiles: 5_000)
        XCTAssertEqual(record.status(currentMileage: 80_000), .healthy)
        XCTAssertEqual(record.status(currentMileage: 89_000), .scheduled)
        XCTAssertEqual(record.status(currentMileage: 90_000), .dueNow)
        XCTAssertEqual(record.status(currentMileage: 91_000), .dueNow)
    }

    func testOverdueDescriptionReadsAsOverdue() {
        let record = ServiceRecord(name: "Tire rotation", dueAtMileage: 90_000)
        let text = record.dueDescription(currentMileage: 90_420)
        XCTAssertTrue(text.contains("Overdue"), "got: \(text)")
        XCTAssertTrue(text.contains("420"), "got: \(text)")
    }

    // MARK: Odometer

    /// Baseline plus everything driven since the reading was taken.
    func testLiveOdometerAddsMilesSinceTheBaseline() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")

        let asOf = Fixture.weekStart()
        let vehicle = Fixture.vehicle(context, odometer: 84_210, asOf: asOf)
        Fixture.shift(context, day: 1, miles: 400, splits: [(account, 100, 5)])
        Fixture.shift(context, day: 2, miles: 212, splits: [(account, 100, 5)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile,
            vehicle: vehicle
        )

        XCTAssertEqual(snapshot.vehicle.odometer, 84_822)
    }

    /// Correcting the reading re-baselines it, so miles logged before the
    /// correction aren't added on top of a number that already includes them.
    func testRebaselineDoesNotDoubleCountEarlierMiles() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")

        let vehicle = Fixture.vehicle(context, odometer: 84_210, asOf: Fixture.weekStart())
        Fixture.shift(context, day: 1, miles: 612, splits: [(account, 100, 5)])

        // The driver reads 85,000 off the dash and corrects it.
        vehicle.odometerBaseline = 85_000
        vehicle.odometerAsOf = .now

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile,
            vehicle: vehicle
        )

        XCTAssertEqual(snapshot.vehicle.odometer, 85_000,
                       "the 612 already logged must not be added again")
    }

    // MARK: Zero data

    /// A freshly onboarded driver has no shifts. Nothing may divide by zero.
    func testEmptyStoreProducesNoNaNs() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)

        let snapshot = EarningsSnapshot.build(
            shifts: [], expenses: [], accounts: [], profile: profile, vehicle: nil
        )

        XCTAssertFalse(snapshot.hasData)
        for (label, value) in [
            ("weeklyTotal", snapshot.weeklyTotal),
            ("perHour", snapshot.perHour),
            ("perMile", snapshot.perMile),
            ("onlineHours", snapshot.onlineHours),
            ("activeHours", snapshot.activeHours),
            ("maintenanceFund", snapshot.maintenanceFund),
            ("maintenanceProgress", snapshot.maintenanceProgress),
            ("taxSavingsYTD", snapshot.taxSavingsYTD),
            ("netProfit", snapshot.netProfit),
            ("expensesTotal", snapshot.expensesTotal),
            ("activeShare", snapshot.activeShare)
        ] {
            XCTAssertFinite(value, label)
        }

        for value in snapshot.series.daily + snapshot.series.hourly + snapshot.series.primary {
            XCTAssertFinite(value, "series value")
        }
    }

    func testNoPriorPeriodReadsAsNewRatherThanAPercentage() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")
        Fixture.shift(context, splits: [(account, 500, 10)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile, vehicle: nil
        )

        XCTAssertEqual(snapshot.weeklyChange, "New",
                       "dividing by an empty prior week would be infinite")
    }

    func testPlatformsWithNoActivityAreOmitted() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let used = Fixture.account(context, name: "Uber", sortIndex: 0)
        Fixture.account(context, name: "Lyft", sortIndex: 1)   // never driven

        Fixture.shift(context, splits: [(used, 300, 12)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile, vehicle: nil
        )

        XCTAssertEqual(snapshot.platforms.count, 1)
        XCTAssertEqual(snapshot.platforms.first?.name, "Uber")
    }

    // MARK: Formatting

    func testMoneyFormatting() {
        XCTAssertEqual(Money.cents(1482.60), "$1,482.60")
        XCTAssertEqual(Money.whole(370.65), "$371")
        XCTAssertEqual(Money.whole(0), "$0")
        XCTAssertEqual(Num.grouped(84_210), "84,210")
    }

    // MARK: Export

    /// A shift with three apps exports three rows, and the attributed columns
    /// sum back to the shift — the same invariant the UI relies on.
    func testCSVExportsOneRowPerPlatform() throws {
        let context = try TestStore.makeContext()
        let a = Fixture.account(context, name: "Uber", sortIndex: 0)
        let b = Fixture.account(context, name: "Lyft", sortIndex: 1)
        let c = Fixture.account(context, name: "DoorDash", sortIndex: 2)

        Fixture.shift(context, from: 15, to: 21.5, miles: 104,
                      splits: [(a, 89.60, 13), (b, 69.01, 10), (c, 84.13, 12)])

        let csv = CSVExport.shifts(try context.fetch(FetchDescriptor<Shift>()))
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 4, "header plus one row per platform")
        XCTAssertTrue(lines[0].hasPrefix("shift_id,"))

        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false)
        let attributedHoursColumn = try XCTUnwrap(header.firstIndex(of: "attributed_hours"))

        let attributedHours = lines.dropFirst().compactMap { line -> Double? in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            // attributed_hours moved from 12 to 14 when base_fare and
            // promotions were added to the export. Looked up by name so the
            // next column change doesn't silently read the wrong one.
            return Double(fields[attributedHoursColumn])
        }
        XCTAssertEqual(attributedHours.count, 3)
        // Each column is rounded to two decimals before being written, so three
        // rows can drift up to 1.5 cents from the true total. Tighter than this
        // would fail on rounding rather than on a real bug.
        XCTAssertEqual(attributedHours.reduce(0, +), 6.5, accuracy: 0.02)
    }

    func testCSVQuotesFieldsContainingCommas() throws {
        let context = try TestStore.makeContext()
        Fixture.expense(context, amount: 42, category: .maintenance)
        let expense = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>()).first)
        expense.note = "brakes, front pair"

        let csv = CSVExport.expenses(try context.fetch(FetchDescriptor<Expense>()))
        XCTAssertTrue(csv.contains("\"brakes, front pair\""), "got: \(csv)")
    }

    func testCSVLabelsWhichPotAnExpenseCameFrom() throws {
        let context = try TestStore.makeContext()
        Fixture.expense(context, amount: 300, category: .maintenance)
        Fixture.expense(context, amount: 100, category: .fuel)

        let csv = CSVExport.expenses(try context.fetch(FetchDescriptor<Expense>()))
        XCTAssertTrue(csv.contains("maintenance reserve"))
        XCTAssertTrue(csv.contains("out of pocket"))
    }
}
