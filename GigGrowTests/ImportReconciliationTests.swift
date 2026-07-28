//
//  ImportReconciliationTests.swift
//  GigGrowTests
//

import SwiftData
import XCTest
@testable import GigGrow

@MainActor
final class ImportReconciliationTests: XCTestCase {

    func testWeeklyReportAutomaticallyReplacesManualAndImportedDays() throws {
        let context = try TestStore.makeContext()
        let uber = Fixture.account(context, name: "Uber")
        let manual = Fixture.shift(context, day: 0, splits: [(uber, 100, 4)])
        let imported = Fixture.shift(context, day: 1, splits: [(uber, 200, 8)])
        imported.note = "Imported from screenshot"
        try context.save()

        let overlaps = ImportReconciler.overlaps(
            ImportCoverage(
                platform: "Uber",
                period: .week,
                date: Fixture.weekStart()
            ),
            in: [manual, imported]
        )

        XCTAssertEqual(overlaps.count, 2)
        XCTAssertEqual(overlaps.filter { $0.origin == .manual }.count, 1)
        XCTAssertEqual(overlaps.filter { $0.origin == .imported }.count, 1)

        let incoming = ImportCoverage(
            platform: "Uber",
            period: .week,
            date: Fixture.weekStart()
        )
        XCTAssertFalse(
            ImportReconciler.hasBlockingDuplicate(
                incoming: incoming,
                overlaps: overlaps
            )
        )

        let automatic = ImportReconciler.replacements(
            from: overlaps,
            incoming: incoming,
            replacingImported: false
        )
        XCTAssertEqual(automatic.count, 2)

        let corrected = ImportReconciler.replacements(
            from: overlaps,
            incoming: incoming,
            replacingImported: true
        )
        XCTAssertEqual(corrected.count, 2)
    }

    func testWeeklyReportStillBlocksAnotherImportedWeek() throws {
        let context = try TestStore.makeContext()
        let uber = Fixture.account(context, name: "Uber")
        let start = Fixture.weekStart()
        let storedWeek = Shift(
            start: start,
            end: Calendar.gigGrow.date(byAdding: .day, value: 7, to: start)!
        )
        storedWeek.isAggregate = true
        storedWeek.note = "Imported from a weekly summary"
        context.insert(storedWeek)
        let earning = PlatformEarning(account: uber, gross: 700, trips: 30)
        context.insert(earning)
        earning.shift = storedWeek
        storedWeek.earningItems.append(earning)
        try context.save()

        let incoming = ImportCoverage(
            platform: "Uber",
            period: .week,
            date: start
        )
        let overlaps = ImportReconciler.overlaps(
            incoming,
            in: [storedWeek]
        )

        XCTAssertTrue(
            ImportReconciler.hasBlockingDuplicate(
                incoming: incoming,
                overlaps: overlaps
            )
        )
        XCTAssertTrue(
            ImportReconciler.replacements(
                from: overlaps,
                incoming: incoming,
                replacingImported: false
            ).isEmpty
        )
    }

    func testReplacingUberPreservesLyftOnTheSameManualShift() throws {
        let context = try TestStore.makeContext()
        let uber = Fixture.account(context, name: "Uber")
        let lyft = Fixture.account(context, name: "Lyft", unitNoun: "rides")
        let shared = Fixture.shift(
            context,
            day: 0,
            splits: [(uber, 100, 4), (lyft, 80, 3)]
        )
        try context.save()

        let overlaps = ImportReconciler.overlaps(
            ImportCoverage(
                platform: "Uber",
                period: .week,
                date: Fixture.weekStart()
            ),
            in: [shared]
        )
        XCTAssertEqual(ImportReconciler.remove(overlaps, from: context), 1)
        try context.save()

        let shifts = try context.fetch(FetchDescriptor<Shift>())
        let earnings = try context.fetch(FetchDescriptor<PlatformEarning>())
        XCTAssertEqual(shifts.count, 1)
        XCTAssertMoneyEqual(shifts.first?.gross ?? 0, 80)
        XCTAssertEqual(earnings.count, 1)
        XCTAssertEqual(earnings.first?.account?.name, "Lyft")
    }

    func testReplacingTheOnlyAppRemovesTheEmptyManualShift() throws {
        let context = try TestStore.makeContext()
        let uber = Fixture.account(context, name: "Uber")
        let manual = Fixture.shift(context, day: 0, splits: [(uber, 100, 4)])
        try context.save()

        let overlaps = ImportReconciler.overlaps(
            ImportCoverage(
                platform: "Uber",
                period: .week,
                date: Fixture.weekStart()
            ),
            in: [manual]
        )
        XCTAssertEqual(ImportReconciler.remove(overlaps, from: context), 1)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shift>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlatformEarning>()), 0)
    }

    func testDifferentAppOrWeekIsNeverReplaced() throws {
        let context = try TestStore.makeContext()
        let lyft = Fixture.account(context, name: "Lyft", unitNoun: "rides")
        let lyftShift = Fixture.shift(context, day: 0, splits: [(lyft, 80, 3)])
        try context.save()

        let overlaps = ImportReconciler.overlaps(
            ImportCoverage(
                platform: "Uber",
                period: .week,
                date: Fixture.weekStart()
            ),
            in: [lyftShift]
        )

        XCTAssertTrue(overlaps.isEmpty)
    }
}
