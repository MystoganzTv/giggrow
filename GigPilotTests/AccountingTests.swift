//
//  AccountingTests.swift
//  GigPilotTests
//
//  Where the money goes. A real bug lived here: maintenance spending was
//  subtracted from net profit as well as drawn from the reserve that had
//  already withheld it, so a $300 brake job cost the driver $600 on paper.
//

import XCTest
import SwiftData
@testable import GigPilot

@MainActor
final class AccountingTests: XCTestCase {

    // MARK: The regression

    /// Maintenance comes out of the reserve, not out of take-home.
    func testMaintenanceSpendingDoesNotReduceNetProfit() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context, taxRate: 25, maintenanceRate: 8)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, splits: [(account, 1000, 20)])
        Fixture.expense(context, amount: 300, category: .maintenance)

        let snapshot = try build(context, profile: profile)

        // 1000 − 250 tax − 80 reserve. The 300 is not subtracted again.
        XCTAssertMoneyEqual(snapshot.netProfit, 670)
        XCTAssertMoneyEqual(snapshot.reserveDraw, 300)
        XCTAssertMoneyEqual(snapshot.expensesTotal, 300)
    }

    /// Everything that isn't maintenance does reduce take-home, because
    /// nothing was set aside for it.
    func testOutOfPocketSpendingReducesNetProfit() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, splits: [(account, 1000, 20)])
        Fixture.expense(context, amount: 120, category: .fuel)

        let snapshot = try build(context, profile: profile)

        XCTAssertMoneyEqual(snapshot.netProfit, 550)   // 1000 − 120 − 250 − 80
        XCTAssertMoneyEqual(snapshot.reserveDraw, 0)
    }

    /// Both kinds at once, kept apart.
    func testMixedSpendingSplitsBetweenPots() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, splits: [(account, 1482.60, 30)])
        Fixture.expense(context, amount: 96.40, category: .fuel)
        Fixture.expense(context, amount: 310.00, category: .maintenance)
        Fixture.expense(context, amount: 145.00, category: .insurance)
        Fixture.expense(context, amount: 42.50, category: .maintenance)

        let snapshot = try build(context, profile: profile)

        XCTAssertMoneyEqual(snapshot.expensesTotal, 593.90)
        XCTAssertMoneyEqual(snapshot.reserveDraw, 352.50)

        let outOfPocket = snapshot.expensesTotal - snapshot.reserveDraw
        XCTAssertMoneyEqual(outOfPocket, 241.40)
        XCTAssertMoneyEqual(snapshot.netProfit, 1482.60 - 241.40 - 370.65 - 118.608)
    }

    // MARK: The invariant

    /// Every dollar of gross lands in exactly one bucket. If this drifts,
    /// something is being counted twice or lost.
    func testGrossAllocationBalances() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context, taxRate: 25, maintenanceRate: 8)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, splits: [(account, 1482.60, 30)])
        Fixture.expense(context, amount: 96.40, category: .fuel)
        Fixture.expense(context, amount: 310.00, category: .maintenance)

        let snapshot = try build(context, profile: profile)

        let taxes = snapshot.weeklyTotal * snapshot.taxRate / 100
        let reserve = snapshot.weeklyTotal * snapshot.maintenanceRate / 100
        let outOfPocket = snapshot.expensesTotal - snapshot.reserveDraw

        XCTAssertMoneyEqual(taxes + reserve + outOfPocket + snapshot.netProfit,
                            snapshot.weeklyTotal,
                            "gross must equal taxes + reserve + out-of-pocket + take-home")
    }

    // MARK: Reserve

    func testReserveAccruesAtTheConfiguredRate() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context, maintenanceRate: 10)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, splits: [(account, 1000, 20)])

        let snapshot = try build(context, profile: profile)
        XCTAssertMoneyEqual(snapshot.maintenanceFund, 100)
        XCTAssertMoneyEqual(snapshot.maintenanceThisWeek, 100)
    }

    func testOnlyMaintenanceDrawsDownTheReserve() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context, maintenanceRate: 10)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, splits: [(account, 1000, 20)])
        Fixture.expense(context, amount: 40, category: .fuel)
        Fixture.expense(context, amount: 30, category: .maintenance)

        let snapshot = try build(context, profile: profile)
        XCTAssertMoneyEqual(snapshot.maintenanceFund, 70)   // 100 accrued − 30, fuel untouched
    }

    /// Spending more than the reserve holds is normal — that's what a prior
    /// balance is for — but the displayed fund must not go negative.
    func testReserveNeverDisplaysNegative() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context, maintenanceRate: 8)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, splits: [(account, 500, 10)])
        Fixture.expense(context, amount: 900, category: .maintenance)

        let snapshot = try build(context, profile: profile)
        XCTAssertGreaterThanOrEqual(snapshot.maintenanceFund, 0)
        XCTAssertFinite(snapshot.maintenanceFund, "maintenance fund")
    }

    func testOpeningBalanceCarriesIntoTheFund() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context, maintenanceRate: 8, openingBalance: 2_000)
        let account = Fixture.account(context, name: "Uber")

        Fixture.shift(context, splits: [(account, 1000, 20)])

        let snapshot = try build(context, profile: profile)
        XCTAssertMoneyEqual(snapshot.maintenanceFund, 2_080)
    }

    // MARK: Rates

    func testPerHourAndPerMileUseTheRightDenominators() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")

        // 8 hours online of which 2 idle, 200 miles, $400.
        Fixture.shift(context, from: 9, to: 17, miles: 200, idleMinutes: 120,
                      splits: [(account, 400, 20)])

        let snapshot = try build(context, profile: profile)

        XCTAssertMoneyEqual(snapshot.perHour, 50, "gross ÷ online hours, waiting included")
        XCTAssertMoneyEqual(snapshot.perMile, 2)
        XCTAssertEqual(snapshot.onlineHours, 8, accuracy: 0.0001)
        XCTAssertEqual(snapshot.activeHours, 6, accuracy: 0.0001)
        XCTAssertEqual(snapshot.idleHours, 2, accuracy: 0.0001)
    }

    /// Idle can't exceed the block, however large the entered value.
    func testIdleIsClampedToTheShiftLength() throws {
        let context = try TestStore.makeContext()
        let account = Fixture.account(context, name: "Uber")
        let shift = Fixture.shift(context, from: 9, to: 13, idleMinutes: 600,
                                  splits: [(account, 100, 5)])

        XCTAssertEqual(shift.hours, 4, accuracy: 0.0001)
        XCTAssertEqual(shift.idleHours, 4, accuracy: 0.0001)
        XCTAssertEqual(shift.activeHours, 0, accuracy: 0.0001)
    }

    // MARK: Helper

    private func build(_ context: ModelContext, profile: DriverProfile) throws -> EarningsSnapshot {
        EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: try context.fetch(FetchDescriptor<Expense>()),
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile,
            vehicle: nil
        )
    }
}
