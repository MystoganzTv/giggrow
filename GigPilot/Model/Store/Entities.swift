//
//  Entities.swift
//  GigPilot
//
//  The persisted model.
//
//  The central decision here: a Shift is a block of *time*, not a block of
//  time on one app. Multi-app drivers run Uber and DoorDash simultaneously,
//  so earnings hang off the shift per-platform while the hours are stored
//  once. That keeps $/hour honest — the alternative double-counts every
//  overlapping hour and halves the headline number.
//

import Foundation
import SwiftData

// MARK: - Shift

@Model
final class Shift {
    /// Start of the driving block.
    var start: Date
    /// End of the block. Always ≥ `start`.
    var end: Date
    /// Miles driven across the whole shift, all platforms together.
    var miles: Double
    /// Minutes spent waiting for a ping. Subtracted from the duration to get
    /// active time; the design's dashboard shows this split.
    var idleMinutes: Double
    var note: String?

    /// What each app paid during this block.
    @Relationship(deleteRule: .cascade, inverse: \PlatformEarning.shift)
    var earnings: [PlatformEarning]

    init(
        start: Date,
        end: Date,
        miles: Double = 0,
        idleMinutes: Double = 0,
        note: String? = nil,
        earnings: [PlatformEarning] = []
    ) {
        self.start = start
        self.end = end
        self.miles = miles
        self.idleMinutes = idleMinutes
        self.note = note
        self.earnings = earnings
    }

    // MARK: Derived

    /// Length of the block in hours — counted once, however many apps were on.
    var hours: Double {
        max(end.timeIntervalSince(start), 0) / 3600
    }

    var idleHours: Double { min(idleMinutes / 60, hours) }
    var activeHours: Double { max(hours - idleHours, 0) }

    /// Everything earned during the block, across every platform.
    var gross: Double {
        earnings.reduce(0) { $0 + $1.gross }
    }

    var tripCount: Int {
        earnings.reduce(0) { $0 + $1.trips }
    }

    /// How many apps were running. Two or more means this shift is the reason
    /// per-platform hours have to be attributed rather than counted.
    var platformCount: Int { earnings.count }
}

// MARK: - Platform earning

/// One app's take from one shift.
@Model
final class PlatformEarning {
    /// Gross before expenses, including tips.
    var gross: Double
    /// Portion of `gross` that was tips, when known.
    var tips: Double
    /// Trips, deliveries, batches or blocks — whatever this app counts.
    var trips: Int
    /// Miles attributable to this platform, when the app reports them.
    /// Left at zero when only the shift total is known.
    var reportedMiles: Double

    var account: PlatformAccount?
    var shift: Shift?

    init(
        account: PlatformAccount? = nil,
        gross: Double = 0,
        tips: Double = 0,
        trips: Int = 0,
        reportedMiles: Double = 0
    ) {
        self.account = account
        self.gross = gross
        self.tips = tips
        self.trips = trips
        self.reportedMiles = reportedMiles
    }
}

// MARK: - Platform account

/// A gig platform the driver has connected or added by hand.
@Model
final class PlatformAccount {
    @Attribute(.unique) var name: String
    /// Abbreviated label for tight rows — "Flex" for "Amazon Flex".
    var short: String
    /// Letter shown in the rounded badge.
    var initial: String
    /// Brand gradient endpoints, stored as hex so the palette survives a migration.
    var gradientStart: UInt32
    var gradientEnd: UInt32
    /// Noun this app uses for a unit of work: "trips", "orders", "batches", "blocks".
    var unitNoun: String
    var isActive: Bool
    /// Display order on the Apps screen.
    var sortIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \PlatformEarning.account)
    var earnings: [PlatformEarning]

    init(
        name: String,
        short: String,
        initial: String,
        gradientStart: UInt32,
        gradientEnd: UInt32,
        unitNoun: String = "trips",
        isActive: Bool = true,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.short = short
        self.initial = initial
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.unitNoun = unitNoun
        self.isActive = isActive
        self.sortIndex = sortIndex
        self.earnings = []
    }
}

// MARK: - Expense

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case fuel, maintenance, insurance, phone, supplies, fees, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fuel:        return "Fuel"
        case .maintenance: return "Maintenance"
        case .insurance:   return "Insurance"
        case .phone:       return "Phone"
        case .supplies:    return "Supplies"
        case .fees:        return "Fees"
        case .other:       return "Other"
        }
    }

    /// Maintenance spending draws down the maintenance fund; the rest doesn't.
    var drawsFromMaintenanceFund: Bool { self == .maintenance }
}

@Model
final class Expense {
    var date: Date
    var amount: Double
    var categoryRaw: String
    var note: String?
    /// Whether it counts against taxable income.
    var isDeductible: Bool

