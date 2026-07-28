//
//  ImportOverlapDetector.swift
//  GigGrow
//
//  One weekly report already contains every daily report for that app.
//  Treating "week" and "day" as unrelated duplicate shapes is how the same
//  earnings were able to enter the store twice.
//

import Foundation
import SwiftData

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

    /// Manual entries can be reconciled with a later platform report. A
    /// report imported earlier is different: it is a true duplicate and must
    /// stay excluded until the driver explicitly chooses to replace it.
    static func isImported(_ shift: Shift) -> Bool {
        let note = shift.note?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return note.hasPrefix("imported from")
            || note.hasPrefix("from a weekly screenshot")
    }
}

enum StoredEarningsOrigin: Equatable {
    case manual
    case imported
}

struct StoredEarningsOverlap {
    let shift: Shift
    let earning: PlatformEarning
    let coverage: ImportCoverage
    let origin: StoredEarningsOrigin
}

/// Finds and removes only the app earnings covered by an incoming report.
/// If a manual shift also contains Lyft, replacing its Uber earnings must not
/// erase Lyft or the shared shift metadata.
enum ImportReconciler {
    static func overlaps(
        _ incoming: ImportCoverage,
        in shifts: [Shift],
        calendar: Calendar = .gigGrow
    ) -> [StoredEarningsOverlap] {
        shifts.flatMap { shift in
            shift.earningItems.compactMap { earning in
                guard let platform = earning.account?.name else { return nil }
                let storedCoverage = ImportOverlapDetector.coverage(
                    of: shift,
                    platform: platform,
                    calendar: calendar
                )
                guard
                      ImportOverlapDetector.overlaps(
                        incoming,
                        storedCoverage,
                        calendar: calendar
                      )
                else { return nil }

                return StoredEarningsOverlap(
                    shift: shift,
                    earning: earning,
                    coverage: storedCoverage,
                    origin: ImportOverlapDetector.isImported(shift)
                        ? .imported
                        : .manual
                )
            }
        }
    }

    /// A weekly report legitimately supersedes previously imported daily
    /// reports inside that week. It is a duplicate only when another weekly
    /// report already covers the same app/week. A daily report remains
    /// blocked by either the same day or an existing weekly report.
    static func hasBlockingDuplicate(
        incoming: ImportCoverage,
        overlaps: [StoredEarningsOverlap]
    ) -> Bool {
        overlaps.contains { overlap in
            guard overlap.origin == .imported else { return false }
            return !(incoming.period == .week && overlap.coverage.period == .day)
        }
    }

    /// Manual entries are superseded automatically. Previously imported data
    /// is touched automatically only when a broader weekly report subsumes a
    /// stored day. Other imported data requires an explicit Replace.
    static func replacements(
        from overlaps: [StoredEarningsOverlap],
        incoming: ImportCoverage,
        replacingImported: Bool
    ) -> [StoredEarningsOverlap] {
        overlaps.filter {
            $0.origin == .manual
                || replacingImported
                || (incoming.period == .week && $0.coverage.period == .day)
        }
    }

    /// Removes each matched earning once. A shift survives when another app
    /// still has earnings on it; otherwise the now-empty shell is removed.
    @MainActor
    @discardableResult
    static func remove(
        _ overlaps: [StoredEarningsOverlap],
        from context: ModelContext
    ) -> Int {
        let byShift = Dictionary(grouping: overlaps) {
            $0.shift.persistentModelID
        }
        var removedEarningIDs: Set<PersistentIdentifier> = []

        for group in byShift.values {
            guard let shift = group.first?.shift else { continue }
            let ids = Set(group.map { $0.earning.persistentModelID })
            shift.earningItems.removeAll { ids.contains($0.persistentModelID) }

            for overlap in group
            where removedEarningIDs.insert(overlap.earning.persistentModelID).inserted {
                context.delete(overlap.earning)
            }

            if shift.earningItems.isEmpty {
                context.delete(shift)
            }
        }

        return removedEarningIDs.count
    }
}
