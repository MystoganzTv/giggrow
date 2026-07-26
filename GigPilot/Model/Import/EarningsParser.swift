//
//  EarningsParser.swift
//  GigPilot
//
//  Turns recognised lines into candidate figures.
//
//  This is heuristic and it will be wrong. Every gig app lays its earnings
//  screen out differently and redesigns it without warning, so the parser
//  offers *candidates* and the driver confirms. It never decides silently:
//  a wrong number here would flow into the hourly rate, the tax set-aside
//  and the reserve, and nothing downstream would flag it.
//

import Foundation

// MARK: - Candidate

/// One possible reading, with why it was picked so the UI can rank and
/// explain rather than presenting a bare guess.
struct ParsedCandidate<Value: Equatable>: Identifiable, Equatable {
    let id = UUID()
    let value: Value
    /// The line it came from, shown so the driver can check against the image.
    let source: String
    /// 0…1. Combines OCR confidence with how strong the surrounding cue was.
    let confidence: Double

    static func == (lhs: ParsedCandidate<Value>, rhs: ParsedCandidate<Value>) -> Bool {
        lhs.value == rhs.value && lhs.source == rhs.source
    }
}

// MARK: - Result

struct ParsedEarnings {
    var platformName: String?
    var amounts: [ParsedCandidate<Double>] = []
    var units: [ParsedCandidate<Int>] = []
    var hours: [ParsedCandidate<Double>] = []
    var miles: [ParsedCandidate<Double>] = []
    var dates: [ParsedCandidate<Date>] = []

    /// Every line read, kept so the review screen can show its working.
    var allLines: [String] = []

    var best: (amount: Double?, units: Int?, hours: Double?, miles: Double?, date: Date?) {
        (amounts.first?.value, units.first?.value, hours.first?.value,
         miles.first?.value, dates.first?.value)
    }

    var foundAnything: Bool {
        !amounts.isEmpty || !units.isEmpty || !hours.isEmpty || !miles.isEmpty
    }
}

// MARK: - Parser

enum EarningsParser {

    /// Keywords that identify each platform. Matched case-insensitively
    /// against every line, longest first so "Uber Eats" beats "Uber".
    static let platformKeywords: [(name: String, keywords: [String])] = [
        ("Uber",          ["uber eats", "ubereats", "uber"]),
        ("Lyft",          ["lyft"]),
        ("DoorDash",      ["doordash", "dasher", "door dash"]),
        ("Instacart",     ["instacart", "shopper"]),
        ("Amazon Flex",   ["amazon flex", "amzn flex", "flex"]),
        ("Walmart Spark", ["walmart spark", "spark driver", "spark"])
    ]

    static func parse(_ lines: [RecognisedLine]) -> ParsedEarnings {
        var result = ParsedEarnings()
        result.allLines = lines.map(\.text)
        result.platformName = detectPlatform(lines)

        for (index, line) in lines.enumerated() {
            let lower = line.text.lowercased()
            // The line above often labels the figure below it.
            let context = (index > 0 ? lines[index - 1].text.lowercased() : "") + " " + lower

            for amount in currencyAmounts(in: line.text) {
                result.amounts.append(
                    ParsedCandidate(
                        value: amount,
                        source: line.text,
                        confidence: score(base: Double(line.confidence),
                                          cues: totalCues, in: context,
                                          position: line.topDownY)
                    )
                )
            }

            if let count = number(in: line.text, near: unitCues, context: context) {
                result.units.append(
                    ParsedCandidate(value: Int(count), source: line.text,
                                    confidence: Double(line.confidence))
                )
            }

            if let value = duration(in: line.text, context: context) {
                result.hours.append(
                    ParsedCandidate(value: value, source: line.text,
                                    confidence: Double(line.confidence))
                )
            }

            if let value = number(in: line.text, near: mileCues, context: context) {
                result.miles.append(
                    ParsedCandidate(value: value, source: line.text,
                                    confidence: Double(line.confidence))
                )
            }

            if let date = date(in: line.text) {
                result.dates.append(
                    ParsedCandidate(value: date, source: line.text,
                                    confidence: Double(line.confidence))
                )
            }
        }

        // Strongest cue first; ties broken by the larger figure, since the
        // headline total is usually the biggest number on the screen.
        result.amounts.sort {
            $0.confidence == $1.confidence ? $0.value > $1.value : $0.confidence > $1.confidence
        }
        result.units.sort { $0.confidence > $1.confidence }
        result.hours.sort { $0.confidence > $1.confidence }
        result.miles.sort { $0.confidence > $1.confidence }
        result.dates.sort { $0.confidence > $1.confidence }

        result.amounts = dedupe(result.amounts)
        result.units = dedupe(result.units)
        result.hours = dedupe(result.hours)
        result.miles = dedupe(result.miles)

        return result
    }

    // MARK: Cues

