//
//  ShiftHistoryView.swift
//  GigGrow
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

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.dashboardWash().ignoresSafeArea()

                if shifts.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Earnings history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GG.Ink.secondary)
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
            .sheet(isPresented: $isAdding) { LogShiftView() }
            .sheet(item: $editing) { LogShiftView(editing: $0) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: List

    private var list: some View {
        List {
            Section {
                summaryCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: GG.Layout.screenInset,
                                              bottom: 8, trailing: GG.Layout.screenInset))
            }

            ForEach(weeks) { week in
                Section {
                    ForEach(week.days) { day in
                        dayHeader(day)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 12, leading: GG.Layout.screenInset,
                                                      bottom: 5, trailing: GG.Layout.screenInset))

                        ForEach(day.items) { shift in
                            row(shift)
                                .listRowBackground(GG.Surface.glass)
                                .listRowSeparatorTint(GG.Surface.dividerSoft)
                                .listRowInsets(EdgeInsets(top: 0, leading: GG.Layout.screenInset,
                                                          bottom: 0, trailing: GG.Layout.screenInset))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(shift)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        editing = shift
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(GG.Palette.violet500)
                                }
                        }
                    }
                } header: {
                    weekHeader(week)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "All time")
                    Text(Money.cents(totalGross))
                        .ggText(GG.Typo.heroAmountSmall, tracking: GG.Typo.heroAmountSmallTracking)
                }

                HStack(spacing: 24) {
                    stat("Days", "\(earningDayCount)")
                    stat("Time", Hours.clock(totalHours))
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
                .ggText(.system(size: 10, weight: .semibold), tracking: 1.0, color: GG.Ink.eyebrow)
            Text(value)
                .ggText(.system(size: 17, weight: .semibold), tracking: -0.3)
        }
    }

    private func weekHeader(_ week: HistoryWeek) -> some View {
        HStack {
            Text(week.key.uppercased())
                .ggText(GG.Typo.groupLabel,
                        tracking: GG.Typo.groupLabelTracking,
                        color: GG.Ink.muted)
            Spacer()
            Text(Money.whole(week.items.reduce(0) { $0 + $1.gross }))
                .ggText(GG.Typo.captionMuted, color: GG.Ink.tertiary)
        }
    }

    private func dayHeader(_ day: HistoryDay) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(dayLabel(day.date))
                .ggText(GG.Typo.rowLabel)
            Spacer(minLength: 8)
            Text(day.isEstimated
                 ? Money.whole(day.gross)
                 : Money.cents(day.gross))
                .ggText(.system(size: 16, weight: .semibold), tracking: -0.3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dayLabel(day.date)), \(Money.cents(day.gross))")
    }

    private func row(_ shift: Shift) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ForEach(Array(shift.earnings.enumerated()), id: \.element.id) { _, earning in
                    if let account = earning.account {
                        Text(account.initial)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: account.gradientStart),
                                             Color(hex: account.gradientEnd)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                }
                Text(platformNames(shift))
                    .ggText(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                Text(isWeeklyEstimate(shift)
                     ? Money.whole(shift.gross)
                     : Money.cents(shift.gross))
                    .ggText(.system(size: 14, weight: .semibold),
                            color: GG.Ink.secondary)
            }

            HStack(spacing: 10) {
                Text(detailLine(shift))
                    .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 14)
        // A Button plus a context menu made three recognizers compete with
        // List's native horizontal swipe. A plain row lets swipeActions win
        // immediately while a completed tap still opens the editor.
        .contentShape(Rectangle())
        .onTapGesture { editing = shift }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(platformNames(shift)), \(Money.cents(shift.gross)), \(detailLine(shift))")
        .accessibilityHint("Double tap to edit this shift")
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"
        return f.string(from: date)
    }

    private func detailLine(_ shift: Shift) -> String {
        var parts: [String]
        if isWeeklyEstimate(shift) {
            // The report confirms weekly hours and rides, not daily ones.
            // Their internal allocation conserves the weekly totals and rate,
            // but exposing it here would make a calculation look observed.
            parts = ["Estimated from weekly chart"]
        } else if shift.isAggregate {
            parts = ["Weekly total", Hours.clock(shift.hours)]
        } else {
            let time = DateFormatter()
            time.dateFormat = "HH:mm"
            parts = [
                "\(time.string(from: shift.start))–\(time.string(from: shift.end))",
                Hours.clock(shift.hours)
            ]
        }
        if shift.miles > 0 { parts.append("\(Int(shift.miles.rounded())) mi") }
        if !isWeeklyEstimate(shift), let work = workLabel(for: shift) {
            parts.append(work)
        }
        return parts.joined(separator: " · ")
    }

    private func isWeeklyEstimate(_ shift: Shift) -> Bool {
        shift.note?.hasPrefix("From a weekly screenshot") == true
    }

    private func platformNames(_ shift: Shift) -> String {
        let names = shift.earnings.compactMap { $0.account?.name }
        return names.isEmpty ? "Manual entry" : names.joined(separator: " + ")
    }

    /// Use each platform's own vocabulary. Lyft reports rides; Uber reports
    /// trips; delivery apps may report orders, batches or blocks. A generic
    /// "unit" hides information we already have on the earning record.
    private func workLabel(for shift: Shift) -> String? {
        let earnings = shift.earnings.filter { $0.trips > 0 }
        guard !earnings.isEmpty else { return nil }

        let nouns = Set(earnings.compactMap { $0.account?.unitNoun.lowercased() })
        if nouns.count == 1, let noun = nouns.first {
            let count = earnings.reduce(0) { $0 + $1.trips }
            return "\(count) \(inflected(noun, count: count))"
        }

        return earnings.map { earning in
            let noun = earning.account?.unitNoun.lowercased() ?? "units"
            let prefix = earning.account?.short ?? "App"
            return "\(prefix): \(earning.trips) \(inflected(noun, count: earning.trips))"
        }
        .joined(separator: ", ")
    }

    private func inflected(_ plural: String, count: Int) -> String {
        guard count == 1 else { return plural }
        let known: [String: String] = [
            "trips": "trip",
            "rides": "ride",
            "orders": "order",
            "batches": "batch",
            "blocks": "block",
            "deliveries": "delivery",
            "units": "unit"
        ]
        return known[plural] ?? (plural.hasSuffix("s") ? String(plural.dropLast()) : plural)
    }

    // MARK: Empty

    private var emptyState: some View {
        ScrollView {
            EmptyStateCard(
                title: "No earnings logged",
                message: "Imported reports and shifts you log appear here, so you can always trace or correct a number.",
                actionTitle: "Log your first shift",
                action: { isAdding = true },
                showsLogo: true
            )
            .padding(.horizontal, GG.Layout.screenInset)
            .padding(.top, 8)
        }
    }

    // MARK: Data

    private var totalGross: Double { shifts.reduce(0) { $0 + $1.gross } }
    private var totalHours: Double { shifts.reduce(0) { $0 + $1.hours } }
    private var totalMiles: Double { shifts.reduce(0) { $0 + $1.miles } }
    private var earningDayCount: Int {
        Set(shifts.map { Calendar.gigGrow.startOfDay(for: $0.start) }).count
    }

    /// Newest week first. Labelled by the Monday that starts it.
    private var weeks: [HistoryWeek] {
        let cal = Calendar.gigGrow
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"

        var order: [Date] = []
        var buckets: [Date: [Shift]] = [:]
        for shift in shifts {
            let start = cal.startOfWeek(for: shift.start)
            if buckets[start] == nil { order.append(start) }
            buckets[start, default: []].append(shift)
        }
        return order.map { start in
            HistoryWeek(
                start: start,
                key: "Week of \(f.string(from: start))",
                items: buckets[start] ?? [],
                calendar: cal
            )
        }
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

private struct HistoryWeek: Identifiable {
    let start: Date
    let key: String
    let items: [Shift]
    let days: [HistoryDay]

    var id: Date { start }

    init(start: Date, key: String, items: [Shift], calendar: Calendar) {
        self.start = start
        self.key = key
        self.items = items

        let grouped = Dictionary(grouping: items) {
            calendar.startOfDay(for: $0.start)
        }
        self.days = grouped.keys.sorted(by: >).map {
            HistoryDay(date: $0, items: grouped[$0] ?? [])
        }
    }
}

private struct HistoryDay: Identifiable {
    let date: Date
    let items: [Shift]

    var id: Date { date }
    var gross: Double { items.reduce(0) { $0 + $1.gross } }
    var isEstimated: Bool {
        !items.isEmpty && items.allSatisfy {
            $0.note?.hasPrefix("From a weekly screenshot") == true
        }
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
