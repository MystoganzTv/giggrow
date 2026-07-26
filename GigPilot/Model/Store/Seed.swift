//
//  Seed.swift
//  GigPilot
//
//  First-run contents.
//
//  A real install gets the six platform accounts and nothing else — no
//  profile, no vehicle, no shifts. The profile is what onboarding produces,
//  and its absence is how the app knows onboarding hasn't run.
//
//  The demo week lives behind `#if DEBUG` and is never reachable from a
//  release build. Seeding it on first launch, as this file used to, meant a
//  real driver opened GigPilot and saw $1,482.60 of somebody else's earnings
//  presented as their own.
//

import Foundation
import SwiftData

enum Seed {

    /// Creates the platform catalogue if it's missing. Safe on every launch.
    ///
    /// Deliberately does **not** create a `DriverProfile` — see `hasCompletedOnboarding`.
    static func bootstrapPlatformsIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<PlatformAccount>())) ?? []
        guard existing.isEmpty else { return }

        // Explicit loop rather than `forEach(context.insert)` — passing a
        // generic method as a function value leaves T unresolved.
        for account in defaultAccounts() {
            context.insert(account)
        }
        try? context.save()
    }

    /// Onboarding is complete once a profile exists. One check, one meaning.
    static func hasCompletedOnboarding(_ context: ModelContext) -> Bool {
        let profiles = (try? context.fetch(FetchDescriptor<DriverProfile>())) ?? []
        return !profiles.isEmpty
    }

    /// Writes what onboarding collected. The only path that creates a profile.
    @discardableResult
    static func completeOnboarding(
        _ context: ModelContext,
        name: String,
        location: String,
        vehicleName: String,
        vehicleDetail: String,
        odometer: Int,
        activePlatformNames: Set<String>,
        taxRate: Double = 25,
        maintenanceRate: Double = 8,
        stateCode: String = ""
    ) -> DriverProfile {

        let year = Calendar.gigPilot.component(.year, from: .now)
        let detail = location.isEmpty ? "Since \(year)" : "\(location) · Since \(year)"

        let profile = DriverProfile(
            name: name,
            detail: detail,
            taxRate: taxRate,
            maintenanceRate: maintenanceRate,
            mileageRate: 0.70,
            payoutLast4: "",
            maintenanceGoal: 3_000,
            maintenanceOpeningBalance: 0
        )
        profile.stateCode = stateCode
        context.insert(profile)

        if !vehicleName.isEmpty {
            let vehicle = VehicleRecord(
                name: vehicleName,
                detail: vehicleDetail,
                odometerBaseline: odometer,
                odometerAsOf: .now
            )
            context.insert(vehicle)

            // Service intervals are seeded relative to the driver's own
            // odometer, so the schedule means something from day one.
            for record in defaultService(baseOdometer: odometer) {
                record.vehicle = vehicle
                context.insert(record)
            }
        }

        // Only the platforms they actually drive for stay active.
        let accounts = (try? context.fetch(FetchDescriptor<PlatformAccount>())) ?? []
        for account in accounts {
            account.isActive = activePlatformNames.contains(account.name)
        }

        try? context.save()
        return profile
    }

    // MARK: Platform accounts

    static func defaultAccounts() -> [PlatformAccount] {
        [
            PlatformAccount(name: "Uber", short: "Uber", initial: "U",
                            gradientStart: 0xA78BFA, gradientEnd: 0x7C5CF6,
                            unitNoun: "trips", sortIndex: 0),
            PlatformAccount(name: "Lyft", short: "Lyft", initial: "L",
                            gradientStart: 0xC084FC, gradientEnd: 0x8B5CF6,
                            unitNoun: "trips", sortIndex: 1),
            PlatformAccount(name: "DoorDash", short: "DoorDash", initial: "D",
                            gradientStart: 0x818CF8, gradientEnd: 0x4F76F6,
                            unitNoun: "orders", sortIndex: 2),
            PlatformAccount(name: "Instacart", short: "Instacart", initial: "I",
                            gradientStart: 0x60A5FA, gradientEnd: 0x3B82F6,
                            unitNoun: "batches", sortIndex: 3),
            PlatformAccount(name: "Amazon Flex", short: "Flex", initial: "F",
                            gradientStart: 0x7DD3FC, gradientEnd: 0x38BDF8,
                            unitNoun: "blocks", sortIndex: 4),
            PlatformAccount(name: "Walmart Spark", short: "Spark", initial: "S",
                            gradientStart: 0x93C5FD, gradientEnd: 0x60A5FA,
                            unitNoun: "trips", sortIndex: 5)
        ]
    }

    // MARK: Service schedule

    /// Standard intervals measured forward from the driver's own odometer.
    /// Nothing starts overdue — claiming a stranger's tyres need rotating is
    /// the kind of fabricated detail that costs trust on first launch.
    static func defaultService(baseOdometer: Int) -> [ServiceRecord] {
        [
            ServiceRecord(name: "Oil change",
                          dueAtMileage: baseOdometer + 5_000,
                          intervalMiles: 5_000),
            ServiceRecord(name: "Tire rotation",
                          dueAtMileage: baseOdometer + 6_000,
                          intervalMiles: 6_000),
            ServiceRecord(name: "Brake pads",
                          dueAtMileage: baseOdometer + 20_000,
                          intervalMiles: 20_000),
            ServiceRecord(name: "Registration",
                          dueOn: Calendar.gigPilot.date(byAdding: .year, value: 1, to: .now),
                          intervalMonths: 12)
        ]
    }
}

