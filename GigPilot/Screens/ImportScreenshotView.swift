//
//  ImportScreenshotView.swift
//  GigPilot
//
//  Read a shift off screenshots of gig apps' earnings screens.
//
//  One screenshot per platform, all landing in the same block of time. That
//  mirrors the data model exactly — a Shift with a PlatformEarning per app —
//  and it's the case the whole product is built around: a driver running
//  Uber and DoorDash together screenshots both and gets one honest shift,
//  with the hours counted once.
//
//  The parser is heuristic, so nothing is saved until the driver has seen
//  what was read next to the image it came from. Every field is editable and
//  every alternative reading is one tap away.
//

import SwiftUI
import SwiftData
import PhotosUI

/// What a screenshot covers. Gig apps show both, and they aren't
/// interchangeable — a week imported as a day piles seven days onto one bar.
enum ImportPeriod: String, CaseIterable, Identifiable {
    case day, week
    var id: String { rawValue }
    var label: String { self == .day ? "One day" : "A week" }
}

/// One screenshot and what was read from it.
private struct ImportedSource: Identifiable {
    let id = UUID()
    let image: UIImage
    let parsed: ParsedEarnings
    var platform: String
    var amountText: String
    var unitsText: String
}

struct ImportScreenshotView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var sources: [ImportedSource] = []
    @State private var isReading = false
    @State private var errorMessage: String?

    // Shared across every screenshot: one block of time, one odometer.
    @State private var hoursText = ""
    @State private var milesText = ""
    @State private var date = Date.now
    @State private var period: ImportPeriod = .week

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.appsWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                        if sources.isEmpty {
                            intro
                            picker
                        } else {
                            thumbnails
                            ForEach($sources) { $source in
                                sourceCard($source)
                            }
                            addMore
                            sharedCard
                            summaryCard
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .gpText(GP.Typo.footnote, color: GP.Palette.amber)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 6)
                        }
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }

                if isReading { readingOverlay }
            }
            .navigationTitle("Import screenshots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
                if !sources.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .foregroundStyle(canSave ? GP.Palette.violet400 : GP.Ink.muted)
                            .disabled(!canSave)
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await load(items) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Intro

    private var intro: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("One screenshot per app")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                Text("Screenshot each app's earnings screen and pick them all. They land in the same block of time, so your hours are counted once instead of once per app.")
                    .gpText(.system(size: 14, weight: .regular), color: GP.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                bullet(GP.Palette.mint,
                       "Nothing leaves your phone — the text is read on-device.")
                bullet(GP.Palette.violet400,
                       "Use the screen that shows earnings, online time and trips together. The fare breakdown has the money but none of the rest.")
                bullet(GP.Palette.amber,
                       "Reading a screenshot is guesswork, so check every figure. Anything wrong here quietly skews your hourly rate and tax set-aside.")
            }
        }
    }

    private func bullet(_ colour: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle().fill(colour).frame(width: 6, height: 6).padding(.top, 7)
            Text(text)
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $pickerItems,
                     maxSelectionCount: 6,
                     matching: .images,
                     photoLibrary: .shared()) {
            HStack(spacing: 8) {
                PlusGlyph()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 16, height: 16)
                Text("Choose screenshots")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(GP.Gradients.brandMark, in: Capsule())
        }
    }

    private var addMore: some View {
        PhotosPicker(selection: $pickerItems,
                     maxSelectionCount: 6,
                     matching: .images,
                     photoLibrary: .shared()) {
            HStack(spacing: 8) {
                PlusGlyph()
                    .stroke(GP.Palette.violet400,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 14, height: 14)
                Text("Add another app's screenshot")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(GP.Palette.violet400)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(GP.Surface.glassFaint,
                        in: RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous)
                    .strokeBorder(GP.Surface.strokeDashed,
                                  style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            )
        }
    }

    private var readingOverlay: some View {
        ZStack {
            GP.Palette.screen.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(GP.Palette.violet400)
                Text("Reading…")
                    .gpText(GP.Typo.captionMuted, color: GP.Ink.secondary)
            }
        }
    }

    // MARK: Review

    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sources) { source in
                    Image(uiImage: source.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 74, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(GP.Surface.stroke, lineWidth: 1)
                        )
                }
            }
        }
    }

    private func sourceCard(_ source: Binding<ImportedSource>) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(source.wrappedValue.platform.isEmpty
                         ? "Which app is this?"
                         : source.wrappedValue.platform)
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Spacer()
                    Button {
                        remove(source.wrappedValue.id)
                    } label: {
                        Text("Remove")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0xFB7185))
                    }
                    .buttonStyle(.plain)
                }

                let columns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(accounts.filter(\.isActive)) { account in
                        platformChip(account, selected: source.platform)
                    }
                }

                RowDivider()

                figureRow("Gross", text: source.amountText, prefix: "$",
                          alternatives: source.wrappedValue.parsed.amounts.map {
                              String(format: "%.2f", $0.value)
                          })
                RowDivider()
                figureRow("Units", text: source.unitsText, prefix: "",
                          alternatives: source.wrappedValue.parsed.units.map { "\($0.value)" })
            }
        }
    }

    private func platformChip(_ account: PlatformAccount, selected: Binding<String>) -> some View {
        let isSelected = account.name == selected.wrappedValue
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { selected.wrappedValue = account.name }
        } label: {
            HStack(spacing: 8) {
                Text(account.initial)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        LinearGradient(colors: [Color(hex: account.gradientStart),
                                                Color(hex: account.gradientEnd)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .opacity(isSelected ? 1 : 0.4)
                Text(account.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? GP.Ink.primary : GP.Ink.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? GP.Surface.glassBright : GP.Surface.glassFaint,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? GP.Palette.violet400.opacity(0.5) : GP.Surface.stroke,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Hours, miles and the period belong to the block, not to any one app.
    /// Asking per screenshot would invite counting the same hours twice.
    private var sharedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("The block of time")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    .padding(.bottom, 6)

                Text("Shared by every screenshot above — this is what stops two apps double-counting the same hours.")
                    .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                figureRow("Hours", text: $hoursText, prefix: "", required: true,
                          alternatives: allHourCandidates)

                if (Double(hoursText) ?? 0) <= 0 {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(GP.Palette.amber)
                            .frame(width: 6, height: 6).padding(.top, 6)
                        Text("How long were you online? Without it there's no hourly rate, and GigPilot won't guess one.")
                            .gpText(GP.Typo.footnote, color: GP.Palette.amber.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 12)
                }

                RowDivider()
                figureRow("Miles", text: $milesText, prefix: "",
                          alternatives: allMileCandidates)
                RowDivider()
                periodRow
                RowDivider()
                DatePicker(period == .day ? "Date" : "Week starting",
                           selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(GP.Palette.violet400)
                    .padding(.vertical, 6)

                Text(period == .day
                     ? "One day's driving. It'll show on that day's bar and feed your peak-hours chart."
                     : "A whole week's totals. The figures are exact, but GigPilot won't know which hours of the day they came from, so this one sits out of the peak-hours chart.")
                    .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    private var periodRow: some View {
        HStack(spacing: 7) {
            ForEach(ImportPeriod.allCases) { option in
                let isSelected = option == period
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { period = option }
                } label: {
                    Text(option.label)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : GP.Ink.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? AnyShapeStyle(GP.Gradients.segment)
                                               : AnyShapeStyle(Color.clear),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.vertical, 12)
    }

    private var summaryCard: some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("This block".uppercased())
                    .gpText(GP.Typo.heroEyebrow,
                            tracking: GP.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                Text(Money.cents(totalGross))
                    .gpText(GP.Typo.heroAmountSmall, tracking: GP.Typo.heroAmountSmallTracking)

                HStack(spacing: 18) {
                    summaryStat("Per hour",
                                hours > 0 ? Money.cents(totalGross / hours) : "—")
                    summaryStat("Per mile",
                                miles > 0 ? Money.cents(totalGross / miles) : "—")
                    summaryStat("Apps", "\(sources.filter { !$0.platform.isEmpty }.count)")
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

    private func figureRow(_ label: String, text: Binding<String>, prefix: String,
                           required: Bool = false,
                           alternatives: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .gpText(GP.Typo.rowLabel)
                if required && (Double(text.wrappedValue) ?? 0) <= 0 {
                    Text("required")
                        .gpText(.system(size: 11, weight: .medium), color: GP.Palette.amber)
                }
                Spacer(minLength: 12)
                if !prefix.isEmpty {
                    Text(prefix)
                        .gpText(.system(size: 15, weight: .medium), color: GP.Ink.muted)
                }
                TextField("—", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 110)
            }

            // Other readings, so a wrong pick is one tap to fix.
            if alternatives.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(alternatives.prefix(5).enumerated()), id: \.offset) { _, alt in
                            Button { text.wrappedValue = alt } label: {
                                Text(alt)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(text.wrappedValue == alt
                                                     ? GP.Palette.violet300 : GP.Ink.muted)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(GP.Surface.glassFaint, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: Derived

    private var hours: Double { Double(hoursText) ?? 0 }
    private var miles: Double { Double(milesText) ?? 0 }

    private var totalGross: Double {
        sources.reduce(0) { $0 + (Double($1.amountText) ?? 0) }
    }

    /// Hours and miles can come from any of the screenshots, so every
    /// reading across all of them is offered.
    private var allHourCandidates: [String] {
        sources.flatMap { $0.parsed.hours }.map { String(format: "%.2f", $0.value) }
    }

    private var allMileCandidates: [String] {
        sources.flatMap { $0.parsed.miles }.map { String(format: "%.0f", $0.value) }
    }

    private var canSave: Bool {
        hours > 0
            && sources.contains { !$0.platform.isEmpty && (Double($0.amountText) ?? 0) > 0 }
    }

    // MARK: Loading

    private func load(_ items: [PhotosPickerItem]) async {
        isReading = true
        errorMessage = nil
        defer {
            isReading = false
            pickerItems = []
        }

        var failures = 0

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                failures += 1
                continue
            }

            let parsed: ParsedEarnings
            do {
                parsed = EarningsParser.parse(try TextRecognizer.recognise(in: cgImage))
            } catch {
                failures += 1
                continue
            }

            let best = parsed.best
            sources.append(
                ImportedSource(
                    image: uiImage,
                    parsed: parsed,
                    // Don't reuse a platform already claimed by another
                    // screenshot — two cards on the same app would double it.
                    platform: alreadyUsed(parsed.platformName) ? "" : (parsed.platformName ?? ""),
                    amountText: best.amount.map { String(format: "%.2f", $0) } ?? "",
                    unitsText: best.units.map(String.init) ?? ""
                )
            )

            // Shared fields take the first screenshot that offers them.
            if hoursText.isEmpty, let value = best.hours {
                hoursText = String(format: "%.2f", value)
            }
            if milesText.isEmpty, let value = best.miles {
                milesText = String(format: "%.0f", value)
            }
            if let parsedDate = best.date { date = parsedDate }
        }

        if failures > 0 {
            errorMessage = failures == items.count
                ? "None of those could be read. You can still fill the figures in by hand."
                : "\(failures) of \(items.count) couldn't be read; the rest are below."
        }
    }

    private func alreadyUsed(_ name: String?) -> Bool {
        guard let name else { return false }
        return sources.contains { $0.platform == name }
    }

    private func remove(_ id: UUID) {
        sources.removeAll { $0.id == id }
    }

    // MARK: Save

    private func save() {
        guard canSave else { return }

        let cal = Calendar.gigPilot
        let shift: Shift

        switch period {
        case .day:
            let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            shift = Shift(start: start,
                          end: start.addingTimeInterval(hours * 3600),
                          miles: miles)

        case .week:
            // Spans the week it covers. `recordedHours` carries the real
            // figure so nothing reads 168 hours off the span.
            let start = cal.startOfWeek(for: date)
            let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
            shift = Shift(start: start, end: end, miles: miles)
            shift.recordedHours = hours
            shift.isAggregate = true
        }

        context.insert(shift)

        // One earning per screenshot. The hours stay on the shift, counted
        // once however many apps were running.
        for source in sources {
            guard !source.platform.isEmpty,
                  let account = accounts.first(where: { $0.name == source.platform }),
                  let gross = Double(source.amountText), gross > 0 else { continue }

            let earning = PlatformEarning(account: account,
                                          gross: gross,
                                          trips: Int(source.unitsText) ?? 0)
            context.insert(earning)
            earning.shift = shift
            shift.earnings.append(earning)
        }

        shift.note = sources.count > 1
            ? "Imported from \(sources.count) screenshots"
            : (period == .day ? "Imported from screenshot" : "Imported from a weekly summary")

        try? context.save()
        dismiss()
    }
}

#Preview("Import screenshots") {
    ImportScreenshotView()
        .modelContainer(.preview)
}
