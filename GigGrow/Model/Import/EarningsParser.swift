//
//  EarningsParser.swift
//  GigGrow
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

    /// The breakdown, already matched to its labels during parsing.
    ///
    /// This has to happen where the bounding boxes are. A gig app writes
    /// "Tip" hard left and "$7.00" hard right, and Vision returns those as
    /// two separate observations — so searching a line's own text for the
    /// word "tip" finds nothing, and the driver was left retyping figures
    /// that were sitting on the screen the whole time.
    var breakdown: [BreakdownKind: Double] = [:]

    /// Falls back to the label sharing a line with its figure, for layouts
    /// that write "Tip $7.00" as one string.
    func amount(labelled cues: [String]) -> Double? {
        amounts.first { candidate in
            let line = candidate.source.lowercased()
            guard !PayoutCues.matches(line) else { return false }
            return cues.contains { line.contains($0) }
        }?.value
    }

    /// Uber writes "Tip", Lyft "Tips", DoorDash "Customer tips".
    ///
    /// Lyft's activity list also prints individual green lines such as
    /// "incl. $4.04 tip". That list is only a preview and is not the day's
    /// total. For Lyft, only the TIP STATS card is authoritative.
    var tips: Double? {
        if platformName == "Lyft" { return breakdown[.tips] }
        return breakdown[.tips] ?? amount(labelled: BreakdownKind.tips.cues)
    }

    /// Quests, surges, bonuses and challenges all land here.
    var promotions: Double? {
        if platformName == "Lyft" { return breakdown[.promotions] }
        return breakdown[.promotions] ?? amount(labelled: BreakdownKind.promotions.cues)
    }

    /// The fare before anything was added to it.
    var netFare: Double? { breakdown[.netFare] ?? amount(labelled: BreakdownKind.netFare.cues) }

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

/// Money on the screen that is not money earned in this period.
///
/// Lyft's summary ends with the balance still sitting in the account —
/// earnings already counted further up, waiting to be paid out. It is a
/// dollar figure with a short label in the same type as the breakdown rows,
/// so every structural signal the parser uses says "this is a line item",
/// and it was landing in tips or promotions and inflating the week.
///
/// The distinction isn't whose money it is — it is the driver's — but
/// *when* it was earned. Counting a balance would add the same dollars a
/// second time.
enum PayoutCues {
    static let all = ["balance", "payout", "paid out", "pending", "cash out",
                      "cashout", "instant pay", "express pay", "transfer",
                      "deposit", "available", "withdraw", "lifetime",
                      "all time", "to date"]

    static func matches(_ lowercasedLine: String) -> Bool {
        all.contains { lowercasedLine.contains($0) }
    }
}

/// Rates and averages calculated by the platform are context, not earnings.
///
/// Their values change every week, so filtering a known number is useless.
/// The label is the stable part: "$29.33 per booked hr", "$18.40/hour" and
/// "$4.25 per trip" must never become gross, tips or promotions.
enum DerivedMetricCues {
    static let all = [
        "average", "avg ", "avg.", "hourly",
        "per booked hr", "per booked hour",
        "per active hr", "per active hour",
        "per online hr", "per online hour",
        "per hour", "per hr", "/hour", "/hr",
        "per trip", "per ride", "per delivery", "per order",
        "per mile", "/mile", "/mi"
    ]

    static func matches(_ lowercasedLine: String) -> Bool {
        all.contains { lowercasedLine.contains($0) }
    }
}

/// The named rows of an earnings breakdown.
enum BreakdownKind: String, CaseIterable {
    case netFare, promotions, tips

