//
//  LogShiftView.swift
//  GigPilot
//
//  Manual shift entry. One block of time, one mileage figure, and a gross
//  per app that was running — which is the shape the data model needs and,
//  not coincidentally, the way drivers actually describe their day.
//

import SwiftUI
import SwiftData

struct LogShiftView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]
    @Query private var profiles: [DriverProfile]

    /// Editing an existing shift, or nil when creating one.
    var editing: Shift?

    @State private var start = Calendar.gigPilot.date(
        bySettingHour: 9, minute: 0, second: 0, of: .now
    ) ?? .now
    @State private var end = Calendar.gigPilot.date(
        bySettingHour: 15, minute: 0, second: 0, of: .now
    ) ?? .now
    @State private var milesText = ""
    @State private var idleText = ""
    @State private var note = ""

    /// Per-account entry, keyed by account name so it survives re-renders.
    @State private var rows: [String: EntryRow] = [:]
    @State private var loaded = false

    private struct EntryRow {
        var isOn = false
        var gross = ""
        var trips = ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.dashboardWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                        timeCard
                        distanceCard
                        platformsCard
                        summaryCard
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(editing == nil ? "Log shift" : "Edit shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? GP.Palette.violet400 : GP.Ink.muted)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Time

    private var timeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("When")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                DatePicker("Start", selection: $start)
                    .datePickerStyle(.compact)
                RowDivider()
                DatePicker("End", selection: $end, in: start...)
                    .datePickerStyle(.compact)

                HStack {
                    Text("Duration")
                        .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                    Spacer()
                    Text(durationLabel)
                        .gpText(.system(size: 13, weight: .semibold),
                                color: hours > 0 ? GP.Palette.violet300 : GP.Ink.muted)
                }
            }
            .tint(GP.Palette.violet400)
        }
    }

    // MARK: Distance

    private var distanceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Distance & downtime")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                numberField("Miles driven", text: $milesText, suffix: "mi")
                RowDivider()
                numberField("Time waiting", text: $idleText, suffix: "min")

                Text("Waiting time is subtracted from the block to work out your active hours.")
                    .gpText(GP.Typo.footnote, color: GP.Ink.muted)
            }
        }
    }

    // MARK: Platforms

    private var platformsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Which apps were on")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Text("Turn on every app you had running — overlapping is the point.")
                        .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                }

                ForEach(accounts) { account in
                    platformRow(account)
                    if account.id != accounts.last?.id { RowDivider() }
                }
            }
        }
    }

    private func platformRow(_ account: PlatformAccount) -> some View {
        let binding = rowBinding(for: account.name)

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(account.initial)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: account.gradientStart), Color(hex: account.gradientEnd)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .opacity(binding.wrappedValue.isOn ? 1 : 0.35)

                Text(account.name)
                    .gpText(GP.Typo.rowLabel,
                            color: binding.wrappedValue.isOn ? GP.Ink.primary : GP.Ink.tertiary)

                Spacer()

                Toggle("", isOn: binding.isOn)
                    .labelsHidden()
                    .tint(GP.Palette.violet500)
            }

            if binding.wrappedValue.isOn {
                HStack(spacing: 10) {
                    compactField(placeholder: "Gross", text: binding.gross, prefix: "$")
                    compactField(placeholder: account.unitNoun.capitalized, text: binding.trips)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: binding.wrappedValue.isOn)
    }

    // MARK: Summary

    private var summaryCard: some View {
        HeroCard(glow: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("This shift".uppercased())
                    .gpText(GP.Typo.heroEyebrow,
                            tracking: GP.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                Text(Money.cents(totalGross))
                    .gpText(GP.Typo.heroAmountSmall, tracking: GP.Typo.heroAmountSmallTracking)

                HStack(spacing: 16) {
                    summaryStat("Per hour", activeHours > 0 ? Money.cents(totalGross / activeHours) : "—")
                    summaryStat("Per mile", miles > 0 ? Money.cents(totalGross / miles) : "—")
                    summaryStat("Apps on", "\(activeRowCount)")
                }
            }
        }
    }

    private func summaryStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .gpText(.system(size: 10, weight: .semibold),
                        tracking: 1.0, color: Color.white.opacity(0.45))
            Text(value)
                .gpText(.system(size: 16, weight: .semibold), tracking: -0.3)
        }
    }

    // MARK: Fields

    private func numberField(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label)
                .gpText(GP.Typo.rowLabel)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 90)
            Text(suffix)
                .gpText(GP.Typo.footnote, color: GP.Ink.muted)
        }
    }

    private func compactField(placeholder: String, text: Binding<String>, prefix: String? = nil) -> some View {
        HStack(spacing: 2) {
            if let prefix {
                Text(prefix)
                    .gpText(.system(size: 15, weight: .medium), color: GP.Ink.muted)
            }
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    // MARK: Derived

    private var hours: Double { max(end.timeIntervalSince(start), 0) / 3600 }
    private var idleHours: Double { min((Double(idleText) ?? 0) / 60, hours) }
    private var activeHours: Double { max(hours - idleHours, 0) }
    private var miles: Double { Double(milesText) ?? 0 }

    private var durationLabel: String {
        guard hours > 0 else { return "—" }
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    private var activeRowCount: Int {
        rows.values.filter(\.isOn).count
    }

    private var totalGross: Double {
        rows.values.filter(\.isOn).reduce(0) { $0 + (Double($1.gross) ?? 0) }
    }

    private var canSave: Bool {
        hours > 0 && activeRowCount > 0
    }

    // MARK: Binding plumbing

    private func rowBinding(for name: String) -> Binding<EntryRow> {
        Binding(
            get: { rows[name] ?? EntryRow() },
            set: { rows[name] = $0 }
        )
    }

    // MARK: Load & save

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        guard let shift = editing else {
            for account in accounts where rows[account.name] == nil {
                rows[account.name] = EntryRow()
            }
            // The Settings idle threshold is the starting point, so the
            // preference isn't a number that sits there doing nothing.
            if let minutes = profiles.first?.idleThresholdMinutes, minutes > 0 {
                idleText = "\(minutes)"
            }
            return
        }

        start = shift.start
        end = shift.end
        milesText = shift.miles > 0 ? trimmed(shift.miles) : ""
        idleText = shift.idleMinutes > 0 ? trimmed(shift.idleMinutes) : ""
        note = shift.note ?? ""

        for account in accounts {
            if let earning = shift.earnings.first(where: { $0.account?.name == account.name }) {
                rows[account.name] = EntryRow(
                    isOn: true,
                    gross: String(format: "%.2f", earning.gross),
                    trips: earning.trips > 0 ? "\(earning.trips)" : ""
                )
            } else {
                rows[account.name] = EntryRow()
            }
        }
    }

    private func save() {
        let shift = editing ?? Shift(start: start, end: end)
        shift.start = start
        shift.end = end
        shift.miles = miles
        shift.idleMinutes = Double(idleText) ?? 0
        shift.note = note.isEmpty ? nil : note

        // Rebuild the earnings rather than diffing them — a shift has at most
        // a handful. Detach first, then delete: mutating the relationship
        // while iterating it is asking for trouble.
        let stale = shift.earnings
        shift.earnings = []
        for earning in stale {
            context.delete(earning)
        }

        for account in accounts {
            guard let row = rows[account.name], row.isOn else { continue }
            let earning = PlatformEarning(
                account: account,
                gross: Double(row.gross) ?? 0,
                trips: Int(row.trips) ?? 0
            )
            earning.shift = shift
            context.insert(earning)
            shift.earnings.append(earning)
        }

        if editing == nil { context.insert(shift) }
        try? context.save()
        dismiss()
    }

    private func trimmed(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

#Preview("Log shift") {
    LogShiftView()
        .modelContainer(.preview)
}
