//
//  TaxView.swift
//  GigGrow
//
//  What the year owes, and why.
//
//  Shown as arithmetic rather than a total. A driver who is handed "$4,200"
//  has no way to check it and no reason to believe it; a driver who can see
//  the mileage deduction come off the top understands both the number and
//  what to do about it — drive the same and log more miles.
//
//  Everything here is an estimate and the screen says so twice: once in the
//  header and once at the bottom, with the assumptions listed. This is the
//  only place in GigGrow where a figure might end up on a return.
//

import SwiftUI
import SwiftData

struct TaxView: View {
    /// True when this is a tab rather than a sheet. A tab has no Done button
    /// and no navigation bar of its own — it sits in the same scaffold as the
    /// other four screens.
    var embedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Shift.start) private var shifts: [Shift]
    @Query private var expenses: [Expense]
    @Query private var drives: [DriveRecord]
    @Query private var profiles: [DriverProfile]

    @State private var year: Int = Calendar.gigGrow.component(.year, from: .now)
    @State private var isEditingStateRate = false

    private var profile: DriverProfile? { profiles.first }

    var body: some View {
        if embedded { tab } else { sheet }
    }

    /// Tab form: the app's own scaffold, matching the other four screens.
    private var tab: some View {
        ScreenScaffold {
            GG.Gradients.settingsWash()
        } content: {
            Text("Taxes")
                .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)

            yearPicker
            headline
            workingOut
            breakdown
            setAsideAdvice
            assumptions
        }
        .sheet(isPresented: $isEditingStateRate) { stateRateEditor }
    }

    private var sheet: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.settingsWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                        yearPicker
                        headline
                        workingOut
                        breakdown
                        setAsideAdvice
                        assumptions
                    }
                    .padding(.horizontal, GG.Layout.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Tax estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GG.Ink.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isEditingStateRate) { stateRateEditor }
    }

    @ViewBuilder
    private var stateRateEditor: some View {
        if let profile {
            StepperEditor(
                title: "State income tax",
                explanation: "State tax varies by bracket, city and filing status, so GigGrow doesn't guess it. Look up your state's rate for your income — or ask whoever files for you — and put it here. States with no income tax use 0.",
                unit: "percent",
                value: Int(profile.stateIncomeTaxRate),
                bounds: 0...15
            ) { profile.stateIncomeTaxRate = Double($0); try? context.save() }
        }
    }

    // MARK: Year

    private var yearPicker: some View {
        HStack(spacing: 12) {
            ForEach(availableYears, id: \.self) { candidate in
                let isSelected = candidate == year
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { year = candidate }
                } label: {
                    Text(String(candidate))
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : GG.Ink.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isSelected ? AnyShapeStyle(GG.Gradients.segment)
                                               : AnyShapeStyle(GG.Surface.glassFaint),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Headline

    private var headline: some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Estimated tax for \(String(year))",
                        color: Color.white.opacity(0.55))

                Text(Money.cents(estimate.totalTax))
                    .ggText(GG.Typo.heroAmountSmall, tracking: GG.Typo.heroAmountSmallTracking)

                // The rate that matters: what share of everything you took in
                // ends up as tax. Usually far below the 30% drivers are told
                // to hold back, because the mileage deduction got there first.
                Text(estimate.gross > 0
                     ? "\(Int((estimate.effectiveRate * 100).rounded()))% of \(Money.whole(estimate.gross)) earned"
                     : "Nothing recorded for this year yet")
                    .ggText(GG.Typo.footnote, color: Color.white.opacity(0.6))
            }
        }
    }

    // MARK: The arithmetic

    private var workingOut: some View {
        GlassCard {
            VStack(spacing: 0) {
                Text("How it gets there")
                    .ggText(GG.Typo.cardTitle, tracking: GG.Typo.cardTitleTracking)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)

                line("Gross earnings", estimate.gross)
                deduction("Mileage deduction",
                          estimate.mileageDeduction,
                          note: String(format: "%.0f business miles", estimate.businessMiles))
                deduction("Deductible expenses", estimate.expenses, note: nil)

                RowDivider(color: GG.Surface.divider)
                line("Net business income", estimate.netBusinessIncome, emphasised: true)
            }
        }
    }

    private var breakdown: some View {
        GlassCard {
            VStack(spacing: 0) {
                Text("What's owed on it")
                    .ggText(GG.Typo.cardTitle, tracking: GG.Typo.cardTitleTracking)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)

                taxLine("Self-employment tax", estimate.selfEmploymentTax,
                        note: "15.3% — both halves of Social Security and Medicare. As an employee you only ever saw half.")
                taxLine("Federal income tax", estimate.federalTax,
                        note: estimate.taxableIncome > 0
                            ? "On \(Money.whole(estimate.taxableIncome)) after the standard deduction and the 20% QBI deduction."
                            : "The deductions cover it — nothing federal is owed on this.")

                Button { isEditingStateRate = true } label: {
                    taxLine("State income tax", estimate.stateTax,
                            note: estimate.stateRate > 0
                                ? "At \(Int(estimate.stateRate))%. Tap to change."
                                : "Set to 0%. Tap to set your state's rate.",
                            isTappable: true)
                }
                .buttonStyle(.plain)

                RowDivider(color: GG.Surface.divider)
                line("Left after tax", estimate.netAfterTax, emphasised: true, tint: GG.Palette.mint)
            }
        }
    }

    /// Turns the estimate into the only instruction that matters.
    private var setAsideAdvice: some View {
        GlassCard(radius: GG.Radius.tile,
                  padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
            HStack(alignment: .top, spacing: 11) {
                Circle().fill(GG.Palette.violet400)
                    .frame(width: 6, height: 6).padding(.top, 7)
                VStack(alignment: .leading, spacing: 4) {
                    Text(adviceTitle)
                        .ggText(.system(size: 13.5, weight: .semibold))
                    Text(adviceBody)
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var adviceTitle: String {
        guard estimate.gross > 0 else { return "Set aside as you go" }
        let suggested = Int((estimate.effectiveRate * 100).rounded())
        return "Hold back about \(suggested)% of what you take in"
    }

    private var adviceBody: String {
        guard estimate.gross > 0 else {
            return "Import a few weeks and this will work out what you actually owe rather than guessing a percentage."
        }
        let current = Int(profile?.taxRate ?? 25)
        let suggested = Int((estimate.effectiveRate * 100).rounded())

        if suggested < current - 2 {
            return "You're holding back \(current)%, which is more than this year needs — the mileage deduction has done most of the work. The extra isn't wasted, but it's money sitting idle."
        }
        if suggested > current + 2 {
            return "You're holding back \(current)%, which looks short. Estimated payments are due quarterly, and the gap compounds if it isn't caught until April."
        }
        return "Your \(current)% set-aside is about right for this year."
    }

    private var assumptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This is an estimate, not a filing.")
                .ggText(.system(size: 12.5, weight: .semibold), color: GG.Ink.secondary)
            Text("Worked out for a single filer taking the standard deduction, with no other household income, no dependants or credits, and earnings below the Social Security wage cap. Federal figures are the IRS's published \(String(estimate.year)) brackets, checked \(TaxTables.table(for: year).verifiedOn). Your own return will differ — this is for knowing what to set aside, not for filing.")
                .ggText(GG.Typo.footnote, color: GG.Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }

    // MARK: Rows

    private func line(_ label: String, _ amount: Double,
                      emphasised: Bool = false, tint: Color? = nil) -> some View {
        HStack {
            Text(label)
                .ggText(emphasised ? .system(size: 15.5, weight: .semibold) : GG.Typo.rowLabel)
            Spacer(minLength: 12)
            Text(Money.cents(amount))
                .ggText(.system(size: emphasised ? 16 : 15, weight: .semibold), tracking: -0.3,
                        color: tint ?? GG.Ink.primary)
        }
        .padding(.vertical, 13)
    }

    private func deduction(_ label: String, _ amount: Double, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .ggText(GG.Typo.rowLabel, color: GG.Ink.secondary)
                Spacer(minLength: 12)
                // Written as a subtraction, because that's what it is and
                // seeing it come off is the point of the screen.
                Text("−" + Money.cents(amount))
                    .ggText(.system(size: 15, weight: .semibold), tracking: -0.3,
                            color: GG.Palette.mint)
            }
            if let note {
                Text(note)
                    .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
            }
        }
        .padding(.vertical, 13)
    }

    private func taxLine(_ label: String, _ amount: Double,
                         note: String, isTappable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .ggText(GG.Typo.rowLabel)
                if isTappable {
                    Chevron(size: 12, color: Color.white.opacity(0.25))
                }
                Spacer(minLength: 12)
                Text("−" + Money.cents(amount))
                    .ggText(.system(size: 15, weight: .semibold), tracking: -0.3,
                            color: Color(hex: 0xFB7185))
            }
            Text(note)
                .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: Data

    private var availableYears: [Int] {
        let calendar = Calendar.gigGrow
        let thisYear = calendar.component(.year, from: .now)
        let found = Set(shifts.map { calendar.component(.year, from: $0.start) })
        return Array(found.union([thisYear])).sorted(by: >).prefix(4).map { $0 }
    }

    private var estimate: TaxEstimate {
        let calendar = Calendar.gigGrow
        let inYear = { (date: Date) in calendar.component(.year, from: date) == year }

        let gross = shifts.filter { inYear($0.start) }.reduce(0) { $0 + $1.gross }
        let businessMiles = drives
            .filter { inYear($0.start) && $0.purpose.isDeductible }
            .reduce(0) { $0 + $1.miles }

        // Maintenance-fund spending is already covered by the reserve, so
        // counting it here as well would deduct it twice — the same mistake
        // net profit made before it was fixed.
        let deductible = expenses
            .filter { inYear($0.date) && $0.isDeductible }
            .reduce(0) { $0 + $1.amount }

        return TaxEstimate.build(
            year: year,
            gross: gross,
            businessMiles: businessMiles,
            mileageRate: rateToApply,
            deductibleExpenses: deductible,
            stateRate: profile?.stateIncomeTaxRate ?? 0
        )
    }

    /// The driver's own rate when they set one, otherwise the IRS figure for
    /// mid-year.
    ///
    /// Written out rather than inline: `profile?.mileageRate ?? 0 > 0` parses
    /// as `profile?.mileageRate ?? (0 > 0)` — `??` binds looser than `>` — so
    /// it was comparing a Double against a Bool and would not compile.
    private var rateToApply: Double {
        let override = profile?.mileageRate ?? 0
        return override > 0 ? override : MileageRates.rate(on: midYear)
    }

    /// Mid-year, so a year spanning a rate change lands between the two
    /// rather than on whichever end happened to be picked.
    private var midYear: Date {
        Calendar.gigGrow.date(from: DateComponents(year: year, month: 7, day: 1)) ?? .now
    }
}

#Preview("Tax estimate") {
    TaxView()
        .modelContainer(.preview)
}
