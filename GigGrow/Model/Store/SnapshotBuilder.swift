//
//  SnapshotBuilder.swift
//  GigGrow
//
//  Turns stored shifts into the `EarningsSnapshot` the five screens already
//  read. This is the whole point of having built the UI against a projection:
//  nothing below changes a single line in DashboardView and friends.
//

import Foundation
import SwiftData
import SwiftUI   // Platform carries its brand gradient as Color values

// MARK: - Date ranges

enum DateRange {
    /// Monday-based week containing `date`, matching the design's Mon…Sun axis.
    static func day(containing date: Date, calendar: Calendar = .gigGrow) -> Range<Date> {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return start..<end
    }

    static func week(containing date: Date, calendar: Calendar = .gigGrow) -> Range<Date> {
        let start = calendar.startOfWeek(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return start..<end
    }

    static func month(containing date: Date, calendar: Calendar = .gigGrow) -> Range<Date> {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: comps) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return start..<end
    }

    static func year(containing date: Date, calendar: Calendar = .gigGrow) -> Range<Date> {
        let comps = calendar.dateComponents([.year], from: date)
        let start = calendar.date(from: comps) ?? date
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return start..<end
    }

    static func shifted(_ range: Range<Date>, by value: Int, unit: Calendar.Component,
                        calendar: Calendar = .gigGrow) -> Range<Date> {
        let lower = calendar.date(byAdding: unit, value: value, to: range.lowerBound) ?? range.lowerBound
        let upper = calendar.date(byAdding: unit, value: value, to: range.upperBound) ?? range.upperBound
        return lower..<upper
    }
}

extension Calendar {
    /// Weeks start Monday; the design's bar charts are labelled M T W T F S S.
    static var gigGrow: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? startOfDay(for: date)
    }
}

// MARK: - Attribution

/// How a shift's hours and miles are split between the apps that were running.
///
/// With two apps on at once there is no ground truth for "hours on Uber", so
/// the shift's hours are divided in proportion to what each app paid. A
/// platform that earned 70% of the block is charged 70% of its hours. The sum
/// of attributed hours therefore equals hours actually worked — no double
/// counting — while still giving a per-app rate worth comparing.
///
/// Note this splits *online* hours, not active ones. The dashboard's headline
/// $/hour is gross ÷ online hours, because waiting for a ping is part of the
/// job; per-platform rates have to divide by the same denominator or they
/// aren't comparable to the headline they sit under.
enum ShiftAttribution {

    static func hours(of earning: PlatformEarning, in shift: Shift) -> Double {
        share(of: earning, in: shift) * shift.hours
    }

    static func miles(of earning: PlatformEarning, in shift: Shift) -> Double {
        // Prefer what the app itself reported.
        if earning.reportedMiles > 0 { return earning.reportedMiles }
        return share(of: earning, in: shift) * shift.miles
    }

    private static func share(of earning: PlatformEarning, in shift: Shift) -> Double {
        let total = shift.gross
        guard total > 0 else {
            // Nothing earned: split evenly rather than dividing by zero.
            let n = max(shift.earnings.count, 1)
            return 1 / Double(n)
        }
        return earning.gross / total
    }
}

// MARK: - Builder

extension EarningsSnapshot {

