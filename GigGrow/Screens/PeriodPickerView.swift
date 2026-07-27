//
//  PeriodPickerView.swift
//  GigGrow
//
//  Jump straight to a period instead of stepping to it.
//
//  Arrows are fine for "last week" and useless for "that good month in
//  spring" — eleven taps, each one a full rebuild, with no idea whether the
//  destination has anything in it. Uber and Lyft both make the date header
//  tappable and list the periods; this does the same, and adds the thing
//  their lists don't have: what you earned in each one, so you can pick by
//  the number rather than by the date.
//
//  Only periods with data are listed, plus the current one. A list padded
//  with empty weeks is a list you have to read past.
//

import SwiftUI
import SwiftData

struct PeriodPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: RangeSelection
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()

                if periods.isEmpty {
                    ScrollView {
                        EmptyStateCard(
                            title: "Nothing logged yet",
                            message: "Once you've imported or entered a few shifts, every \(selection.range.noun) you've driven shows up here."
                        )
                        .padding(.horizontal, GG.Layout.screenInset)
                        .padding(.top, 24)
                    }
                } else {
                    List {
                        ForEach(periods) { period in
                            Button { choose(period) } label: { row(period) }
                                .listRowBackground(GG.Surface.glass)
                                .listRowSeparatorTint(GG.Surface.dividerSoft)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Pick a \(selection.range.noun)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GG.Ink.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Row

    private func row(_ period: Period) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(period.title)
                        .ggText(GG.Typo.rowLabel)
                    if period.isCurrent {
                        Text("NOW")
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(GG.Palette.violet300)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GG.Palette.violet500.opacity(0.22), in: Capsule())
                    }
                }
                Text(period.detail)
                    .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
            }

            Spacer(minLength: 8)

            // The figure is why you're picking this one, so it gets weight.
            Text(period.gross > 0 ? Money.whole(period.gross) : "—")
                .ggText(.system(size: 16, weight: .semibold), tracking: -0.3,
                        color: period.gross > 0 ? GG.Ink.primary : GG.Ink.muted)

            if period.isSelected {
                CheckGlyph()
                    .stroke(GG.Palette.mint,
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func choose(_ period: Period) {
        selection.anchor = period.anchor
        dismiss()
    }

    // MARK: Data

    struct Period: Identifiable {
        let id: Date
        let anchor: Date
        let title: String
        let detail: String
        let gross: Double
        let hours: Double
        let isCurrent: Bool
        let isSelected: Bool
    }

    /// Every period that has shifts in it, newest first, plus the present one
    /// so there's always somewhere to come back to.
    private var periods: [Period] {
        let calendar = Calendar.gigGrow
        let range = selection.range

        func anchorFor(_ date: Date) -> Date { range.window(containing: date).lowerBound }

        var totals: [Date: (gross: Double, hours: Double, count: Int)] = [:]
        for shift in shifts {
            let key = anchorFor(shift.start)
            var entry = totals[key] ?? (0, 0, 0)
            entry.gross += shift.gross
            entry.hours += shift.hours
            entry.count += 1
            totals[key] = entry
        }

        let now = anchorFor(.now)
        let current = anchorFor(selection.anchor)
        // The present is always offered even when empty; nothing else is.
        totals[now] = totals[now] ?? (0, 0, 0)

        return totals.keys.sorted(by: >).map { key in
            let entry = totals[key] ?? (0, 0, 0)
            return Period(
                id: key,
                anchor: key,
                title: RangeSelection(range: range, anchor: key).title,
                detail: detail(entry, range: range),
                gross: entry.gross,
                hours: entry.hours,
                isCurrent: key == now,
                isSelected: key == current
            )
        }
    }

    private func detail(_ entry: (gross: Double, hours: Double, count: Int),
                        range: AnalyticsRange) -> String {
        guard entry.count > 0 else { return "Nothing logged" }
        var parts = ["\(entry.count) shift\(entry.count == 1 ? "" : "s")"]
        if entry.hours > 0 {
            parts.append(Hours.clock(entry.hours))
            // Per hour is the figure that makes two periods comparable, which
            // is the whole reason for looking at a list of them.
            parts.append("\(Money.cents(entry.gross / entry.hours))/hr")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Pick a period") {
    struct Harness: View {
        @State private var selection = RangeSelection()
        var body: some View { PeriodPickerView(selection: $selection) }
    }
    return Harness().modelContainer(.preview)
}