    init(
        date: Date,
        amount: Double,
        category: ExpenseCategory,
        note: String? = nil,
        isDeductible: Bool = true
    ) {
        self.date = date
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.note = note
        self.isDeductible = isDeductible
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

// MARK: - Vehicle

@Model
final class VehicleRecord {
    var name: String
    /// "Hybrid · 7KJD812"
    var detail: String
    /// Odometer at the moment `odometerAsOf` was recorded; live mileage is this
    /// plus everything driven since.
    var odometerBaseline: Int
    var odometerAsOf: Date
    var fuelCostPerMile: Double
    var averageMPG: Int

    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.vehicle)
    var service: [ServiceRecord]

    init(
        name: String,
        detail: String,
        odometerBaseline: Int,
        odometerAsOf: Date = .now,
        fuelCostPerMile: Double = 0,
        averageMPG: Int = 0
    ) {
        self.name = name
        self.detail = detail
        self.odometerBaseline = odometerBaseline
        self.odometerAsOf = odometerAsOf
        self.fuelCostPerMile = fuelCostPerMile
        self.averageMPG = averageMPG
        self.service = []
    }
}

// MARK: - Service

/// A maintenance item, due either at a mileage or on a date.
@Model
final class ServiceRecord {
    var name: String
    /// Odometer reading at which this falls due. Zero when it's date-driven.
    var dueAtMileage: Int
    /// Date it falls due. Nil when it's mileage-driven.
    var dueOn: Date?
    /// Free-text suffix shown after the computed distance, e.g. "Sep 2026".
    var dueNote: String?
    var vehicle: VehicleRecord?

    init(
        name: String,
        dueAtMileage: Int = 0,
        dueOn: Date? = nil,
        dueNote: String? = nil
    ) {
        self.name = name
        self.dueAtMileage = dueAtMileage
        self.dueOn = dueOn
        self.dueNote = dueNote
    }

    /// Status is computed from the live odometer rather than stored, so a row
    /// can't drift out of date while the app is closed.
    func status(currentMileage: Int, now: Date = .now) -> ServiceStatus {
        if dueAtMileage > 0 {
            let remaining = dueAtMileage - currentMileage
            if remaining <= 0 { return .dueNow }
            return remaining < 2_000 ? .scheduled : .healthy
        }
        if let dueOn {
            let days = Calendar.current.dateComponents([.day], from: now, to: dueOn).day ?? 0
            if days <= 0 { return .dueNow }
            return days < 60 ? .scheduled : .healthy
        }
        return .healthy
    }

    /// The "In 1,790 mi · Sep 2026" / "Overdue by 420 mi" subtitle.
    func dueDescription(currentMileage: Int) -> String {
        if dueAtMileage > 0 {
            let remaining = dueAtMileage - currentMileage
            let base = remaining >= 0
                ? "In \(Num.grouped(remaining)) mi"
                : "Overdue by \(Num.grouped(-remaining)) mi"
            if let dueNote { return "\(base) · \(dueNote)" }
            return base
        }
        if let dueNote { return dueNote }
        if let dueOn {
            let f = DateFormatter()
            f.dateFormat = "MMM yyyy"
            return "Renews \(f.string(from: dueOn))"
        }
        return ""
    }
}

// MARK: - Driver profile

/// One row. Holds the driver's identity and the percentages every screen
/// derives its set-asides from.
@Model
final class DriverProfile {
    var name: String
    /// "Phoenix, AZ · Since 2023"
    var detail: String
    /// Percent of gross reserved for taxes.
    var taxRate: Double
    /// Percent of gross reserved for maintenance.
    var maintenanceRate: Double
    /// IRS standard mileage rate, dollars per mile.
    var mileageRate: Double
    var payoutLast4: String
    var maintenanceGoal: Double
    /// Opening balance of the maintenance fund, for drivers who already had one.
    var maintenanceOpeningBalance: Double

    // Tracking preferences — the Settings rows that were inert.
    var autoMileageTracking: Bool
    var shiftDetectionAutomatic: Bool
    var idleThresholdMinutes: Int

    init(
        name: String = "",
        detail: String = "",
        taxRate: Double = 25,
        maintenanceRate: Double = 8,
        mileageRate: Double = 0.70,
        payoutLast4: String = "",
        maintenanceGoal: Double = 3_000,
        maintenanceOpeningBalance: Double = 0,
        autoMileageTracking: Bool = true,
        shiftDetectionAutomatic: Bool = true,
        idleThresholdMinutes: Int = 8
    ) {
        self.name = name
        self.detail = detail
        self.taxRate = taxRate
        self.maintenanceRate = maintenanceRate
        self.mileageRate = mileageRate
        self.payoutLast4 = payoutLast4
        self.maintenanceGoal = maintenanceGoal
        self.maintenanceOpeningBalance = maintenanceOpeningBalance
        self.autoMileageTracking = autoMileageTracking
        self.shiftDetectionAutomatic = shiftDetectionAutomatic
        self.idleThresholdMinutes = idleThresholdMinutes
    }
}

// MARK: - Schema

enum GigPilotSchema {
    static let all: [any PersistentModel.Type] = [
        Shift.self,
        PlatformEarning.self,
        PlatformAccount.self,
        Expense.self,
        VehicleRecord.self,
        ServiceRecord.self,
        DriverProfile.self
    ]
}
