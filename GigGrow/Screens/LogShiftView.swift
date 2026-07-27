//
//  LogShiftView.swift
//  GigGrow
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

    @State private var start = Calendar.gigGrow.date(
        bySettingHour: 9, minute: 0, second: 0, of: .now
    ) ?? .now
    @State private var end = Calendar.gigGrow.date(
        bySettingHour: 15, minute: 0, second: 0, of: .now
    ) ?? .now
    @State private var milesText = ""
    @State private var idleText = ""
    @State private var note = ""

    /// Neither pad has a return key. This is the third screen to need it;
    /// the two I fixed before were the two I happened to be looking at.
    @FocusState private var isEditingField: Bool

    /// True when this row covers a period rather than one sitting — an
    /// imported weekly total. Its hours are stated, not derived from a span.
    @State private var isAggregate = false
    @State private var recordedHoursText = ""
    @State private var recordedMinutesText = ""

    private var recordedHours: Double {
        Hours.decimal(hours: Int(recordedHoursText) ?? 0,
                      minutes: Int(recordedMinutesText) ?? 0)
    }

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
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.dashboardWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                        timeCard
                        distanceCard
                        platformsCard
                        summaryCard

                        if editing != nil { deleteButton }
                    }
                    .padding(.horizontal, GG.Layout.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(editing == nil ? "Log shift" : "Edit shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditingField = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(GG.Palette.violet300)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GG.Ink.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? GG.Palette.violet400 : GG.Ink.muted)
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
                    .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

                DatePicker("Start", selection: $start)
                    .datePickerStyle(.compact)
                RowDivider()
                DatePicker("End", selection: $end, in: start...)
                    .datePickerStyle(.compact)

                if isAggregate {
                    RowDivider(color: GG.Surface.dividerSoft)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hours worked")
                                .ggText(GG.Typo.rowLabel)
                            Text("This is a whole week's total, so the hours are the ones you recorded — not the span above.")
                                .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        TextField("0", text: $recordedHoursText)
                            .keyboardType(.numberPad)
                            .focused($isEditingField)
                            .multilineTextAlignment(.trailing)
                            .ggText(.system(size: 16, weight: .semibold))
                            .frame(width: 40)
                        Text("h").ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                        TextField("00", text: $recordedMinutesText)
                            .keyboardType(.numberPad)
                            .focused($isEditingField)
                            .multilineTextAlignment(.trailing)
                            .ggText(.system(size: 16, weight: .semibold))
                            .frame(width: 40)
                        Text("m").ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                    }
                    .padding(.vertical, 12)
                }

                HStack {
                    Text(isAggregate ? "Period" : "Duration")
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                    Spacer()
                    Text(durationLabel)
                        .ggText(.system(size: 13, weight: .semibold),
                                color: hours > 0 ? GG.Palette.violet300 : GG.Ink.muted)
                }
            }
            .tint(GG.Palette.violet400)
        }
    }

    // MARK: Distance

    private var distanceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Distance & downtime")
                    .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

                numberField("Miles driven", text: $milesText, suffix: "mi")
                RowDivider()
                numberField("Time waiting", text: $idleText, suffix: "min")

                Text("Waiting time is subtracted from the block to work out your active hours.")
                    .ggText(GG.Typo.footnote, color: GG.Ink.muted)
            }
        }
    }

    // MARK: Platforms

    private var platformsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Which apps were on")
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                    Text("Turn on every app you had running — overlapping is the point.")
                        .ggText(GG.Typo.footnote, color: GG.Ink.muted)
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
                    .ggText(GG.Typo.rowLabel,
                            color: binding.wrappedValue.isOn ? GG.Ink.primary : GG.Ink.tertiary)

                Spacer()

                Toggle("", isOn: binding.isOn)
                    .labelsHidden()
                    .tint(GG.Palette.violet500)
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
                    .ggText(GG.Typo.heroEyebrow,
                            tracking: GG.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                Text(Money.cents(totalGross))
                    .ggText(GG.Typo.heroAmountSmall, tracking: GG.Typo.heroAmountSmallTracking)

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
                .ggText(.system(size: 10, weight: .semibold),
                        tracking: 1.0, color: Color.white.opacity(0.45))
            Text(value)
                .ggText(.system(size: 16, weight: .semibold), tracking: -0.3)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: deleteShift) {
            Text("Delete shift")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFB7185))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color(hex: 0xFB7185, opacity: 0.10),
                            in: RoundedRectangle(cornerRadius: GG.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: Fields

    private func numberField(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label)
                .ggText(GG.Typo.rowLabel)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .focused($isEditingField)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 90)
            Text(suffix)
                .ggText(GG.Typo.footnote, color: GG.Ink.muted)
        }
    }

    private func compactField(placeholder: String, text: Binding<String>, prefix: String? = nil) -> some View {
        HStack(spacing: 2) {
            if let prefix {
                Text(prefix)
                    .ggText(.system(size: 15, weight: .medium), color: GG.Ink.muted)
            }
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .focused($isEditingField)
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

    /// A stated figure beats the span, the same rule `Shift.hours` follows.
    /// Without this an imported week shows 168 hours and every rate on the
    /// sheet is wrong by a factor of eight.
    private var hours: Double {
        if isAggregate && recordedHours > 0 { return recordedHours }
        return max(end.timeIntervalSince(start), 0) / 3600
    }
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
        isAggregate = shift.isAggregate
        // A weekly import spans seven days but records the hours actually
        // worked. Editing it as a start-to-end block would read 168 hours
        // and, on save, throw the real figure away.
        if let recorded = shift.recordedHours, recorded > 0 {
            recordedHoursText = "\(Hours.split(recorded).hours)"
            recordedMinutesText = "\(Hours.split(recorded).minutes)"
        }
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

        // Insert before wiring up relationships — attaching an earning to a
        // shift the context hasn't seen yet leaves the graph half-registered.
        if editing == nil { context.insert(shift) }
        shift.isAggregate = isAggregate
        // Written back explicitly. Saving an imported week without this left
        // recordedHours holding a figure the sheet had just been editing
        // around, so the row read one thing here and another everywhere else.
        shift.recordedHours = isAggregate && recordedHours > 0 ? recordedHours : nil

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
            context.insert(earning)
            earning.shift = shift
            shift.earnings.append(earning)
        }

        try? context.save()
        dismiss()
    }

    /// Same action as the history list's context menu, somewhere obvious.
    private func deleteShift() {
        guard let shift = editing else { return }
        let earnings = shift.earnings
        shift.earnings = []
        for earning in earnings { context.delete(earning) }
        context.delete(shift)
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