    private static let totalCues = ["total", "earnings", "earned", "you made",
                                    "payout", "net pay", "gross", "balance"]
    private static let unitCues  = ["trip", "trips", "delivery", "deliveries",
                                    "order", "orders", "batch", "batches",
                                    "ride", "rides", "job", "jobs"]
    private static let mileCues  = ["mile", "miles", "mi"]

    private static func detectPlatform(_ lines: [RecognisedLine]) -> String? {
        let haystack = lines.map { $0.text.lowercased() }.joined(separator: " ")
        for (name, keywords) in platformKeywords {
            if keywords.contains(where: { haystack.contains($0) }) { return name }
        }
        return nil
    }

    /// Confidence blends OCR certainty, whether a labelling word is nearby,
    /// and how high on the screen the line sat — headline totals are at the top.
    private static func score(base: Double, cues: [String],
                              in context: String, position: CGFloat) -> Double {
        var value = base * 0.5
        if cues.contains(where: { context.contains($0) }) { value += 0.35 }
        if position < 0.4 { value += 0.15 }
        return min(value, 1)
    }

    // MARK: Extractors

    /// `$1,482.60`, `1482.60`, `$47`. Requires either a currency symbol or
    /// exactly two decimals, so bare counts aren't mistaken for money and
    /// "6.5 hrs" isn't read as $6.50.
    ///
    /// The grouped branch needs `(?:,\d{3})+` rather than `*`: with `*` the
    /// leading `\d{1,3}` matched only the last three digits of an ungrouped
    /// figure, so `1482.60` came back as `482.60` — a thousand-dollar error
    /// with nothing downstream to catch it.
    static func currencyAmounts(in text: String) -> [Double] {
        let pattern = #"\$\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)|\b(\d{1,3}(?:,\d{3})+\.\d{2}|\d+\.\d{2})\b"#
        return matches(pattern, in: text).compactMap { groups in
            let raw = groups.compactMap { $0 }.last
            return raw.flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }
        }
    }

    /// A number adjacent to one of `cues`, in either order: "12 trips" or
    /// "Trips 12".
    static func number(in text: String, near cues: [String], context: String) -> Double? {
        let lower = text.lowercased()
        guard cues.contains(where: { lower.contains($0) }) || cues.contains(where: { context.contains($0) })
        else { return nil }

        // Skip anything that's part of a currency figure.
        guard !lower.contains("$") else { return nil }

        let numbers = matches(#"(\d{1,3}(?:,\d{3})*(?:\.\d+)?)"#, in: text)
            .compactMap { $0.first ?? nil }
            .compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
        return numbers.first
    }

    /// "6h 30m", "6.5 hrs", "6:30". Returns hours as a decimal.
    static func duration(in text: String, context: String) -> Double? {
        let lower = text.lowercased()

        // 6:30 → 6.5
        if let groups = matches(#"\b(\d{1,2}):([0-5]\d)\b"#, in: lower).first,
           let h = groups.first.flatMap({ $0 }).flatMap(Double.init),
           groups.count > 1, let m = groups[1].flatMap(Double.init) {
            return h + m / 60
        }

        // 6h 30m
        if let groups = matches(#"\b(\d{1,2})\s*h(?:r|rs|ours)?\s*(\d{1,2})\s*m"#, in: lower).first,
           let h = groups.first.flatMap({ $0 }).flatMap(Double.init),
           groups.count > 1, let m = groups[1].flatMap(Double.init) {
            return h + m / 60
        }

        // 6.5 hrs
        guard lower.contains("h") || context.contains("online") || context.contains("hour")
        else { return nil }
        if let groups = matches(#"\b(\d{1,2}(?:\.\d+)?)\s*h(?:r|rs|ours)?\b"#, in: lower).first,
           let h = groups.first.flatMap({ $0 }).flatMap(Double.init) {
            return h
        }
        return nil
    }

    static func date(in text: String) -> Date? {
        let formats = ["MMM d, yyyy", "MMM d yyyy", "d MMM yyyy",
                       "MM/dd/yyyy", "yyyy-MM-dd", "MMM d"]
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let date = f.date(from: cleaned) {
                // "MMM d" has no year and defaults to 2000; assume this year.
                if format == "MMM d" {
                    var comps = Calendar.gigPilot.dateComponents([.month, .day], from: date)
                    comps.year = Calendar.gigPilot.component(.year, from: .now)
                    return Calendar.gigPilot.date(from: comps)
                }
                return date
            }
        }
        return nil
    }

    // MARK: Helpers

    /// Returns each match's capture groups.
    private static func matches(_ pattern: String, in text: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).map { index in
                guard let r = Range(match.range(at: index), in: text) else { return nil }
                return String(text[r])
            }
        }
    }

    private static func dedupe<T: Equatable>(_ candidates: [ParsedCandidate<T>]) -> [ParsedCandidate<T>] {
        var seen: [T] = []
        var out: [ParsedCandidate<T>] = []
        for candidate in candidates where !seen.contains(candidate.value) {
            seen.append(candidate.value)
            out.append(candidate)
        }
        return out
    }
}
