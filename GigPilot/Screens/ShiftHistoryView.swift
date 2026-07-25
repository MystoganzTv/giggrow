//
//  ShiftHistoryView.swift
//  GigPilot
//
//  Every shift logged, newest first, grouped by week.
//
//  This closes the app's worst gap: shifts were write-only. A mistyped gross
//  was permanent and poisoned the hourly rate, the tax set-aside, the reserve
//  and every chart, with no way back to the row that caused it.
//

import SwiftUI
import SwiftData

struct ShiftHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]

    @State private var isAdding = false
    @State private var editing: Shift?
    @State private var pendingDelete: Shift?

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.dashboardWash().ignoresSafeArea()

                if shifts.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Shifts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isAdding = true
                    } label: {
                        PlusGlyph()
                            .stroke(GP.Palette.violet400,
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .frame(width: 17, height: 17)
                    }
                }
            }
            .sheet(isPresented: $isAdding) { LogShiftView() }
            .sheet(item: $editing) { LogShiftView(editing: $0) }
            // Deleting a shift throws away real money data, so it asks first.
            .confirmationDialog(
                "Delete this shift?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let shift = pendingDelete { delete(shift) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                if let shift = pendingDelete {
                    Text("\(Money.cents(shift.gross)) across \(shift.platformCount) app\(shift.platformCount == 1 ? "" : "s") will be removed from your totals.")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                summaryCard

                ForEach(weeks, id: \.key) { week in
                    weekSection(week)
                }
            }
            .padding(.horizontal, GP.Layout.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "All time")
                    Text(Money.cents(totalGross))
                        .gpText(GP.Typo.heroAmountSmall, tracking: GP.Typo.heroAmountSmallTracking)
                }

                HStack(spacing: 24) {
                    stat("Shifts", "\(shifts.count)")
                    stat("Hours", String(format: "%.0f", totalHours))
                    stat("Miles", Num.grouped(Int(totalMiles.rounded())))
                    if totalHours > 0 {
                        stat("Per hour", Money.cents(totalGross / totalHours))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .gpText(.system(size: 10, weight: .semibold), tracking: 1.0, color: GP.Ink.eyebrow)
            Text(value)
                .gpText(.system(size: 17, weight: .semibold), tracking: -0.3)
        }
    }

    private func weekSection(_ week: (key: String, items: [Shift])) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(week.key.uppercased())
                    .gpText(GP.Typo.groupLabel,
                            tracking: GP.Typo.groupLabelTracking,
                            color: GP.Ink.muted)
                Spacer()
                Text(Money.whole(week.items.reduce(0) { $0 + $1.gross }))
                    .gpText(GP.Typo.captionMuted, color: GP.Ink.tertiary)
            }
            .padding(.horizontal, 6)

            GlassCard(radius: GP.Radius.tile,
                      padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(week.items.enumerated()), id: \.element.id) { index, shift in
                        row(shift)
                        if index < week.items.count - 1 {
                            RowDivider(color: GP.Surface.dividerSoft)
                        }
                    }
                }
            }
        }
    }

    private func row(_ shift: Shift) -> some View {
        Button {
            editing = shift
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dayLabel(shift.start))
                        .gpText(GP.Typo.rowLabel)
                    Spacer(minLength: 8)
                    Text(Money.cents(shift.gross))
                        .gpText(.system(size: 16, weight: .semibold), tracking: -0.3)
                }

                HStack(spacing: 10) {
                    Text(detailLine(shift))
                        .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                    Spacer(minLength: 0)
                }

                // Which apps ran, as the same brand dots used everywhere else.
                if !shift.earnings.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(shift.earnings.enumerated()), id: \.element.id) { _, earning in
                            if let account = earning.account {
                                Text(account.initial)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(hex: account.gradientStart),
                                                     Color(hex: account.gradientEnd)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    )
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") { editing = shift }
            Button("Delete", role: .destructive) { pendingDelete = shift }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dayLabel(shift.start)), \(Money.cents(shift.gross)), \(detailLine(shift))")
        .accessibilityHint("Double tap to edit this shift")
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"
        return f.string(from: date)
    }

    private func detailLine(_ shift: Shift) -> String {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        var parts = ["\(time.string(from: shift.start))–\(time.string(from: shift.end))"]
        parts.append(String(format: "%.1f hrs", shift.hours))
        if shift.miles > 0 { parts.append("\(Int(shift.miles.rounded())) mi") }
        if shift.tripCount > 0 { parts.append("\(shift.tripCount) units") }
        return parts.joined(separator: " · ")
    }

    // MARK: Empty

    private var emptyState: some View {
        ScrollView {
            EmptyStateCard(
                title: "No shifts logged",
                message: "Every shift you log shows up here, so you can come back and fix a number rather than living with it.",
                actionTitle: "Log your first shift",
                action: { isAdding = true },
                showsLogo: true
            )
            .padding(.horizontal, GP.Layout.screenInset)
            .padding(.top, 8)
        }
    }

    // MARK: Data

    private var totalGross: Double { shifts.reduce(0) { $0 + $1.gross } }
    private var totalHours: Double { shifts.reduce(0) { $0 + $1.hours } }
    private var totalMiles: Double { shifts.reduce(0) { $0 + $1.miles } }

    /// Newest week first. Labelled by the Monday that starts it.
    private var weeks: [(key: String, items: [Shift])] {
        let cal = Calendar.gigPilot
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"

        var order: [String] = []
        var buckets: [String: [Shift]] = [:]
        for shift in shifts {
            let start = cal.startOfWeek(for: shift.start)
            let key = "Week of \(f.string(from: start))"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(shift)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// Removes the shift and its earnings. The relationship is cascade-delete,
    /// but the earnings are detached first so nothing is left pointing at a
    /// deleted object mid-transaction.
    private func delete(_ shift: Shift) {
        let earnings = shift.earnings
        shift.earnings = []
        for earning in earnings { context.delete(earning) }
        context.delete(shift)
        try? context.save()
    }
}

#Preview("Shift history") {
    ShiftHistoryView()
        .modelContainer(.preview)
}

#Preview("Shift history — empty") {
    ShiftHistoryView()
        .modelContainer(.previewEmpty)
}
