//
//  MileageView.swift
//  GigGrow
//
//  Every recorded drive, and the deduction they add up to.
//
//  Built on the review model QuickBooks uses, because it solves a real
//  problem: a driver opens this on Sunday with forty drives waiting, and the
//  only way that gets done is if each one takes a flick of the thumb. So the
//  split is unreviewed versus reviewed, not business versus personal — the
//  question the screen is asking is "have you decided about this one yet".
//
//  The headline is labelled *potential* deduction on purpose. It is what
//  these miles would be worth if claimed; whether they can be is between the
//  driver and their accountant, and this app is not going to pretend
//  otherwise on a screen someone might read as tax advice.
//

import SwiftUI
import SwiftData

struct MileageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @Query private var profiles: [DriverProfile]

    var tracker: MileageTracker? = nil

    @State private var tab: Tab = .unreviewed
    @State private var year: Int = Calendar.gigGrow.component(.year, from: .now)
    @State private var isTrackingTrip = false
    @State private var isAddingDrive = false
    @State private var isPickingYear = false
    @State private var undo: UndoEntry?

    private var profile: DriverProfile? { profiles.first }
    private var overrideRate: Double { profile?.mileageRate ?? 0 }

    enum Tab: String, CaseIterable, Identifiable {
        case unreviewed, reviewed
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    /// Remembers one classification so it can be taken back. A swipe is an
    /// easy gesture to make by accident, and without this the only remedy is
    /// hunting the drive down in the other tab.
    private struct UndoEntry: Identifiable {
        let id = UUID()
        let drive: DriveRecord
        let previous: DrivePurpose
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.vehicleWash().ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    controlRows
                    TabSelector(selection: $tab)
                    yearFilter
                    listOrEmpty
                }

                addButton
            }
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
        .sheet(isPresented: $isTrackingTrip) { TrackTripView(tracker: tracker) }
        .sheet(isPresented: $isAddingDrive) { AddDriveView() }
        .confirmationDialog("Year", isPresented: $isPickingYear, titleVisibility: .visible) {
            ForEach(availableYears, id: \.self) { candidate in
                Button(String(candidate)) { year = candidate }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Mileage")
                .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)

            HStack(spacing: 6) {
                Text("\(String(year)) potential deduction")
                    .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                Text(Money.cents(yearDeduction))
                    .ggText(.system(size: 14.5, weight: .semibold), color: GG.Palette.mint)
            }

            // 2026 changed rate on 1 July. A single total spanning that would
            // look like one rate was used, so the screen says otherwise.
            if rateChangedThisYear {
                Text("Rates changed mid-year, so each drive is valued at the rate in force the day it happened.")
                    .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GG.Layout.screenInset)
        .padding(.bottom, 16)
    }

    // MARK: Rows

    private var controlRows: some View {
        VStack(spacing: 0) {
            RowDivider(color: GG.Surface.dividerSoft)

            HStack {
                Text("Auto-tracking")
                    .ggText(GG.Typo.rowLabel)
                Spacer(minLength: 12)
                Text(autoTrackingLabel)
                    .ggText(.system(size: 14.5, weight: .semibold), color: autoTrackingColour)
                Chevron(size: 15, color: Color.white.opacity(0.25))
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleAutoTracking() }
            .padding(.horizontal, GG.Layout.screenInset)
            .padding(.vertical, 15)

            RowDivider(color: GG.Surface.dividerSoft)

            HStack {
                Text("Track a trip")
                    .ggText(GG.Typo.rowLabel)
                Spacer(minLength: 12)
                if tracker?.status == .recording {
                    Text("Recording")
                        .ggText(.system(size: 14.5, weight: .semibold), color: GG.Palette.mint)
                }
                Chevron(size: 15, color: Color.white.opacity(0.25))
            }
            .contentShape(Rectangle())
            .onTapGesture { isTrackingTrip = true }
            .padding(.horizontal, GG.Layout.screenInset)
            .padding(.vertical, 15)

            RowDivider(color: GG.Surface.dividerSoft)
        }
    }

    private var autoTrackingLabel: String {
        switch tracker?.status {
        case .recording, .waiting: return "ON"
        case .denied:              return "BLOCKED"
        case .restricted:          return "UNAVAILABLE"
        default:                   return "OFF"
        }
    }

    private var autoTrackingColour: Color {
        switch tracker?.status {
        case .recording, .waiting:   return GG.Palette.mint
        case .denied, .restricted:   return GG.Palette.amber
        default:                     return GG.Ink.tertiary
        }
    }

    private func toggleAutoTracking() {
        guard let tracker else { return }
        let turningOn = !tracker.status.isArmed
        profile?.autoMileageTracking = turningOn
        try? context.save()
        if turningOn { tracker.enable() } else { tracker.disable() }
    }

    // MARK: Filter

    private var yearFilter: some View {
        HStack {
            Button { isPickingYear = true } label: {
                Text("Filter: \(String(year))")
                    .ggText(.system(size: 14, weight: .semibold), color: GG.Palette.violet300)
            }
            .buttonStyle(.plain)
            .disabled(availableYears.count < 2)

            Spacer(minLength: 8)

            if let undo {
                Button {
                    undo.drive.purpose = undo.previous
                    try? context.save()
                    self.undo = nil
                } label: {
                    Text("Undo")
                        .ggText(.system(size: 14, weight: .semibold), color: GG.Ink.secondary)
                }
                .buttonStyle(.plain)
            } else if !visible.isEmpty {
                Text("\(visible.count) drive\(visible.count == 1 ? "" : "s") · \(String(format: "%.0f mi", visibleMiles))")
                    .ggText(GG.Typo.captionMuted, color: GG.Ink.muted)
            }
        }
        .padding(.horizontal, GG.Layout.screenInset)
        .padding(.vertical, 13)
        .animation(.easeOut(duration: 0.18), value: undo?.id)
    }

    // MARK: List

    @ViewBuilder
    private var listOrEmpty: some View {
        if visible.isEmpty {
            emptyState
        } else {
            List {
                ForEach(days, id: \.key) { day in
                    Section {
                        ForEach(day.items) { drive in
                            DriveRow(drive: drive, overrideRate: overrideRate)
                                .listRowBackground(GG.Surface.glass)
                                .listRowSeparatorTint(GG.Surface.dividerSoft)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { classify(drive, as: .business) } label: {
                                        Label("Business", systemImage: "briefcase.fill")
                                    }
                                    .tint(GG.Palette.violet500)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button { classify(drive, as: .personal) } label: {
                                        Label("Personal", systemImage: "house.fill")
                                    }
                                    .tint(GG.Ink.muted)

                                    Button(role: .destructive) {
                                        context.delete(drive)
                                        try? context.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(day.key.uppercased())
                                .ggText(GG.Typo.groupLabel,
                                        tracking: GG.Typo.groupLabelTracking, color: GG.Ink.muted)
                            Spacer()
                            Text(String(format: "%.1f mi", day.items.reduce(0) { $0 + $1.miles }))
                                .ggText(GG.Typo.captionMuted, color: GG.Ink.tertiary)
                        }
                    }
                }

                Section {
                    accuracyNote
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: GG.Layout.stackSpacing) {
                EmptyStateCard(
                    title: tab == .reviewed ? "Nothing reviewed yet" : "Take a drive",
                    message: emptyMessage,
                    showsLogo: tab == .unreviewed
                )
                accuracyNote
            }
            .padding(.horizontal, GG.Layout.screenInset)
            .padding(.top, 26)
        }
    }

    private var emptyMessage: String {
        if tab == .reviewed {
            return "Drives you've marked business or personal land here. Until then they're worth nothing on a return."
        }
        if drives.isEmpty {
            return tracker?.status.isArmed == true
                ? "Tracking is on and waiting. Drive, and trips will appear here for you to sort."
                : "Turn on auto-tracking above, or tap Track a trip to record one by hand."
        }
        return "Everything from \(String(year)) is sorted. Nice."
    }

    private var addButton: some View {
        Button { isAddingDrive = true } label: {
            PlusGlyph()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: 20, height: 20)
                .padding(19)
                .background(GG.Gradients.brandMark, in: Circle())
                .shadow(color: Color(hex: 0x5C3CDC, opacity: 0.5), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, GG.Layout.screenInset)
        .padding(.bottom, 26)
    }

    private var accuracyNote: some View {
        Text("Recorded distance comes from GPS, which samples your route as straight segments and usually reads a little under the odometer. For a deduction you can defend, check it against your dashboard.")
            .ggText(GG.Typo.footnote, color: GG.Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 10)
    }

    // MARK: Actions

    private func classify(_ drive: DriveRecord, as purpose: DrivePurpose) {
        let previous = drive.purpose
        withAnimation(.easeOut(duration: 0.2)) {
            drive.purpose = purpose
            try? context.save()
            undo = UndoEntry(drive: drive, previous: previous)
        }
    }

    // MARK: Data

    private var inYear: [DriveRecord] {
        drives.filter { Calendar.gigGrow.component(.year, from: $0.start) == year }
    }

    /// Reviewed means decided, either way. An unreviewed drive is worth
    /// nothing, which is why the two tabs are the split that matters.
    private var visible: [DriveRecord] {
        inYear.filter { tab == .reviewed ? $0.purpose != .unclassified : $0.purpose == .unclassified }
    }

    private var visibleMiles: Double { visible.reduce(0) { $0 + $1.miles } }

    /// Summed per drive at its own date's rate, never miles × one rate.
    private var yearDeduction: Double {
        inYear.reduce(0) { $0 + $1.deduction(overrideRate: overrideRate) }
    }

    /// Only worth saying when the driver hasn't pinned their own rate — an
    /// override applies to the whole year and no change happened.
    private var rateChangedThisYear: Bool {
        guard overrideRate == 0 else { return false }
        let calendar = Calendar.gigGrow
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return false }
        return MileageRates.changesDuring(start..<end)
    }

    /// Years that actually have drives, newest first, always including the
    /// current one so a fresh install isn't filtering by an empty year.
    private var availableYears: [Int] {
        let calendar = Calendar.gigGrow
        let thisYear = calendar.component(.year, from: .now)
        let found = Set(drives.map { calendar.component(.year, from: $0.start) })
        return Array(found.union([thisYear])).sorted(by: >)
    }

    private var days: [(key: String, items: [DriveRecord])] {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"

        var order: [String] = []
        var buckets: [String: [DriveRecord]] = [:]
        for drive in visible {
            let key = f.string(from: drive.start)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(drive)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

// MARK: - Row

private struct DriveRow: View {
    let drive: DriveRecord
    let overrideRate: Double

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(String(format: "%.1f mi", drive.miles))
                        .ggText(GG.Typo.rowLabel)
                    if drive.purpose != .unclassified {
                        Text(drive.purpose.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(drive.purpose.isDeductible
                                             ? GG.Palette.violet300 : GG.Ink.muted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(GG.Surface.glassFaint, in: Capsule())
                    }
                }
                Text(timeRange)
                    .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
            }

            Spacer(minLength: 8)

            if drive.purpose.isDeductible {
                Text(Money.cents(drive.deduction(overrideRate: overrideRate)))
                    .ggText(.system(size: 15, weight: .semibold), color: GG.Palette.mint)
            } else if drive.purpose == .unclassified {
                // Swipe is invisible until someone tries it, so the row says
                // which way is which rather than waiting to be discovered.
                Text("Swipe →← to sort")
                    .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
            }
        }
        .padding(.vertical, 12)
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: drive.start))–\(f.string(from: drive.end)) · \(Int(drive.duration / 60)) min"
    }
}

// MARK: - Tabs

private struct TabSelector: View {
    @Binding var selection: MileageView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MileageView.Tab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = tab }
                } label: {
                    VStack(spacing: 9) {
                        Text(tab.label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(selection == tab ? GG.Ink.primary : GG.Ink.muted)
                        Rectangle()
                            .fill(selection == tab
                                  ? AnyShapeStyle(GG.Gradients.brandMark)
                                  : AnyShapeStyle(Color.clear))
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(GG.Surface.dividerSoft).frame(height: 1)
        }
    }
}

#Preview("Mileage") {
    MileageView()
        .modelContainer(.preview)
}