// MARK: - Demo data
//
// Debug builds only. This is what makes the screens look like the mockup
// while developing, and it must never reach a shipping build.

#if DEBUG
extension Seed {

    /// Wipes the store and lays down the design's exact week. Reachable from
    /// the debug menu, never from first launch.
    static func loadDemoData(_ context: ModelContext) {
        try? context.delete(model: Shift.self)
        try? context.delete(model: PlatformEarning.self)
        try? context.delete(model: Expense.self)
        try? context.delete(model: ServiceRecord.self)
        try? context.delete(model: VehicleRecord.self)
        try? context.delete(model: DriverProfile.self)
        try? context.delete(model: PlatformAccount.self)

        let accounts = defaultAccounts()
        for account in accounts { context.insert(account) }

        let profile = DriverProfile(
            name: "Marco Delgado",
            detail: "Phoenix, AZ · Since 2023",
            taxRate: 25,
            maintenanceRate: 8,
            mileageRate: 0.70,
            payoutLast4: "4417",
            maintenanceGoal: 3_000,
            // The design's fund is $2,684; the demo week contributes 8% of
            // $1,482.60 and the rest is treated as prior balance.
            maintenanceOpeningBalance: 2_684 - 1_482.60 * 0.08
        )
        context.insert(profile)

        let vehicle = VehicleRecord(
            name: "2022 Toyota RAV4",
            detail: "Hybrid · 7KJD812",
            odometerBaseline: 83_598,          // + the demo week's 612 mi = 84,210
            odometerAsOf: Calendar.gigPilot.startOfWeek(for: .now),
            fuelCostPerMile: 0.11,
            averageMPG: 39
        )
        context.insert(vehicle)

        for record in demoService(baseOdometer: 84_210) {
            record.vehicle = vehicle
            context.insert(record)
        }

        for shift in demoWeek(accounts: accounts) {
            context.insert(shift)
        }

        try? context.save()
    }

    /// Erases everything, returning the app to a genuine first-run state.
    static func wipe(_ context: ModelContext) {
        try? context.delete(model: Shift.self)
        try? context.delete(model: PlatformEarning.self)
        try? context.delete(model: Expense.self)
        try? context.delete(model: ServiceRecord.self)
        try? context.delete(model: VehicleRecord.self)
        try? context.delete(model: DriverProfile.self)
        try? context.delete(model: PlatformAccount.self)
        try? context.save()
    }

    /// The design's exact mix of statuses: one scheduled, one overdue, two healthy.
    static func demoService(baseOdometer: Int) -> [ServiceRecord] {
        [
            ServiceRecord(name: "Oil change",
                          dueAtMileage: baseOdometer + 1_790,
                          dueNote: "Sep 2026"),
            ServiceRecord(name: "Tire rotation",
                          dueAtMileage: baseOdometer - 420),
            ServiceRecord(name: "Brake pads",
                          dueAtMileage: baseOdometer + 8_200),
            ServiceRecord(name: "Registration",
                          dueOn: Calendar.gigPilot.date(from: DateComponents(year: 2027, month: 3, day: 1)),
                          dueNote: "Renews Mar 2027")
        ]
    }

