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

    /// Hours worked, when they can't be derived from the span.
    ///
    /// A weekly summary is real data — $829.41 over 20h21m and 47 trips —
    /// but it isn't a block of time. Stored as a week-long entry, `hours`
    /// would read 168 from start to end. When this is set it wins, so the
    /// figure stays the one the driver confirmed.
    var recordedHours: Double?

    /// True when this covers a period rather than a single sitting. Such
    /// entries are excluded from the hourly distribution: the total is
    /// known, but not which hours of the day it came from.
    var isAggregate: Bool = false
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

    /// Hours worked — counted once, however many apps were on.
    ///
    /// A confirmed figure beats the span, so an imported week reports the
    /// 20h21m the driver actually worked rather than the 168 hours it covers.
    var hours: Double {
        if let recordedHours, recordedHours > 0 { return recordedHours }
        return max(end.timeIntervalSince(start), 0) / 3600
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

    // Sync state. Populated once an earnings provider is connected; until
    // then every account is manual and these stay at their defaults.
    /// Provider-side account id, for tracing a row back to its source.
    var providerAccountId: String?
    var connectionStatusRaw: String = ConnectionStatus.disconnected.rawValue
    var lastSyncedAt: Date?

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

    // MARK: Sync

    var connectionStatus: ConnectionStatus {
        get { ConnectionStatus(rawValue: connectionStatusRaw) ?? .disconnected }
        set { connectionStatusRaw = newValue.rawValue }
    }

    // MARK: Sync helpers

    /// True once an aggregator is behind this account.
    var isLinked: Bool {
        providerAccountId != nil && connectionStatus != .disconnected
    }
}

// MARK: - Drive

/// What a recorded drive was for. Only business miles are deductible, and
/// the IRS expects the classification to be the driver's, not an algorithm's.
enum DrivePurpose: String, Codable, CaseIterable, Identifiable {
    case unclassified
    case business
    case personal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unclassified: return "Not set"
        case .business:     return "Business"
        case .personal:     return "Personal"
        }
    }

    var isDeductible: Bool { self == .business }
}

/// One drive captured by the tracker.
///
/// Kept separate from a shift's `miles`. GPS distance and an odometer
/// reading disagree by a few percent, and a deduction is a tax figure — so
/// a recorded estimate never silently overwrites a number the driver read
/// off the dashboard. The shift can adopt it, explicitly.
@Model
final class DriveRecord {
    var start: Date
    var end: Date
    /// Metres, as Core Location reports them. Converted for display.
    var distanceMeters: Double
    var purposeRaw: String

    /// Human-readable end points, when reverse geocoding succeeded. Never
    /// coordinates: a stored trail of where a driver has been is a liability
    /// this app has no use for.
    var startPlace: String?
    var endPlace: String?

    /// Set when the driver attaches the drive to a shift.
    var shift: Shift?

    init(
        start: Date,
        end: Date,
        distanceMeters: Double,
        purpose: DrivePurpose = .unclassified,
        startPlace: String? = nil,
        endPlace: String? = nil
    ) {
        self.start = start
        self.end = end
        self.distanceMeters = distanceMeters
        self.purposeRaw = purpose.rawValue
        self.startPlace = startPlace
        self.endPlace = endPlace
    }

    var purpose: DrivePurpose {
        get { DrivePurpose(rawValue: purposeRaw) ?? .unclassified }
        set { purposeRaw = newValue.rawValue }
    }

