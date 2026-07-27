//
//  ReceiptParser.swift
//  GigGrow
//
//  Reads a till receipt.
//
//  Same on-device Vision pass as the earnings importer, different problem.
//  An earnings screen is a designed layout that changes twice a year; a
//  receipt is whatever the till printed, in whatever order, often crumpled
//  and photographed at an angle.
//
//  So this leans on the one thing receipts agree about: the total is
//  labelled, and it is the largest figure that isn't the change from a
//  fifty. Everything else — date, merchant, category — is offered as a
//  suggestion the driver confirms, because a wrong expense quietly changes
//  a tax figure and nothing downstream would catch it.
//
//  The trap here is the opposite of the earnings one. There, the biggest
//  number was the customer's fare and not the driver's. Here, "Cash $50.00"
//  and "Change $12.40" sit right under the total and look just like it.
//

import Foundation

struct ParsedReceipt {
    var total: Double?
    var date: Date?
    var merchant: String?
    var suggestedCategory: ExpenseCategory?
    /// Every amount found, best first, so a wrong pick is one tap to fix.
    var amounts: [ParsedCandidate<Double>] = []
    var allLines: [String] = []

    var foundAnything: Bool { total != nil || date != nil || merchant != nil }
}

enum ReceiptParser {

    // MARK: Cues

    /// What tills call the figure that matters.
    private static let totalCues = ["total", "amount due", "balance due",
                                    "grand total", "you paid", "sale amount",
                                    "purchase", "charged"]

    /// Figures that look like a total and are not. "Subtotal" contains
    /// "total", so it has to be excluded before the cue is applied, not after.
    private static let notTotalCues = ["subtotal", "sub total", "tax", "vat",
                                       "tip", "gratuity", "change", "cash",
                                       "tendered", "savings", "discount",
                                       "points", "balance:", "gallons", "price/gal",
                                       "unit price", "per gal", "@"]

    /// Merchants a gig driver actually sees, grouped by what the spend is.
    ///
    /// Kept deliberately short. A long brand list looks thorough and rots —
    /// these are the categories where guessing right saves a tap and guessing
    /// wrong is obvious enough to correct.
    private static let merchantHints: [(ExpenseCategory, [String])] = [
        (.fuel, ["shell", "chevron", "exxon", "mobil", "bp", "texaco", "sunoco",
                 "citgo", "marathon", "valero", "arco", "76", "wawa", "sheetz",
                 "quiktrip", "racetrac", "pilot", "loves", "circle k", "speedway",
                 "gas", "fuel", "petro", "supercharger", "electrify", "evgo",
                 "chargepoint"]),
        (.maintenance, ["jiffy lube", "valvoline", "midas", "firestone", "pep boys",
                        "autozone", "o'reilly", "napa", "discount tire",
                        "tire", "lube", "auto", "mechanic", "service center",
                        "car wash", "oil change"]),
        (.insurance, ["geico", "progressive", "state farm", "allstate", "insurance"]),
        (.phone, ["verizon", "at&t", "t-mobile", "mint mobile", "wireless"]),
        (.fees, ["toll", "ez pass", "e-zpass", "fastrak", "parking", "garage",
                 "meter", "sunpass"])
    ]

    // MARK: Entry point

    static func parse(_ lines: [RecognisedLine]) -> ParsedReceipt {
        var result = ParsedReceipt()
        result.allLines = lines.map(\.text)

        let tallest = lines.map(\.box.height).max() ?? 0

        for line in lines {
            let lower = line.text.lowercased()
            guard !isNegativeOrExcluded(lower) else { continue }

            for amount in currencyAmounts(in: line.text) {
                result.amounts.append(
                    ParsedCandidate(
                        value: amount,
                        source: line.text,
                        confidence: score(line: line, lower: lower, tallest: tallest)
                    )
                )
            }
        }

        result.amounts.sort {
            $0.confidence == $1.confidence ? $0.value > $1.value : $0.confidence > $1.confidence
        }
        result.amounts = dedupe(result.amounts)
        result.total = result.amounts.first?.value

        result.date = firstDate(in: lines)
        result.merchant = merchant(in: lines, tallest: tallest)
        result.suggestedCategory = category(for: result.merchant, lines: lines)
        return result
    }