    // MARK: Demo week
    //
    // Seven shifts whose totals land on the design's numbers: $1,482.60 gross,
    // 38.4 online hours, 9.2 idle, 612 miles, 214 units of work, and the six
    // platform shares (29/21/18/14/11/7%). Several days deliberately run two
    // apps at once so the multi-app hour attribution has something to chew on.

    static func demoWeek(accounts: [PlatformAccount]) -> [Shift] {
        let cal = Calendar.gigPilot
        let weekStart = cal.startOfWeek(for: .now)

        func account(_ name: String) -> PlatformAccount? {
            accounts.first { $0.name == name }
        }

        /// day 0 = Monday. Times are local.
        func shift(
            day: Int, from startHour: Double, to endHour: Double,
            miles: Double, idle: Double,
            _ splits: [(String, Double, Int)]
        ) -> Shift {
            let dayStart = cal.date(byAdding: .day, value: day, to: weekStart) ?? weekStart
            let start = dayStart.addingTimeInterval(startHour * 3600)
            let end = dayStart.addingTimeInterval(endHour * 3600)

            let earnings = splits.map { name, gross, trips in
                PlatformEarning(account: account(name), gross: gross, trips: trips)
            }
            return Shift(start: start, end: end, miles: miles, idleMinutes: idle * 60, earnings: earnings)
        }

        // Hours 38.4 · idle 9.2 · miles 612 · 214 units · $1,482.60,
        // split 29/21/18/14/11/7% across the six apps. Five of the seven days
        // run two or three apps at once.
        return [
            // Mon — Uber + DoorDash
            shift(day: 0, from: 8, to: 13, miles: 82, idle: 1.2, [
                ("Uber", 84.24, 12), ("DoorDash", 91.01, 13)
            ]),
            // Tue — Uber + Lyft
            shift(day: 1, from: 7.5, to: 12, miles: 74, idle: 1.0, [
                ("Uber", 82.71, 12), ("Lyft", 83.09, 12)
            ]),
            // Wed — a single Flex block, the one solo day
            shift(day: 2, from: 10, to: 14, miles: 96, idle: 0.7, [
                ("Amazon Flex", 131.21, 19)
            ]),
            // Thu — Uber + Instacart
            shift(day: 3, from: 9, to: 14.5, miles: 88, idle: 1.3, [
                ("Uber", 104.47, 15), ("Instacart", 102.07, 15)
            ]),
            // Fri — three apps at once
            shift(day: 4, from: 15, to: 21.5, miles: 104, idle: 1.5, [
                ("Uber", 89.60, 13), ("DoorDash", 84.13, 12), ("Lyft", 69.01, 10)
            ]),
            // Sat — the long one, Lyft-led
            shift(day: 5, from: 11, to: 18.5, miles: 118, idle: 2.0, [
                ("Lyft", 159.25, 23), ("Uber", 68.93, 10), ("Walmart Spark", 103.78, 15)
            ]),
            // Sun — delivery day
            shift(day: 6, from: 10, to: 15.4, miles: 50, idle: 1.5, [
                ("DoorDash", 91.73, 13), ("Instacart", 105.49, 15), ("Amazon Flex", 31.88, 5)
            ])
        ]
    }
}
#endif

// MARK: - Store access

/// Small helper so views can pull everything the projection needs in one call.
enum Store {

    /// Returns nil before onboarding has run — there is no profile to build from.
    static func snapshot(
        _ context: ModelContext,
        range: Range<Date> = DateRange.week(containing: .now),
        now: Date = .now
    ) -> EarningsSnapshot? {
        guard let profile = (try? context.fetch(FetchDescriptor<DriverProfile>()))?.first else {
            return nil
        }
        let shifts = (try? context.fetch(FetchDescriptor<Shift>())) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<PlatformAccount>())) ?? []
        let vehicle = (try? context.fetch(FetchDescriptor<VehicleRecord>()))?.first

        return EarningsSnapshot.build(
            shifts: shifts,
            expenses: expenses,
            accounts: accounts,
            profile: profile,
            vehicle: vehicle,
            range: range,
            now: now
        )
    }
}
