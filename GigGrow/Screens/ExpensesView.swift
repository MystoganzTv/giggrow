//
//  ExpensesView.swift
//  GigGrow
//
//  Every expense, newest first, grouped by month.
//
//  The header splits the total two ways — what came out of the maintenance
//  reserve versus out of take-home — because those are genuinely different
//  kinds of money, and conflating them is what made net profit wrong.
//

import SwiftUI
import SwiftData

struct ExpensesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ggUsesWideLayout) private var usesWideLayout

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    /// True when this is a tab rather than a sheet.
    ///
    /// A tab has nowhere to be dismissed to, so the Done button has to go —
    /// it was the one control that would have done nothing at all.
    var embedded: Bool = false

    @State private var isAdding = false
    @State private var editing: Expense?

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.analyticsWash().ignoresSafeArea()

                if expenses.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(GG.Ink.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isAdding = true
                    } label: {
                        PlusGlyph()
                            .stroke(GG.Palette.violet400,
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .frame(width: 17, height: 17)
                    }
                }
            }
            .sheet(isPresented: $isAdding) { LogExpenseView() }
            .sheet(item: $editing) { LogExpenseView(editing: $0) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                summaryCard

                ForEach(months, id: \.key) { month in
                    monthSection(month)
                }
            }
            // A ledger needs a readable scan line. Letting every row stretch
            // across the whole iPad made dates, notes and amounts feel
            // disconnected from one another.
            .frame(
                maxWidth: usesWideLayout ? 680 : .infinity,
                alignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, GG.Layout.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "All time")
                    Text(Money.cents(total))
                        .ggText(GG.Typo.heroAmountSmall, tracking: GG.Typo.heroAmountSmallTracking)
                }

                // Two pots, stated separately.
                HStack(spacing: 22) {
                    splitStat("From reserve", reserveTotal, GG.Palette.blue400)
                    splitStat("Out of pocket", pocketTotal, GG.Palette.violet400)
                    Spacer(minLength: 0)
                }

                if total > 0 {
                    ProgressBar(
                        progress: reserveTotal / total,
                        height: 8,
                        fill: LinearGradient(colors: [GG.Palette.blue400, GG.Palette.blue400],
                                             startPoint: .leading, endPoint: .trailing),
                        track: GG.Palette.violet400.opacity(0.55)
                    )
                }
            }
        }
    }

    private func splitStat(_ label: String, _ value: Double, _ colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LegendDot(color: colour, label: label)
            Text(Money.whole(value))
                .ggText(.system(size: 19, weight: .semibold), tracking: -0.4)
        }
    }

    private func monthSection(_ month: (key: String, items: [Expense])) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(month.key.uppercased())
                    .ggText(GG.Typo.groupLabel,
                            tracking: GG.Typo.groupLabelTracking,
                            color: GG.Ink.muted)
                Spacer()
                Text(Money.whole(month.items.reduce(0) { $0 + $1.amount }))
                    .ggText(GG.Typo.captionMuted, color: GG.Ink.tertiary)
            }
            .padding(.horizontal, 6)

            GlassCard(radius: GG.Radius.tile,
                      padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(month.items.enumerated()), id: \.element.id) { index, expense in
                        row(expense)
                        if index < month.items.count - 1 {
                            RowDivider(color: GG.Surface.dividerSoft)
                        }
                    }
                }
            }
        }
    }

    private func row(_ expense: Expense) -> some View {
        Button {
            editing = expense
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(expense.category.drawsFromMaintenanceFund
                          ? GG.Palette.blue400 : GG.Palette.violet400)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.category.label)
                        .ggText(GG.Typo.rowLabel)
                    Text(subtitle(for: expense))
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                }

                Spacer(minLength: 8)

                // Which expenses could survive being questioned, visible
                // without opening any of them. An expense with no receipt
                // isn't wrong — it just rests on your word.
                if expense.hasReceipt {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GG.Ink.tertiary)
                        .accessibilityLabel("Receipt attached")
                }

                Text(Money.cents(expense.amount))
                    .ggText(.system(size: 16, weight: .semibold), tracking: -0.3)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `swipeActions` — that only works inside a List, and these rows
        // live in a ScrollView so they can keep the glass card styling.
        .contextMenu {
            Button("Edit") { editing = expense }
            Button("Delete", role: .destructive) { delete(expense) }
        }
    }

    private func delete(_ expense: Expense) {
        context.delete(expense)
        try? context.save()
    }

    private func subtitle(for expense: Expense) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        var parts = [f.string(from: expense.date)]
        if let note = expense.note, !note.isEmpty { parts.append(note) }
        if !expense.isDeductible { parts.append("not deductible") }
        return parts.joined(separator: " · ")
    }

    // MARK: Empty

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: GG.Layout.stackSpacing) {
                EmptyStateCard(
                    title: "No expenses yet",
                    message: "Fuel, insurance, a phone mount, a brake job. Logging them sharpens your net profit and your mileage deduction.",
                    actionTitle: "Add your first expense",
                    action: { isAdding = true }
                )

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Two kinds of money")
                            .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

                        HStack(alignment: .top, spacing: 11) {
                            Circle().fill(GG.Palette.blue400)
                                .frame(width: 7, height: 7).padding(.top, 6)
                            Text("Maintenance comes out of the reserve you've been building. It doesn't touch your take-home.")
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(alignment: .top, spacing: 11) {
                            Circle().fill(GG.Palette.violet400)
                                .frame(width: 7, height: 7).padding(.top, 6)
                            Text("Everything else is out of pocket, so it comes off your net profit.")
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(
                maxWidth: usesWideLayout ? 680 : .infinity,
                alignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, GG.Layout.screenInset)
            .padding(.top, 8)
        }
    }

    // MARK: Derived

    private var total: Double { expenses.reduce(0) { $0 + $1.amount } }

    private var reserveTotal: Double {
        expenses.filter { $0.category.drawsFromMaintenanceFund }.reduce(0) { $0 + $1.amount }
    }

    private var pocketTotal: Double { total - reserveTotal }

    /// Newest month first, preserving the query's ordering inside each group.
    private var months: [(key: String, items: [Expense])] {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"

        var order: [String] = []
        var buckets: [String: [Expense]] = [:]
        for expense in expenses {
            let key = f.string(from: expense.date)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(expense)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

#Preview("Expenses") {
    ExpensesView()
        .modelContainer(.preview)
}

#Preview("Expenses — empty") {
    ExpensesView()
        .modelContainer(.previewEmpty)
}
