//
//  MockData.swift
//  GigPilot
//
//  Ported verbatim from the `renderVals()` block in GigPilot.dc.html so the
//  running app shows exactly the numbers the design was drawn against.
//

import SwiftUI

extension EarningsSnapshot {

    static let mock = EarningsSnapshot(
        weeklyTotal: 1482.60,
        taxRate: 25,
        maintenanceRate: 8,

        perHour: 38.60,
        perMile: 2.42,
        onlineHours: 38.4,
        activeHours: 29.2,
        mileage: 612,
        tripCount: 214,
        weeklyChange: "+12.4%",
        monthlyChange: "+6.1%",

        maintenanceFund: 2684,
        maintenanceGoal: 3000,
        taxSavingsYTD: 8420,
        monthlyIncome: 5940,
        netProfit: 994,

        platforms: [
            Platform(name: "Uber", short: "Uber", initial: "U", share: 0.29,
                     hourly: "$41.20", meta: "58 trips · 128 mi", delta: "+9%",
                     gradient: [Color(hex: 0xA78BFA), Color(hex: 0x7C5CF6)]),

            Platform(name: "Lyft", short: "Lyft", initial: "L", share: 0.21,
                     hourly: "$36.80", meta: "41 trips · 96 mi", delta: "+14%",
                     gradient: [Color(hex: 0xC084FC), Color(hex: 0x8B5CF6)]),

            Platform(name: "DoorDash", short: "DoorDash", initial: "D", share: 0.18,
                     hourly: "$34.10", meta: "47 orders · 104 mi", delta: "+6%",
                     gradient: [Color(hex: 0x818CF8), Color(hex: 0x4F76F6)]),

            Platform(name: "Instacart", short: "Instacart", initial: "I", share: 0.14,
                     hourly: "$32.40", meta: "22 batches · 88 mi", delta: "+3%",
                     gradient: [Color(hex: 0x60A5FA), Color(hex: 0x3B82F6)]),

            Platform(name: "Amazon Flex", short: "Flex", initial: "F", share: 0.11,
                     hourly: "$30.90", meta: "6 blocks · 132 mi", delta: "+11%",
                     gradient: [Color(hex: 0x7DD3FC), Color(hex: 0x38BDF8)]),

            Platform(name: "Walmart Spark", short: "Spark", initial: "S", share: 0.07,
                     hourly: "$28.50", meta: "19 trips · 64 mi", delta: "+5%",
                     gradient: [Color(hex: 0x93C5FD), Color(hex: 0x60A5FA)])
        ],

        service: [
            ServiceItem(name: "Oil change",    due: "In 1,790 mi · Sep 2026",  status: .scheduled),
            ServiceItem(name: "Tire rotation", due: "Overdue by 420 mi",       status: .dueNow),
            ServiceItem(name: "Brake pads",    due: "In 8,200 mi",             status: .healthy),
            ServiceItem(name: "Registration",  due: "Renews Mar 2027",         status: .healthy)
        ],

        settingGroups: [
            SettingGroup(title: "Money", rows: [
                SettingRow(label: "Tax set-aside",         value: "25%"),
                SettingRow(label: "Maintenance set-aside", value: "8%"),
                SettingRow(label: "Mileage rate",          value: "$0.70 / mi"),
                SettingRow(label: "Payout account",        value: "•••• 4417")
            ]),
            SettingGroup(title: "Tracking", rows: [
                SettingRow(label: "Auto mileage tracking", value: "On"),
                SettingRow(label: "Shift detection",       value: "Automatic"),
                SettingRow(label: "Idle threshold",        value: "8 min")
            ]),
            SettingGroup(title: "General", rows: [
                SettingRow(label: "Notifications", value: "Weekly digest"),
                SettingRow(label: "Export data",   value: "CSV, PDF"),
                SettingRow(label: "Privacy",       value: "")
            ])
        ],

        driver: Driver(name: "Marco Delgado", detail: "Phoenix, AZ · Since 2023"),

        vehicle: Vehicle(
            name: "2022 Toyota RAV4",
            detail: "Hybrid · 7KJD812",
            odometer: 84_210,
            milesThisWeek: 612,
            fuelCostPerMile: 0.11,
            averageMPG: 39
        )
    )
}

// MARK: - Chart series
//
// The design hard-codes its chart geometry as SVG path data. Those coordinates
// are reproduced here as normalised series so the SwiftUI shapes render the
// identical curve at any width.

enum ChartData {

