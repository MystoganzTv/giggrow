//
//  ShiftHistoryTests.swift
//  GigGrowTests
//

import SwiftData
import XCTest
@testable import GigGrow

@MainActor
final class ShiftHistoryTests: XCTestCase {

    func testBulkDeleteRemovesOnlySelectedShiftsAndTheirEarnings() throws {
        let context = try TestStore.makeContext()
        let uber = Fixture.account(context, name: "Uber")
        let lyft = Fixture.account(context, name: "Lyft", unitNoun: "rides")

        let monday = Fixture.shift(context, day: 0, splits: [(uber, 100, 4)])
        let tuesday = Fixture.shift(context, day: 1, splits: [(lyft, 200, 8)])
        let wednesday = Fixture.shift(context, day: 2, splits: [(uber, 300, 12)])
        try context.save()

        try ShiftDeletion.delete([monday, wednesday], from: context)

        let remainingShifts = try context.fetch(FetchDescriptor<Shift>())
        let remainingEarnings = try context.fetch(FetchDescriptor<PlatformEarning>())

        XCTAssertEqual(remainingShifts.count, 1)
        XCTAssertEqual(remainingShifts.first?.persistentModelID,
                       tuesday.persistentModelID)
        XCTAssertMoneyEqual(remainingShifts.first?.gross ?? 0, 200)
        XCTAssertEqual(remainingEarnings.count, 1)
        XCTAssertEqual(remainingEarnings.first?.account?.name, "Lyft")
    }

    func testBulkDeleteAcceptsAnEmptySelection() throws {
        let context = try TestStore.makeContext()
        let uber = Fixture.account(context, name: "Uber")
        Fixture.shift(context, splits: [(uber, 100, 4)])
        try context.save()

        try ShiftDeletion.delete([], from: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shift>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlatformEarning>()), 1)
    }
}
