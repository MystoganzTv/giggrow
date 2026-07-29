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
    @State private var previewingReceipt: Expense?
    @State private var filter: ExpenseFilter = .all

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
            .fullScreenCover(item: $previewingReceipt) { expense in
                if let data = expense.receiptImage,
                   let image = UIImage(data: data) {
                    ReceiptViewer(
                        image: image,
                        title: expense.merchant ?? expense.category.label,
                        detail: receiptDetail(for: expense)
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                summaryCard

                Picker("Expense evidence", selection: $filter) {
                    ForEach(ExpenseFilter.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Filters expenses by whether a receipt photo is saved")

                if filteredExpenses.isEmpty {
                    GlassCard {
                        Text(filter.emptyMessage)
                            .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(months, id: \.key) { month in
                        monthSection(month)
                    }
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

                RowDivider(color: GG.Surface.dividerSoft)

                HStack(spacing: 10) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GG.Palette.violet300)
                    Text("\(receiptCount) receipt\(receiptCount == 1 ? "" : "s") saved")
                        .ggText(.system(size: 13.5, weight: .semibold))
                    Spacer(minLength: 8)
                    if missingReceiptCount > 0 {
                        Text("\(missingReceiptCount) without photo")
                            .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                    }
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
        HStack(spacing: 12) {
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Which expenses could survive being questioned, visible
            // without opening any of them. An expense with no receipt
            // isn't wrong — it just rests on your word.
            if expense.hasReceipt {
                Button {
                    previewingReceipt = expense
                } label: {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GG.Palette.violet300)
                        .frame(width: 34, height: 34)
                        .background(GG.Palette.violet500.opacity(0.13),
                                    in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View receipt")
            }

            Text(Money.cents(expense.amount))
                .ggText(.system(size: 16, weight: .semibold), tracking: -0.3)
        }
        .padding(.vertical, 10)
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

    private func receiptDetail(for expense: Expense) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: expense.date)) · \(Money.cents(expense.amount))"
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

    private var receiptCount: Int { expenses.filter(\.hasReceipt).count }

    private var missingReceiptCount: Int { expenses.count - receiptCount }

    private var filteredExpenses: [Expense] {
        switch filter {
        case .all:
            return expenses
        case .receipts:
            return expenses.filter(\.hasReceipt)
        case .missing:
            return expenses.filter { !$0.hasReceipt }
        }
    }

    /// Newest month first, preserving the query's ordering inside each group.
    private var months: [(key: String, items: [Expense])] {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"

        var order: [String] = []
        var buckets: [String: [Expense]] = [:]
        for expense in filteredExpenses {
            let key = f.string(from: expense.date)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(expense)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

private enum ExpenseFilter: String, CaseIterable, Identifiable {
    case all
    case receipts
    case missing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:      return "All"
        case .receipts: return "Receipts"
        case .missing:  return "Missing"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all:
            return "No expenses yet."
        case .receipts:
            return "No receipt photos are saved yet. Open an expense to photograph or choose its receipt."
        case .missing:
            return "Every expense has a receipt photo saved."
        }
    }
}

/// Full-screen evidence viewer shared by saved and newly selected receipts.
///
/// The expense row remains an edit action. Its receipt button opens this
/// viewer directly, so checking a merchant or line item cannot accidentally
/// change the accounting record.
struct ReceiptViewer: View {
    let image: UIImage
    let title: String
    let detail: String

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(zoomGesture.simultaneously(with: dragGesture))
                .onTapGesture(count: 2, perform: toggleZoom)
                .accessibilityLabel("Receipt image")

            VStack(spacing: 0) {
                HStack {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.62))
                    Text("Pinch or double-tap to zoom")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(settledScale * value.magnification, 1), 5)
            }
            .onEnded { _ in
                settledScale = scale
                if scale == 1 { resetPosition() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                settledOffset = offset
            }
    }

    private func toggleZoom() {
        if scale > 1 {
            scale = 1
            settledScale = 1
            resetPosition()
        } else {
            scale = 2.5
            settledScale = 2.5
        }
    }

    private func resetPosition() {
        offset = .zero
        settledOffset = .zero
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