    var miles: Double { distanceMeters / 1_609.344 }
    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }

    /// The deduction this drive is worth, at the rate in force the day it
    /// happened. Unclassified drives are worth nothing until decided.
    func deduction(overrideRate: Double = 0) -> Double {
        guard purpose.isDeductible else { return 0 }
        let rate = overrideRate > 0 ? overrideRate : MileageRates.rate(on: start)
        return miles * rate
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
    /// Legacy free-text name, kept so existing installs migrate cleanly.
    /// New records fill the structured fields below and `displayName`
    /// composes from those.
    var name: String
    /// Legacy free-text subtitle. Superseded by `displayDetail`.
    var detail: String

    // Structured identity. One free-text line couldn't be queried, validated
    // or used to work out what the car actually costs to run.
    var make: String = ""
    var model: String = ""
    var year: Int = 0
    var plate: String = ""
    var fuelTypeRaw: String = FuelType.gasoline.rawValue
    /// Odometer at the moment `odometerAsOf` was recorded; live mileage is this
    /// plus everything driven since.
    var odometerBaseline: Int
    var odometerAsOf: Date
    var fuelCostPerMile: Double
    var averageMPG: Int

    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.vehicle)
    var service: [ServiceRecord]

    init(
        name: String = "",
        detail: String = "",
        odometerBaseline: Int,
        odometerAsOf: Date = .now,
        fuelCostPerMile: Double = 0,
        averageMPG: Int = 0,
        make: String = "",
        model: String = "",
        year: Int = 0,
        plate: String = "",
        fuelType: FuelType = .gasoline
    ) {
        self.name = name
        self.detail = detail
        self.odometerBaseline = odometerBaseline
        self.odometerAsOf = odometerAsOf
        self.fuelCostPerMile = fuelCostPerMile
        self.averageMPG = averageMPG
        self.make = make
        self.model = model
        self.year = year
        self.plate = plate
        self.fuelTypeRaw = fuelType.rawValue
        self.service = []
    }

    // MARK: Derived

    var fuelType: FuelType {
        get { FuelType(rawValue: fuelTypeRaw) ?? .gasoline }
        set { fuelTypeRaw = newValue.rawValue }
    }

    /// "2024 Tesla Model Y", falling back to the legacy free-text name for
    /// records created before the fields were split out.
    var displayName: String {
        let parts = [year > 0 ? "\(year)" : "", make, model]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? name : parts.joined(separator: " ")
    }

    /// "Electric · SVERIGE"
    var displayDetail: String {
        let parts = [fuelType.shortLabel, plate].filter { !$0.isEmpty }
        return parts.isEmpty ? detail : parts.joined(separator: " · ")
    }

    /// Efficiency with the unit that actually applies — an EV has no mpg.
    var efficiencyLabel: String {
        guard averageMPG > 0 || efficiency > 0 else { return "—" }
        return fuelType.burnsFuel
            ? "\(averageMPG) \(fuelType.efficiencyUnit)"
            : String(format: "%.1f %@", efficiency, fuelType.efficiencyUnit)
    }

    /// Miles per kWh for an EV, stored in the same column as mpg but read
    /// with one decimal, since the useful range is roughly 2–5.
    var efficiency: Double {
        get { Double(averageMPG) / (fuelType.burnsFuel ? 1 : 10) }
        set { averageMPG = Int((newValue * (fuelType.burnsFuel ? 1 : 10)).rounded()) }
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

    /// How far apart these fall due. Without it there is nothing to reset to,
    /// which is why the schedule used to be frozen: you could watch a row go
    /// overdue and never clear it.
    var intervalMiles: Int = 0
    /// Interval for date-driven items, in months.
    var intervalMonths: Int = 0

    var lastDoneAtMileage: Int?
    var lastDoneOn: Date?

    init(
        name: String,
        dueAtMileage: Int = 0,
        dueOn: Date? = nil,
        dueNote: String? = nil,
        intervalMiles: Int = 0,
        intervalMonths: Int = 0
    ) {
        self.name = name
        self.dueAtMileage = dueAtMileage
        self.dueOn = dueOn
        self.dueNote = dueNote
        self.intervalMiles = intervalMiles
        self.intervalMonths = intervalMonths
    }

    /// Records the service and rolls the next one forward.
    ///
    /// Measured from the odometer *now*, not from when it was previously due
    /// — a driver who changes the oil 800 miles late should get a full
    /// interval from today, not an interval that's already partly spent.
    func markDone(currentMileage: Int, on date: Date = .now) {
        lastDoneAtMileage = currentMileage
        lastDoneOn = date

        if intervalMiles > 0 {
            dueAtMileage = currentMileage + intervalMiles
            dueNote = nil
        }
        if intervalMonths > 0 {
            dueOn = Calendar.gigPilot.date(byAdding: .month, value: intervalMonths, to: date)
        } else if intervalMiles == 0, let existing = dueOn {
            // Neither interval set: keep it a year out rather than leaving a
            // row permanently overdue.
            dueOn = Calendar.gigPilot.date(byAdding: .year, value: 1, to: max(existing, date))
        }
    }

    /// Whether completing it means anything — a one-off has no next due.
    var isRecurring: Bool { intervalMiles > 0 || intervalMonths > 0 }

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
    /// Manual override of the IRS standard mileage rate, in dollars per mile.
    ///
    /// Zero means "use the published schedule", which is the right default:
    /// the rate is set by date, and in 2026 it changed mid-year. Storing one
    /// number would misstate whichever half of the year it didn't match.
    var mileageRate: Double
    var payoutLast4: String
    var maintenanceGoal: Double
    /// Opening balance of the maintenance fund, for drivers who already had one.
    var maintenanceOpeningBalance: Double

    // Tracking preferences.
    //
    // `autoMileageTracking` is honoured by `MileageTracker` and defaults to
    // off: reading someone's location is not a thing to switch on for them.
    // `shiftDetectionAutomatic` is still stored but unimplemented — Settings
    // must not present it as active; see `TrackingCapability`.
    var autoMileageTracking: Bool
    var shiftDetectionAutomatic: Bool
    /// Minutes of waiting before time counts as idle. Used as the default in
    /// the shift entry sheet.
    var idleThresholdMinutes: Int

    /// The rate to apply to miles driven on `date` — the driver's override
    /// if they set one, otherwise the IRS figure in force that day.
    func mileageRate(on date: Date) -> Double {
        mileageRate > 0 ? mileageRate : MileageRates.rate(on: date)
    }

    /// USPS code for where the driver works. Drives the suggested tax
    /// hold-back, since state income tax runs from nothing to over 13%.
    var stateCode: String = ""

    /// Persisted so the UI has an answer before StoreKit finishes loading.
    /// StoreKit remains the source of truth; this is a cache, and
    /// `Entitlement` is the only type that should read it.
    var planTierRaw: String = PlanTier.free.rawValue
    /// End of the current paid period, when there is one.
    var planRenewsOn: Date?

    init(
        name: String = "",
        detail: String = "",
        taxRate: Double = 25,
        maintenanceRate: Double = 8,
        mileageRate: Double = 0.70,
        payoutLast4: String = "",
        maintenanceGoal: Double = 3_000,
        maintenanceOpeningBalance: Double = 0,
        autoMileageTracking: Bool = false,
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
        DriveRecord.self,
        Expense.self,
        VehicleRecord.self,
        ServiceRecord.self,
        DriverProfile.self
    ]
}
