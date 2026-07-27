//
//  USState.swift
//  GigGrow
//
//  Where the driver works, and what that means for their set-aside.
//
//  This isn't decoration. Self-employment tax is 15.3% everywhere, but state
//  income tax ranges from nothing to over 13%. A driver in Texas putting away
//  the same percentage as one in California is over-saving by thousands a
//  year; the reverse is worse.
//
//  The nine states with no broad-based personal income tax as of 2026:
//  AK, FL, NV, NH, SD, TN, TX, WA, WY. New Hampshire's interest-and-dividends
//  tax ended 1 January 2025, making it a true zero.
//
//  These are starting points, not tax advice — see `suggestedTaxRate`.
//

import Foundation

struct USState: Identifiable, Hashable {
    /// USPS abbreviation, shown in the picker tile.
    let code: String
    let name: String
    /// Whether the state levies a broad-based personal income tax.
    let hasIncomeTax: Bool

    var id: String { code }

    /// A starting percentage to hold back, not a calculation.
    ///
    /// Federal self-employment tax alone is 15.3%, and federal income tax
    /// sits on top of that. The two bands here are deliberately coarse:
    /// anything more precise would need the driver's total income, filing
    /// status and deductions, and pretending otherwise would be worse than
    /// admitting the estimate is rough. Editable in Settings.
    var suggestedTaxRate: Double { hasIncomeTax ? 27 : 22 }

    var taxNote: String {
        hasIncomeTax
            ? "Federal self-employment and income tax, plus \(name) state tax."
            : "\(name) has no state income tax, so this covers federal only."
    }
}

enum StateDirectory {

    /// Verified against published 2026 guidance. The no-income-tax list is the
    /// part that actually changes; the rest is stable.
    static let verifiedOn = "July 2026"

    private static let noIncomeTax: Set<String> = ["AK", "FL", "NV", "NH", "SD", "TN", "TX", "WA", "WY"]

    static let all: [USState] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"),
        ("CA", "California"), ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"),
        ("DC", "District of Columbia"), ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"),
        ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"), ("IA", "Iowa"),
        ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"),
        ("MD", "Maryland"), ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
        ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"),
        ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"),
        ("NY", "New York"), ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"),
        ("OK", "Oklahoma"), ("OR", "Oregon"), ("PA", "Pennsylvania"), ("RI", "Rhode Island"),
        ("SC", "South Carolina"), ("SD", "South Dakota"), ("TN", "Tennessee"), ("TX", "Texas"),
        ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"), ("WA", "Washington"),
        ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming")
    ].map { USState(code: $0.0, name: $0.1, hasIncomeTax: !noIncomeTax.contains($0.0)) }

    static func state(code: String) -> USState? {
        all.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

}
