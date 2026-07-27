//
//  MileageRate.swift
//  GigGrow
//
//  The IRS standard mileage rate, resolved by the date the miles were driven.
//
//  A single stored number can't be right. The IRS normally sets one rate per
//  calendar year, but it raises it mid-year when fuel moves sharply — it did
//  exactly that in 2026, going from 72.5¢ to 76¢ on 1 July. Miles driven in
//  June and miles driven in August deduct at different rates, and an app that
//  stores one figure quietly misstates one of them.
//
//  Rates below are the IRS business-use figures. They need a check each
//  January, and again whenever a mid-year revision is announced.
//

import Foundation

struct MileageRate: Equatable {
    /// First day this rate applies.
    let effectiveFrom: DateComponents
    /// Dollars per mile.
    let dollarsPerMile: Double
}

enum MileageRates {

    /// When these were last checked against irs.gov.
    static let verifiedOn = "July 2026"

    /// Newest first. `rate(on:)` walks down to the first one that has started.
    static let schedule: [MileageRate] = [
        // Mid-year revision, announced because fuel costs rose.
        MileageRate(effectiveFrom: DateComponents(year: 2026, month: 7, day: 1),
                    dollarsPerMile: 0.76),
        MileageRate(effectiveFrom: DateComponents(year: 2026, month: 1, day: 1),
                    dollarsPerMile: 0.725),
        MileageRate(effectiveFrom: DateComponents(year: 2025, month: 1, day: 1),
                    dollarsPerMile: 0.70),
        MileageRate(effectiveFrom: DateComponents(year: 2024, month: 1, day: 1),
                    dollarsPerMile: 0.67)
    ]

    /// The rate in force on `date`.
    static func rate(on date: Date, calendar: Calendar = .gigGrow) -> Double {
        for band in schedule {
            guard let start = calendar.date(from: band.effectiveFrom) else { continue }
            if date >= start { return band.dollarsPerMile }
        }
        // Older than anything listed: use the earliest known rate rather than
        // zero, which would silently wipe out a deduction.
        return schedule.last?.dollarsPerMile ?? 0.67
    }

    static var current: Double { rate(on: .now) }

    /// The deduction for miles driven on a given date.
    static func deduction(miles: Double, on date: Date) -> Double {
        miles * rate(on: date)
    }

    /// Whether more than one rate applies across a period, which is worth
    /// saying out loud rather than letting a total quietly blend two.
    ///
    /// Note this asks whether the *rate* differs, not whether a band starts
    /// inside the range. Every calendar year begins on a band boundary, so
    /// the naive reading of "a band starts in here" is true of every year and
    /// answers nothing.
    static func changesDuring(_ range: Range<Date>, calendar: Calendar = .gigGrow) -> Bool {
        guard range.lowerBound < range.upperBound else { return false }

        let atStart = rate(on: range.lowerBound, calendar: calendar)
        return schedule.contains { band in
            guard let start = calendar.date(from: band.effectiveFrom) else { return false }
            // A band that begins after the range opens and before it closes,
            // carrying a different number.
            return start > range.lowerBound
                && start < range.upperBound
                && band.dollarsPerMile != atStart
        }
    }

    static func formatted(_ rate: Double) -> String {
        String(format: "$%.3f", rate)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }
}
