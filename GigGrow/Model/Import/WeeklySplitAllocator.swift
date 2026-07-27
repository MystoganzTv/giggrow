//
//  WeeklySplitAllocator.swift
//  GigGrow
//
//  Combines weekly charts without making one platform inherit another's days.
//

import Foundation

struct WeeklyPlatformSplit: Equatable {
    let platform: String
    let gross: Double
    let tips: Double
    let promotions: Double
    let trips: Int
    let dailyShares: [Double]
}

struct WeeklyDayEarning: Equatable {
    let platform: String
    let gross: Double
    let tips: Double
    let promotions: Double
    let trips: Int
}

struct WeeklyDaySplit: Equatable {
    let dayIndex: Int
    /// Share of the combined multi-app gross. Used only to preserve the
    /// confirmed weekly hours/miles totals across the derived day records.
    let combinedShare: Double
    let earnings: [WeeklyDayEarning]
}

enum WeeklySplitAllocator {
    static func allocate(_ sources: [WeeklyPlatformSplit],
                         minimumShare: Double = 0.0001) -> [WeeklyDaySplit] {
        let totalGross = sources.reduce(0) { $0 + $1.gross }
        guard totalGross > 0 else { return [] }

        return (0..<7).compactMap { dayIndex in
            let earnings = sources.compactMap { source -> WeeklyDayEarning? in
                guard source.dailyShares.indices.contains(dayIndex) else { return nil }
                let share = source.dailyShares[dayIndex]
                guard share > minimumShare else { return nil }
                return WeeklyDayEarning(
                    platform: source.platform,
                    gross: source.gross * share,
                    tips: source.tips * share,
                    promotions: source.promotions * share,
                    trips: Int((Double(source.trips) * share).rounded())
                )
            }
            guard !earnings.isEmpty else { return nil }
            let dayGross = earnings.reduce(0) { $0 + $1.gross }
            return WeeklyDaySplit(
                dayIndex: dayIndex,
                combinedShare: dayGross / totalGross,
                earnings: earnings
            )
        }
    }
}
