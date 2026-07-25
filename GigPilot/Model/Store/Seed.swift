//
//  Seed.swift
//  GigPilot
//
//  First-run contents. A brand-new install gets the six platform accounts,
//  a profile and a service schedule; the demo flag additionally lays down a
//  week of shifts that reproduces the design's figures exactly, which is what
//  makes the screens look like the mockup on first launch.
//

import Foundation
import SwiftData

enum Seed {

    /// Runs once. Safe to call on every launch — it no-ops if a profile exists.
    @discardableResult
    static func bootstrapIfNeeded(_ context: ModelContext, includeDemoWeek: Bool = true) -> DriverProfile {
        if let existing = try? context.fetch(FetchDescriptor<DriverProfile>()), let profile = existing.first {
            return profile
        }

        let profile = DriverProfile(
            name: "Marco Delgado",
            detail: "Phoenix, AZ · Since 2023",
            taxRate: 25,
            maintenanceRate: 8,
            mileageRate: 0.70,
            payoutLast4: "4417",
            maintenanceGoal: 3_000,
            maintenanceOpeningBalance: 0
        )
        context.insert(profile)

        let accounts = defaultAccounts()
        accounts.forEach(context.insert)

        let vehicle = VehicleRecord(
            name: "2022 Toyota RAV4",
            detail: "Hybrid · 7KJD812",
            odometerBaseline: 83_598,          // + the demo week's 612 mi = 84,210
            odometerAsOf: Calendar.gigPilot.startOfWeek(for: .now),
            fuelCostPerMile: 0.11,
            averageMPG: 39
        )
        context.insert(vehicle)

        for record in defaultService(baseOdometer: 84_210) {
            record.vehicle = vehicle
            context.insert(record)
        }

        if includeDemoWeek {
            for shift in demoWeek(accounts: accounts) {
                context.insert(shift)
            }
            // The design's maintenance fund is $2,684, of which the demo week
            // contributes 8% of $1,482.60. The rest is treated as prior balance.
            profile.maintenanceOpeningBalance = 2_684 - 1_482.60 * 0.08
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

    static func defaultService(baseOdometer: Int) -> [ServiceRecord] {
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

// MARK: - Store access

/// Small helper so views can pull everything the projection needs in one call.
enum Store {

    static func snapshot(
        _ context: ModelContext,
        range: Range<Date> = DateRange.week(containing: .now),
        now: Date = .now
    ) -> EarningsSnapshot {
        let profile = Seed.bootstrapIfNeeded(context)
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
