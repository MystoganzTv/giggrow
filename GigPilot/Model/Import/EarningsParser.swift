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

    /// The amount whose line mentions one of these words.
    ///
    /// The breakdown is already parsed — every one of those figures is in
    /// `amounts` with the line it came from. Nothing new has to be read; the
    /// importer simply stopped throwing the labels away.
    func amount(labelled cues: [String]) -> Double? {
        amounts.first { candidate in
            let line = candidate.source.lowercased()
            return cues.contains { line.contains($0) }
        }?.value
    }

    /// Uber writes "Tip", Lyft "Tips", DoorDash "Customer tips".
    var tips: Double? { amount(labelled: ["tip"]) }

    /// Quests, surges, bonuses and challenges all land here.
    var promotions: Double? {
        amount(labelled: ["promotion", "promo", "quest", "bonus", "surge",
                          "incentive", "challenge", "boost"])
    }

    /// The fare before anything was added to it.
    var netFare: Double? {
        amount(labelled: ["net fare", "fare", "base pay", "base fare"])
    }

    /// Whether the breakdown adds up to the headline.
    ///
    /// A free integrity check on the most important number in the app: if
    /// fare + promotions + tips doesn't reach the total, one of the four was
    /// misread and the driver should look before saving. Only meaningful
    /// when all of them were found.
    func reconciliation(against total: Double) -> (sum: Double, matches: Bool)? {
        guard let netFare, total > 0 else { return nil }
        let sum = netFare + (promotions ?? 0) + (tips ?? 0)
        // Two cents of slack for rounding in the platform's own display.
        return (sum, abs(sum - total) <= 0.02)
    }

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

        // Text height stands in for font size. On a weekly summary the
        // headline total is physically the largest thing on screen, which is
        // a stronger signal than any keyword — Uber's doesn't say "total"
        // anywhere near it.
        let tallest = lines.map(\.box.height).max() ?? 0

        for (index, line) in lines.enumerated() {
            let lower = line.text.lowercased()
            let context = (index > 0 ? lines[index - 1].text.lowercased() : "") + " " + lower

            // A deduction is not income. Uber's fare breakdown lists four of
            // them, and dropping the sign turned "Amount Uber kept −$206.19"
            // into a plausible week's earnings.
            let isDeduction = lower.contains("-$") || lower.contains("−$")
                || lower.hasPrefix("-") || lower.hasPrefix("−")

            if !isDeduction {
                for amount in currencyAmounts(in: line.text) {
                    result.amounts.append(
                        ParsedCandidate(
                            value: amount,
                            source: line.text,
                            confidence: score(base: Double(line.confidence),
                                              cues: totalCues, in: context,
                                              position: line.topDownY,
                                              relativeSize: tallest > 0
                                                  ? line.box.height / tallest : 0)
                        )
                    )
                }
            }

            if let value = duration(in: line.text, context: context) {
                result.hours.append(
                    ParsedCandidate(value: value, source: line.text,
                                    confidence: Double(line.confidence))
                )
            }

            for date in dates(in: line.text) {
                result.dates.append(
                    ParsedCandidate(value: date, source: line.text,
                                    confidence: Double(line.confidence))
                )
            }
        }

        // Counts and distances are matched by column, not by reading order.
        // "Online" and "Trips" sit side by side with their values beneath,
        // so the line before "47" is "20 h 21 m" — following reading order
        // read the trip count as 20.
        result.units = valuesUnderLabel(cues: unitCues, in: lines)
            .compactMap { candidate in
                guard let whole = Int(exactly: candidate.value.rounded()) else { return nil }
                return ParsedCandidate(value: whole,
                                       source: candidate.source,
                                       confidence: candidate.confidence)
            }
        result.miles = valuesUnderLabel(cues: mileCues, in: lines)

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

    /// Confidence blends OCR certainty, a nearby labelling word, height on
    /// the screen, and how large the text is relative to everything else.
    ///
    /// Size carries real weight: on Uber's weekly summary the total is the
    /// biggest text on screen and carries no label at all, while a chart
    /// axis label sits equally high in tiny type. Position alone scored
    /// those two the same.
    private static func score(base: Double, cues: [String],
                              in context: String, position: CGFloat,
                              relativeSize: CGFloat) -> Double {
        var value = base * 0.35
        if cues.contains(where: { context.contains($0) }) { value += 0.30 }
        if position < 0.4 { value += 0.10 }
        value += Double(min(relativeSize, 1)) * 0.25
        return min(value, 1)
    }

    // MARK: Column matching

    /// Finds the value belonging to each label, by column rather than by
    /// reading order.
    ///
    /// Vision returns lines top-to-bottom, so a two-column stat block
    /// interleaves labels and values. The value for a label is the nearest
    /// line *below* it whose horizontal span overlaps the label's — which is
    /// what "underneath it" means on screen.
    private static func valuesUnderLabel(cues: [String],
                                         in lines: [RecognisedLine]) -> [ParsedCandidate<Double>] {
        var found: [ParsedCandidate<Double>] = []

        for label in lines {
            let lower = label.text.lowercased()
            guard cues.contains(where: { lower.contains($0) }) else { continue }

            // The label may carry its own value — "47 trips" on one line.
            if let inline = firstNumber(in: label.text), !label.text.contains("$") {
                found.append(ParsedCandidate(value: inline, source: label.text,
                                             confidence: Double(label.confidence)))
                continue
            }

            let candidates = lines
                .filter { $0.topDownY > label.topDownY }
                .filter { horizontallyOverlaps($0.box, label.box) }
                .sorted { $0.topDownY < $1.topDownY }

            for line in candidates.prefix(2) {
                guard !line.text.contains("$"),
                      // A duration is not a count; "20 h 21 m" must not be
                      // read as 20 trips.
                      duration(in: line.text, context: "") == nil,
                      let value = firstNumber(in: line.text) else { continue }
                found.append(ParsedCandidate(value: value, source: line.text,
                                             confidence: Double(line.confidence)))
                break
            }
        }
        return found
    }

    /// True when two boxes share horizontal space — the same column.
    private static func horizontallyOverlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return overlap > min(a.width, b.width) * 0.4
    }

    private static func firstNumber(in text: String) -> Double? {
        matches(#"(\d{1,3}(?:,\d{3})*(?:\.\d+)?)"#, in: text)
            .compactMap { $0.first ?? nil }
            .compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
            .first
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


    /// "6h 30m", "6.5 hrs", "6:30". Returns hours as a decimal.
    ///
    /// The colon form is the dangerous one. Every iOS screenshot has a clock
    /// in the top-left, and "17:52" reads as a perfectly plausible 17.87-hour
    /// shift — which is exactly what it did, producing a week that claimed
    /// eighteen hours online. So the colon form now needs a reason to be
    /// believed: an explicit unit, or a nearby "online"/"hours" label.
    static func duration(in text: String, context: String) -> Double? {
        let lower = text.lowercased()
        let hasCue = context.contains("online") || context.contains("hour")
            || context.contains("time") || context.contains("active")

        // 6h 30m — unambiguous, no cue needed.
        if let groups = matches(#"\b(\d{1,2})\s*h(?:r|rs|ours)?\s*(\d{1,2})\s*m"#, in: lower).first,
           let h = groups.first.flatMap({ $0 }).flatMap(Double.init),
           groups.count > 1, let m = groups[1].flatMap(Double.init) {
            return sane(h + m / 60)
        }

        // 6:30 → 6.5, but only where something says this is a duration.
        if hasCue,
           let groups = matches(#"\b(\d{1,2}):([0-5]\d)\b"#, in: lower).first,
           let h = groups.first.flatMap({ $0 }).flatMap(Double.init),
           groups.count > 1, let m = groups[1].flatMap(Double.init) {
            return sane(h + m / 60)
        }

        // 6.5 hrs
        guard lower.contains("h") || hasCue else { return nil }
        if let groups = matches(#"\b(\d{1,2}(?:\.\d+)?)\s*h(?:r|rs|ours)?\b"#, in: lower).first,
           let h = groups.first.flatMap({ $0 }).flatMap(Double.init) {
            return sane(h)
        }
        return nil
    }

    /// A day has 24 hours and a week has 168. Anything outside that was a
    /// misread, and a misread here divides into every rate on the dashboard.
    private static func sane(_ hours: Double) -> Double? {
        (hours > 0 && hours <= 168) ? hours : nil
    }

    /// Every date in a line. Uber's header is a range — "Jul 13 - Jul 20" —
    /// so a parser that only handles one date per line found nothing at all.
    static func dates(in text: String) -> [Date] {
        // Split on the dash forms a range might use, then parse each half.
        let parts = text.components(separatedBy: CharacterSet(charactersIn: "-–—"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var found = parts.compactMap { singleDate(in: $0) }
        if found.isEmpty, let whole = singleDate(in: text) { found = [whole] }
        return found
    }

    /// Kept for callers wanting one answer; returns the earliest match.
    static func date(in text: String) -> Date? {
        dates(in: text).min()
    }

    /// The period header — "Jun 1 - Jun 8", "Jun 29 – Jul 5" — wherever it is.
    ///
    /// Worth its own pass rather than relying on the general date scan. The
    /// header is the one date on the screen that is definitely the period
    /// being shown, and without it the day detector has no week to place a
    /// bar into. When this returned nothing the importer fell back to today,
    /// which turned a screenshot of June into "Sunday 26 July" — confidently,
    /// with a chart reading to back it up. A wrong date presented that firmly
    /// is worse than no date at all.
    static func weekStart(in lines: [RecognisedLine], now: Date = .now) -> Date? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun",
                      "jul", "aug", "sep", "oct", "nov", "dec"]
        let monthGroup = months.joined(separator: "|")
        // "Jun 1 - Jun 8" and "1 Jun - 8 Jun" both appear in the wild.
        let patterns = [
            #"\b(\#(monthGroup))[a-z]*\.?\s+(\d{1,2})\b\s*[-–—]"#,
            #"\b(\d{1,2})\s+(\#(monthGroup))[a-z]*\.?\b\s*[-–—]"#
        ]

        for line in lines {
            let lower = line.text.lowercased()
            for (index, pattern) in patterns.enumerated() {
                guard let groups = matches(pattern, in: lower).first,
                      groups.count >= 2,
                      let a = groups[0], let b = groups[1] else { continue }

                let monthText = index == 0 ? a : b
                let dayText   = index == 0 ? b : a
                guard let month = months.firstIndex(of: String(monthText.prefix(3))).map({ $0 + 1 }),
                      let day = Int(dayText), (1...31).contains(day) else { continue }

                if let date = resolveYear(month: month, day: day, now: now) {
                    return Calendar.gigPilot.startOfWeek(for: date)
                }
            }
        }
        return nil
    }

    /// Picks the year a bare "Jun 1" means.
    ///
    /// A screenshot is always of something that already happened, so a date
    /// that would land in the future belongs to last year. Without this, a
    /// December screenshot imported in January reads as eleven months away.
    private static func resolveYear(month: Int, day: Int, now: Date) -> Date? {
        let calendar = Calendar.gigPilot
        let thisYear = calendar.component(.year, from: now)

        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = thisYear
        guard let candidate = calendar.date(from: components) else { return nil }

        // A couple of days of slack: a screenshot taken this morning of a
        // period ending today shouldn't be thrown back a year.
        if candidate.timeIntervalSince(now) > 2 * 86_400 {
            components.year = thisYear - 1
            return calendar.date(from: components)
        }
        return candidate
    }

    private static func singleDate(in text: String) -> Date? {
        let formats = ["MMM d, yyyy", "MMM d yyyy", "d MMM yyyy",
                       "MM/dd/yyyy", "yyyy-MM-dd", "MMM d"]
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let date = f.date(from: cleaned) {
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
