//
//  DrivesView.swift
//  GigPilot
//
//  Recorded drives, waiting to be called business or personal.
//
//  The classification is deliberately the driver's. The IRS expects a
//  contemporaneous record of business use, and an app that guessed — then
//  put the guess in a deduction — would be handing someone a number they
//  can't defend. Unclassified drives are worth nothing until decided.
//

import SwiftUI
import SwiftData

struct DrivesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @Query private var profiles: [DriverProfile]

    var tracker: MileageTracker? = nil

    private var profile: DriverProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.vehicleWash().ignoresSafeArea()

                if drives.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Drives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                if let tracker, tracker.status == .recording { recordingCard(tracker) }

                summaryCard

                if unclassifiedCount > 0 { unclassifiedPrompt }

                ForEach(days, id: \.key) { day in
                    daySection(day)
                }

                accuracyNote
            }
            .padding(.horizontal, GP.Layout.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private func recordingCard(_ tracker: MileageTracker) -> some View {
        HeroCard(glow: true) {
            HStack(spacing: 14) {
                Circle()
                    .fill(GP.Palette.mint)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Recording")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Text(String(format: "%.1f mi so far", tracker.currentDistance / 1_609.344))
                        .gpText(GP.Typo.footnote, color: Color.white.opacity(0.6))
                }

                Spacer(minLength: 8)

                Button("Stop") { tracker.finishNow() }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.15), in: Capsule())
            }
        }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Business miles, all time")
                    Text(String(format: "%.0f mi", businessMiles))
                        .gpText(GP.Typo.heroAmountSmall, tracking: GP.Typo.heroAmountSmallTracking)
                }

                HStack(spacing: 22) {
                    stat("Deduction", Money.whole(totalDeduction))
                    stat("Personal", String(format: "%.0f mi", personalMiles))
                    if unclassifiedCount > 0 {
                        stat("Unsorted", "\(unclassifiedCount)")
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

    private var unclassifiedPrompt: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle().fill(GP.Palette.amber)
                .frame(width: 6, height: 6).padding(.top, 7)
            Text("\(unclassifiedCount) drive\(unclassifiedCount == 1 ? "" : "s") still unsorted. They count for nothing until you say whether they were business — GigPilot won't decide that for you.")
                .gpText(GP.Typo.footnote, color: GP.Palette.amber.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }

    private func daySection(_ day: (key: String, items: [DriveRecord])) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(day.key.uppercased())
                    .gpText(GP.Typo.groupLabel,
                            tracking: GP.Typo.groupLabelTracking, color: GP.Ink.muted)
                Spacer()
                Text(String(format: "%.1f mi", day.items.reduce(0) { $0 + $1.miles }))
                    .gpText(GP.Typo.captionMuted, color: GP.Ink.tertiary)
            }
            .padding(.horizontal, 6)

            GlassCard(radius: GP.Radius.tile,
                      padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, drive in
                        row(drive)
                        if index < day.items.count - 1 {
                            RowDivider(color: GP.Surface.dividerSoft)
                        }
                    }
                }
            }
        }
    }

    private func row(_ drive: DriveRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f mi", drive.miles))
                    .gpText(GP.Typo.rowLabel)
                Spacer(minLength: 8)
                if drive.purpose.isDeductible {
                    Text(Money.cents(drive.deduction(overrideRate: profile?.mileageRate ?? 0)))
                        .gpText(.system(size: 15, weight: .semibold), color: GP.Palette.mint)
                }
            }

            Text(timeRange(drive))
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)

            // Two taps, no menu. Sorting a week of drives shouldn't be a chore.
            HStack(spacing: 8) {
                purposeChip(drive, .business)
                purposeChip(drive, .personal)
                Spacer(minLength: 0)
                Button {
                    context.delete(drive)
                    try? context.save()
                } label: {
                    Text("Delete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFB7185).opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
    }

    private func purposeChip(_ drive: DriveRecord, _ purpose: DrivePurpose) -> some View {
        let isSelected = drive.purpose == purpose
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                drive.purpose = isSelected ? .unclassified : purpose
                try? context.save()
            }
        } label: {
            Text(purpose.label)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : GP.Ink.tertiary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? AnyShapeStyle(purpose == .business
                                        ? AnyShapeStyle(GP.Gradients.brandMark)
                                        : AnyShapeStyle(Color.white.opacity(0.16)))
                        : AnyShapeStyle(GP.Surface.glassFaint),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(
                    isSelected ? Color.clear : GP.Surface.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// GPS and an odometer will not agree, and a tax figure is the wrong
    /// place to imply a precision that isn't there.
    private var accuracyNote: some View {
        Text("Recorded distance comes from GPS, which samples your route as straight segments and usually reads a little under the odometer. For a deduction you can defend, check it against your dashboard.")
            .gpText(GP.Typo.footnote, color: GP.Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }

    // MARK: Empty

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: GP.Layout.stackSpacing) {
                EmptyStateCard(
                    title: "No drives recorded",
                    message: TrackingCapability.automaticMileage
                        ? "With tracking on, GigPilot records each drive on its own and waits here for you to say which were for work."
                        : "Turn on automatic tracking in Settings and drives will start appearing here.",
                    showsLogo: true
                )
                accuracyNote
            }
            .padding(.horizontal, GP.Layout.screenInset)
            .padding(.top, 8)
        }
    }

    // MARK: Data

    private var businessMiles: Double {
        drives.filter { $0.purpose.isDeductible }.reduce(0) { $0 + $1.miles }
    }

    private var personalMiles: Double {
        drives.filter { $0.purpose == .personal }.reduce(0) { $0 + $1.miles }
    }

    private var unclassifiedCount: Int {
        drives.filter { $0.purpose == .unclassified }.count
    }

    /// Summed per drive, because the rate depends on the day each one
    /// happened — 2026 changed mid-year.
    private var totalDeduction: Double {
        drives.reduce(0) { $0 + $1.deduction(overrideRate: profile?.mileageRate ?? 0) }
    }

    private func timeRange(_ drive: DriveRecord) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let minutes = Int(drive.duration / 60)
        return "\(f.string(from: drive.start))–\(f.string(from: drive.end)) · \(minutes) min"
    }

    private var days: [(key: String, items: [DriveRecord])] {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"

        var order: [String] = []
        var buckets: [String: [DriveRecord]] = [:]
        for drive in drives {
            let key = f.string(from: drive.start)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(drive)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

#Preview("Drives") {
    DrivesView()
        .modelContainer(.preview)
}