    /// Longest and most specific first: "net fare" must win over "fare", and
    /// "tip" must not swallow "Total" — which it wouldn't, but "other
    /// earnings" sitting next to a tip row is the kind of thing that does.
    var cues: [String] {
        switch self {
        case .netFare:
            return ["net fare", "base fare", "base pay", "fare"]
        case .promotions:
            return ["promotion", "promo", "quest", "bonus", "surge",
                    "incentive", "challenge", "boost"]
        case .tips:
            return ["tip"]
        }
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
            let isExcludedAmount = isNonPeriodAmount(line, in: lines)

            if !isDeduction && !isExcludedAmount {
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
        result.units = valuesUnderLabel(
            cues: unitCues,
            excluding: ["rejected", "declined", "cancelled", "canceled"],
            preferred: ["completed", "complete"],
            in: lines
        )
            .compactMap { candidate in
                guard let whole = Int(exactly: candidate.value.rounded()) else { return nil }
                return ParsedCandidate(value: whole,
                                       source: candidate.source,
                                       confidence: candidate.confidence)
            }
        result.miles = valuesUnderLabel(cues: mileCues, in: lines)

        // The breakdown reads across the row, not down the column: the label
        // is on the left and the money is on the right, at the same height.
        for kind in BreakdownKind.allCases {
            if result.platformName == "Lyft" {
                switch kind {
                case .tips:
                    // The only complete Lyft tip total on Day/Week screens.
                    // Individual trip tips above it are intentionally ignored.
                    if let value = amountBesideLabel(
                        cues: ["tip stats"],
                        in: lines
                    ) {
                        result.breakdown[kind] = value
                    }
                    continue
                case .promotions:
                    // Lyft's visible activity list is partial ("See all daily
                    // activity"), so an inline trip bonus is not a daily
                    // promotions total.
                    continue
                case .netFare:
                    break
                }
            }
            if let value = amountBesideLabel(cues: kind.cues, in: lines) {
                result.breakdown[kind] = value
            }
        }

        // Uber's earnings graph prints its highest day beside the dotted
        // guide line. If Vision misses the large centred total, that small
        // axis figure used to become "gross" merely because it was the first
        // remaining dollar amount. On an Uber summary, accept only a total
        // we can identify structurally or reconstruct from every visible
        // component. An empty review field is safer than invented income.
        if isUberEarningsSummary(result, lines: lines) {
            result.amounts = trustedUberGrossCandidates(
                from: lines,
                parsed: result,
                tallest: tallest
            )
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
                                    "net pay", "gross"]
    private static let unitCues  = ["trip", "trips", "delivery", "deliveries",
                                    "order", "orders", "batch", "batches",
                                    "ride", "rides", "job", "jobs"]
    private static let mileCues  = ["mile", "miles", "mileage", "mi"]

    private static func isUberEarningsSummary(_ parsed: ParsedEarnings,
                                              lines: [RecognisedLine]) -> Bool {
        guard parsed.platformName == "Uber" else { return false }
        let text = lines.map(\.text).joined(separator: " ").lowercased()
        return text.contains("total earnings")
            && text.contains("online")
            && (text.contains("trip") || text.contains("delivery"))
    }

    private static func trustedUberGrossCandidates(
        from lines: [RecognisedLine],
        parsed: ParsedEarnings,
        tallest: CGFloat
    ) -> [ParsedCandidate<Double>] {
        var trusted: [ParsedCandidate<Double>] = []

        if let labelled = amountForDriverTotal(in: lines) {
            trusted.append(labelled)
        }

        // The selected day/week amount is the large centred figure above the
        // graph. The graph maximum is small and left-aligned, so it cannot
        // pass this geometry check even when it is the only number OCR saw.
        for line in lines {
            let relativeSize = tallest > 0 ? line.box.height / tallest : 0
            let centre = line.box.midX
            guard relativeSize >= 0.65,
                  centre >= 0.25, centre <= 0.75
            else { continue }
            for amount in currencyAmounts(in: line.text) {
                trusted.append(
                    ParsedCandidate(
                        value: amount,
                        source: line.text,
                        confidence: min(Double(line.confidence) * 0.95, 0.95)
                    )
                )
            }
        }

        // When every row exists, the breakdown is an independent checksum
        // for the headline: Net Fare + Promotions + Tips = Total Earnings.
        // Requiring all three labels avoids silently treating a missed row
        // as zero.
        let hasEveryComponent = BreakdownKind.allCases.allSatisfy { kind in
            lines.contains { line in
                let lower = line.text.lowercased()
                return kind.cues.contains { lower.contains($0) }
            } && parsed.breakdown[kind] != nil
        }
        if hasEveryComponent,
           let fare = parsed.breakdown[.netFare],
           let promotions = parsed.breakdown[.promotions],
           let tips = parsed.breakdown[.tips] {
            trusted.append(
                ParsedCandidate(
                    value: fare + promotions + tips,
                    source: "Net Fare + Promotions + Tips",
                    confidence: 0.99
                )
            )
        }

        return trusted
    }

    /// Finds the driver's own labelled total, never a customer's total.
    private static func amountForDriverTotal(
        in lines: [RecognisedLine]
    ) -> ParsedCandidate<Double>? {
        let cues = ["your total earnings", "total earnings"]

        for label in lines {
            let lower = label.text.lowercased()
            guard cues.contains(where: { lower.contains($0) }),
                  !notYoursCues.contains(where: { lower.contains($0) })
            else { continue }

            if let amount = currencyAmounts(in: label.text).first {
                return ParsedCandidate(
                    value: amount,
                    source: label.text,
                    confidence: Double(label.confidence)
                )
            }

            let sameRow = lines
                .filter { $0.text != label.text }
                .filter { verticallyOverlaps($0.box, label.box) }
                .filter { $0.box.minX >= label.box.minX }
                .sorted { $0.box.minX < $1.box.minX }
            if let money = sameRow.first(where: {
                currencyAmounts(in: $0.text).first != nil
                    && !isNonPeriodAmount($0, in: lines)
            }), let amount = currencyAmounts(in: money.text).first {
                return ParsedCandidate(
                    value: amount,
                    source: "\(label.text) \(money.text)",
                    confidence: min(Double(label.confidence),
                                    Double(money.confidence))
                )
            }

            let below = lines
                .filter { $0.topDownY > label.topDownY }
                .filter { $0.topDownY - label.topDownY < 0.10 }
                .filter { horizontallyOverlaps($0.box, label.box) }
                .sorted { $0.topDownY < $1.topDownY }
            if let money = below.first(where: {
                currencyAmounts(in: $0.text).first != nil
                    && !isNonPeriodAmount($0, in: lines)
            }), let amount = currencyAmounts(in: money.text).first {
                return ParsedCandidate(
                    value: amount,
                    source: "\(label.text) \(money.text)",
                    confidence: min(Double(label.confidence),
                                    Double(money.confidence))
                )
            }
        }
        return nil
    }

    private static func detectPlatform(_ lines: [RecognisedLine]) -> String? {
        let haystack = lines.map { $0.text.lowercased() }.joined(separator: " ")
        for (name, keywords) in platformKeywords {
            if keywords.contains(where: { haystack.contains($0) }) { return name }
        }
        // Lyft's earnings screen does not currently print the Lyft name.
        // These three labels appear together on its weekly dashboard and
        // are more reliable than leaving the platform blank.
        if haystack.contains("rides rejected"),
           haystack.contains("weekly stats"),
           haystack.contains("cash out") {
            return "Lyft"
        }
        // Uber's weekly earnings page also omits the brand name. Its stat
        // and breakdown vocabulary together form a stable signature; without
        // this the review could save Lyft and silently drop the unassigned
        // Uber screenshot.
        if haystack.contains("total earnings"),
           haystack.contains("online"),
           haystack.contains("trips"),
           (haystack.contains("net fare")
            || haystack.contains("points")
            || haystack.contains("how we calculate stats")) {
            return "Uber"
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
    /// Words that mean this money was never the driver's.
    ///
    /// Uber's breakdown opens with "Total customer fare $1,091.87" — which
    /// carries the "total" cue, sits high on the screen, and is the biggest
    /// number there. It beat "Your total earnings $829.41" on every signal
    /// and would have imported a 32% overstatement as income. What separates
    /// them isn't position or size, it's whose money it is.
    private static let notYoursCues = ["customer", "rider", "passenger",
                                       "uber kept", "lyft kept", "service fee",
                                       "gross fare", "total fare"]

    private static func score(base: Double, cues: [String],
                              in context: String, position: CGFloat,
                              relativeSize: CGFloat) -> Double {
        var value = base * 0.35
        if cues.contains(where: { context.contains($0) }) { value += 0.30 }
        if position < 0.4 { value += 0.10 }
        value += Double(min(relativeSize, 1)) * 0.25

        // Applied last and heavily: a figure labelled as the customer's is
        // disqualified rather than merely ranked lower, because it is
        // plausible enough to survive a glance in the review sheet.
        if notYoursCues.contains(where: { context.contains($0) }) { value *= 0.25 }
        // Same treatment for a pending balance: right money, wrong period.
        if PayoutCues.matches(context) { value *= 0.25 }
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
                                         excluding excludedCues: [String] = [],
                                         preferred preferredCues: [String] = [],
                                         in lines: [RecognisedLine]) -> [ParsedCandidate<Double>] {
        var found: [ParsedCandidate<Double>] = []
        var preferredFound: [ParsedCandidate<Double>] = []

        for label in lines {
            let lower = label.text.lowercased()
            guard cues.contains(where: { containsWholeCue($0, in: lower) }) else { continue }
            guard !excludedCues.contains(where: { lower.contains($0) }) else { continue }

            let isPreferred = preferredCues.contains(where: { lower.contains($0) })
            let confidence = min(
                Double(label.confidence) * (isPreferred ? 1.05 : 0.85),
                1
            )

            // The label may carry its own value — "47 trips" on one line.
            if let inline = firstNumber(in: label.text), !label.text.contains("$") {
                let candidate = ParsedCandidate(value: inline, source: label.text,
                                                confidence: confidence)
                found.append(candidate)
                if isPreferred { preferredFound.append(candidate) }
                continue
            }

            // Lyft writes "Rides completed" on the left and "60" at the
            // far-right edge of the same card row. Their boxes do not
            // overlap horizontally, so a strictly "under label" search
            // misses 60 and later mistakes "16 rides" in Tip Stats for the
            // completed count.
            let sameRow = lines
                .filter { $0.text != label.text }
                .filter { verticallyOverlaps($0.box, label.box) }
                .filter { $0.box.minX >= label.box.maxX }
                .sorted { $0.box.minX < $1.box.minX }

            if let line = sameRow.first(where: {
                !$0.text.contains("$")
                    && duration(in: $0.text, context: "") == nil
                    && firstNumber(in: $0.text) != nil
            }), let value = firstNumber(in: line.text) {
                let candidate = ParsedCandidate(value: value, source: line.text,
                                                confidence: confidence)
                found.append(candidate)
                if isPreferred { preferredFound.append(candidate) }
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
                let candidate = ParsedCandidate(
                    value: value,
                    source: line.text,
                    confidence: min(confidence, Double(line.confidence))
                )
                found.append(candidate)
                if isPreferred { preferredFound.append(candidate) }
                break
            }
        }
        // When the screen explicitly says "completed", alternatives from
        // cards such as "16 rides tipped" are not alternative totals. They
        // describe a different statistic and should not be offered at all.
        return preferredFound.isEmpty ? found : preferredFound
    }

    /// Matches `mi` as a word, not as the first two letters of `min`.
    ///
    /// This distinction matters on Lyft: "30 hr 23 min" used to become both
    /// 30 hours and 30 imaginary miles.
    private static func containsWholeCue(_ cue: String, in text: String) -> Bool {
        if cue.contains(" ") { return text.contains(cue) }
        let words = text.split { !$0.isLetter && !$0.isNumber }
            .map { $0.lowercased() }
        return words.contains(cue)
    }

    /// True when two boxes share horizontal space — the same column.
    /// The money sitting on the same row as a label.
    ///
    /// "Tip" and "$7.00" are one visual row and two OCR observations, so the
    /// match is vertical overlap plus being further right. Reading order
    /// alone isn't enough — Vision interleaves the two columns differently
    /// depending on spacing, and the line after "Tip" is sometimes the next
    /// label rather than its own figure.
    private static func amountBesideLabel(cues: [String],
                                          in lines: [RecognisedLine]) -> Double? {
        for label in lines {
            let lower = label.text.lowercased()
            guard cues.contains(where: { lower.contains($0) }) else { continue }
            // A row that is its own total isn't a breakdown line.
            guard !lower.contains("total") else { continue }
            // "Per booked hour · Excluding tips" describes a rate; it is not
            // a tips row and must never borrow money from a later card.
            guard !lower.contains("excluding tip"),
                  !lower.contains("without tip") else { continue }
            // Nor is the balance waiting to be paid out — that money was
            // already earned and counted somewhere above.
            guard !PayoutCues.matches(lower) else { continue }

            // Written together — "Tip $7.00".
            if let inline = currencyAmounts(in: label.text).first { return inline }

            let sameRow = lines
                .filter { $0.text != label.text }
                .filter { verticallyOverlaps($0.box, label.box) }
                .filter { $0.box.minX >= label.box.minX }
                .sorted { $0.box.minX < $1.box.minX }

            for line in sameRow {
                // A negative is a fee Uber kept, not something earned.
                let text = line.text
                guard !text.contains("-$"), !text.contains("−$"),
                      !text.hasPrefix("-"), !text.hasPrefix("−"),
                      !isNonPeriodAmount(line, in: lines) else { continue }
                if let amount = currencyAmounts(in: text).first { return amount }
            }

            // Lyft's "TIP STATS" is a card heading with the amount beneath
            // it, not a table row. It is close and in the same column, but
            // does not vertically overlap the heading.
            let below = lines
                .filter { $0.topDownY > label.topDownY }
                .filter { $0.topDownY - label.topDownY < 0.12 }
                .filter { horizontallyOverlaps($0.box, label.box) }
                .sorted { $0.topDownY < $1.topDownY }

            for line in below {
                let text = line.text
                guard !text.contains("-$"), !text.contains("−$"),
                      !text.hasPrefix("-"), !text.hasPrefix("−"),
                      !isNonPeriodAmount(line, in: lines) else { continue }
                if let amount = currencyAmounts(in: text).first { return amount }
            }
        }
        return nil
    }

    /// A payout balance can arrive from Vision as one line
    /// (`"$1,055.51 balance"`) or as separate amount, label and `Cash out`
    /// observations. In either shape it is money earned in an earlier period,
    /// not part of the week currently shown.
    private static func isPayoutRelated(_ line: RecognisedLine,
                                        in lines: [RecognisedLine]) -> Bool {
        if PayoutCues.matches(line.text.lowercased()) { return true }

        return lines.contains { neighbour in
            guard neighbour.text != line.text,
                  PayoutCues.matches(neighbour.text.lowercased())
            else { return false }

            return verticallyOverlaps(neighbour.box, line.box)
                || abs(neighbour.topDownY - line.topDownY) < 0.035
        }
    }

    /// A derived rate is often split into an amount above and a caption below.
    /// Require horizontal overlap for nearby captions so an unrelated rate
    /// elsewhere on the dashboard cannot suppress the weekly headline.
    private static func isDerivedMetricRelated(_ line: RecognisedLine,
                                               in lines: [RecognisedLine]) -> Bool {
        if DerivedMetricCues.matches(line.text.lowercased()) { return true }

        return lines.contains { neighbour in
            guard neighbour.text != line.text,
                  DerivedMetricCues.matches(neighbour.text.lowercased())
            else { return false }

            return verticallyOverlaps(neighbour.box, line.box)
                || (abs(neighbour.topDownY - line.topDownY) < 0.085
                    && horizontallyOverlaps(neighbour.box, line.box))
        }
    }

    private static func isNonPeriodAmount(_ line: RecognisedLine,
                                          in lines: [RecognisedLine]) -> Bool {
        isPayoutRelated(line, in: lines)
            || isDerivedMetricRelated(line, in: lines)
    }

    /// Two boxes share a row when their vertical spans mostly coincide.
    private static func verticallyOverlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > min(a.height, b.height) * 0.5
    }

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
                    return Calendar.gigGrow.startOfWeek(for: date)
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
        let calendar = Calendar.gigGrow
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
                    var comps = Calendar.gigGrow.dateComponents([.month, .day], from: date)
                    comps.year = Calendar.gigGrow.component(.year, from: .now)
                    return Calendar.gigGrow.date(from: comps)
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
