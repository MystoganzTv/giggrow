//
//  TestSupport.swift
//  GigGrowTests
//
//  Shared fixtures. Everything runs against an in-memory store so tests
//  never touch the simulator's real database and never see each other's data.
//

import Foundation
import SwiftData
import XCTest
@testable import GigGrow

// MARK: - Store

enum TestStore {

    /// A fresh, empty in-memory context.
    @MainActor
    static func makeContext() throws -> ModelContext {
        let schema = Schema(GigGrowSchema.all)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}

// MARK: - Builders

enum Fixture {

    static let calendar = Calendar.gigGrow

    /// Monday of the week containing `date`, at midnight.
    static func weekStart(_ date: Date = .now) -> Date {
        calendar.startOfWeek(for: date)
    }

    @MainActor
    @discardableResult
    static func account(
        _ context: ModelContext,
        name: String,
        unitNoun: String = "trips",
        sortIndex: Int = 0
    ) -> PlatformAccount {
        let account = PlatformAccount(
            name: name,
            short: name,
            initial: String(name.prefix(1)),
            gradientStart: 0xA78BFA,
            gradientEnd: 0x7C5CF6,
            unitNoun: unitNoun,
            sortIndex: sortIndex
        )
        context.insert(account)
        return account
    }

    /// A shift on `day` (0 = Monday of the current week), running `startHour`
    /// to `endHour`, with `splits` of (account, gross, units).
    @MainActor
    @discardableResult
    static func shift(
        _ context: ModelContext,
        day: Int = 0,
        from startHour: Double = 9,
        to endHour: Double = 15,
        miles: Double = 100,
        idleMinutes: Double = 0,
        splits: [(PlatformAccount, Double, Int)] = [],
        weekOf reference: Date = .now
    ) -> Shift {
        let dayStart = calendar.date(byAdding: .day, value: day, to: weekStart(reference))
            ?? weekStart(reference)

        let shift = Shift(
            start: dayStart.addingTimeInterval(startHour * 3600),
            end: dayStart.addingTimeInterval(endHour * 3600),
            miles: miles,
            idleMinutes: idleMinutes
        )
        context.insert(shift)

        for (account, gross, units) in splits {
            let earning = PlatformEarning(account: account, gross: gross, trips: units)
            context.insert(earning)
            earning.shift = shift
            shift.earnings.append(earning)
        }
        return shift
    }

    @MainActor
    @discardableResult
    static func expense(
        _ context: ModelContext,
        amount: Double,
        category: ExpenseCategory,
        daysAgo: Int = 0
    ) -> Expense {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let expense = Expense(date: date, amount: amount, category: category)
        context.insert(expense)
        return expense
    }

    @MainActor
    @discardableResult
    static func profile(
        _ context: ModelContext,
        taxRate: Double = 25,
        maintenanceRate: Double = 8,
        openingBalance: Double = 0
    ) -> DriverProfile {
        let profile = DriverProfile(
            name: "Test Driver",
            detail: "Nowhere · Since 2026",
            taxRate: taxRate,
            maintenanceRate: maintenanceRate,
            maintenanceOpeningBalance: openingBalance
        )
        context.insert(profile)
        return profile
    }

    @MainActor
    @discardableResult
    static func vehicle(
        _ context: ModelContext,
        odometer: Int = 80_000,
        asOf: Date = .now
    ) -> VehicleRecord {
        let vehicle = VehicleRecord(
            name: "Test Car",
            detail: "",
            odometerBaseline: odometer,
            odometerAsOf: asOf
        )
        context.insert(vehicle)
        return vehicle
    }
}

// MARK: - Assertions

/// Money comparisons to the cent. Anything looser hides real rounding bugs;
/// anything tighter fails on binary floating point.
func XCTAssertMoneyEqual(
    _ actual: Double,
    _ expected: Double,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual, expected, accuracy: 0.005, message, file: file, line: line)
}

func XCTAssertFinite(
    _ value: Double,
    _ label: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(value.isNaN, "\(label) is NaN", file: file, line: line)
    XCTAssertFalse(value.isInfinite, "\(label) is infinite", file: file, line: line)
}
