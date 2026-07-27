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

        // Round once, at the weekly-report boundary, then conserve those
        // cents across the active days. Rounding each day independently made
        // four Uber rows add to $245.35 while the confirmed week was $245.34.
        // The chart is still an estimate; this only prevents its estimates
        // from contradicting the exact total printed on the screenshot.
        let allocatedSources = sources.map { source in
            (
                source: source,
                gross: allocateMoney(source.gross,
                                     shares: source.dailyShares,
                                     minimumShare: minimumShare),
                tips: allocateMoney(source.tips,
                                    shares: source.dailyShares,
                                    minimumShare: minimumShare),
                promotions: allocateMoney(source.promotions,
                                          shares: source.dailyShares,
                                          minimumShare: minimumShare),
                trips: allocateUnits(source.trips,
                                     shares: source.dailyShares,
                                     minimumShare: minimumShare)
            )
        }

        return (0..<7).compactMap { dayIndex in
            let earnings = allocatedSources.compactMap { allocation -> WeeklyDayEarning? in
                let source = allocation.source
                guard source.dailyShares.indices.contains(dayIndex) else { return nil }
                let share = source.dailyShares[dayIndex]
                guard share > minimumShare else { return nil }
                return WeeklyDayEarning(
                    platform: source.platform,
                    gross: allocation.gross[dayIndex],
                    tips: allocation.tips[dayIndex],
                    promotions: allocation.promotions[dayIndex],
                    trips: allocation.trips[dayIndex]
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

    private static func allocateMoney(_ total: Double,
                                      shares: [Double],
                                      minimumShare: Double) -> [Double] {
        allocateInteger(
            Int((max(total, 0) * 100).rounded()),
            shares: shares,
            minimumShare: minimumShare
        )
        .map { Double($0) / 100 }
    }

    private static func allocateUnits(_ total: Int,
                                      shares: [Double],
                                      minimumShare: Double) -> [Int] {
        allocateInteger(max(total, 0),
                        shares: shares,
                        minimumShare: minimumShare)
    }

    /// Largest-remainder allocation. Active chart bars receive an integer
    /// number of cents/units and the results add back to the exact report.
    private static func allocateInteger(_ total: Int,
                                        shares: [Double],
                                        minimumShare: Double) -> [Int] {
        var result = Array(repeating: 0, count: 7)
        let active = shares.indices.filter {
            $0 < result.count && shares[$0] > minimumShare
        }
        let weight = active.reduce(0.0) { $0 + shares[$1] }
        guard total > 0, weight > 0 else { return result }

        var ranked: [(index: Int, fraction: Double)] = []
        var assigned = 0
        for index in active {
            let raw = Double(total) * shares[index] / weight
            let base = Int(floor(raw))
            result[index] = base
            assigned += base
            ranked.append((index, raw - Double(base)))
        }

        ranked.sort {
            if $0.fraction == $1.fraction { return $0.index < $1.index }
            return $0.fraction > $1.fraction
        }
        var remainder = total - assigned
        var cursor = 0
        while remainder > 0, !ranked.isEmpty {
            result[ranked[cursor % ranked.count].index] += 1
            remainder -= 1
            cursor += 1
        }
        return result
    }
}