    // MARK: Scoring

    private static func isNegativeOrExcluded(_ lower: String) -> Bool {
        if lower.contains("-$") || lower.contains("−$") { return true }
        // Fuel receipts price per gallon on the same line as a currency
        // figure; that is a rate, not a spend.
        return notTotalCues.contains { lower.contains($0) }
    }

    private static func score(line: RecognisedLine, lower: String, tallest: CGFloat) -> Double {
        var value = Double(line.confidence) * 0.30

        if totalCues.contains(where: { lower.contains($0) }) { value += 0.40 }

        // A till prints the total near the bottom, the opposite of an
        // earnings screen. Position is weak evidence either way, so it gets
        // less weight than the label.
        if line.topDownY > 0.55 { value += 0.10 }

        if tallest > 0 { value += Double(min(line.box.height / tallest, 1)) * 0.20 }
        return min(value, 1)
    }

    // MARK: Merchant

    /// The largest text in the top third, which is where tills print the name.
    private static func merchant(in lines: [RecognisedLine], tallest: CGFloat) -> String? {
        let candidates = lines
            .filter { $0.topDownY < 0.35 }
            .filter { $0.text.count >= 3 && $0.text.count <= 32 }
            // A phone number or an address is not a name.
            .filter { !$0.text.contains(where: \.isNumber) || $0.text.contains(where: \.isLetter) }
            .filter { currencyAmounts(in: $0.text).isEmpty }
            .sorted { $0.box.height > $1.box.height }

        guard let best = candidates.first else { return nil }
        return best.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    private static func category(for merchant: String?,
                                 lines: [RecognisedLine]) -> ExpenseCategory? {
        // Search the whole receipt, not just the name: a supermarket forecourt
        // prints "UNLEADED" in the body and nothing useful at the top.
        let haystack = ((merchant ?? "") + " " + lines.map(\.text).joined(separator: " "))
            .lowercased()

        for (category, hints) in merchantHints
        where hints.contains(where: { haystack.contains($0) }) {
            return category
        }
        return nil
    }

    // MARK: Dates

    private static func firstDate(in lines: [RecognisedLine]) -> Date? {
        let patterns = [
            #"\b\d{4}-\d{1,2}-\d{1,2}\b"#,
            #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#,
            #"(?i)\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2},?\s+\d{4}\b"#
        ]
        let formats = ["yyyy-M-d", "M/d/yyyy", "M/d/yy", "M-d-yyyy", "M-d-yy",
                       "MMM d, yyyy", "MMM d yyyy", "MMMM d, yyyy", "MMMM d yyyy",
                       "d/M/yyyy"]

        for line in lines {
            let fullRange = NSRange(line.text.startIndex..<line.text.endIndex, in: line.text)
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: line.text, range: fullRange) {
                    guard let range = Range(match.range, in: line.text) else { continue }
                    let candidate = String(line.text[range])

                for format in formats {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.isLenient = false
                    f.dateFormat = format
                        if let date = f.date(from: candidate) {
                        // A receipt is for something that already happened;
                        // a future date is a misread, usually a till number.
                        guard date <= Date.now.addingTimeInterval(86_400) else { continue }
                        return date
                    }
                }
            }
            }
        }
        return nil
    }

    // MARK: Shared helpers

    private static func currencyAmounts(in text: String) -> [Double] {
        let pattern = #"\$\s?(\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+\.\d{2})|\b(\d{1,3}(?:,\d{3})+\.\d{2}|\d+\.\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            for index in 1..<match.numberOfRanges {
                guard let r = Range(match.range(at: index), in: text) else { continue }
                return Double(String(text[r]).replacingOccurrences(of: ",", with: ""))
            }
            return nil
        }
    }

    private static func dedupe(_ items: [ParsedCandidate<Double>]) -> [ParsedCandidate<Double>] {
        var seen = Set<Double>()
        return items.filter { seen.insert($0.value).inserted }
    }
}
