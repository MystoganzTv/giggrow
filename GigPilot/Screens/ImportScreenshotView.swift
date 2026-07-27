//
//  ImportScreenshotView.swift
//  GigPilot
//
//  Read shifts off screenshots of gig apps' earnings screens.
//
//  This used to assume one block of time and one screenshot per app. That is
//  a real case — Uber and DoorDash running together, hours counted once — but
//  it is not the only one, and a driver who imported a week of daily screens
//  got seven days piled onto a single date with one day's hours.
//
//  So each screenshot now carries its own day. Screenshots that land on the
//  same date are merged into one shift, which preserves the multi-app case
//  exactly; screenshots on different dates become different shifts, which is
//  what a week of dailies actually is.
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
///
/// Time lives here rather than on the screen as a whole. Two screenshots of
/// the same day still share a shift — they're merged on save — but nothing
/// forces a Tuesday and a Thursday to pretend they happened together.
private struct ImportedSource: Identifiable {
    let id = UUID()
    let image: UIImage
    let parsed: ParsedEarnings
    var platform: String
    var amountText: String
    var unitsText: String
    var hoursText: String
    var milesText: String
    var period: ImportPeriod
    var date: Date
    /// What the chart said, when it said anything. Shown so the driver can
    /// see the app's reasoning instead of a date appearing from nowhere.
    var detectedNote: String?

    var gross: Double { Double(amountText) ?? 0 }
    var hours: Double { Double(hoursText) ?? 0 }
    var miles: Double { Double(milesText) ?? 0 }

    /// The key screenshots are merged on. Same day and same period means the
    /// same block of time.
    func groupKey(_ calendar: Calendar) -> String {
        let anchor = period == .week ? calendar.startOfWeek(for: date)
                                     : calendar.startOfDay(for: date)
        return "\(period.rawValue)-\(anchor.timeIntervalSince1970)"
    }
}

