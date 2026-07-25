//
//  AttributionTests.swift
//  GigPilotTests
//
//  The multi-app hour split. This is the load-bearing idea of the whole
//  product: a driver with three apps running has worked one set of hours,
//  not three, and $/hour is meaningless if that's wrong.
//

import XCTest
import SwiftData
@testable import GigPilot

@MainActor
final class AttributionTests: XCTestCase {

    // MARK: The invariant

    /// Attributed hours must sum to the shift's hours. If they don't, every
    /// per-app rate is measured against a different total than the headline.
    func testAttributedHoursSumToShiftHours() throws {
        let context = try TestStore.makeContext()
        let uber = Fixture.account(context, name: "Uber", sortIndex: 0)
        let dd   = Fixture.account(context, name: "DoorDash", sortIndex: 1)
        let lyft = Fixture.account(context, name: "Lyft", sortIndex: 2)

        let shift = Fixture.shift(
            context, from: 15, to: 21.5, miles: 104,
            splits: [(uber, 89.60, 13), (dd, 84.13, 12), (lyft, 69.01, 10)]
        )

        let total = shift.earnings.reduce(0.0) {
            $0 + ShiftAttribution.hours(of: $1, in: shift)
        }
        XCTAssertEqual(total, shift.hours, accuracy: 0.0001)
        XCTAssertEqual(shift.hours, 6.5, accuracy: 0.0001)
    }

    func testAttributedMilesSumToShiftMiles() throws {
        let context = try TestStore.makeContext()
        let a = Fixture.account(context, name: "Uber", sortIndex: 0)
        let b = Fixture.account(context, name: "Lyft", sortIndex: 1)

        let shift = Fixture.shift(context, miles: 104, splits: [(a, 60, 5), (b, 40, 4)])

        let total = shift.earnings.reduce(0.0) {
            $0 + ShiftAttribution.miles(of: $1, in: shift)
        }
        XCTAssertMoneyEqual(total, 104)
    }

    /// Hours follow money: an app earning 70% of the block is charged 70%.
    func testHoursSplitInProportionToGross() throws {
        let context = try TestStore.makeContext()
        let big = Fixture.account(context, name: "Uber", sortIndex: 0)
        let small = Fixture.account(context, name: "Lyft", sortIndex: 1)

        let shift = Fixture.shift(context, from: 10, to: 20,
                                  splits: [(big, 70, 7), (small, 30, 3)])
        let earnings = shift.earnings.sorted { $0.gross > $1.gross }

        XCTAssertEqual(ShiftAttribution.hours(of: earnings[0], in: shift), 7, accuracy: 0.0001)
        XCTAssertEqual(ShiftAttribution.hours(of: earnings[1], in: shift), 3, accuracy: 0.0001)
    }

    // MARK: Edges

    /// A shift that earned nothing still has hours. Splitting on gross would
    /// divide by zero, so it falls back to an even split.
    func testZeroGrossSplitsEvenly() throws {
        let context = try TestStore.makeContext()
        let a = Fixture.account(context, name: "Uber", sortIndex: 0)
        let b = Fixture.account(context, name: "Lyft", sortIndex: 1)

        let shift = Fixture.shift(context, from: 10, to: 14, splits: [(a, 0, 0), (b, 0, 0)])

        for earning in shift.earnings {
            let hours = ShiftAttribution.hours(of: earning, in: shift)
            XCTAssertFinite(hours, "attributed hours")
            XCTAssertEqual(hours, 2, accuracy: 0.0001)
        }
    }

    func testSingleAppTakesTheWholeShift() throws {
        let context = try TestStore.makeContext()
        let flex = Fixture.account(context, name: "Amazon Flex")
        let shift = Fixture.shift(context, from: 10, to: 14, miles: 96,
                                  splits: [(flex, 131.21, 19)])

        let earning = try XCTUnwrap(shift.earnings.first)
        XCTAssertEqual(ShiftAttribution.hours(of: earning, in: shift), 4, accuracy: 0.0001)
        XCTAssertMoneyEqual(ShiftAttribution.miles(of: earning, in: shift), 96)
    }

    /// When an app reports its own mileage, that beats the proportional guess.
    func testReportedMilesWinOverProportionalSplit() throws {
        let context = try TestStore.makeContext()
        let a = Fixture.account(context, name: "Uber", sortIndex: 0)
        let b = Fixture.account(context, name: "Lyft", sortIndex: 1)

        let shift = Fixture.shift(context, miles: 100, splits: [(a, 50, 5), (b, 50, 5)])
        let first = try XCTUnwrap(shift.earnings.first)
        first.reportedMiles = 88

        XCTAssertMoneyEqual(ShiftAttribution.miles(of: first, in: shift), 88)
    }

    // MARK: Hours counted once

    /// The reason a Shift is a block of time rather than time-on-one-app.
    /// Three apps for six hours is six hours worked, not eighteen.
    func testOverlappingAppsDoNotMultiplyHours() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let a = Fixture.account(context, name: "Uber", sortIndex: 0)
        let b = Fixture.account(context, name: "Lyft", sortIndex: 1)
        let c = Fixture.account(context, name: "DoorDash", sortIndex: 2)

        Fixture.shift(context, from: 9, to: 15, miles: 90,
                      splits: [(a, 100, 10), (b, 100, 10), (c, 100, 10)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile,
            vehicle: nil
        )

        XCTAssertEqual(snapshot.onlineHours, 6, accuracy: 0.0001,
                       "six hours with three apps on is six hours, not eighteen")
        XCTAssertMoneyEqual(snapshot.weeklyTotal, 300)
        XCTAssertMoneyEqual(snapshot.perHour, 50)
    }

    /// Per-app rates divide by the same denominator as the headline, so the
    /// weighted average of the app rates equals the headline rate.
    func testPerPlatformRatesAreComparableToTheHeadline() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let a = Fixture.account(context, name: "Uber", sortIndex: 0)
        let b = Fixture.account(context, name: "Lyft", sortIndex: 1)

        Fixture.shift(context, from: 9, to: 17, miles: 120,
                      splits: [(a, 300, 20), (b, 100, 8)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile,
            vehicle: nil
        )

        // 400 over 8 hours.
        XCTAssertMoneyEqual(snapshot.perHour, 50)
        XCTAssertEqual(snapshot.platforms.count, 2)

        // Both apps ran the same block, so both land on the same rate:
        // gross and hours were split by the identical ratio.
        for platform in snapshot.platforms {
            XCTAssertEqual(platform.hourly, "$50.00")
        }
    }

    /// Shares are normalised against the largest platform for the bar widths,
    /// while `share` itself stays a fraction of the total.
    func testSharesAreFractionsOfTheTotal() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let a = Fixture.account(context, name: "Uber", sortIndex: 0)
        let b = Fixture.account(context, name: "Lyft", sortIndex: 1)

        Fixture.shift(context, splits: [(a, 75, 5), (b, 25, 3)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile,
            vehicle: nil
        )

        let total = snapshot.platforms.reduce(0) { $0 + $1.share }
        XCTAssertEqual(total, 1, accuracy: 0.0001)
        XCTAssertEqual(snapshot.platforms.first?.share ?? 0, 0.75, accuracy: 0.0001)
    }
}
