//
//  BackupTests.swift
//  GigGrowTests
//

import XCTest
import SwiftData
@testable import GigGrow

@MainActor
final class BackupTests: XCTestCase {
    func testCustomPlatformCanBeAddedAndIsImmediatelyActive() throws {
        let context = try TestStore.makeContext()
        for account in Seed.defaultAccounts() { context.insert(account) }

        let custom = try Seed.addCustomPlatform(
            name: "Roadie",
            unitNoun: "deliveries",
            in: context
        )

        XCTAssertEqual(custom.name, "Roadie")
        XCTAssertEqual(custom.unitNoun, "deliveries")
        XCTAssertEqual(custom.initial, "R")
        XCTAssertTrue(custom.isActive)
        XCTAssertFalse(Seed.isBuiltInPlatform(named: custom.name))
    }

    func testCustomPlatformRejectsDuplicateNamesIgnoringCaseAndSpaces() throws {
        let context = try TestStore.makeContext()
        _ = try Seed.addCustomPlatform(name: "Roadie", unitNoun: "jobs", in: context)

        XCTAssertThrowsError(
            try Seed.addCustomPlatform(name: "  roadie  ", unitNoun: "jobs", in: context)
        )
    }


    func testCloudKitCatalogueReconciliationKeepsEarningsAndUserPreference() throws {
        let context = try TestStore.makeContext()
        let locallySeeded = Fixture.account(context, name: "Lyft", unitNoun: "rides")
        let restored = Fixture.account(context, name: " lyft ", unitNoun: "rides")
        restored.isActive = false
        restored.lastSyncedAt = .now
        _ = Fixture.shift(context, splits: [(restored, 300, 15)])
        try context.save()

        XCTAssertEqual(Seed.reconcileDuplicatePlatforms(context), 1)

        let accounts = try context.fetch(FetchDescriptor<PlatformAccount>())
        let earnings = try context.fetch(FetchDescriptor<PlatformEarning>())
        XCTAssertEqual(accounts.count, 1)
        XCTAssertFalse(accounts[0].isActive)
        XCTAssertEqual(accounts[0].earningItems.count, 1)
        XCTAssertEqual(earnings.count, 1)
        XCTAssertTrue(earnings[0].account === accounts[0])
        XCTAssertTrue(earnings[0].account === locallySeeded)
    }

    func testCompleteBackupRoundTripPreservesDataAndRelationships() throws {
        let context = try TestStore.makeContext()
        let account = Fixture.account(context, name: "Lyft", unitNoun: "rides")
        let profile = Fixture.profile(context, taxRate: 24, maintenanceRate: 9)
        profile.stateCode = "FL"
        profile.stateIncomeTaxRate = 1.5

        let vehicle = VehicleRecord(
            name: "Tesla Model Y",
            detail: "Electric · SVERIGE",
            odometerBaseline: 29_329,
            make: "Tesla",
            model: "Model Y",
            year: 2024,
            plate: "SVERIGE",
            fuelType: .electric
        )
        context.insert(vehicle)
        let service = ServiceRecord(
            name: "Tire rotation",
            dueAtMileage: 35_329,
            intervalMiles: 6_000
        )
        service.vehicle = vehicle
        context.insert(service)
        vehicle.serviceItems.append(service)

        let shift = Fixture.shift(
            context,
            day: 2,
            from: 10,
            to: 18,
            miles: 121,
            splits: [(account, 300, 15)]
        )
        shift.earningItems[0].tips = 34.17
        shift.earningItems[0].promotions = 12

        let drive = DriveRecord(
            start: shift.start,
            end: shift.end,
            distanceMeters: 121 * 1_609.344,
            purpose: .business,
            startPlace: "Miami",
            endPlace: "Fort Lauderdale"
        )
        drive.shift = shift
        context.insert(drive)
        _ = Fixture.expense(context, amount: 18.42, category: .fees)
        try context.save()

        let original = try GigGrowBackup.capture(from: context)
        let data = try original.encoded()
        let decoded = try GigGrowBackup.decoded(from: data)
        try decoded.restore(into: context)

        let restoredProfiles = try context.fetch(FetchDescriptor<DriverProfile>())
        let restoredShifts = try context.fetch(FetchDescriptor<Shift>())
        let restoredDrives = try context.fetch(FetchDescriptor<DriveRecord>())
        let restoredExpenses = try context.fetch(FetchDescriptor<Expense>())
        let restoredVehicles = try context.fetch(FetchDescriptor<VehicleRecord>())

        XCTAssertEqual(restoredProfiles.count, 1)
        XCTAssertEqual(restoredProfiles[0].stateCode, "FL")
        XCTAssertEqual(restoredProfiles[0].taxRate, 24)

        XCTAssertEqual(restoredShifts.count, 1)
        XCTAssertEqual(restoredShifts[0].gross, 300, accuracy: 0.001)
        XCTAssertEqual(restoredShifts[0].earningItems[0].tips, 34.17, accuracy: 0.001)
        XCTAssertEqual(restoredShifts[0].earningItems[0].account?.name, "Lyft")

        XCTAssertEqual(restoredDrives.count, 1)
        let restoredDriveShift = try XCTUnwrap(restoredDrives[0].shift)
        XCTAssertEqual(restoredDriveShift.gross, 300, accuracy: 0.001)
        XCTAssertEqual(restoredDrives[0].purpose, .business)

        XCTAssertEqual(restoredExpenses.count, 1)
        XCTAssertEqual(restoredExpenses[0].amount, 18.42, accuracy: 0.001)

        XCTAssertEqual(restoredVehicles.count, 1)
        XCTAssertEqual(restoredVehicles[0].fuelType, .electric)
        XCTAssertEqual(restoredVehicles[0].serviceItems.first?.name, "Tire rotation")
    }
}
