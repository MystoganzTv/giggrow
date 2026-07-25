//
//  Models.swift
//  GigPilot
//
//  Value types backing the five screens. These mirror the shape of the
//  `renderVals()` payload in the design doc's DCLogic component, so the
//  mock data drops straight in and a real API can replace it later.
//

import SwiftUI

// MARK: - Platform

/// One gig platform the driver is connected to.
struct Platform: Identifiable, Hashable {
    let id = UUID()

    /// Full display name — "Amazon Flex".
    let name: String
    /// Abbreviated name used in the analytics comparison rows — "Flex".
    let short: String
    /// Single letter shown in the rounded badge on the Apps screen.
    let initial: String
    /// This platform's share of the weekly total, 0…1.
    let share: Double
    /// Effective hourly rate, pre-formatted.
    let hourly: String
    /// Row subtitle — "58 trips · 128 mi".
    let meta: String
    /// Week-over-week change, pre-formatted.
    let delta: String
    /// Brand gradient for the badge and the share bar.
    let gradient: [Color]

    var brandGradient: LinearGradient {
        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Horizontal gradient used for the thin share bars.
    var barGradient: LinearGradient {
        LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Vehicle service

/// Health of a single maintenance item.
enum ServiceStatus: Hashable {
    case scheduled
    case dueNow
    case healthy

    var label: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .dueNow:    return "Due now"
        case .healthy:   return "Healthy"
        }
    }

    var tint: Color {
        switch self {
        case .scheduled: return Color.white.opacity(0.60)
        case .dueNow:    return GP.Palette.amber
        case .healthy:   return GP.Palette.mint
        }
    }

    var background: Color {
        switch self {
        case .scheduled: return Color.white.opacity(0.08)
        case .dueNow:    return Color(hex: 0xFB923C, opacity: 0.18)
        case .healthy:   return Color(hex: 0x34D399, opacity: 0.16)
        }
    }
}

/// A row in the vehicle service schedule.
struct ServiceItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    /// When it's next due — "In 1,790 mi · Sep 2026".
    let due: String
    let status: ServiceStatus
}

// MARK: - Settings

struct SettingRow: Identifiable, Hashable {
    let id = UUID()
    let label: String
    /// Trailing value; empty string renders the chevron alone.
    let value: String
}

struct SettingGroup: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let rows: [SettingRow]
}

// MARK: - Vehicle

struct Vehicle: Hashable {
    let name: String
    /// "Hybrid · 7KJD812"
    let detail: String
    let odometer: Int
    let milesThisWeek: Int
    let fuelCostPerMile: Double
    let averageMPG: Int
}

// MARK: - Driver

struct Driver: Hashable {
    let name: String
    /// "Phoenix, AZ · Since 2023"
    let detail: String
    var initial: String { String(name.prefix(1)) }
}

// MARK: - Earnings snapshot

/// Everything the five screens read from. One object, injected at the root,
/// so swapping mock data for a live source is a single change.
struct EarningsSnapshot {

    // Inputs
    let weeklyTotal: Double
    /// Percentage of gross set aside for taxes.
    let taxRate: Double
    /// Percentage of gross set aside for maintenance.
    let maintenanceRate: Double

    // Weekly performance
    let perHour: Double
    let perMile: Double
    let onlineHours: Double
    let activeHours: Double
    let mileage: Int
    let tripCount: Int
    let weeklyChange: String
    let monthlyChange: String

    // Rollups
    let maintenanceFund: Double
    let maintenanceGoal: Double
    let taxSavingsYTD: Double
    let monthlyIncome: Double
    let netProfit: Double

    // Collections
    let platforms: [Platform]
    let service: [ServiceItem]
    let settingGroups: [SettingGroup]

    let driver: Driver
    let vehicle: Vehicle

    // MARK: Derived

    var idleHours: Double { max(onlineHours - activeHours, 0) }
    var activeShare: Double { onlineHours > 0 ? activeHours / onlineHours : 0 }

    var taxesToSave: Double { weeklyTotal * taxRate / 100 }
    var maintenanceThisWeek: Double { weeklyTotal * maintenanceRate / 100 }

    var maintenanceProgress: Double {
        maintenanceGoal > 0 ? min(maintenanceFund / maintenanceGoal, 1) : 0
    }

    /// The largest single-platform share, used to normalise the bar widths
    /// so the top platform always fills its track (matches the design's
    /// `Math.round(a.pct / max * 100)`).
    var maxShare: Double { platforms.map(\.share).max() ?? 1 }

    func normalisedShare(for platform: Platform) -> Double {
        maxShare > 0 ? platform.share / maxShare : 0
    }

    func amount(for platform: Platform) -> Double {
        weeklyTotal * platform.share
    }
}

// MARK: - Formatting

enum Money {
    /// `$1,482.60` — matches the design's `money(total, 2)`.
    static func cents(_ value: Double) -> String {
        format(value, fractionDigits: 2)
    }

    /// `$371` — matches the design's `money(total, 0)`.
    static func whole(_ value: Double) -> String {
        format(value, fractionDigits: 0)
    }

    private static func format(_ value: Double, fractionDigits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        let number = f.string(from: NSNumber(value: value)) ?? "0"
        return "$" + number
    }
}

enum Num {
    /// `84,210`
    static func grouped(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
