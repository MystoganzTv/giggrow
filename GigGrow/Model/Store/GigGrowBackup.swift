//
//  GigGrowBackup.swift
//  GigGrow
//
//  A complete, versioned backup of the user's local store.
//
//  CSV exports are reports. This is the recovery format: it includes profile,
//  platforms, shifts and their earnings, drives, expenses, vehicles, and
//  service history, while preserving the relationships between them.
//

import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shareable document

struct GigGrowBackupDocument: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { document in
            document.data
        }
        .suggestedFileName { $0.filename }
    }
}

// MARK: - Backup format

struct GigGrowBackup: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String
    let profiles: [ProfileRecord]
    let accounts: [AccountRecord]
    let shifts: [ShiftRecord]
    let drives: [DriveRecordValue]
    let expenses: [ExpenseRecord]
    let vehicles: [VehicleRecordValue]
    let services: [ServiceRecordValue]

    struct ProfileRecord: Codable {
        let name: String
        let detail: String
        let taxRate: Double
        let maintenanceRate: Double
        let mileageRate: Double
        let payoutLast4: String
        let maintenanceGoal: Double
        let maintenanceOpeningBalance: Double
        let autoMileageTracking: Bool
        let shiftDetectionAutomatic: Bool
        let idleThresholdMinutes: Int
        let stateIncomeTaxRate: Double
        let stateCode: String
        let planTierRaw: String
        let planRenewsOn: Date?
    }

    struct AccountRecord: Codable {
        let name: String
        let short: String
        let initial: String
        let gradientStart: UInt32
        let gradientEnd: UInt32
        let unitNoun: String
        let isActive: Bool
        let sortIndex: Int
        let providerAccountId: String?
        let connectionStatusRaw: String
        let lastSyncedAt: Date?
    }

    struct EarningRecord: Codable {
        let accountName: String?
        let gross: Double
        let tips: Double
        let promotions: Double
        let trips: Int
        let reportedMiles: Double
    }

    struct ShiftRecord: Codable {
        let id: UUID
        let start: Date
        let end: Date
        let miles: Double
        let recordedHours: Double?
        let isAggregate: Bool
        let idleMinutes: Double
        let note: String?
        let earnings: [EarningRecord]
    }

    struct DriveRecordValue: Codable {
        let start: Date
        let end: Date
        let distanceMeters: Double
        let purposeRaw: String
        let startPlace: String?
        let endPlace: String?
        let shiftID: UUID?
    }

    struct ExpenseRecord: Codable {
        let date: Date
        let amount: Double
        let categoryRaw: String
        let note: String?
        let isDeductible: Bool
        /// The receipt photo, base64 in the JSON.
        ///
        /// It makes the file considerably bigger, and it is included anyway:
        /// a backup that restores the amounts but loses the evidence behind
        /// them restores the part you could have retyped and drops the part
        /// you can't. Optional so files written before receipts existed still
        /// decode.
        var receiptImage: Data?
        var merchant: String?
    }

    struct VehicleRecordValue: Codable {
        let id: UUID
        let name: String
        let detail: String
        let make: String
        let model: String
        let year: Int
        let plate: String
        let fuelTypeRaw: String
        let odometerBaseline: Int
        let odometerAsOf: Date
        let fuelCostPerMile: Double
        let averageMPG: Int
    }

    struct ServiceRecordValue: Codable {
        let vehicleID: UUID?
        let name: String
        let dueAtMileage: Int
        let dueOn: Date?
        let dueNote: String?
        let intervalMiles: Int
        let intervalMonths: Int
        let lastDoneAtMileage: Int?
        let lastDoneOn: Date?
    }

    // MARK: Capture

    @MainActor
    static func capture(from context: ModelContext) throws -> GigGrowBackup {
        let profiles = try context.fetch(FetchDescriptor<DriverProfile>())
        let accounts = try context.fetch(
            FetchDescriptor<PlatformAccount>(
                sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
            )
        )
        let shifts = try context.fetch(
            FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.start)])
        )
        let drives = try context.fetch(
            FetchDescriptor<DriveRecord>(sortBy: [SortDescriptor(\.start)])
        )
        let expenses = try context.fetch(
            FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)])
        )
        let vehicles = try context.fetch(FetchDescriptor<VehicleRecord>())
        let services = try context.fetch(FetchDescriptor<ServiceRecord>())

        let shiftIDs = Dictionary(
            uniqueKeysWithValues: shifts.map { (ObjectIdentifier($0), UUID()) }
        )
        let vehicleIDs = Dictionary(
            uniqueKeysWithValues: vehicles.map { (ObjectIdentifier($0), UUID()) }
        )

        return GigGrowBackup(
            formatVersion: currentFormatVersion,
            exportedAt: .now,
            appVersion: bundleVersion,
            profiles: profiles.map {
                ProfileRecord(
                    name: $0.name,
                    detail: $0.detail,
                    taxRate: $0.taxRate,
                    maintenanceRate: $0.maintenanceRate,
                    mileageRate: $0.mileageRate,
                    payoutLast4: $0.payoutLast4,
                    maintenanceGoal: $0.maintenanceGoal,
                    maintenanceOpeningBalance: $0.maintenanceOpeningBalance,
                    autoMileageTracking: $0.autoMileageTracking,
                    shiftDetectionAutomatic: $0.shiftDetectionAutomatic,
                    idleThresholdMinutes: $0.idleThresholdMinutes,
                    stateIncomeTaxRate: $0.stateIncomeTaxRate,
                    stateCode: $0.stateCode,
                    planTierRaw: $0.planTierRaw,
                    planRenewsOn: $0.planRenewsOn
                )
            },
            accounts: accounts.map {
                AccountRecord(
                    name: $0.name,
                    short: $0.short,
                    initial: $0.initial,
                    gradientStart: $0.gradientStart,
                    gradientEnd: $0.gradientEnd,
                    unitNoun: $0.unitNoun,
                    isActive: $0.isActive,
                    sortIndex: $0.sortIndex,
                    providerAccountId: $0.providerAccountId,
                    connectionStatusRaw: $0.connectionStatusRaw,
                    lastSyncedAt: $0.lastSyncedAt
                )
            },
            shifts: shifts.map { shift in
                ShiftRecord(
                    id: shiftIDs[ObjectIdentifier(shift)]!,
                    start: shift.start,
                    end: shift.end,
                    miles: shift.miles,
                    recordedHours: shift.recordedHours,
                    isAggregate: shift.isAggregate,
                    idleMinutes: shift.idleMinutes,
                    note: shift.note,
                    earnings: shift.earningItems.map {
                        EarningRecord(
                            accountName: $0.account?.name,
                            gross: $0.gross,
                            tips: $0.tips,
                            promotions: $0.promotions,
                            trips: $0.trips,
                            reportedMiles: $0.reportedMiles
                        )
                    }
                )
            },
            drives: drives.map {
                DriveRecordValue(
                    start: $0.start,
                    end: $0.end,
                    distanceMeters: $0.distanceMeters,
                    purposeRaw: $0.purposeRaw,
                    startPlace: $0.startPlace,
                    endPlace: $0.endPlace,
                    shiftID: $0.shift.flatMap { shiftIDs[ObjectIdentifier($0)] }
                )
            },
            expenses: expenses.map {
                ExpenseRecord(
                    date: $0.date,
                    amount: $0.amount,
                    categoryRaw: $0.categoryRaw,
                    note: $0.note,
                    isDeductible: $0.isDeductible,
                    receiptImage: $0.receiptImage,
                    merchant: $0.merchant
                )
            },
            vehicles: vehicles.map {
                VehicleRecordValue(
                    id: vehicleIDs[ObjectIdentifier($0)]!,
                    name: $0.name,
                    detail: $0.detail,
                    make: $0.make,
                    model: $0.model,
                    year: $0.year,
                    plate: $0.plate,
                    fuelTypeRaw: $0.fuelTypeRaw,
                    odometerBaseline: $0.odometerBaseline,
                    odometerAsOf: $0.odometerAsOf,
                    fuelCostPerMile: $0.fuelCostPerMile,
                    averageMPG: $0.averageMPG
                )
            },
            services: services.map {
                ServiceRecordValue(
                    vehicleID: $0.vehicle.flatMap { vehicleIDs[ObjectIdentifier($0)] },
                    name: $0.name,
                    dueAtMileage: $0.dueAtMileage,
                    dueOn: $0.dueOn,
                    dueNote: $0.dueNote,
                    intervalMiles: $0.intervalMiles,
                    intervalMonths: $0.intervalMonths,
                    lastDoneAtMileage: $0.lastDoneAtMileage,
                    lastDoneOn: $0.lastDoneOn
                )
            }
        )
    }

    // MARK: Encode/decode

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> GigGrowBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(GigGrowBackup.self, from: data)
        try backup.validate()
        return backup
    }

    var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "GigGrow-backup-\(formatter.string(from: exportedAt)).json"
    }

    var summary: String {
        var parts = ["\(shifts.count) shift\(shifts.count == 1 ? "" : "s")"]
        if !drives.isEmpty {
            parts.append("\(drives.count) drive\(drives.count == 1 ? "" : "s")")
        }
        if !expenses.isEmpty {
            parts.append("\(expenses.count) expense\(expenses.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Restore

    @MainActor
    func restore(into context: ModelContext) throws {
        try validate()
        Seed.prepareForRestore(context)

        do {
            var accountsByName: [String: PlatformAccount] = [:]
            for value in accounts {
                let account = PlatformAccount(
                    name: value.name,
                    short: value.short,
                    initial: value.initial,
                    gradientStart: value.gradientStart,
                    gradientEnd: value.gradientEnd,
                    unitNoun: value.unitNoun,
                    isActive: value.isActive,
                    sortIndex: value.sortIndex
                )
                account.providerAccountId = value.providerAccountId
                account.connectionStatusRaw = value.connectionStatusRaw
                account.lastSyncedAt = value.lastSyncedAt
                context.insert(account)
                accountsByName[value.name] = account
            }

            for value in profiles {
                let profile = DriverProfile(
                    name: value.name,
                    detail: value.detail,
                    taxRate: value.taxRate,
                    maintenanceRate: value.maintenanceRate,
                    mileageRate: value.mileageRate,
                    payoutLast4: value.payoutLast4,
                    maintenanceGoal: value.maintenanceGoal,
                    maintenanceOpeningBalance: value.maintenanceOpeningBalance,
                    autoMileageTracking: value.autoMileageTracking,
                    shiftDetectionAutomatic: value.shiftDetectionAutomatic,
                    idleThresholdMinutes: value.idleThresholdMinutes
                )
                profile.stateIncomeTaxRate = value.stateIncomeTaxRate
                profile.stateCode = value.stateCode
                profile.planTierRaw = value.planTierRaw
                profile.planRenewsOn = value.planRenewsOn
                context.insert(profile)
            }

            var vehiclesByID: [UUID: VehicleRecord] = [:]
            for value in vehicles {
                let vehicle = VehicleRecord(
                    name: value.name,
                    detail: value.detail,
                    odometerBaseline: value.odometerBaseline,
                    odometerAsOf: value.odometerAsOf,
                    fuelCostPerMile: value.fuelCostPerMile,
                    averageMPG: value.averageMPG,
                    make: value.make,
                    model: value.model,
                    year: value.year,
                    plate: value.plate,
                    fuelType: FuelType(rawValue: value.fuelTypeRaw) ?? .gasoline
                )
                context.insert(vehicle)
                vehiclesByID[value.id] = vehicle
            }

            for value in services {
                let record = ServiceRecord(
                    name: value.name,
                    dueAtMileage: value.dueAtMileage,
                    dueOn: value.dueOn,
                    dueNote: value.dueNote,
                    intervalMiles: value.intervalMiles,
                    intervalMonths: value.intervalMonths
                )
                record.lastDoneAtMileage = value.lastDoneAtMileage
                record.lastDoneOn = value.lastDoneOn
                record.vehicle = value.vehicleID.flatMap { vehiclesByID[$0] }
                context.insert(record)
            }

            var shiftsByID: [UUID: Shift] = [:]
            for value in shifts {
                let shift = Shift(
                    start: value.start,
                    end: value.end,
                    miles: value.miles,
                    idleMinutes: value.idleMinutes,
                    note: value.note
                )
                shift.recordedHours = value.recordedHours
                shift.isAggregate = value.isAggregate
                context.insert(shift)

                for earningValue in value.earnings {
                    let earning = PlatformEarning(
                        account: earningValue.accountName.flatMap { accountsByName[$0] },
                        gross: earningValue.gross,
                        tips: earningValue.tips,
                        promotions: earningValue.promotions,
                        trips: earningValue.trips,
                        reportedMiles: earningValue.reportedMiles
                    )
                    earning.shift = shift
                    context.insert(earning)
                    shift.earningItems.append(earning)
                }
                shiftsByID[value.id] = shift
            }

            for value in drives {
                let drive = DriveRecord(
                    start: value.start,
                    end: value.end,
                    distanceMeters: value.distanceMeters,
                    purpose: DrivePurpose(rawValue: value.purposeRaw) ?? .unclassified,
                    startPlace: value.startPlace,
                    endPlace: value.endPlace
                )
                drive.shift = value.shiftID.flatMap { shiftsByID[$0] }
                context.insert(drive)
            }

            for value in expenses {
                let expense = Expense(
                    date: value.date,
                    amount: value.amount,
                    category: ExpenseCategory(rawValue: value.categoryRaw) ?? .other,
                    note: value.note,
                    isDeductible: value.isDeductible,
                    receiptImage: value.receiptImage,
                    merchant: value.merchant
                )
                context.insert(expense)
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Validation

    private func validate() throws {
        guard formatVersion > 0, formatVersion <= Self.currentFormatVersion else {
            throw BackupError.unsupportedVersion(formatVersion)
        }
        guard Set(accounts.map(\.name)).count == accounts.count else {
            throw BackupError.duplicatePlatforms
        }

        let shiftIDs = Set(shifts.map(\.id))
        guard drives.allSatisfy({ $0.shiftID == nil || shiftIDs.contains($0.shiftID!) }) else {
            throw BackupError.brokenRelationship
        }

        let vehicleIDs = Set(vehicles.map(\.id))
        guard services.allSatisfy({
            $0.vehicleID == nil || vehicleIDs.contains($0.vehicleID!)
        }) else {
            throw BackupError.brokenRelationship
        }
    }

    private static var bundleVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        return "\(version) (\(build))"
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case duplicatePlatforms
    case brokenRelationship

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This backup uses format \(version), which this version of GigGrow can't restore."
        case .duplicatePlatforms:
            return "The backup contains duplicate platform records."
        case .brokenRelationship:
            return "The backup is incomplete or damaged."
        }
    }
}