    /// Builds the snapshot for `range` out of everything in the store.
    ///
    /// - Parameters:
    ///   - shifts: every shift, unfiltered. Filtering happens here so the
    ///     all-time rollups (maintenance fund, YTD taxes) stay correct.
    ///   - expenses: every expense, unfiltered, for the same reason.
    static func build(
        shifts: [Shift],
        expenses: [Expense],
        accounts: [PlatformAccount],
        profile: DriverProfile,
        vehicle vehicleRecord: VehicleRecord?,
        range: Range<Date> = DateRange.week(containing: .now),
        /// Which range the caller is asking about. Drives both the bar
        /// bucketing and the period a delta compares against — a month view
        /// that compared itself to last week would be quietly wrong.
        rangeKind: AnalyticsRange = .week,
        now: Date = .now,
        calendar: Calendar = .gigGrow
    ) -> EarningsSnapshot {

        let inRange = shifts.filter { range.contains($0.start) }
        let gross = inRange.reduce(0) { $0 + $1.gross }

        // Hours are summed per shift, so an hour with three apps on counts once.
        let onlineHours = inRange.reduce(0) { $0 + $1.hours }
        let activeHours = inRange.reduce(0) { $0 + $1.activeHours }
        let miles = inRange.reduce(0) { $0 + $1.miles }
        let trips = inRange.reduce(0) { $0 + $1.tripCount }

        // MARK: Platforms

        let previous = DateRange.shifted(range, by: -1, unit: rangeKind.comparisonUnit, calendar: calendar)
        let previousShifts = shifts.filter { previous.contains($0.start) }

        var platforms: [Platform] = []
        for account in accounts.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            var accGross = 0.0, accHours = 0.0, accMiles = 0.0, accTrips = 0
            var accDaily = Array(repeating: 0.0, count: 7)

            for shift in inRange {
                for earning in shift.earnings where earning.account?.name == account.name {
                    accGross += earning.gross
                    accHours += ShiftAttribution.hours(of: earning, in: shift)
                    accMiles += ShiftAttribution.miles(of: earning, in: shift)
                    accTrips += earning.trips
                    if rangeKind == .week {
                        let day = calendar.dateComponents(
                            [.day], from: range.lowerBound, to: shift.start
                        ).day ?? -1
                        if accDaily.indices.contains(day) {
                            accDaily[day] += earning.gross
                        }
                    }
                }
            }

            // Skip apps with no activity this period rather than showing a zero row.
            guard accGross > 0 || accTrips > 0 else { continue }

            let prevGross = previousShifts.reduce(0.0) { total, shift in
                total + shift.earnings
                    .filter { $0.account?.name == account.name }
                    .reduce(0) { $0 + $1.gross }
            }

            platforms.append(
                Platform(
                    name: account.name,
                    short: account.short,
                    initial: account.initial,
                    share: gross > 0 ? accGross / gross : 0,
                    hourly: accHours > 0 ? Money.cents(accGross / accHours) : "—",
                    meta: "\(accTrips) \(account.unitNoun) · \(Int(accMiles.rounded())) mi",
                    delta: percentChange(from: prevGross, to: accGross),
                    daily: rangeKind == .week ? accDaily : [],
                    gradient: [Color(hex: account.gradientStart), Color(hex: account.gradientEnd)]
                )
            )
        }
        platforms.sort { $0.share > $1.share }

        // MARK: Rollups

        // The comparison baseline must exclude the period being compared.
        // Including the selected first week in "your usual" compared the
        // week to itself and produced the meaningless message "0% above".
        let historicalShifts = shifts.filter { !range.contains($0.start) }
        let historicalGross = historicalShifts.reduce(0) { $0 + $1.gross }
        let historicalHours = historicalShifts.reduce(0) { $0 + $1.hours }
        let lifetimePerHour = historicalHours > 0
            ? historicalGross / historicalHours
            : 0

        let allTimeGross = shifts.reduce(0) { $0 + $1.gross }
        let maintenanceSpent = expenses
            .filter { $0.category.drawsFromMaintenanceFund }
            .reduce(0) { $0 + $1.amount }
        let maintenanceFund = profile.maintenanceOpeningBalance
            + allTimeGross * profile.maintenanceRate / 100
            - maintenanceSpent

        let yearRange = DateRange.year(containing: now, calendar: calendar)
        let ytdGross = shifts
            .filter { yearRange.contains($0.start) }
            .reduce(0) { $0 + $1.gross }

        let monthRange = DateRange.month(containing: now, calendar: calendar)
        let monthGross = shifts
            .filter { monthRange.contains($0.start) }
            .reduce(0) { $0 + $1.gross }
        let previousMonth = DateRange.shifted(monthRange, by: -1, unit: .month, calendar: calendar)
        let previousMonthGross = shifts
            .filter { previousMonth.contains($0.start) }
            .reduce(0) { $0 + $1.gross }

        let previousGross = previousShifts.reduce(0) { $0 + $1.gross }

        let rangeExpenses = expenses.filter { range.contains($0.date) }
        let expensesTotal = rangeExpenses.reduce(0) { $0 + $1.amount }

        // Maintenance spending is paid out of the reserve the maintenance
        // rate already withheld. Subtracting it from net profit as well would
        // charge the driver twice for the same dollar — once when it was set
        // aside, once when it was spent. Only out-of-pocket categories reduce
        // take-home.
        let outOfPocket = rangeExpenses
            .filter { !$0.category.drawsFromMaintenanceFund }
            .reduce(0) { $0 + $1.amount }
        let reserveDraw = expensesTotal - outOfPocket

