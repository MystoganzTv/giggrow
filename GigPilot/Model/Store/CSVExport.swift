//
//  CSVExport.swift
//  GigPilot
//
//  Comma-separated exports of shifts and expenses.
//
//  The Settings row promised "CSV, PDF" and delivered neither. This does the
//  CSV half; the PDF claim was removed rather than left standing.
//
//  Shifts export one row per platform per shift, not one per shift. A shift
//  with three apps running produces three rows sharing a shift id, so an
//  accountant can pivot by platform without the app having pre-decided how
//  to attribute the hours.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

// MARK: - Document

/// Wraps a CSV string so `ShareLink` can hand it to the share sheet.
struct CSVDocument: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { doc in
            Data(doc.text.utf8)
        }
        .suggestedFileName { "\($0.name).csv" }
    }
}

// MARK: - Builder

enum CSVExport {

    /// One row per platform per shift.
    static func shifts(_ shifts: [Shift]) -> String {
        var rows = [
            "shift_id,date,start,end,online_hours,active_hours,idle_hours,"
            + "shift_miles,platform,gross,tips,units,attributed_hours,attributed_miles"
        ]

        let day = formatter("yyyy-MM-dd")
        let time = formatter("HH:mm")

        for (index, shift) in shifts.sorted(by: { $0.start < $1.start }).enumerated() {
            let id = index + 1
            let base = [
                "\(id)",
                day.string(from: shift.start),
                time.string(from: shift.start),
                time.string(from: shift.end),
                num(shift.hours),
                num(shift.activeHours),
                num(shift.idleHours),
                num(shift.miles)
            ]

            if shift.earnings.isEmpty {
                rows.append((base + ["", "0", "0", "0", num(shift.hours), num(shift.miles)])
                    .joined(separator: ","))
                continue
            }

            for earning in shift.earnings {
                rows.append((base + [
                    escape(earning.account?.name ?? "Unknown"),
                    num(earning.gross),
                    num(earning.tips),
                    "\(earning.trips)",
                    num(ShiftAttribution.hours(of: earning, in: shift)),
                    num(ShiftAttribution.miles(of: earning, in: shift))
                ]).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    static func expenses(_ expenses: [Expense]) -> String {
        var rows = ["date,category,amount,deductible,paid_from,note"]
        let day = formatter("yyyy-MM-dd")

        for expense in expenses.sorted(by: { $0.date < $1.date }) {
            rows.append([
                day.string(from: expense.date),
                escape(expense.category.label),
                num(expense.amount),
                expense.isDeductible ? "yes" : "no",
                expense.category.drawsFromMaintenanceFund ? "maintenance reserve" : "out of pocket",
                escape(expense.note ?? "")
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// Two decimals, always a dot — spreadsheets in other locales choke on
    /// a comma decimal separator inside a comma-separated file.
    private static func num(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Quotes any field containing a comma, quote or newline, per RFC 4180.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
