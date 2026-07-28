//
//  ImportOverlapDetector.swift
//  GigGrow
//
//  One weekly report already contains every daily report for that app.
//  Treating "week" and "day" as unrelated duplicate shapes is how the same
//  earnings were able to enter the store twice.
//

import Foundation

/// What a screenshot covers. A week and one of its days are overlapping
/// reports, not independent earnings.
enum ImportPeriod: String, CaseIterable, Identifiable {
    case day, week
    var id: String { rawValue }
    var label: String { self == .day ? "One day" : "A week" }
}

struct ImportCoverage: Equatable {
    let platform: String
    let period: ImportPeriod
    let date: Date
}

enum ImportOverlapDetector {
    static func overlaps(_ lhs: ImportCoverage,
                         _ rhs: ImportCoverage,
                         calendar: Calendar = .gigGrow) -> Bool {
        let leftPlatform = lhs.platform
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let rightPlatform = rhs.platform
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !leftPlatform.isEmpty, leftPlatform == rightPlatform else {
            return false
        }

        if lhs.period == .week || rhs.period == .week {
            return calendar.startOfWeek(for: lhs.date)
                == calendar.startOfWeek(for: rhs.date)
        }

        return calendar.startOfDay(for: lhs.date)
            == calendar.startOfDay(for: rhs.date)
    }

    /// Every row derived from a weekly screenshot still covers the source
    /// week for duplicate purposes. Even if its chart produced no Sunday row,
    /// the exact weekly total already accounts for that reporting period.
    static func coverage(of shift: Shift, platform: String,
                         calendar: Calendar = .gigGrow) -> ImportCoverage {
        let span = shift.end.timeIntervalSince(shift.start)
        let comesFromWeek = shift.isAggregate
            && (shift.note?.hasPrefix("Imported from a weekly summary") == true
                || shift.note?.hasPrefix("From a weekly screenshot") == true
                || span >= 6 * 24 * 60 * 60)
        return ImportCoverage(
            platform: platform,
            period: comesFromWeek ? .week : .day,
            date: comesFromWeek
                ? calendar.startOfWeek(for: shift.start)
                : calendar.startOfDay(for: shift.start)
        )
    }
}
