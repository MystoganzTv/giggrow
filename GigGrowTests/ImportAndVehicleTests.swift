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

    func testRideSharePlatformsUseTheirOwnWorkVocabulary() {
        let accounts = Dictionary(
            uniqueKeysWithValues: Seed.defaultAccounts().map { ($0.name, $0.unitNoun) }
        )

        XCTAssertEqual(accounts["Uber"], "trips")
        XCTAssertEqual(accounts["Lyft"], "rides")
    }

    func testTeslaDefaultsToElectricAndHasNoOilService() throws {
        XCTAssertEqual(
            FuelType.unambiguousType(make: "Tesla", model: "Model Y"),
            .electric
        )
        let service = Seed.defaultService(
            baseOdometer: 29_329,
            fuelType: .electric
        )
        XCTAssertFalse(service.contains {
            $0.name.localizedCaseInsensitiveContains("oil change")
        })
    }

    func testExistingTeslaGasolineDefaultIsRepaired() throws {
        let context = try TestStore.makeContext()
        let vehicle = VehicleRecord(
            name: "Tesla Model Y",
            detail: "Gasoline · SVERIGE",
            odometerBaseline: 29_329,
            make: "Tesla",
            model: "Model Y",
            plate: "SVERIGE",
            fuelType: .gasoline
        )
        context.insert(vehicle)
        let oil = ServiceRecord(
            name: "Oil change",
            dueAtMileage: 34_329,
            intervalMiles: 5_000
        )
        context.insert(oil)
        oil.vehicle = vehicle
        vehicle.service.append(oil)

        Seed.repairKnownVehicleDefaults(context)

        XCTAssertEqual(vehicle.fuelType, .electric)
        XCTAssertEqual(vehicle.displayDetail, "Electric · SVERIGE")
        XCTAssertFalse(vehicle.service.contains {
            $0.name.localizedCaseInsensitiveContains("oil change")
        })
    }

    // MARK: Vehicle catalog

    func testVehicleCatalogFiltersModelsByMake() {
        XCTAssertTrue(VehicleCatalog.models(for: "Tesla").contains("Model Y"))
        XCTAssertFalse(VehicleCatalog.models(for: "Toyota").contains("Model Y"))
        XCTAssertTrue(VehicleCatalog.models(for: "Toyota").contains("RAV4"))
    }

    func testVehicleCatalogMatchesStoredNamesWithoutChangingTheirCase() {
        XCTAssertEqual(VehicleCatalog.canonicalMake(matching: " tesla "), "Tesla")
        XCTAssertEqual(
            VehicleCatalog.canonicalModel(matching: "model y", for: "TESLA"),
            "Model Y"
        )
    }

    func testVehicleCatalogHasUniqueMakesAndModels() {
        XCTAssertEqual(
            Set(VehicleCatalog.makeNames).count,
            VehicleCatalog.makeNames.count
        )
        for make in VehicleCatalog.makes {
            XCTAssertEqual(
                Set(make.models).count,
                make.models.count,
                "\(make.name) contains a duplicate model"
            )
        }
    }

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

    func testInactivePlatformStillAppearsWhenItHasEarnings() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Uber")
        account.isActive = false
        Fixture.shift(context, from: 9, to: 14, miles: 0, splits: [(account, 200, 8)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: [account],
            profile: profile,
            vehicle: nil
        )

        XCTAssertEqual(snapshot.platforms.map(\.name), ["Uber"],
                       "turning an app off must not erase its historical comparison row")
    }

    func testDaySplitFromWeeklyScreenshotDoesNotInventClockHours() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let account = Fixture.account(context, name: "Lyft")
        let start = Calendar.gigGrow.date(
            bySettingHour: 9, minute: 0, second: 0, of: Fixture.weekStart()
        )!
        let shift = Shift(
            start: start,
            end: start.addingTimeInterval(3 * 3_600),
            note: "From a weekly screenshot — day split read off the chart"
        )
        context.insert(shift)
        let earning = PlatformEarning(account: account, gross: 150, trips: 10)
        context.insert(earning)
        earning.shift = shift
        shift.earnings.append(earning)

        let snapshot = EarningsSnapshot.build(
            shifts: [shift],
            expenses: [],
            accounts: [account],
            profile: profile,
            vehicle: nil
        )

        XCTAssertEqual(snapshot.onlineHours, 3, accuracy: 0.001,
                       "weekly total hours remain useful for the overall hourly rate")
        XCTAssertEqual(snapshot.series.hourly.reduce(0, +), 0, accuracy: 0.001,
                       "9am was a storage anchor, not observed time-of-day data")
    }

    func testWeeklyPlatformsKeepTheirOwnActiveDays() throws {
        let days = WeeklySplitAllocator.allocate([
            WeeklyPlatformSplit(
                platform: "Lyft", gross: 100, tips: 10,
                promotions: 0, trips: 10,
                dailyShares: [0.5, 0.5, 0, 0, 0, 0, 0]
            ),
            WeeklyPlatformSplit(
                platform: "Uber", gross: 50, tips: 5,
                promotions: 0, trips: 5,
                dailyShares: [0, 0.2, 0.8, 0, 0, 0, 0]
            )
        ])

        XCTAssertEqual(days.map(\.dayIndex), [0, 1, 2])
        XCTAssertEqual(days[0].earnings.map(\.platform), ["Lyft"],
                       "Uber must not inherit Lyft's Monday bar")
        XCTAssertEqual(Set(days[1].earnings.map(\.platform)), Set(["Lyft", "Uber"]))
        XCTAssertEqual(days[2].earnings.map(\.platform), ["Uber"],
                       "Lyft must not inherit Uber's Wednesday bar")

        let lyftTotal = days.flatMap(\.earnings)
            .filter { $0.platform == "Lyft" }
            .reduce(0) { $0 + $1.gross }
        let uberTotal = days.flatMap(\.earnings)
            .filter { $0.platform == "Uber" }
            .reduce(0) { $0 + $1.gross }
        XCTAssertEqual(lyftTotal, 100, accuracy: 0.001)
        XCTAssertEqual(uberTotal, 50, accuracy: 0.001)
        XCTAssertEqual(days.reduce(0) { $0 + $1.combinedShare }, 1, accuracy: 0.001)
    }

    func testWeeklyDayRoundingConservesExactMoneyAndUnits() {
        let days = WeeklySplitAllocator.allocate([
            WeeklyPlatformSplit(
                platform: "Uber",
                gross: 245.34,
                tips: 27.00,
                promotions: 8.40,
                trips: 12,
                dailyShares: [0.157, 0, 0, 0, 0.263, 0.461, 0.119]
            )
        ])

        let earnings = days.flatMap(\.earnings)
        XCTAssertEqual(earnings.reduce(0) { $0 + $1.gross }, 245.34, accuracy: 0.0001)
        XCTAssertEqual(earnings.reduce(0) { $0 + $1.tips }, 27.00, accuracy: 0.0001)
        XCTAssertEqual(earnings.reduce(0) { $0 + $1.promotions }, 8.40, accuracy: 0.0001)
        XCTAssertEqual(earnings.reduce(0) { $0 + $1.trips }, 12)
        XCTAssertTrue(earnings.allSatisfy {
            abs($0.gross * 100 - ($0.gross * 100).rounded()) < 0.0001
        })
    }

    func testAnalyticsExposesEachPlatformsDailyBreakdown() throws {
        let context = try TestStore.makeContext()
        let profile = Fixture.profile(context)
        let lyft = Fixture.account(context, name: "Lyft", unitNoun: "rides")
        let uber = Fixture.account(context, name: "Uber", sortIndex: 1)

        Fixture.shift(context, day: 0, splits: [(lyft, 5, 1)])
        Fixture.shift(context, day: 1, splits: [(lyft, 142, 9), (uber, 30, 2)])
        Fixture.shift(context, day: 2, splits: [(lyft, 300, 18)])

        let snapshot = EarningsSnapshot.build(
            shifts: try context.fetch(FetchDescriptor<Shift>()),
            expenses: [],
            accounts: [lyft, uber],
            profile: profile,
            vehicle: nil,
            range: AnalyticsRange.week.window(containing: .now),
            rangeKind: .week
        )

        let lyftDaily = try XCTUnwrap(
            snapshot.platforms.first(where: { $0.name == "Lyft" })?.daily
        )
        let uberDaily = try XCTUnwrap(
            snapshot.platforms.first(where: { $0.name == "Uber" })?.daily
        )
        XCTAssertEqual(lyftDaily, [5, 142, 300, 0, 0, 0, 0])
        XCTAssertEqual(uberDaily, [0, 30, 0, 0, 0, 0, 0])
    }

    func testZeroSundayShareCreatesNoLyftSundayEarning() throws {
        let days = WeeklySplitAllocator.allocate([
            WeeklyPlatformSplit(
                platform: "Lyft", gross: 998.31, tips: 89.67,
                promotions: 0, trips: 60,
                dailyShares: [
                    5 / 998.0, 142 / 998.0, 300 / 998.0,
                    123 / 998.0, 273 / 998.0, 155 / 998.0, 0
                ]
            )
        ])

        XCTAssertEqual(days.map(\.dayIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertNil(days.first(where: { $0.dayIndex == 6 }),
                     "the dark Sunday dot in Lyft is zero, not a worked shift")
    }

    func testWeeklyReportOverlapsADailyReportForTheSameAppAndWeek() {
        let week = Fixture.weekStart()
        let thursday = Calendar.gigGrow.date(
            byAdding: .day, value: 3, to: week
        )!

        XCTAssertTrue(
            ImportOverlapDetector.overlaps(
                ImportCoverage(platform: "Lyft", period: .week, date: week),
                ImportCoverage(platform: "Lyft", period: .day, date: thursday)
            ),
            "a Lyft week already contains that Lyft day"
        )
        XCTAssertTrue(
            ImportOverlapDetector.overlaps(
                ImportCoverage(platform: "Lyft", period: .day, date: thursday),
                ImportCoverage(platform: "Lyft", period: .week, date: week)
            ),
            "the check must work regardless of which report was imported first"
        )
    }

    func testWeeklyReportDoesNotOverlapAnotherAppsDailyReport() {
        let week = Fixture.weekStart()
        let thursday = Calendar.gigGrow.date(
            byAdding: .day, value: 3, to: week
        )!

        XCTAssertFalse(
            ImportOverlapDetector.overlaps(
                ImportCoverage(platform: "Uber", period: .week, date: week),
                ImportCoverage(platform: "Lyft", period: .day, date: thursday)
            ),
            "Uber's weekly report does not contain Lyft's earnings"
        )
    }

    func testSplitWeeklyDayStillBlocksTheMatchingDailyImport() {
        let monday = Fixture.weekStart()
        let sunday = Calendar.gigGrow.date(
            byAdding: .day, value: 6, to: monday
        )!
        let splitDay = Shift(
            start: monday,
            end: monday.addingTimeInterval(2 * 3_600),
            note: "From a weekly screenshot — day split read off the chart"
        )
        splitDay.isAggregate = true

        let stored = ImportOverlapDetector.coverage(
            of: splitDay,
            platform: "Uber"
        )
        XCTAssertEqual(stored.period, .week)
        XCTAssertTrue(
            ImportOverlapDetector.overlaps(
                ImportCoverage(platform: "Uber", period: .day, date: sunday),
                stored
            ),
            "the weekly source covers Sunday even when its chart stored no Sunday row"
        )
    }

    func testWholeWeeklyAggregateBlocksAnyMatchingDailyImport() {
        let monday = Fixture.weekStart()
        let sunday = Calendar.gigGrow.date(
            byAdding: .day, value: 6, to: monday
        )!
        let wholeWeek = Shift(
            start: monday,
            end: Calendar.gigGrow.date(
                byAdding: .day, value: 7, to: monday
            )!,
            note: "Imported from a weekly summary"
        )
        wholeWeek.isAggregate = true

        let stored = ImportOverlapDetector.coverage(
            of: wholeWeek,
            platform: "Uber"
        )
        XCTAssertEqual(stored.period, .week)
        XCTAssertTrue(
            ImportOverlapDetector.overlaps(
                ImportCoverage(platform: "Uber", period: .day, date: sunday),
                stored
            )
        )
    }

    // MARK: Fuel type

    func testElectricVehiclesDoNotReportMPG() {
        XCTAssertFalse(FuelType.electric.burnsFuel)
        XCTAssertEqual(FuelType.electric.efficiencyUnit, "miles/kWh")
        XCTAssertEqual(FuelType.electric.costPerMileTitle, "Electricity cost")
        XCTAssertEqual(FuelType.electric.costPerMileFootnote, "to drive 1 mile")
        XCTAssertEqual(FuelType.electric.efficiencyTitle, "Energy efficiency")
        XCTAssertEqual(FuelType.electric.efficiencyFootnote, "miles from 1 kWh")

        for fuel in [FuelType.gasoline, .diesel, .hybrid, .pluginHybrid] {
            XCTAssertTrue(fuel.burnsFuel, "\(fuel.label) burns fuel")
            XCTAssertEqual(fuel.efficiencyUnit, "mpg")
        }
    }

    /// Catches an mpg typed into an EV and the reverse — the two are an order
    /// of magnitude apart, so a swap is silently plausible without a check.
    func testImplausibleEfficiencyIsRejected() {
        XCTAssertTrue(FuelType.gasoline.isPlausibleEfficiency(39))
        XCTAssertFalse(FuelType.gasoline.isPlausibleEfficiency(3.5), "3.5 mpg is a mistyped miles/kWh")

        XCTAssertTrue(FuelType.electric.isPlausibleEfficiency(3.5))
        XCTAssertFalse(FuelType.electric.isPlausibleEfficiency(39), "39 miles/kWh is a mistyped mpg")

        XCTAssertFalse(FuelType.electric.isPlausibleEfficiency(0))
    }

    func testEfficiencyRoundTripsForBothKinds() throws {
        let context = try TestStore.makeContext()

        let ev = VehicleRecord(odometerBaseline: 1_000, fuelType: .electric)
        context.insert(ev)
        ev.efficiency = 3.5
        XCTAssertEqual(ev.efficiency, 3.5, accuracy: 0.05)
        XCTAssertEqual(ev.efficiencyLabel, "3.5 miles/kWh")

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

    func testOnboardingStoresMakeModelAndPlateSeparately() throws {
        let context = try TestStore.makeContext()

        Seed.completeOnboarding(
            context,
            name: "Enrique",
            location: "Florida",
            vehicleMake: "Tesla",
            vehicleModel: "Model Y",
            vehiclePlate: "SVERIGE",
            odometer: 12_345,
            activePlatformNames: []
        )

        let vehicle = try XCTUnwrap(
            context.fetch(FetchDescriptor<VehicleRecord>()).first
        )
        XCTAssertEqual(vehicle.make, "Tesla")
        XCTAssertEqual(vehicle.model, "Model Y")
        XCTAssertEqual(vehicle.plate, "SVERIGE")
        XCTAssertEqual(vehicle.displayName, "Tesla Model Y")
    }
}