struct ImportScreenshotView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var sources: [ImportedSource] = []
    @State private var isReading = false
    @State private var errorMessage: String?

    /// Which card is expanded. With a week of dailies on screen, showing
    /// every field of every screenshot at once is unreadable.
    @State private var expanded: UUID?

    /// The decimal pad has no return key, so without this there is no way
    /// off the keyboard at all — you can open Gross and never get back.
    @FocusState private var isEditingField: Bool

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
                            if let overlapWarning { overlapCard(overlapWarning) }
                            ForEach($sources) { $source in
                                sourceCard($source)
                            }
                            addMore
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
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditingField = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(GP.Palette.violet400)
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
                Text("Send as many as you like")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                Text("A whole week of daily screens, several apps from one day, or both. Screenshots from the same day are merged into one shift so your hours are counted once; different days become different shifts.")
                    .gpText(.system(size: 14, weight: .regular), color: GP.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                bullet(GP.Palette.mint,
                       "Nothing leaves your phone — the text is read on-device.")
                bullet(GP.Palette.violet400,
                       "Use the screen that shows earnings, online time and trips together. The fare breakdown has the money but none of the rest.")
                bullet(GP.Palette.violet300,
                       "Don't send a weekly total and its days together — the week already contains them, and both would count the money twice.")
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
                     maxSelectionCount: 20,
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
                     maxSelectionCount: 20,
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
        let value = source.wrappedValue
        let isOpen = expanded == value.id

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                // Identity first. With seven near-identical screenshots on
                // screen, a card that doesn't say which one it is can't be
                // edited or removed with any confidence.
                HStack(spacing: 12) {
                    Image(uiImage: value.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(GP.Surface.stroke, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(value.platform.isEmpty ? "Which app is this?" : value.platform)
                            .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                        HStack(spacing: 6) {
                            Text(dayLabel(value))
                                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                            if value.gross > 0 {
                                Text("·").gpText(GP.Typo.footnote, color: GP.Ink.muted)
                                Text(Money.cents(value.gross))
                                    .gpText(.system(size: 13, weight: .semibold),
                                            color: GP.Palette.mint)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    Button { remove(value.id) } label: {
                        Text("Remove")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0xFB7185))
                    }
                    .buttonStyle(.plain)
                }
                if let note = value.detectedNote {
                    Text(note)
                        .gpText(.system(size: 11.5, weight: .regular), color: GP.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isOpen {
                    let columns = [GridItem(.flexible(), spacing: 10),
                                   GridItem(.flexible(), spacing: 10)]
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(accounts.filter(\.isActive)) { account in
                            platformChip(account, selected: source.platform)
                        }
                    }

                    RowDivider()
                    figureRow("Gross", text: source.amountText, prefix: "$",
                              alternatives: value.parsed.amounts.map {
                                  String(format: "%.2f", $0.value)
                              })
                    RowDivider()
                    // "Units" meant nothing to anyone. Every app has its own
                    // word for the thing it counts, and it is on the screen
                    // being imported.
                    figureRow(unitNoun(for: value.platform), text: source.unitsText,
                              prefix: "",
                              alternatives: value.parsed.units.map { "\($0.value)" })
                    RowDivider()
                    figureRow("Hours online", text: source.hoursText, prefix: "",
                              required: true,
                              alternatives: value.parsed.hours.map {
                                  String(format: "%.2f", $0.value)
                              })
                    RowDivider()
                    figureRow("Miles", text: source.milesText, prefix: "",
                              alternatives: value.parsed.miles.map {
                                  String(format: "%.0f", $0.value)
                              })
                    RowDivider()
                    periodRow(source.period)
                    DatePicker(value.period == .day ? "Date" : "Week starting",
                               selection: source.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(GP.Palette.violet400)
                        .padding(.vertical, 6)
                    Button {
                        isEditingField = false
                        withAnimation(.easeOut(duration: 0.2)) { expanded = nil }
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GP.Palette.violet400)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(GP.Surface.glassFaint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 14) {
                        miniStat(value.period == .day ? "Day" : "Week")
                        if value.hours > 0 {
                            miniStat(String(format: "%.2f h", value.hours))
                        } else {
                            Text("Hours missing")
                                .gpText(.system(size: 12, weight: .medium), color: GP.Palette.amber)
                        }
                        Spacer(minLength: 0)
                        Text("Tap to edit")
                            .gpText(.system(size: 12, weight: .medium), color: GP.Ink.muted)
                    }
                }
            }
            // The whole card is the target while collapsed. A tap strip the
            // width of the header is a hit area you have to aim for.
            .contentShape(Rectangle())
        }
        .onTapGesture {
            guard !isOpen else { return }
            withAnimation(.easeOut(duration: 0.2)) { expanded = value.id }
        }
    }

    private func miniStat(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(GP.Ink.tertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(GP.Surface.glassFaint, in: Capsule())
    }

    /// What this platform calls the thing it counts.
    private func unitNoun(for platform: String) -> String {
        let noun = accounts.first { $0.name == platform }?.unitNoun ?? "trips"
        return noun.prefix(1).uppercased() + noun.dropFirst()
    }

    private func dayLabel(_ source: ImportedSource) -> String {
        let f = DateFormatter()
        if source.period == .week {
            f.dateFormat = "'Week of' MMM d"
            return f.string(from: Calendar.gigPilot.startOfWeek(for: source.date))
        }
        f.dateFormat = "EEEE d MMM"
        return f.string(from: source.date)
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

    private func periodRow(_ period: Binding<ImportPeriod>) -> some View {
        HStack(spacing: 7) {
            ForEach(ImportPeriod.allCases) { option in
                let isSelected = option == period.wrappedValue
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { period.wrappedValue = option }
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

    /// A weekly total already contains the days inside it. Importing both is
    /// the one mistake this screen can make that silently doubles a year's
    /// income, so it is called out by name rather than left to the driver to
    /// spot in a chart three weeks later.
    private func overlapCard(_ message: String) -> some View {
        GlassCard(radius: GP.Radius.tile,
                  padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
            HStack(alignment: .top, spacing: 11) {
                Circle().fill(GP.Palette.amber)
                    .frame(width: 6, height: 6).padding(.top, 7)
                Text(message)
                    .gpText(GP.Typo.footnote, color: GP.Palette.amber.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryCard: some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text((blockCount == 1 ? "This block" : "\(blockCount) shifts").uppercased())
                    .gpText(GP.Typo.heroEyebrow,
                            tracking: GP.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                Text(Money.cents(totalGross))
                    .gpText(GP.Typo.heroAmountSmall, tracking: GP.Typo.heroAmountSmallTracking)

                HStack(spacing: 18) {
                    summaryStat("Per hour",
                                totalHours > 0 ? Money.cents(totalGross / totalHours) : "—")
                    summaryStat("Per mile",
                                totalMiles > 0 ? Money.cents(totalGross / totalMiles) : "—")
                    summaryStat(blockCount == 1 ? "Shift" : "Shifts", "\(blockCount)")
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
                    .focused($isEditingField)
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

    private var totalGross: Double { sources.reduce(0) { $0 + $1.gross } }

    /// Summed across blocks, not across screenshots: two apps in the same
    /// block share those hours, and adding them would halve every rate.
    private var totalHours: Double {
        Dictionary(grouping: sources) { $0.groupKey(Calendar.gigPilot) }
            .values
            .reduce(0) { $0 + ($1.map(\.hours).max() ?? 0) }
    }

    private var totalMiles: Double {
        Dictionary(grouping: sources) { $0.groupKey(Calendar.gigPilot) }
            .values
            .reduce(0) { $0 + ($1.map(\.miles).max() ?? 0) }
    }

    private var blockCount: Int {
        Set(sources.map { $0.groupKey(Calendar.gigPilot) }).count
    }

    /// Names the actual clash rather than warning in general terms.
    private var overlapWarning: String? {
        let calendar = Calendar.gigPilot
        let weeks = sources.filter { $0.period == .week }
        guard !weeks.isEmpty else { return nil }

        let f = DateFormatter()
        f.dateFormat = "MMM d"

        for week in weeks {
            let start = calendar.startOfWeek(for: week.date)
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { continue }
            let inside = sources.filter { $0.period == .day && $0.date >= start && $0.date < end }
            guard !inside.isEmpty else { continue }
            return "The weekly total for \(f.string(from: start)) already includes \(inside.count) of the daily screenshots below. Saving both counts that money twice — remove the week, or remove the days."
        }
        return nil
    }

    private var canSave: Bool {
        sources.contains { !$0.platform.isEmpty && $0.gross > 0 }
            && sources.allSatisfy { $0.platform.isEmpty || $0.hours > 0 }
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

            let lines: [RecognisedLine]
            let parsed: ParsedEarnings
            do {
                lines = try TextRecognizer.recognise(in: cgImage)
                parsed = EarningsParser.parse(lines)
            } catch {
                failures += 1
                continue
            }

            let best = parsed.best

            // Which day is this? Uber's daily screens are textually identical
            // — same header, same day labels — so the only thing that says
            // Wednesday is that Wednesday's bar is the solid one.
            let reading = ChartDayDetector.read(image: cgImage, lines: lines)
            let weekStart = Calendar.gigPilot.startOfWeek(for: best.date ?? .now)

            var period: ImportPeriod = .week
            var resolved = best.date ?? .now
            var note: String?

            switch reading {
            case .day(_, _, let dayOfMonth):
                period = .day
                if let day = ChartDayDetector.date(for: reading, weekStart: weekStart) {
                    resolved = day
                    let f = DateFormatter()
                    f.dateFormat = "EEEE, MMMM d"
                    // Says where the date came from. "Read as Wednesday" left
                    // the driver to work out which Wednesday.
                    note = dayOfMonth != nil
                        ? "\(f.string(from: day)) — the highlighted bar is labelled \(dayOfMonth!)."
                        : "\(f.string(from: day)) — read from the highlighted bar. Change it if that's wrong."
                }
            case .aggregate:
                period = .week
                resolved = weekStart
                note = "Every bar is filled, so this looks like a whole week rather than one day."
            case .inconclusive:
                note = "Couldn't tell which day this is from the chart — check the date below."
            }

            sources.append(
                ImportedSource(
                    image: uiImage,
                    parsed: parsed,
                    // Don't reuse a platform already claimed by another
                    // screenshot of the same block — that would double it.
                    platform: parsed.platformName ?? "",
                    amountText: best.amount.map { String(format: "%.2f", $0) } ?? "",
                    unitsText: best.units.map(String.init) ?? "",
                    hoursText: best.hours.map { String(format: "%.2f", $0) } ?? "",
                    milesText: best.miles.map { String(format: "%.0f", $0) } ?? "",
                    period: period,
                    date: resolved,
                    detectedNote: note
                )
            )
        }

        if failures > 0 {
            errorMessage = failures == items.count
                ? "None of those could be read. You can still fill the figures in by hand."
                : "\(failures) of \(items.count) couldn't be read; the rest are below."
        }
    }

    private func remove(_ id: UUID) {
        sources.removeAll { $0.id == id }
    }

    // MARK: Save

    /// Screenshots are grouped by the block they describe, and each group
    /// becomes one shift. Two apps on the same Tuesday share a shift and its
    /// hours; Tuesday and Wednesday do not.
    private func save() {
        guard canSave else { return }

        let calendar = Calendar.gigPilot
        let usable = sources.filter { !$0.platform.isEmpty && $0.gross > 0 && $0.hours > 0 }
        let groups = Dictionary(grouping: usable) { $0.groupKey(calendar) }

        for group in groups.values {
            guard let first = group.first else { continue }

            // The block's hours are the longest any app reported, not the
            // sum. Running two apps at once doesn't create more hours.
            let hours = group.map(\.hours).max() ?? 0
            let miles = group.map(\.miles).max() ?? 0
            let shift: Shift

            switch first.period {
            case .day:
                let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: first.date)
                    ?? first.date
                shift = Shift(start: start,
                              end: start.addingTimeInterval(hours * 3600),
                              miles: miles)

            case .week:
                // Spans the week it covers. `recordedHours` carries the real
                // figure so nothing reads 168 hours off the span.
                let start = calendar.startOfWeek(for: first.date)
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
                shift = Shift(start: start, end: end, miles: miles)
                shift.recordedHours = hours
                shift.isAggregate = true
            }

            context.insert(shift)

            // One earning per screenshot in the block. Two screenshots of the
            // same app on the same day are added together rather than
            // creating a duplicate account row.
            var byAccount: [String: PlatformEarning] = [:]
            for source in group {
                guard let account = accounts.first(where: { $0.name == source.platform })
                else { continue }

                if let existing = byAccount[source.platform] {
                    existing.gross += source.gross
                    existing.trips += Int(source.unitsText) ?? 0
                    continue
                }

                let earning = PlatformEarning(account: account,
                                              gross: source.gross,
                                              trips: Int(source.unitsText) ?? 0)
                context.insert(earning)
                earning.shift = shift
                shift.earnings.append(earning)
                byAccount[source.platform] = earning
            }

            shift.note = first.period == .week
                ? "Imported from a weekly summary"
                : (group.count > 1
                   ? "Imported from \(group.count) screenshots"
                   : "Imported from screenshot")
        }

        try? context.save()
        dismiss()
    }
}

#Preview("Import screenshots") {
    ImportScreenshotView()
        .modelContainer(.preview)
}
