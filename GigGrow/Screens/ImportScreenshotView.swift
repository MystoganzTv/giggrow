//
//  ImportScreenshotView.swift
//  GigGrow
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
    var tipsText: String
    var promotionsText: String
    var unitsText: String
    var hoursText: String
    var minutesText: String
    var milesText: String
    var period: ImportPeriod
    var date: Date
    /// What the chart said, when it said anything. Shown so the driver can
    /// see the app's reasoning instead of a date appearing from nowhere.
    var detectedNote: String?
    /// True when the date is a guess rather than something read off the
    /// screen. Blocks saving until it's confirmed.
    var needsDate: Bool = false
    /// For a weekly total: how much of it each day earned, read off the bar
    /// chart. Nil when the chart couldn't be measured.
    var dailyShares: [Double]?
    /// Set when this looks like something already in the store. Not a block —
    /// a driver may legitimately be replacing a bad import — but silence here
    /// means quietly doubling a week's income, which is the worst kind of
    /// wrong number because every rate downstream still looks plausible.
    var isDuplicate: Bool = false
    /// Excluded from the save. Duplicates start excluded.
    var isSkipped: Bool = false
    /// The driver deliberately chose to include a duplicate after seeing the
    /// warning. Without remembering this, changing its app/date immediately
    /// runs duplicate detection again and silently excludes it.
    var duplicateOverride = false
    /// Ticked off by hand. With a week of near-identical cards on screen,
    /// there is otherwise no way to remember which ones you've already been
    /// through — you check the same three twice and miss the fourth.
    var isReviewed: Bool = false

    var gross: Double { Double(amountText) ?? 0 }
    var tips: Double { Double(tipsText) ?? 0 }
    var promotions: Double { Double(promotionsText) ?? 0 }
    /// What the platform paid for the work itself.
    var baseFare: Double { max(gross - tips - promotions, 0) }
    /// Decimal inside, clock outside. The two fields are the only
    /// representation the driver sees; this is what everything divides by.
    var hours: Double {
        Hours.decimal(hours: Int(hoursText) ?? 0, minutes: Int(minutesText) ?? 0)
    }
    var miles: Double { Double(milesText) ?? 0 }

    /// The key screenshots are merged on. Platform is part of the key
    /// because an Uber weekly total and a Lyft weekly total carry independent
    /// online hours. Treating them as one simultaneous block silently drops
    /// time for drivers who switch apps rather than multi-app.
    func groupKey(_ calendar: Calendar) -> String {
        let anchor = period == .week ? calendar.startOfWeek(for: date)
                                     : calendar.startOfDay(for: date)
        let shape = period == .week
            ? (dailyShares != nil ? "split" : "whole")
            : "day"
        return "\(period.rawValue)-\(shape)-\(platform.lowercased())-\(anchor.timeIntervalSince1970)"
    }
}