        // What the driver actually keeps once both set-asides are honoured.
        let netProfit = gross
            - outOfPocket
            - gross * profile.taxRate / 100
            - gross * profile.maintenanceRate / 100

        // MARK: Vehicle

        // The service schedule is not projected here. VehicleView queries the
        // records directly, because rows that arrive as display-only values
        // have no route back to the object — the shape that left every
        // Settings chevron dead.
        let odometer = liveOdometer(vehicleRecord, shifts: shifts)

        let vehicle = Vehicle(
            name: vehicleRecord?.name ?? "No vehicle",
            detail: vehicleRecord?.detail ?? "Add one in Settings",
            odometer: odometer,
            milesThisWeek: Int(miles.rounded()),
            fuelCostPerMile: vehicleRecord?.fuelCostPerMile ?? 0,
            averageMPG: vehicleRecord?.averageMPG ?? 0
        )

        // MARK: Assemble

        return EarningsSnapshot(
            weeklyTotal: gross,
            taxRate: profile.taxRate,
            maintenanceRate: profile.maintenanceRate,

            perHour: onlineHours > 0 ? gross / onlineHours : 0,

            lifetimePerHour: lifetimePerHour,
            perMile: miles > 0 ? gross / miles : 0,
            onlineHours: onlineHours,
            activeHours: activeHours,
            mileage: Int(miles.rounded()),
            tripCount: trips,
            weeklyChange: percentChange(from: previousGross, to: gross),
            monthlyChange: percentChange(from: previousMonthGross, to: monthGross),

            maintenanceFund: max(maintenanceFund, 0),
            maintenanceGoal: profile.maintenanceGoal,
            taxSavingsYTD: ytdGross * profile.taxRate / 100,
            monthlyIncome: monthGross,
            netProfit: max(netProfit, 0),

            expensesTotal: expensesTotal,
            reserveDraw: reserveDraw,

            platforms: platforms,

            driver: Driver(name: profile.name, detail: profile.detail),
            vehicle: vehicle,

            series: series(
                shifts: shifts,
                expenses: expenses,
                profile: profile,
                range: range,
                rangeKind: rangeKind,
                now: now,
                calendar: calendar
            ),

            entitlement: Entitlement(
                tier: PlanTier(rawValue: profile.planTierRaw) ?? .free
            ),
            planRenewsOn: profile.planRenewsOn
        )
    }

    // MARK: Chart series

    /// Buckets the shifts into the arrays every chart plots.
    ///
    /// A shift is credited to the day it started, and its gross is spread
    /// evenly across the two-hour buckets it actually spans — a 15:00–21:30
    /// block puts money into the 14:00, 16:00, 18:00 and 20:00 slots rather
    /// than dumping it all at its start time, which is what makes the "peak
    /// hours" chart worth reading.
    static func series(
        shifts: [Shift],
        expenses: [Expense],
        profile: DriverProfile,
        range: Range<Date>,
        rangeKind: AnalyticsRange = .week,
        now: Date,
        calendar: Calendar
    ) -> ChartSeries {

        // The dashboard's series is always the current week, whatever the
        // Analytics picker says, so it's computed from its own window.
        let weekWindow = DateRange.week(containing: now, calendar: calendar)
        let weekStart = weekWindow.lowerBound

        var daily = Array(repeating: 0.0, count: 7)
        var dailyMiles = Array(repeating: 0.0, count: 7)

        for shift in shifts where weekWindow.contains(shift.start) {
            let dayIndex = calendar.dateComponents([.day], from: weekStart, to: shift.start).day ?? -1
            guard (0..<7).contains(dayIndex) else { continue }
            daily[dayIndex] += shift.gross
            dailyMiles[dayIndex] += shift.miles
        }

        // The Analytics series follows the selected range.
        var primary = Array(repeating: 0.0, count: rangeKind.bucketCount)
        var hourly = Array(repeating: 0.0, count: 12)

        for shift in shifts where range.contains(shift.start) {
            if let bucket = rangeKind.bucketIndex(
                for: shift.start, windowStart: range.lowerBound, calendar: calendar
            ) {
                primary[bucket] += shift.gross
            }
            // An imported week has a real total but no idea which hours of
            // the day produced it. Spreading it would invent a peak. Older
            // builds saved day-split weeks as ordinary 9am shifts, so keep
            // recognising their note as aggregate data too.
            let isDerivedFromWeeklyChart =
                shift.note?.hasPrefix("From a weekly screenshot") == true
            if !shift.isAggregate && !isDerivedFromWeeklyChart {
                spread(shift: shift, into: &hourly, calendar: calendar)
            }
        }

        // Take-home per day, after both set-asides. Only out-of-pocket
        // expenses are deducted — maintenance comes out of the reserve, and
        // charging it here too would double-count it.
        let keepRate = 1 - (profile.taxRate + profile.maintenanceRate) / 100
        var dailyNet = daily.map { $0 * keepRate }
        for expense in expenses
        where weekWindow.contains(expense.date) && !expense.category.drawsFromMaintenanceFund {
            let i = calendar.dateComponents([.day], from: weekStart, to: expense.date).day ?? -1
            if (0..<7).contains(i) { dailyNet[i] = Swift.max(dailyNet[i] - expense.amount, 0) }
        }

        // Running total for the dashboard's rising line.
        var running = 0.0
        let cumulative = daily.map { running += $0; return running }

        // Last four calendar months, oldest first.
        var monthly: [Double] = []
        for offset in stride(from: 3, through: 0, by: -1) {
            let month = DateRange.month(
                containing: calendar.date(byAdding: .month, value: -offset, to: now) ?? now,
                calendar: calendar
            )
            monthly.append(
                shifts.filter { month.contains($0.start) }.reduce(0) { $0 + $1.gross }
            )
        }

        return ChartSeries(
            daily: daily,
            cumulative: cumulative,
            hourly: hourly,
            monthly: monthly,
            dailyMiles: dailyMiles,
            dailyNet: dailyNet,
            primary: primary,
            primaryLabels: rangeKind.labels
        )
    }

    /// Distributes a shift's gross across the two-hour buckets it overlaps,
    /// weighted by how much of each bucket the shift occupied.
    private static func spread(shift: Shift, into hourly: inout [Double], calendar: Calendar) {
        let bucketCount = hourly.count                 // 12
        guard bucketCount > 0 else { return }          // no buckets, nothing to spread
        let bucketHours = 24.0 / Double(bucketCount)   // 2
        let dayStart = calendar.startOfDay(for: shift.start)

        // Buckets start at 06:00 — drivers' days, not calendar days.
        let originOffset = 6.0

        let startHour = shift.start.timeIntervalSince(dayStart) / 3600
        let endHour = startHour + shift.hours
        guard endHour > startHour else { return }

        let perHour = shift.gross / (endHour - startHour)

        for bucket in 0..<bucketCount {
            let lower = originOffset + Double(bucket) * bucketHours
            let upper = lower + bucketHours

            // Compare on a 24h wheel so a late shift wraps into the small hours.
            for shiftOffset in [0.0, 24.0, -24.0] {
                let overlap = Swift.min(endHour + shiftOffset, upper)
                    - Swift.max(startHour + shiftOffset, lower)
                if overlap > 0 { hourly[bucket] += overlap * perHour }
            }
        }
    }

    // MARK: Helpers

    /// Baseline odometer plus everything driven since it was recorded.
    private static func liveOdometer(_ vehicle: VehicleRecord?, shifts: [Shift]) -> Int {
        guard let vehicle else { return 0 }
        let since = shifts
            .filter { $0.start >= vehicle.odometerAsOf }
            .reduce(0) { $0 + $1.miles }
        return vehicle.odometerBaseline + Int(since.rounded())
    }

    /// "+12.4%" / "−6%" / "—" when there's no prior period to compare against.
    private static func percentChange(from old: Double, to new: Double) -> String {
        guard old > 0 else { return new > 0 ? "New" : "—" }
        let pct = (new - old) / old * 100
        let rounded = (pct * 10).rounded() / 10
        let sign = rounded >= 0 ? "+" : "−"
        // Whole numbers read better without a trailing .0
        let magnitude = abs(rounded)
        let text = magnitude == magnitude.rounded()
            ? String(format: "%.0f", magnitude)
            : String(format: "%.1f", magnitude)
        return "\(sign)\(text)%"
    }

}