    /// Dashboard hero area chart. Design viewBox 300×72, y measured from top.
    /// Path: M0 58 L38 48 L76 52 L114 34 L152 40 L190 22 L228 26 L266 12 L300 8
    static let weekTrend: [CGPoint] = [
        .init(x: 0,   y: 58), .init(x: 38,  y: 48), .init(x: 76,  y: 52),
        .init(x: 114, y: 34), .init(x: 152, y: 40), .init(x: 190, y: 22),
        .init(x: 228, y: 26), .init(x: 266, y: 12), .init(x: 300, y: 8)
    ]
    static let weekTrendBox = CGSize(width: 300, height: 72)

    /// Dashboard "Weekly trend" sparkline. viewBox 100×30.
    static let weeklySparkline: [CGPoint] = [
        .init(x: 0, y: 24), .init(x: 20, y: 20), .init(x: 40, y: 22),
        .init(x: 60, y: 12), .init(x: 80, y: 14), .init(x: 100, y: 4)
    ]

    /// Dashboard "Monthly trend" sparkline. viewBox 100×30.
    static let monthlySparkline: [CGPoint] = [
        .init(x: 0, y: 20), .init(x: 25, y: 22), .init(x: 50, y: 14),
        .init(x: 75, y: 16), .init(x: 100, y: 8)
    ]
    static let sparklineBox = CGSize(width: 100, height: 30)

    /// Analytics mileage tile sparkline. viewBox 100×40.
    static let mileageSpark: [CGPoint] = [
        .init(x: 0, y: 30), .init(x: 20, y: 26), .init(x: 40, y: 28),
        .init(x: 60, y: 18), .init(x: 80, y: 20), .init(x: 100, y: 10)
    ]

    /// Analytics net-profit tile sparkline. viewBox 100×40.
    static let profitSpark: [CGPoint] = [
        .init(x: 0, y: 32), .init(x: 20, y: 24), .init(x: 40, y: 26),
        .init(x: 60, y: 16), .init(x: 80, y: 14), .init(x: 100, y: 6)
    ]
    static let tileSparkBox = CGSize(width: 100, height: 40)

    /// Analytics weekly income bars. viewBox 300×112; bars sit on a 100pt baseline.
    /// Tuples are (height, opacity) taken from the design's `<rect>` list.
    static let weeklyBars: [(height: CGFloat, opacity: Double)] = [
        (48, 0.55), (60, 0.65), (40, 0.50), (74, 0.80), (66, 0.72), (92, 1.00), (80, 0.88)
    ]
    static let weeklyBarsMax: CGFloat = 92
    static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]
    static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Analytics monthly income curve — a smooth cubic path in a 300×104 box.
    /// M0 78 C30 74 42 56 70 58 C100 60 112 40 140 44 C170 48 182 28 210 30 C240 32 258 14 300 10
    static let monthlyCurveStart = CGPoint(x: 0, y: 78)
    static let monthlyCurve: [(c1: CGPoint, c2: CGPoint, end: CGPoint)] = [
        (.init(x: 30,  y: 74), .init(x: 42,  y: 56), .init(x: 70,  y: 58)),
        (.init(x: 100, y: 60), .init(x: 112, y: 40), .init(x: 140, y: 44)),
        (.init(x: 170, y: 48), .init(x: 182, y: 28), .init(x: 210, y: 30)),
        (.init(x: 240, y: 32), .init(x: 258, y: 14), .init(x: 300, y: 10))
    ]
    static let monthlyCurveBox = CGSize(width: 300, height: 104)
    static let monthLabels = ["Apr", "May", "Jun", "Jul"]

    /// Analytics hourly earnings — 12 two-hour buckets from 8am.
    /// Tuples are (height, colour, opacity) from the design's `<rect>` list.
    static let hourlyBars: [(height: CGFloat, color: Color, opacity: Double)] = [
        (26, Color(hex: 0x6366F1), 0.45),
        (36, Color(hex: 0x6366F1), 0.50),
        (48, Color(hex: 0x7C6CF6), 0.60),
        (42, Color(hex: 0x7C6CF6), 0.55),
        (58, Color(hex: 0x8B5CF6), 0.70),
        (54, Color(hex: 0x8B5CF6), 0.66),
        (66, Color(hex: 0x9B6CFA), 0.80),
        (78, Color(hex: 0xA78BFA), 1.00),
        (72, Color(hex: 0xA78BFA), 0.90),
        (52, Color(hex: 0x818CF8), 0.60),
        (38, Color(hex: 0x818CF8), 0.50),
        (22, Color(hex: 0x818CF8), 0.40)
    ]
    static let hourlyBarsMax: CGFloat = 78
    static let hourLabels = ["8a", "12p", "4p", "8p", "12a"]
}
