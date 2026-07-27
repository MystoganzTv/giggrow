//
//  ImportAndVehicleTests.swift
//  GigGrowTests
//
//  Regressions from testing the app with real data.
//

import XCTest
import SwiftData
@testable import GigGrow

@MainActor
final class ImportAndVehicleTests: XCTestCase {

    // MARK: The invented hour

    /// A Spark screenshot showing $185.27 and no duration produced a one-hour
    /// shift, so the dashboard reported $185.27 per hour. A fabricated
    /// denominator is worse than a missing figure: nothing downstream can
    /// tell it apart from a real one.
    func testAShiftWithNoHoursProducesNoHourlyRate() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Walmart Spark")

        // Zero-length block, as an import with no hours would create.
        let start = Fixture.weekStart()
        let shift = Shift(start: start, end: start, miles: 0)
        context.insert(shift)
        let earning = PlatformEarning(account: account, gross: 185.27, trips: 0)
        context.insert(earning)
        earning.shift = shift
        shift.earnings.append(earning)

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile, vehicle: nil
        )

        XCTAssertEqual(snapshot.onlineHours, 0, accuracy: 0.0001)
        XCTAssertMoneyEqual(snapshot.perHour, 0)
        XCTAssertEqual(snapshot.perHourLabel, "—",
                       "a rate with no denominator must read as unknown, not as a figure")
    }

    func testZeroMileageShowsADashRatherThanZeroPerMile() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")
        Fixture.shift(context, from: 9, to: 14, miles: 0, splits: [(account, 200, 8)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: try context.fetch(FetchDescriptor<PlatformAccount>()),
            profile: profile, vehicle: nil
        )

        XCTAssertEqual(snapshot.perMileLabel, "—")
        XCTAssertEqual(snapshot.perHourLabel, "$40.00", "hours were real, so this one is a figure")
    }

    // MARK: Fuel type

    func testElectricVehiclesDoNotReportMPG() {
        XCTAssertFalse(FuelType.electric.burnsFuel)
        XCTAssertEqual(FuelType.electric.efficiencyUnit, "mi/kWh")
        XCTAssertEqual(FuelType.electric.costPerMileTitle, "Charging / mi")

        for fuel in [FuelType.gasoline, .diesel, .hybrid, .pluginHybrid] {
            XCTAssertTrue(fuel.burnsFuel, "\(fuel.label) burns fuel")
            XCTAssertEqual(fuel.efficiencyUnit, "mpg")
        }
    }

    /// Catches an mpg typed into an EV and the reverse — the two are an order
    /// of magnitude apart, so a swap is silently plausible without a check.
    func testImplausibleEfficiencyIsRejected() {
        XCTAssertTrue(FuelType.gasoline.isPlausibleEfficiency(39))
        XCTAssertFalse(FuelType.gasoline.isPlausibleEfficiency(3.5), "3.5 mpg is a mistyped mi/kWh")

        XCTAssertTrue(FuelType.electric.isPlausibleEfficiency(3.5))
        XCTAssertFalse(FuelType.electric.isPlausibleEfficiency(39), "39 mi/kWh is a mistyped mpg")

        XCTAssertFalse(FuelType.electric.isPlausibleEfficiency(0))
    }

    func testEfficiencyRoundTripsForBothKinds() throws {
        let context = try TestStore.makeContext()

        let ev = VehicleRecord(odometerBaseline: 1_000, fuelType: .electric)
        context.insert(ev)
        ev.efficiency = 3.5
        XCTAssertEqual(ev.efficiency, 3.5, accuracy: 0.05)
        XCTAssertEqual(ev.efficiencyLabel, "3.5 mi/kWh")

        let petrol = VehicleRecord(odometerBaseline: 1_000, fuelType: .gasoline)
        context.insert(petrol)
        petrol.averageMPG = 39
        XCTAssertEqual(petrol.efficiencyLabel, "39 mpg")
    }

    func testEfficiencyLabelIsADashWhenUnset() throws {
        let context = try TestStore.makeContext()
        let vehicle = VehicleRecord(odometerBaseline: 1_000, fuelType: .electric)
        context.insert(vehicle)
        XCTAssertEqual(vehicle.efficiencyLabel, "—")
    }

    // MARK: Display name

    func testDisplayNameComposesFromTheStructuredFields() throws {
        let context = try TestStore.makeContext()
        let vehicle = VehicleRecord(
            odometerBaseline: 12_000,
            make: "Tesla", model: "Model Y", year: 2024,
            plate: "SVERIGE", fuelType: .electric
        )
        context.insert(vehicle)

        XCTAssertEqual(vehicle.displayName, "2024 Tesla Model Y")
        XCTAssertEqual(vehicle.displayDetail, "Electric · SVERIGE")
    }

    /// Records created before the fields were split still read correctly.
    func testLegacyRecordsFallBackToTheFreeTextLine() throws {
        let context = try TestStore.makeContext()
        let vehicle = VehicleRecord(
            name: "2022 Toyota RAV4",
            detail: "Hybrid · 7KJD812",
            odometerBaseline: 84_210
        )
        context.insert(vehicle)

        XCTAssertEqual(vehicle.displayName, "2022 Toyota RAV4")
        // Fuel type defaults to gasoline, so the detail composes from that.
        XCTAssertTrue(vehicle.displayDetail.contains("Gasoline"))
    }

    func testPartialIdentityStillProducesAName() throws {
        let context = try TestStore.makeContext()
        let vehicle = VehicleRecord(odometerBaseline: 0, model: "Model Y")
        context.insert(vehicle)
        XCTAssertEqual(vehicle.displayName, "Model Y")
    }
}
