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

// Service rows are queried from the store by VehicleView, not projected here.
// As snapshot values they carried no identity, so a row could be drawn but
// never opened, completed or deleted.

// MARK: - Settings

// Settings rows are built in SettingsView from the live DriverProfile rather
// than passed through the snapshot. They were plain display data here, with
// no way to carry an action — which is exactly why every chevron led nowhere.

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

// MARK: - Analytics range

/// The Week / Month / Year selector on the Analytics screen.
///
/// Each range owns three things that have to stay consistent with each other:
/// the window of time it covers, how that window is cut into bars, and what
/// prior period a delta compares against. Keeping them on one type is what
/// stops a month view from quietly comparing itself to last week.
enum AnalyticsRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }

    /// Noun used in card titles — "This week's income".
    var possessive: String {
        switch self {
        case .week:  return "This week"
        case .month: return "This month"
        case .year:  return "This year"
        }
    }

    /// Unit stepped back by one to find the comparison period.
    var comparisonUnit: Calendar.Component {
        switch self {
        case .week:  return .weekOfYear
        case .month: return .month
        case .year:  return .year
        }
    }

    /// How many bars the chart draws.
    ///
    /// A month is cut into weeks rather than days: 31 bars at phone width are
    /// unreadable, and a driver thinks about their month in weeks anyway.
    var bucketCount: Int {
        switch self {
        case .week:  return 7
        case .month: return 5
        case .year:  return 12
        }
    }

    /// Which calendar unit one bar spans.
    var bucketUnit: Calendar.Component {
        switch self {
        case .week:  return .day
        case .month: return .weekOfYear
        case .year:  return .month
        }
    }

    var labels: [String] {
        switch self {
        case .week:  return ["M", "T", "W", "T", "F", "S", "S"]
        case .month: return (1...5).map { "W\($0)" }
        case .year:  return ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        }
    }

    /// The window this range covers, containing `date`.
    func window(containing date: Date, calendar: Calendar = .gigPilot) -> Range<Date> {
        switch self {
        case .week:  return DateRange.week(containing: date, calendar: calendar)
        case .month: return DateRange.month(containing: date, calendar: calendar)
        case .year:  return DateRange.year(containing: date, calendar: calendar)
        }
    }

    /// Which bar a shift belongs in, or nil if it falls outside the window.
    func bucketIndex(for date: Date, windowStart: Date, calendar: Calendar = .gigPilot) -> Int? {
        let index: Int
        switch self {
        case .week:
            index = calendar.dateComponents([.day], from: windowStart, to: date).day ?? -1
        case .month:
            // Week of the month, 0-based, counted from the 1st.
            let day = calendar.component(.day, from: date)
            index = (day - 1) / 7
        case .year:
            index = calendar.component(.month, from: date) - 1
        }
        return (0..<bucketCount).contains(index) ? index : nil
    }
}

// MARK: - Chart series

/// The numbers behind every chart, as plain arrays in chronological order.
/// Shapes normalise them at draw time, so nothing here carries pixel
/// coordinates — that was the design doc's job, not the app's.
struct ChartSeries: Equatable {

    /// Gross per weekday, Monday first. Always 7 entries.
    var daily: [Double]
    /// Running total across the week — what the dashboard's rising line plots.
    var cumulative: [Double]
    /// Gross per two-hour bucket across the day, starting 06:00. 12 entries.
    var hourly: [Double]
    /// Gross for each of the last months, oldest first.
    var monthly: [Double]
    /// Miles per weekday, Monday first.
    var dailyMiles: [Double]
    /// Take-home per weekday after both set-asides.
    var dailyNet: [Double]

    /// Gross per bar for whichever range Analytics is showing. Equals `daily`
    /// when that range is the week; becomes weeks-of-month or months-of-year
    /// otherwise. Kept separate so the dashboard's weekly view is unaffected
    /// by what the Analytics picker is set to.
    var primary: [Double]
    /// Axis captions matching `primary`, one per bar.
    var primaryLabels: [String]

    /// Labels under the hourly chart, derived from the bucket definition so
    /// they can't drift away from the data the way hard-coded ones do.
    static let hourLabels = ["6a", "12p", "6p", "12a", "6a"]

    /// First bucket covers 06:00–08:00.
    static let hourlyOrigin = 6
    static var bucketHours: Int { 24 / 12 }

    var hasAnyEarnings: Bool { daily.contains { $0 > 0 } }
    var hasMonthlyHistory: Bool { monthly.filter { $0 > 0 }.count >= 2 }

    /// "Peak 6–8pm", computed from the busiest bucket rather than asserted.
    /// The design hard-coded this string; leaving it that way would let the
    /// caption contradict the bars directly beneath it.
    var peakWindowLabel: String {
        guard let peak = hourly.max(), peak > 0,
              let index = hourly.firstIndex(of: peak) else { return "No data yet" }

        let startHour = (Self.hourlyOrigin + index * Self.bucketHours) % 24
        let endHour = (startHour + Self.bucketHours) % 24
        return "Peak \(Self.clock(startHour))–\(Self.clock(endHour))"
    }

    /// 0 → "12am", 13 → "1pm", 18 → "6pm".
    private static func clock(_ hour: Int) -> String {
        let suffix = hour < 12 ? "am" : "pm"
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display)\(suffix)"
    }

    static let empty = ChartSeries(
        daily: Array(repeating: 0, count: 7),
        cumulative: Array(repeating: 0, count: 7),
        hourly: Array(repeating: 0, count: 12),
        monthly: Array(repeating: 0, count: 4),
        dailyMiles: Array(repeating: 0, count: 7),
        dailyNet: Array(repeating: 0, count: 7),
        primary: Array(repeating: 0, count: 7),
        primaryLabels: AnalyticsRange.week.labels
    )
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

    /// Everything spent in the period, both pots together.
    let expensesTotal: Double
    /// The part of `expensesTotal` paid out of the maintenance reserve rather
    /// than out of take-home. Kept separate so the split can be shown, and so
    /// nobody is tempted to subtract it from net profit a second time.
    let reserveDraw: Double

    // Collections
    let platforms: [Platform]

    let driver: Driver
    let vehicle: Vehicle

    /// Everything the charts plot.
    let series: ChartSeries

    /// What this user is allowed to see.
    let entitlement: Entitlement
    /// End of the current paid period, when subscribed.
    let planRenewsOn: Date?

    // MARK: Derived

    /// Whether there's anything to show. Every screen branches on this before
    /// rendering a chart or a rate, because all of them divide by something
    /// that is zero on a fresh install.
    var hasData: Bool { weeklyTotal > 0 || onlineHours > 0 || mileage > 0 }

    /// True once the driver has logged anything at all, this week or not.
    var hasEverLoggedShift: Bool { hasData || maintenanceFund > 0 || taxSavingsYTD > 0 }

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
