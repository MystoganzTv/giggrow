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
    /// Set when this looks like something already in the store. Not a block —
    /// a driver may legitimately be replacing a bad import — but silence here
    /// means quietly doubling a week's income, which is the worst kind of
    /// wrong number because every rate downstream still looks plausible.
    var isDuplicate: Bool = false
    /// Excluded from the save. Duplicates start excluded.
    var isSkipped: Bool = false
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
        let shifts: Int
        let gross: Double
        let earliest: Date
        let latest: Date
        /// True when none of it falls in the week the dashboard displays.
        let outsideThisWeek: Bool
    }

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
                    Button { viewing = ViewedImage(image: source.image) } label: {
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
                                .strokeBorder(GP.Surface.stroke, lineWidth: 1))
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
                if value.isDuplicate {
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(GP.Palette.amber)
                            .frame(width: 6, height: 6).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(value.isSkipped
                                 ? "Already imported — this one will be skipped."
                                 : "Already imported. Saving it again will double this day's earnings.")
                                .gpText(.system(size: 11.5, weight: .medium),
                                        color: GP.Palette.amber.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                source.wrappedValue.isSkipped.toggle()
                            } label: {
                                Text(value.isSkipped ? "Import it anyway" : "Skip this one")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GP.Palette.violet300)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if let note = value.detectedNote {
                    Text(note)
                        .gpText(.system(size: 11.5, weight: .regular),
                                color: value.needsDate ? GP.Palette.amber.opacity(0.9)
                                                       : GP.Ink.muted)
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
                                .foregroundStyle(GP.Palette.violet400)
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
                        .tint(GP.Palette.violet400)
                        .padding(.vertical, 6)

                    if value.needsDate {
                        Text("GigPilot couldn't read this one's date, so it won't save until you set it. Tap the screenshot above to check.")
                            .gpText(GP.Typo.footnote, color: GP.Palette.amber.opacity(0.9))
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
                            .foregroundStyle(GP.Palette.violet400)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(GP.Surface.glassFaint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 14) {
                        if value.needsDate {
                            Text("Date needed")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GP.Palette.amber)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(GP.Palette.amber.opacity(0.14), in: Capsule())
                        } else {
                            miniStat(value.period == .day ? "Day" : "Week")
                        }
                        if value.hours > 0 {
                            miniStat(Hours.clock(value.hours))
                        } else {
                            Text("Hours missing")
                                .gpText(.system(size: 12, weight: .medium), color: GP.Palette.amber)
                        }
                        Spacer(minLength: 0)
                        if value.isReviewed {
                            HStack(spacing: 4) {
                                CheckGlyph()
                                    .stroke(GP.Palette.mint,
                                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round,
                                                               lineJoin: .round))
                                    .frame(width: 9, height: 9)
                                Text("Checked")
                                    .gpText(.system(size: 12, weight: .semibold),
                                            color: GP.Palette.mint)
                            }
                        } else {
                            Text("Tap to edit")
                                .gpText(.system(size: 12, weight: .medium), color: GP.Ink.muted)
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
                    .opacity(value.isSkipped ? 0 : 1)
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
                    .gpText(.system(size: 12.5, weight: .regular), color: GP.Ink.muted)
                Text(Money.cents(value.baseFare))
                    .gpText(.system(size: 12.5, weight: .semibold), color: GP.Ink.secondary)
                if value.promotions > 0 {
                    Text("  ·  Promos ")
                        .gpText(.system(size: 12.5, weight: .regular), color: GP.Ink.muted)
                    Text(Money.cents(value.promotions))
                        .gpText(.system(size: 12.5, weight: .semibold), color: GP.Palette.amber)
                }
                if value.tips > 0 {
                    Text("  ·  Tips ")
                        .gpText(.system(size: 12.5, weight: .regular), color: GP.Ink.muted)
                    Text(Money.cents(value.tips))
                        .gpText(.system(size: 12.5, weight: .semibold), color: GP.Palette.mint)
                }
                Spacer(minLength: 0)
            }

            if !balances {
                Text("Tips and promotions come to more than the total — one of these was read wrong.")
                    .gpText(.system(size: 11.5, weight: .regular),
                            color: GP.Palette.amber.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let readFare = value.parsed.netFare,
                      abs(readFare - value.baseFare) > 0.02 {
                // The screenshot printed a fare and the fields imply another.
                // Say which is which rather than silently preferring one.
                Text("The screenshot says the fare was \(Money.cents(readFare)); these figures work out to \(Money.cents(value.baseFare)). Check the total and the tip.")
                    .gpText(.system(size: 11.5, weight: .regular),
                            color: GP.Palette.amber.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            } else if value.promotions > 0 {
                let share = Int((value.promotions / value.gross * 100).rounded())
                Text("\(share)% of this came from promotions, which won't repeat on a normal day.")
                    .gpText(.system(size: 11.5, weight: .regular), color: GP.Ink.muted)
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
                    .gpText(GP.Typo.rowLabel)
                if value.hours <= 0 {
                    Text("required")
                        .gpText(.system(size: 11, weight: .medium), color: GP.Palette.amber)
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
                                    .foregroundStyle(isPicked ? GP.Palette.violet300
                                                              : GP.Ink.secondary)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(GP.Surface.glassFaint,
                                                in: RoundedRectangle(cornerRadius: 10,
                                                                     style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(isPicked
                                                          ? GP.Palette.violet400.opacity(0.55)
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
                .gpText(.system(size: 13.5, weight: .medium), color: GP.Ink.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(GP.Surface.glassFaint,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Where this card stands: needs something, been checked, or untouched.
    private func statusColour(_ value: ImportedSource) -> Color {
        if value.needsDate || value.platform.isEmpty || value.hours <= 0 {
            return GP.Palette.amber
        }
        return value.isReviewed ? GP.Palette.mint : Color.clear
    }

    private func miniStat(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(GP.Ink.tertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(GP.Surface.glassFaint, in: Capsule())
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
                    summaryStat("Time", totalHours > 0 ? Hours.clock(totalHours) : "—")
                    summaryStat("Per mile",
                                totalMiles > 0 ? Money.cents(totalGross / totalMiles) : "—")
                    summaryStat(blockCount == 1 ? "Shift" : "Shifts", "\(blockCount)")
                    summaryStat("Checked", "\(reviewedCount)/\(included.count)")
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
                    .frame(maxWidth: 90)

                if !suffix.isEmpty {
                    Text(suffix)
                        .gpText(.system(size: 12.5, weight: .medium), color: GP.Ink.muted)
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
                                        .foregroundStyle(isPicked ? GP.Palette.violet300
                                                                  : GP.Ink.secondary)
                                    if !alt.source.isEmpty {
                                        Text(alt.source)
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(GP.Ink.muted)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(GP.Surface.glassFaint,
                                            in: RoundedRectangle(cornerRadius: 10,
                                                                 style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(isPicked
                                                      ? GP.Palette.violet400.opacity(0.55)
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

    /// Summed across blocks, not across screenshots: two apps in the same
    /// block share those hours, and adding them would halve every rate.
    private var totalHours: Double {
        Dictionary(grouping: included) { $0.groupKey(Calendar.gigPilot) }
            .values
            .reduce(0) { $0 + ($1.map(\.hours).max() ?? 0) }
    }

    private var totalMiles: Double {
        Dictionary(grouping: included) { $0.groupKey(Calendar.gigPilot) }
            .values
            .reduce(0) { $0 + ($1.map(\.miles).max() ?? 0) }
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

    private var blockCount: Int {
        Set(included.map { $0.groupKey(Calendar.gigPilot) }).count
    }

    /// Names the actual clash rather than warning in general terms.
    private var overlapWarning: String? {
        let calendar = Calendar.gigPilot
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
        included.contains { !$0.platform.isEmpty && $0.gross > 0 }
            && included.allSatisfy { $0.platform.isEmpty || ($0.hours > 0 && !$0.needsDate) }
    }

    /// Whether a shift already stored covers this screenshot's day with the
    /// same app. Matched on the block, not the exact amount, because the
    /// second import of a day is usually a *corrected* one — same day, same
    /// app, different figure — and that is still a duplicate.
    private func alreadyStored(_ source: ImportedSource) -> Bool {
        guard !source.platform.isEmpty else { return false }
        let calendar = Calendar.gigPilot
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
                ?? best.date.map { Calendar.gigPilot.startOfWeek(for: $0) }

            var period: ImportPeriod = .week
            var resolved = headerWeek ?? Calendar.gigPilot.startOfWeek(for: .now)
            var note: String?
            var needsDate = headerWeek == nil

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
                note = headerWeek != nil
                    ? "Every bar is filled, so this is the whole week."
                    : "Every bar is filled, so this is a whole week — but the date header couldn't be read."

            case (.inconclusive, _):
                note = headerWeek != nil
                    ? "Couldn't tell a single day from the chart, so this is treated as the week. Switch it below if it's one day."
                    : "Couldn't read the date header or tell which day this is. Set both below."
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
                    needsDate: needsDate
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
            if duplicate { sources[index].isSkipped = true }
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
        let usable = included.filter { !$0.platform.isEmpty && $0.gross > 0 && $0.hours > 0 }
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

        report(groups: groups)
    }

    /// Says what landed and, crucially, when. Importing June's screenshots in
    /// July saves correctly and changes nothing on a dashboard headed "This
    /// week" — which reads exactly like a broken Save button.
    private func report(groups: [String: [ImportedSource]]) {
        let saved = groups.values.flatMap { $0 }
        guard !saved.isEmpty else {
            errorMessage = "Nothing was saved — each screenshot needs an app, an amount and a time."
            return
        }

        let calendar = Calendar.gigPilot
        let dates = saved.map(\.date)
        let thisWeek = calendar.startOfWeek(for: .now)

        outcome = SaveOutcome(
            shifts: groups.count,
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
        let shifts = "\(result.shifts) shift\(result.shifts == 1 ? "" : "s")"
        var text = "\(Money.cents(result.gross)) across \(shifts), \(span)."

        if result.outsideThisWeek {
            text += "\n\nThe dashboard shows this week, so it won't change. Open Analytics and pick a wider range, or Shift history, to see these."
        }
        return text
    }

    private func calendarSpan(_ result: SaveOutcome, formatter f: DateFormatter) -> String {
        let calendar = Calendar.gigPilot
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