struct ImportScreenshotView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]
    /// Everything already stored, so an import can tell you when you're
    /// about to add a day you've already added.
    @Query private var existingShifts: [Shift]

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

    /// The screenshot being looked at full size. Checking a figure against
    /// the source shouldn't mean leaving the app for Photos and losing every
    /// edit made so far.
    ///
    /// Holds the wrapper, not the image. Deriving the wrapper in the binding
    /// minted a fresh UUID on every render, so `fullScreenCover(item:)` saw a
    /// different item each pass and the cover would not close.
    @State private var viewing: ViewedImage?

    /// What the save actually produced. Tapping Save and watching the sheet
    /// close is indistinguishable from tapping Save and nothing happening,
    /// especially when the shifts land in a week the dashboard isn't showing.
    @State private var outcome: SaveOutcome?

    private struct SaveOutcome: Identifiable {
        let id = UUID()
        /// Derived daily rows plus any weekly rows that were kept whole.
        /// These are storage entries, not claims about how many shifts the
        /// driver actually worked.
        let entries: Int
        let reports: Int
        /// True when a weekly total was kept whole rather than split.
        let wasWholeWeek: Bool
        let gross: Double
        let earliest: Date
        let latest: Date
        /// True when none of it falls in the week the dashboard displays.
        let outsideThisWeek: Bool
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.appsWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                        if sources.isEmpty {
                            intro
                            picker
                        } else {
                            thumbnails
                            if let overlapWarning { overlapCard(overlapWarning) }
                            // Checked and skipped ones sink, so what still
                            // needs you is always what's in front of you.
                            // Ordered by id and indexed back into the binding:
                            // a Binding<Array> can't be sorted directly.
                            ForEach(displayOrder, id: \.self) { id in
                                if let index = sources.firstIndex(where: { $0.id == id }) {
                                    sourceCard($sources[index])
                                }
                            }
                            addMore
                            summaryCard
                            if let saveBlockingMessage {
                                Text(saveBlockingMessage)
                                    .ggText(GG.Typo.footnote,
                                            color: GG.Palette.amber.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 6)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .ggText(GG.Typo.footnote, color: GG.Palette.amber)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 6)
                        }
                    }
                    .padding(.horizontal, GG.Layout.screenInset)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }

                if isReading { readingOverlay }
            }
            .navigationTitle("Import screenshots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GG.Ink.secondary)
                }
                if !sources.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .foregroundStyle(canSave ? GG.Palette.violet400 : GG.Ink.muted)
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
                        .foregroundStyle(GG.Palette.violet400)
                }
            }
            .onChange(of: sources.map { "\($0.platform)-\($0.date.timeIntervalSince1970)" }) { _, _ in
            // Picking the app or fixing the date is what makes a duplicate
            // visible, so the check has to run again after either.
            markDuplicates()
        }
        .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await load(items) }
            }
        }
        .preferredColorScheme(.dark)
        .alert(item: $outcome) { result in
            Alert(
                title: Text("Saved"),
                message: Text(summary(result)),
                dismissButton: .default(Text("Done")) { dismiss() }
            )
        }
        .fullScreenCover(item: $viewing) { viewed in
            // Closing is handed over explicitly rather than left to
            // `@Environment(\.dismiss)`, so there is exactly one way out and
            // it can't be defeated by presentation state.
            ScreenshotViewer(image: viewed.image) { viewing = nil }
        }
    }

    /// `fullScreenCover(item:)` needs identity, and UIImage has none.
    /// Created once, when the driver taps — never re-derived.
    private struct ViewedImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    // MARK: Intro

    private var intro: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Send as many as you like")
                    .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

                Text("A whole week of daily screens, several apps from one day, or both. Screenshots from the same day are merged into one shift so your hours are counted once; different days become different shifts.")
                    .ggText(.system(size: 14, weight: .regular), color: GG.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                bullet(GG.Palette.mint,
                       "Nothing leaves your phone — the text is read on-device.")
                bullet(GG.Palette.violet400,
                       "Use the screen that shows earnings, online time and trips together. The fare breakdown has the money but none of the rest.")
                bullet(GG.Palette.violet300,
                       "Don't send a weekly total and its days together — the week already contains them, and both would count the money twice.")
                bullet(GG.Palette.amber,
                       "Reading a screenshot is guesswork, so check every figure. Anything wrong here quietly skews your hourly rate and tax set-aside.")
            }
        }
    }

    private func bullet(_ colour: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle().fill(colour).frame(width: 6, height: 6).padding(.top, 7)
            Text(text)
                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
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
            .background(GG.Gradients.brandMark, in: Capsule())
        }
    }

    private var addMore: some View {
        PhotosPicker(selection: $pickerItems,
                     maxSelectionCount: 20,
                     matching: .images,
                     photoLibrary: .shared()) {
            HStack(spacing: 8) {
                PlusGlyph()
                    .stroke(GG.Palette.violet400,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 14, height: 14)
                Text("Add another app's screenshot")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(GG.Palette.violet400)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(GG.Surface.glassFaint,
                        in: RoundedRectangle(cornerRadius: GG.Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GG.Radius.tile, style: .continuous)
                    .strokeBorder(GG.Surface.strokeDashed,
                                  style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            )
        }
    }

    private var readingOverlay: some View {
        ZStack {
            GG.Palette.screen.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(GG.Palette.violet400)
                Text("Reading…")
                    .ggText(GG.Typo.captionMuted, color: GG.Ink.secondary)
            }
        }
    }

    // MARK: Review

    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sources) { source in
                    Button { viewing = ViewedImage(image: source.image) } label: {
                        Image(uiImage: source.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 74, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(GG.Surface.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
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
                    Button { viewing = ViewedImage(image: value.image) } label: {
                        Image(uiImage: value.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(GG.Surface.stroke, lineWidth: 1))
                            .overlay(alignment: .bottomTrailing) {
                                // Says it's tappable. A thumbnail that happens
                                // to be a button is a thumbnail nobody taps.
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(Color.black.opacity(0.55), in: Circle())
                                    .padding(3)
                            }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(value.platform.isEmpty ? "Which app is this?" : value.platform)
                            .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                        HStack(spacing: 6) {
                            Text(dayLabel(value))
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                            if value.gross > 0 {
                                Text("·").ggText(GG.Typo.footnote, color: GG.Ink.muted)
                                Text(Money.cents(value.gross))
                                    .ggText(.system(size: 13, weight: .semibold),
                                            color: GG.Palette.mint)
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
                if value.isDuplicate {
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(GG.Palette.amber)
                            .frame(width: 6, height: 6).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(value.isSkipped
                                 ? "Already imported — this one will be skipped."
                                 : "Already imported. Saving it again will double this day's earnings.")
                                .ggText(.system(size: 11.5, weight: .medium),
                                        color: GG.Palette.amber.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                if value.isSkipped {
                                    source.wrappedValue.duplicateOverride = true
                                    source.wrappedValue.isSkipped = false
                                } else {
                                    source.wrappedValue.duplicateOverride = false
                                    source.wrappedValue.isSkipped = true
                                }
                            } label: {
                                Text(value.isSkipped
                                     ? "Include this corrected import"
                                     : "Exclude this duplicate")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GG.Palette.violet300)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if let note = value.detectedNote {
                    Text(note)
                        .ggText(.system(size: 11.5, weight: .regular),
                                color: value.needsDate ? GG.Palette.amber.opacity(0.9)
                                                       : GG.Ink.muted)
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

                    // A week of dailies is seven screenshots of one app.
                    // Asking seven times is asking six times too many.
                    if !value.platform.isEmpty && sources.contains(where: { $0.platform.isEmpty }) {
                        Button {
                            let name = value.platform
                            withAnimation(.easeOut(duration: 0.18)) {
                                for index in sources.indices where sources[index].platform.isEmpty {
                                    sources[index].platform = name
                                }
                            }
                        } label: {
                            Text("Use \(value.platform) for the rest")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(GG.Palette.violet400)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    RowDivider()
                    figureRow("Gross", text: source.amountText, prefix: "$",
                              alternatives: value.parsed.amounts.map {
                                  (String(format: "%.2f", $0.value), context(of: $0.source))
                              })
                    // The breakdown was on the screen and being thrown away.
                    // It's what answers "was this a good day or a good quest".
                    // Fare is editable too, and writes back through the
                    // total. Four independent boxes could disagree; a fare
                    // that adjusts the gross cannot.
                    RowDivider()
                    figureRow("Fare", text: fareBinding(source), prefix: "$",
                              alternatives: value.parsed.amounts.map {
                                  (String(format: "%.2f", $0.value), context(of: $0.source))
                              })
                    RowDivider()
                    figureRow("of which tips", text: source.tipsText, prefix: "$",
                              alternatives: value.parsed.amounts.map {
                                  (String(format: "%.2f", $0.value), context(of: $0.source))
                              })
                    RowDivider()
                    figureRow("of which promotions", text: source.promotionsText, prefix: "$",
                              alternatives: value.parsed.amounts.map {
                                  (String(format: "%.2f", $0.value), context(of: $0.source))
                              })

                    if value.gross > 0 {
                        breakdownSummary(value)
                    }

                    RowDivider()
                    // "Units" meant nothing to anyone. Every app has its own
                    // word for the thing it counts, and it is on the screen
                    // being imported.
                    figureRow(unitNoun(for: value.platform), text: source.unitsText,
                              prefix: "",
                              alternatives: value.parsed.units.map {
                                  ("\($0.value)", context(of: $0.source))
                              })
                    RowDivider()
                    timeRow(source)
                    RowDivider()
                    figureRow("Miles", text: source.milesText, prefix: "",
                              alternatives: value.parsed.miles.map {
                                  (String(format: "%.0f", $0.value), context(of: $0.source))
                              })
                    if value.period == .week, let shares = value.dailyShares {
                        RowDivider()
                        splitRow(source, shares: shares)
                    } else if value.period == .week {
                        RowDivider()
                        Text("Daily estimate unavailable—the chart couldn't be read. The exact weekly total can still be saved.")
                            .ggText(.system(size: 11.5, weight: .regular),
                                    color: GG.Palette.amber.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    RowDivider()
                    periodRow(source.period)
                    DatePicker(value.period == .day ? "Date" : "Week starting",
                               selection: Binding(
                                   get: { source.wrappedValue.date },
                                   set: { newDate in
                                       source.wrappedValue.date = newDate
                                       // Setting it by hand is the confirmation.
                                       source.wrappedValue.needsDate = false
                                       source.wrappedValue.detectedNote = nil
                                   }
                               ),
                               displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(GG.Palette.violet400)
                        .padding(.vertical, 6)

                    if value.needsDate {
                        Text("GigGrow couldn't read this one's date, so it won't save until you set it. Tap the screenshot above to check.")
                            .ggText(GG.Typo.footnote, color: GG.Palette.amber.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        isEditingField = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            source.wrappedValue.isReviewed = true
                            expanded = nil
                        }
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GG.Palette.violet400)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(GG.Surface.glassFaint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 14) {
                        if value.needsDate {
                            Text("Date needed")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GG.Palette.amber)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(GG.Palette.amber.opacity(0.14), in: Capsule())
                        } else {
                            let splitDays = value.dailyShares?
                                .filter { $0 > 0.0001 }.count ?? 0
                            miniStat(
                                value.period == .day
                                    ? "Day"
                                    : (splitDays > 0
                                       ? "\(splitDays) earning days"
                                       : "Week")
                            )
                        }
                        if value.hours > 0 {
                            miniStat(Hours.clock(value.hours))
                        } else {
                            Text("Hours missing")
                                .ggText(.system(size: 12, weight: .medium), color: GG.Palette.amber)
                        }
                        Spacer(minLength: 0)
                        if value.isSkipped {
                            Text(value.isDuplicate ? "Duplicate" : "Excluded")
                                .ggText(.system(size: 12, weight: .semibold),
                                        color: GG.Palette.amber)
                        } else if !isReady(value) {
                            Text("Needs info")
                                .ggText(.system(size: 12, weight: .semibold),
                                        color: GG.Palette.amber)
                        } else if value.isReviewed {
                            HStack(spacing: 4) {
                                CheckGlyph()
                                    .stroke(GG.Palette.mint,
                                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round,
                                                               lineJoin: .round))
                                    .frame(width: 9, height: 9)
                                Text("Ready")
                                    .ggText(.system(size: 12, weight: .semibold),
                                            color: GG.Palette.mint)
                            }
                        } else {
                            Text("Tap to edit")
                                .ggText(.system(size: 12, weight: .medium), color: GG.Ink.muted)
                        }
                    }
                }
            }
            .opacity(value.isSkipped ? 0.4 : 1)
            .overlay(alignment: .leading) {
                // A stripe down the edge rather than a tinted card: the
                // amounts have to stay legible, and colouring the whole
                // surface fights the figures for attention.
                Capsule()
                    .fill(statusColour(value))
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .offset(x: -9)
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

    /// Fare, as an editable value over the three that are stored.
    ///
    /// Reading it is `gross - tips - promotions`. Writing it moves the total
    /// instead: set the fare to $102.18 with $5.11 of promos and a $7.00 tip
    /// and the gross becomes $114.29. That keeps one stored truth, so the
    /// four figures can never contradict each other — which they would the
    /// moment fare became a fourth independent box.
    private func fareBinding(_ source: Binding<ImportedSource>) -> Binding<String> {
        Binding(
            get: {
                let fare = source.wrappedValue.baseFare
                return fare > 0 ? String(format: "%.2f", fare) : ""
            },
            set: { newValue in
                guard let fare = Double(newValue) else { return }
                let parts = source.wrappedValue.tips + source.wrappedValue.promotions
                source.wrappedValue.amountText = String(format: "%.2f", fare + parts)
            }
        )
    }

    /// Shows the three parts against the total. If they don't add up, one
    /// was misread — and that is worth catching here rather than in April.
    @ViewBuilder
    private func breakdownSummary(_ value: ImportedSource) -> some View {
        let parts = value.tips + value.promotions
        let balances = parts <= value.gross + 0.02

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 0) {
                Text("Fare ")
                    .ggText(.system(size: 12.5, weight: .regular), color: GG.Ink.muted)
                Text(Money.cents(value.baseFare))
                    .ggText(.system(size: 12.5, weight: .semibold), color: GG.Ink.secondary)
                if value.promotions > 0 {
                    Text("  ·  Promos ")
                        .ggText(.system(size: 12.5, weight: .regular), color: GG.Ink.muted)
                    Text(Money.cents(value.promotions))
                        .ggText(.system(size: 12.5, weight: .semibold), color: GG.Palette.amber)
                }
                if value.tips > 0 {
                    Text("  ·  Tips ")
                        .ggText(.system(size: 12.5, weight: .regular), color: GG.Ink.muted)
                    Text(Money.cents(value.tips))
                        .ggText(.system(size: 12.5, weight: .semibold), color: GG.Palette.mint)
                }
                Spacer(minLength: 0)
            }

            if !balances {
                Text("Tips and promotions come to more than the total — one of these was read wrong.")
                    .ggText(.system(size: 11.5, weight: .regular),
                            color: GG.Palette.amber.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let readFare = value.parsed.netFare,
                      abs(readFare - value.baseFare) > 0.02 {
                // The screenshot printed a fare and the fields imply another.
                // Say which is which rather than silently preferring one.
                Text("The screenshot says the fare was \(Money.cents(readFare)); these figures work out to \(Money.cents(value.baseFare)). Check the total and the tip.")
                    .ggText(.system(size: 11.5, weight: .regular),
                            color: GG.Palette.amber.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            } else if value.promotions > 0 {
                let share = Int((value.promotions / value.gross * 100).rounded())
                Text("\(share)% of this came from promotions, which won't repeat on a normal day.")
                    .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    /// Time online, entered the way the screenshot writes it.
    ///
    /// Two fields rather than one decimal. Nobody knows what 4.37 hours is
    /// without doing arithmetic, and being asked to type it is worse — the
    /// driver reads "4 h 22 m" off the photo and would have to convert it
    /// themselves to fill in a box marked Hours.
    @ViewBuilder
    private func timeRow(_ source: Binding<ImportedSource>) -> some View {
        let value = source.wrappedValue

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Time online")
                    .ggText(GG.Typo.rowLabel)
                if value.hours <= 0 {
                    Text("required")
                        .ggText(.system(size: 11, weight: .medium), color: GG.Palette.amber)
                }

                Spacer(minLength: 12)

                unitField(source.hoursText, placeholder: "0", unit: "h", width: 46)
                unitField(source.minutesText, placeholder: "00", unit: "m", width: 46)
            }

            if value.parsed.hours.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(value.parsed.hours.prefix(5).enumerated()),
                                id: \.offset) { _, candidate in
                            let split = Hours.split(candidate.value)
                            let isPicked = abs(candidate.value - value.hours) < 0.005
                            Button {
                                source.wrappedValue.hoursText = "\(split.hours)"
                                source.wrappedValue.minutesText = "\(split.minutes)"
                            } label: {
                                // Written exactly as the screenshot writes it,
                                // so it can be matched without arithmetic.
                                Text(Hours.spaced(candidate.value))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(isPicked ? GG.Palette.violet300
                                                              : GG.Ink.secondary)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(GG.Surface.glassFaint,
                                                in: RoundedRectangle(cornerRadius: 10,
                                                                     style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(isPicked
                                                          ? GG.Palette.violet400.opacity(0.55)
                                                          : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 14)
    }

    private func unitField(_ text: Binding<String>, placeholder: String,
                           unit: String, width: CGFloat) -> some View {
        HStack(spacing: 3) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .focused($isEditingField)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: width)
            Text(unit)
                .ggText(.system(size: 13.5, weight: .medium), color: GG.Ink.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(GG.Surface.glassFaint,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Where this card stands: needs something, been checked, or untouched.
    private func statusColour(_ value: ImportedSource) -> Color {
        if value.isSkipped || !isReady(value) {
            return GG.Palette.amber
        }
        return value.isReviewed ? GG.Palette.mint : Color.clear
    }

    private func isReady(_ value: ImportedSource) -> Bool {
        !value.platform.isEmpty
            && value.gross > 0
            && value.hours > 0
            && !value.needsDate
    }

    /// Offer to estimate which calendar days received the week's earnings.
    ///
    /// The total is exact — it's printed on the screen. The split is measured
    /// off a bar chart maybe eighty pixels tall, so it's good to a few dollars
    /// per day, not to the cent. The card says which is which, because a
    /// figure that looks precise and isn't is worse than an obvious estimate.
    @ViewBuilder
    private func splitRow(_ source: Binding<ImportedSource>, shares: [Double]) -> some View {
        let value = source.wrappedValue
        let calendar = Calendar.gigGrow
        let weekStart = calendar.startOfWeek(for: value.date)

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated earnings by day")
                    .ggText(GG.Typo.rowLabel)
                Text("Read from the chart automatically. It cannot identify exact shifts or daily online hours.")
                    .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                    if let day = calendar.date(byAdding: .day, value: index, to: weekStart) {
                        HStack {
                            Text(shortWeekdayLabel(for: day))
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                                .frame(width: 38, alignment: .leading)
                            // The bar, redrawn — so the split can be
                            // checked against the screenshot by eye.
                            GeometryReader { geo in
                                Capsule()
                                    .fill(share > 0.001
                                          ? AnyShapeStyle(GG.Gradients.brandMark)
                                          : AnyShapeStyle(GG.Surface.glassFaint))
                                    .frame(width: min(max(geo.size.width * share * 3, 2),
                                                      geo.size.width))
                            }
                            .frame(height: 6)
                            Text(share > 0.001
                                 ? "~\(Money.whole(value.gross * share))"
                                 : "—")
                                .ggText(.system(size: 12.5, weight: .medium),
                                        color: share > 0.001 ? GG.Ink.secondary : GG.Ink.muted)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }

            Text("The weekly total is exact; each daily amount is approximate. These are days with earnings, not necessarily days worked—late tips or adjustments can add a day.")
                .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
    }

    private func miniStat(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(GG.Ink.tertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(GG.Surface.glassFaint, in: Capsule())
    }

    private func shortWeekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// The words around a parsed figure, trimmed to a chip's worth.
    ///
    /// The raw source is the whole OCR line — "Total Earnings $291.64" — so
    /// stripping the number leaves exactly the label that identifies it.
    private func context(of source: String) -> String {
        let words = source
            .replacingOccurrences(of: #"[$€£]?\s?-?[\d,]+\.?\d*"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:·-–—"))
        return words.count > 22 ? String(words.prefix(21)) + "…" : words
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
            return f.string(from: Calendar.gigGrow.startOfWeek(for: source.date))
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
                    .foregroundStyle(isSelected ? GG.Ink.primary : GG.Ink.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? GG.Surface.glassBright : GG.Surface.glassFaint,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? GG.Palette.violet400.opacity(0.5) : GG.Surface.stroke,
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
                        .foregroundStyle(isSelected ? .white : GG.Ink.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? AnyShapeStyle(GG.Gradients.segment)
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
        GlassCard(radius: GG.Radius.tile,
                  padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
            HStack(alignment: .top, spacing: 11) {
                Circle().fill(GG.Palette.amber)
                    .frame(width: 6, height: 6).padding(.top, 7)
                Text(message)
                    .ggText(GG.Typo.footnote, color: GG.Palette.amber.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryCard: some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(appCount) \(appCount == 1 ? "APP" : "APPS")")
                    .ggText(GG.Typo.heroEyebrow,
                            tracking: GG.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                Text(Money.cents(totalGross))
                    .ggText(GG.Typo.heroAmountSmall, tracking: GG.Typo.heroAmountSmallTracking)

                HStack(spacing: 18) {
                    summaryStat("Per hour",
                                totalHours > 0 ? Money.cents(totalGross / totalHours) : "—")
                    summaryStat("Time", totalHours > 0 ? Hours.clock(totalHours) : "—")
                    summaryStat("Per mile",
                                totalMiles > 0 ? Money.cents(totalGross / totalMiles) : "—")
                    summaryStat("Calendar days",
                                calendarDayCount.map(String.init) ?? "—")
                    summaryStat("Checked", "\(reviewedCount)/\(included.count)")
                }

                if !coverageLabels.isEmpty {
                    Text(coverageLabels.joined(separator: "  ·  "))
                        .ggText(.system(size: 11.5, weight: .medium),
                                color: Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Online time is added across apps; GigGrow does not assume Uber and Lyft were running simultaneously.")
                    .ggText(.system(size: 10.5, weight: .regular),
                            color: Color.white.opacity(0.40))
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Fields

    /// One field, plus the other readings the parser found.
    ///
    /// Each alternative carries the line it was read from. A row of bare
    /// numbers — 258.20, 291.64, 26.12 — is unusable: there is no way to tell
    /// which is the total and which is a tip without going back to the image.
    /// "291.64 · Total Earnings" answers it on the spot.
    private func figureRow(_ label: String, text: Binding<String>, prefix: String,
                           required: Bool = false,
                           suffix: String = "",
                           alternatives: [(value: String, source: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .ggText(GG.Typo.rowLabel)
                if required && (Double(text.wrappedValue) ?? 0) <= 0 {
                    Text("required")
                        .ggText(.system(size: 11, weight: .medium), color: GG.Palette.amber)
                }
                Spacer(minLength: 12)
                if !prefix.isEmpty {
                    Text(prefix)
                        .ggText(.system(size: 15, weight: .medium), color: GG.Ink.muted)
                }
                TextField("—", text: text)
                    .keyboardType(.decimalPad)
                    .focused($isEditingField)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 90)

                if !suffix.isEmpty {
                    Text(suffix)
                        .ggText(.system(size: 12.5, weight: .medium), color: GG.Ink.muted)
                        .frame(minWidth: 54, alignment: .trailing)
                }
            }

            // Other readings, so a wrong pick is one tap to fix.
            if alternatives.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(alternatives.prefix(6).enumerated()), id: \.offset) { _, alt in
                            let isPicked = text.wrappedValue == alt.value
                            Button { text.wrappedValue = alt.value } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(alt.value)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(isPicked ? GG.Palette.violet300
                                                                  : GG.Ink.secondary)
                                    if !alt.source.isEmpty {
                                        Text(alt.source)
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(GG.Ink.muted)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(GG.Surface.glassFaint,
                                            in: RoundedRectangle(cornerRadius: 10,
                                                                 style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(isPicked
                                                      ? GG.Palette.violet400.opacity(0.55)
                                                      : Color.clear, lineWidth: 1)
                                )
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

    private var totalGross: Double { included.reduce(0) { $0 + $1.gross } }

    /// Each app report carries its own online total. The importer cannot
    /// prove overlap, so it keeps those denominators independent and adds
    /// them instead of silently discarding the shorter platform's time.
    private var totalHours: Double {
        included.reduce(0) { $0 + $1.hours }
    }

    private var totalMiles: Double {
        included.reduce(0) { $0 + $1.miles }
    }

    /// Unchecked first, then checked, then skipped — stable within each
    /// group so cards don't shuffle while you're reading them.
    private var displayOrder: [UUID] {
        sources.enumerated()
            .sorted { a, b in
                let x = a.element, y = b.element
                if x.isSkipped != y.isSkipped { return !x.isSkipped }
                if x.isReviewed != y.isReviewed { return !x.isReviewed }
                return a.offset < b.offset
            }
            .map(\.element.id)
    }

    private var reviewedCount: Int { included.filter(\.isReviewed).count }

    private var appCount: Int {
        Set(included.map(\.platform).filter { !$0.isEmpty }).count
    }

    /// Distinct dates represented across every app. Uber and Lyft can both
    /// contribute to Monday without turning Monday into two calendar days.
    /// A whole weekly total with no readable distribution makes this
    /// unknowable, so the summary shows a dash rather than "1".
    private var calendarDayCount: Int? {
        let calendar = Calendar.gigGrow
        var dates: Set<Date> = []

        for source in included {
            if source.period == .day {
                dates.insert(calendar.startOfDay(for: source.date))
                continue
            }

            guard let shares = source.dailyShares
            else { return nil }

            let weekStart = calendar.startOfWeek(for: source.date)
            for (index, share) in shares.enumerated() where share > 0.0001 {
                guard let day = calendar.date(byAdding: .day,
                                              value: index,
                                              to: weekStart)
                else { continue }
                dates.insert(calendar.startOfDay(for: day))
            }
        }
        return dates.count
    }

    /// Coverage is reported per app rather than collapsed into a fictional
    /// number of shifts. A non-zero bar is an earnings day; it may be a late
    /// tip or adjustment and therefore is not proof the driver worked.
    private var coverageLabels: [String] {
        included.map { source in
            if source.period == .day {
                return "\(source.platform): 1 report day"
            }
            if let shares = source.dailyShares {
                let count = shares.filter { $0 > 0.0001 }.count
                return "\(source.platform): \(count) earning \(count == 1 ? "day" : "days")"
            }
            return "\(source.platform): weekly total"
        }
    }

    /// Names the actual clash rather than warning in general terms.
    private var overlapWarning: String? {
        let calendar = Calendar.gigGrow
        let weeks = included.filter { $0.period == .week }
        guard !weeks.isEmpty else { return nil }

        let f = DateFormatter()
        f.dateFormat = "MMM d"

        for week in weeks {
            let start = calendar.startOfWeek(for: week.date)
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { continue }
            let inside = included.filter { $0.period == .day && $0.date >= start && $0.date < end }
            guard !inside.isEmpty else { continue }
            return "The weekly total for \(f.string(from: start)) already includes \(inside.count) of the daily screenshots below. Saving both counts that money twice — remove the week, or remove the days."
        }
        return nil
    }

    private var included: [ImportedSource] { sources.filter { !$0.isSkipped } }

    private var canSave: Bool {
        !included.isEmpty
            && included.allSatisfy(isReady)
    }

    private var saveBlockingMessage: String? {
        guard !canSave else { return nil }
        if included.isEmpty, !sources.isEmpty {
            return "Nothing is included. These reports were already imported, so GigGrow excluded them to prevent double-counting. Open each card and tap “Include this corrected import”, or delete the previous import first."
        }
        let missingApps = included.filter { $0.platform.isEmpty }.count
        let missingGross = included.filter { $0.gross <= 0 }.count
        let missingHours = included.filter { $0.hours <= 0 }.count
        let missingDates = included.filter(\.needsDate).count
        var reasons: [String] = []
        if missingApps > 0 { reasons.append("\(missingApps) app name") }
        if missingGross > 0 { reasons.append("\(missingGross) gross total") }
        if missingHours > 0 { reasons.append("\(missingHours) online time") }
        if missingDates > 0 { reasons.append("\(missingDates) date") }
        return reasons.isEmpty
            ? "Review the included reports before saving."
            : "Save is waiting for: \(reasons.joined(separator: ", "))."
    }

    /// Whether a shift already stored covers this screenshot's day with the
    /// same app. Matched on the block, not the exact amount, because the
    /// second import of a day is usually a *corrected* one — same day, same
    /// app, different figure — and that is still a duplicate.
    private func alreadyStored(_ source: ImportedSource) -> Bool {
        guard !source.platform.isEmpty else { return false }
        let calendar = Calendar.gigGrow
        let anchor = source.period == .week
            ? calendar.startOfWeek(for: source.date)
            : calendar.startOfDay(for: source.date)

        return existingShifts.contains { shift in
            guard shift.isAggregate == (source.period == .week) else { return false }
            let shiftAnchor = source.period == .week
                ? calendar.startOfWeek(for: shift.start)
                : calendar.startOfDay(for: shift.start)
            guard shiftAnchor == anchor else { return false }
            return shift.earnings.contains { $0.account?.name == source.platform }
        }
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

            // The period header — "Jun 1 - Jun 8" — is the only date on the
            // screen that definitely describes what's being shown. Falling
            // back to today, as this used to, turned a June screenshot into
            // "Sunday 26 July" and stated it with a chart reading behind it.
            let headerWeek = EarningsParser.weekStart(in: lines)
                ?? best.date.map { Calendar.gigGrow.startOfWeek(for: $0) }

            var period: ImportPeriod = .week
            var resolved = headerWeek ?? Calendar.gigGrow.startOfWeek(for: .now)
            var note: String?
            var needsDate = headerWeek == nil
            var shares: [Double]?

            let f = DateFormatter()
            f.dateFormat = "EEEE, MMMM d"

            switch (reading, headerWeek) {
            case (.day(_, _, let dayOfMonth), .some(let week)):
                period = .day
                if let day = ChartDayDetector.date(for: reading, weekStart: week) {
                    resolved = day
                    note = dayOfMonth != nil
                        ? "\(f.string(from: day)) — the highlighted bar is labelled \(dayOfMonth!)."
                        : "\(f.string(from: day)) — read from the highlighted bar."
                }

            case (.day(_, _, let dayOfMonth), .none):
                // The bar was readable but there's no week to place it in.
                period = .day
                needsDate = true
                note = dayOfMonth != nil
                    ? "The highlighted bar is labelled \(dayOfMonth!), but the date header couldn't be read — set the date below."
                    : "Couldn't read the date header. Set the date below."

            case (.aggregate, _):
                period = .week
                // A week's bars are the only record of its shape. Read them
                // now so the driver can choose to keep it.
                shares = parsed.platformName == "Lyft"
                    ? ChartDayDetector.lyftDailyShares(
                        image: cgImage, lines: lines, total: best.amount
                    )
                    : ChartDayDetector.dailyShares(
                        image: cgImage, lines: lines, total: best.amount
                    )
                note = headerWeek != nil
                    ? "This appears to be the weekly earnings chart."
                    : "This appears to be a weekly chart, but the date header couldn't be read."

            case (.inconclusive, _):
                // Some weekly charts (notably Lyft in dark mode) don't have
                // enough saturated pixels to classify as aggregate, but the
                // weekday row and printed daily dollar labels still provide
                // a usable earnings distribution.
                if parsed.platformName == "Lyft" {
                    shares = ChartDayDetector.lyftDailyShares(
                        image: cgImage,
                        lines: lines,
                        total: best.amount
                    )
                }
                if shares != nil {
                    note = headerWeek != nil
                        ? "Weekly earnings distribution read from the chart."
                        : "Weekly earnings distribution found, but the date header couldn't be read."
                } else {
                    note = headerWeek != nil
                        ? "Couldn't identify a selected day, so this is kept as a weekly total."
                        : "Couldn't read the date header or identify a selected day. Set both below."
                }
            }

            sources.append(
                ImportedSource(
                    image: uiImage,
                    parsed: parsed,
                    // Don't reuse a platform already claimed by another
                    // screenshot of the same block — that would double it.
                    platform: parsed.platformName ?? "",
                    amountText: best.amount.map { String(format: "%.2f", $0) } ?? "",
                    tipsText: parsed.tips.map { String(format: "%.2f", $0) } ?? "",
                    promotionsText: parsed.promotions.map { String(format: "%.2f", $0) } ?? "",
                    unitsText: best.units.map(String.init) ?? "",
                    hoursText: best.hours.map { "\(Hours.split($0).hours)" } ?? "",
                    minutesText: best.hours.map { "\(Hours.split($0).minutes)" } ?? "",
                    milesText: best.miles.map { String(format: "%.0f", $0) } ?? "",
                    period: period,
                    date: resolved,
                    detectedNote: note,
                    needsDate: needsDate,
                    dailyShares: shares
                    // A readable weekly chart is always stored by day. The
                    // only honest reason to keep one opaque total is that no
                    // daily distribution was available.
                )
            )
        }

        markDuplicates()

        if failures > 0 {
            errorMessage = failures == items.count
                ? "None of those could be read. You can still fill the figures in by hand."
                : "\(failures) of \(items.count) couldn't be read; the rest are below."
        }
    }

    /// Duplicates start excluded rather than deleted — you may be replacing
    /// a bad import on purpose, and the app shouldn't decide that for you.
    private func markDuplicates() {
        for index in sources.indices {
            let duplicate = alreadyStored(sources[index])
            sources[index].isDuplicate = duplicate
            if duplicate && !sources[index].duplicateOverride {
                sources[index].isSkipped = true
            }
        }
    }

    private func remove(_ id: UUID) {
        sources.removeAll { $0.id == id }
    }

    // MARK: Save

    /// Screenshots are grouped by platform and the period they describe.
    /// Platform time stays independent: without trip-level timestamps there
    /// is no evidence that Uber's online hours overlap Lyft's.
    private func save() {
        guard canSave else { return }

        let calendar = Calendar.gigGrow
        let usable = included.filter { !$0.platform.isEmpty && $0.gross > 0 && $0.hours > 0 }
        let groups = Dictionary(grouping: usable) { $0.groupKey(calendar) }
        var daysStored = 0

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
                if first.dailyShares != nil {
                    // Each platform keeps the shape of its own chart. Reusing
                    // Uber's bars for Lyft (or the reverse) fabricates work
                    // on days where that app was actually idle.
                    daysStored += saveSplitWeek(
                        group, hours: hours, miles: miles, calendar: calendar
                    )
                    continue
                }
                // Spans the week it covers. `recordedHours` carries the real
                // figure so nothing reads 168 hours off the span.
                let start = calendar.startOfWeek(for: first.date)
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
                shift = Shift(start: start, end: end, miles: miles)
                shift.recordedHours = hours
                shift.isAggregate = true
            }

            context.insert(shift)
            daysStored += 1

            // One earning per screenshot in the block. Two screenshots of the
            // same app on the same day are added together rather than
            // creating a duplicate account row.
            var byAccount: [String: PlatformEarning] = [:]
            for source in group {
                guard let account = accounts.first(where: { $0.name == source.platform })
                else { continue }

                if let existing = byAccount[source.platform] {
                    existing.gross += source.gross
                    existing.tips += source.tips
                    existing.promotions += source.promotions
                    existing.trips += Int(source.unitsText) ?? 0
                    continue
                }

                let earning = PlatformEarning(account: account,
                                              gross: source.gross,
                                              tips: source.tips,
                                              promotions: source.promotions,
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

        do {
            try context.save()
        } catch {
            errorMessage = "Those couldn't be saved: \(error.localizedDescription)"
            return
        }

        report(groups: groups, daysStored: daysStored)
    }

    /// Turns a weekly total into the days that made it.
    ///
    /// Days the chart shows as empty are skipped rather than stored as zero
    /// shifts — a day you didn't drive is not a day you earned nothing, and
    /// an empty row would drag your average down.
    @discardableResult
    private func saveSplitWeek(_ group: [ImportedSource],
                               hours: Double, miles: Double,
                               calendar: Calendar) -> Int {
        guard let first = group.first else { return 0 }
        var created = 0
        let weekStart = calendar.startOfWeek(for: first.date)
        let allocations = WeeklySplitAllocator.allocate(group.compactMap { source in
            guard let shares = source.dailyShares else { return nil }
            return WeeklyPlatformSplit(
                platform: source.platform,
                gross: source.gross,
                tips: source.tips,
                promotions: source.promotions,
                trips: Int(source.unitsText) ?? 0,
                dailyShares: shares
            )
        })

        for allocation in allocations {
            guard let day = calendar.date(byAdding: .day,
                                          value: allocation.dayIndex,
                                          to: weekStart),
                  let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
            else { continue }

            // Weekly screenshots do not contain hours per day. Allocate the
            // confirmed weekly total in proportion to combined earnings so
            // the overall $/hour remains exact, while keeping it explicitly
            // marked as estimated/aggregate.
            let dayHours = hours * allocation.combinedShare
            let shift = Shift(start: start,
                              end: start.addingTimeInterval(dayHours * 3600),
                              miles: miles * allocation.combinedShare)
            // The day is real, but 9am is only a storage anchor. A weekly
            // screenshot says how many hours were online, not which hours of
            // the clock produced the money, so it must not fabricate an
            // hourly peak in Analytics.
            shift.recordedHours = dayHours
            shift.isAggregate = true
            shift.note = "From a weekly screenshot — day split read off the chart"
            context.insert(shift)

            for dayEarning in allocation.earnings {
                guard let account = accounts.first(where: {
                    $0.name == dayEarning.platform
                })
                else { continue }
                let earning = PlatformEarning(
                    account: account,
                    gross: dayEarning.gross,
                    tips: dayEarning.tips,
                    promotions: dayEarning.promotions,
                    trips: dayEarning.trips
                )
                context.insert(earning)
                earning.shift = shift
                shift.earnings.append(earning)
            }
            created += 1
        }
        return created
    }

    /// Says what landed and, crucially, when. Importing June's screenshots in
    /// July saves correctly and changes nothing on a dashboard headed "This
    /// week" — which reads exactly like a broken Save button.
    private func report(groups: [String: [ImportedSource]], daysStored: Int) {
        let saved = groups.values.flatMap { $0 }
        guard !saved.isEmpty else {
            errorMessage = "Nothing was saved — each screenshot needs an app, an amount and a time."
            return
        }

        let calendar = Calendar.gigGrow
        let dates = saved.map(\.date)
        let thisWeek = calendar.startOfWeek(for: .now)

        outcome = SaveOutcome(
            entries: daysStored,
            reports: saved.count,
            wasWholeWeek: saved.contains { $0.period == .week && $0.dailyShares == nil },
            gross: saved.reduce(0) { $0 + $1.gross },
            earliest: dates.min() ?? .now,
            latest: dates.max() ?? .now,
            outsideThisWeek: !dates.contains { calendar.startOfWeek(for: $0) == thisWeek }
        )
    }

    private func summary(_ result: SaveOutcome) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"

        let span = calendarSpan(result, formatter: f)
        var text: String
        if result.reports > 1 {
            text = "\(Money.cents(result.gross)) from \(result.reports) app reports, \(span)."
        } else if result.wasWholeWeek {
            text = "\(Money.cents(result.gross)) for the week of \(span), kept as one total."
        } else {
            text = "\(Money.cents(result.gross)) on \(span)."
        }

        if result.entries > result.reports {
            text += "\n\nThe chart produced \(result.entries) estimated daily earnings entries. That is not a count of actual shifts."
        }

        if result.outsideThisWeek {
            text += "\n\nThe dashboard shows this week, so it won't change. Open Analytics and pick a wider range, or Shift history, to see these."
        }
        return text
    }

    private func calendarSpan(_ result: SaveOutcome, formatter f: DateFormatter) -> String {
        let calendar = Calendar.gigGrow
        if calendar.isDate(result.earliest, inSameDayAs: result.latest) {
            return f.string(from: result.earliest)
        }
        return "\(f.string(from: result.earliest))–\(f.string(from: result.latest))"
    }
}

#Preview("Import screenshots") {
    ImportScreenshotView()
        .modelContainer(.preview)
}
