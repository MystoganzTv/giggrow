//
//  TaxEstimate.swift
//  GigGrow
//
//  What a year of driving actually owes.
//
//  GigGrow's "tax set-aside" was a flat percentage the driver typed in. That
//  is fine as a savings rule and useless as an answer, because it ignores the
//  three things that decide a gig driver's bill:
//
//  1. Self-employment tax. 15.3% on top of income tax, covering both halves
//     of Social Security and Medicare. It is the number that blindsides
//     first-year drivers, because as an employee they only ever saw half of
//     it and never on a payslip line of their own.
//  2. The mileage deduction. It comes off income *before* tax, so 10,000
//     business miles at 76¢ removes $7,600 from the base. For most drivers
//     it is the single biggest thing standing between gross and taxable.
//  3. The QBI deduction — 20% of qualified business income, which gig work
//     is. Nobody sets that aside because nobody mentions it.
//
//  Every figure here is a published, dated constant with its source, and the
//  whole thing is presented as an estimate. This is the one place in the app
//  where a number might end up on a return, so it says what it assumes and
//  what it leaves out rather than implying it is a filing.
//
//  Assumptions, stated once and surfaced in the UI:
//  - Single filer, standard deduction, no other household income.
//  - Income below the Social Security wage cap, so SE tax is a flat 15.3%.
//  - No dependants, credits, or itemising.
//
//  Sources:
//  - Federal brackets and standard deduction: IRS Rev. Proc. 2025-32, via
//    Tax Foundation's 2026 tables.
//  - SE tax rates and the 92.35% base: IRS Schedule SE.
//

import Foundation

// MARK: - Tax year

/// One year's published parameters. Dated, so last year's return doesn't get
/// this year's brackets applied to it.
struct TaxYear {
    let year: Int
    /// Upper bound of each bracket and the rate that applies within it.
    /// The last entry's bound is infinite.
    let brackets: [(upTo: Double, rate: Double)]
    let standardDeduction: Double
    /// When these were last checked against the source.
    let verifiedOn: String

    /// Progressive tax on `taxableIncome` — each slice at its own rate, not
    /// the whole amount at the top rate. Getting that wrong is the most
    /// common misunderstanding about brackets and would overstate the bill
    /// by thousands.
    func federalTax(on taxableIncome: Double) -> Double {
        guard taxableIncome > 0 else { return 0 }
        var remaining = taxableIncome
        var previousBound: Double = 0
        var total: Double = 0

        for bracket in brackets {
            let width = bracket.upTo - previousBound
            let taxedHere = min(remaining, width)
            guard taxedHere > 0 else { break }
            total += taxedHere * bracket.rate
            remaining -= taxedHere
            previousBound = bracket.upTo
        }
        return total
    }
}

enum TaxTables {

    /// 2026, single filer. IRS Revenue Procedure 2025-32.
    static let year2026 = TaxYear(
        year: 2026,
        brackets: [
            (upTo:  12_400, rate: 0.10),
            (upTo:  50_400, rate: 0.12),
            (upTo: 105_700, rate: 0.22),
            (upTo: 201_775, rate: 0.24),
            (upTo: 256_225, rate: 0.32),
            (upTo: 640_600, rate: 0.35),
            (upTo: .infinity, rate: 0.37)
        ],
        standardDeduction: 16_100,
        verifiedOn: "July 2026"
    )

    /// 2025, single filer. Kept so a prior-year total isn't recomputed with
    /// this year's numbers.
    static let year2025 = TaxYear(
        year: 2025,
        brackets: [
            (upTo:  11_925, rate: 0.10),
            (upTo:  48_475, rate: 0.12),
            (upTo: 103_350, rate: 0.22),
            (upTo: 197_300, rate: 0.24),
            (upTo: 250_525, rate: 0.32),
            (upTo: 626_350, rate: 0.35),
            (upTo: .infinity, rate: 0.37)
        ],
        standardDeduction: 15_750,
        verifiedOn: "July 2026"
    )

    /// Every year GigGrow has verified figures for, newest first.
    ///
    /// 2025 is the earliest on purpose. Going further back means finding and
    /// checking a full bracket table per year, and a half-remembered one is
    /// worse than none here — the number leaves this screen and goes on a
    /// return. Adding a year is adding a struct to this array; nothing else
    /// needs to change.
    static let all: [TaxYear] = [year2026, year2025]

    /// The most recent year with real figures.
    static var latest: TaxYear { all[0] }

    /// The earliest year the app will let you select.
    static var earliestYear: Int { all.last?.year ?? latest.year }

    static func isVerified(_ year: Int) -> Bool { table(for: year) != nil }

    /// Nil for a year we don't have verified figures for.
    ///
    /// This used to be `default: return year2026`, which meant asking for
    /// 2023 got you 2026's brackets and 2026's standard deduction under a
    /// 2023 heading — a wrong tax figure returned with no indication that
    /// anything was missing. On this screen that is the worst possible
    /// failure: nobody checks a number that looks plausible, and the mistake
    /// only surfaces when someone files on it.
    static func table(for year: Int) -> TaxYear? {
        all.first { $0.year == year }
    }

    // MARK: Self-employment

    /// Schedule SE: only 92.35% of net earnings is subject to SE tax.
    static let selfEmploymentBase = 0.9235
    /// 12.4% Social Security + 2.9% Medicare.
    static let selfEmploymentRate = 0.153
    /// Half of SE tax comes off income before federal tax is worked out.
    static let selfEmploymentDeductibleShare = 0.5
    /// Qualified Business Income deduction — 20% for anyone under the
    /// phase-in threshold, which is every driver this app is built for.
    static let qbiRate = 0.20
}

// MARK: - Estimate

/// A worked-through estimate, keeping every intermediate figure so the screen
/// can show the arithmetic rather than a total the driver has to trust.
struct TaxEstimate {
    let year: Int
    let gross: Double
    let businessMiles: Double
    let mileageDeduction: Double
    let expenses: Double

    let netBusinessIncome: Double
    let selfEmploymentTax: Double
    let qbiDeduction: Double
    let taxableIncome: Double
    let federalTax: Double
    let stateTax: Double
    let stateRate: Double

    var totalTax: Double { federalTax + stateTax + selfEmploymentTax }
    var netAfterTax: Double { netBusinessIncome - totalTax }

    /// What share of gross ends up as tax. The number worth setting aside,
    /// and usually well below the flat 25–30% drivers are told to hold back —
    /// because the mileage deduction has already done most of the work.
    var effectiveRate: Double { gross > 0 ? totalTax / gross : 0 }

    /// Built from figures the app already has.
    ///
    /// `stateRate` is the driver's own setting rather than a table: state
    /// income tax varies by bracket, city and filing status in ways a single
    /// national table would get wrong more often than right, and a confident
    /// wrong figure is worse here than an honest editable one.
    static func build(year: Int,
                      gross: Double,
                      businessMiles: Double,
                      mileageRate: Double,
                      deductibleExpenses: Double,
                      stateRate: Double) -> TaxEstimate {

        // A year past the last published table — January 2027 on a copy of
        // the app that shipped in 2026 — falls back to the newest figures
        // rather than to nothing. The screen says so; see `usesEstimatedYear`
        // in TaxView. Silently substituting them without saying is what the
        // old `default: return year2026` did, and that is the version of this
        // that gets someone into trouble.
        let table = TaxTables.table(for: year) ?? TaxTables.latest

        let mileageDeduction = businessMiles * mileageRate
        // Floored at zero: a loss is a real thing on a return, but showing a
        // negative tax bill here would be a promise this app can't make.
        let net = max(gross - mileageDeduction - deductibleExpenses, 0)

        let seTax = net * TaxTables.selfEmploymentBase * TaxTables.selfEmploymentRate
        let halfSE = seTax * TaxTables.selfEmploymentDeductibleShare

        // QBI is taken on business income after the SE deduction.
        let qbiBase = max(net - halfSE, 0)
        let qbi = qbiBase * TaxTables.qbiRate

        let taxable = max(net - halfSE - qbi - table.standardDeduction, 0)
        let federal = table.federalTax(on: taxable)

        // State tax on business income, not on the federally taxable figure:
        // most states start from federal AGI, and AGI here is net minus the
        // SE deduction — before the standard deduction.
        let state = max(net - halfSE, 0) * stateRate / 100

        return TaxEstimate(
            year: year,
            gross: gross,
            businessMiles: businessMiles,
            mileageDeduction: mileageDeduction,
            expenses: deductibleExpenses,
            netBusinessIncome: net,
            selfEmploymentTax: seTax,
            qbiDeduction: qbi,
            taxableIncome: taxable,
            federalTax: federal,
            stateTax: state,
            stateRate: stateRate
        )
    }
}
