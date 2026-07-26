//
//  ImportScreenshotView.swift
//  GigPilot
//
//  Read a shift off a screenshot of a gig app's earnings screen.
//
//  Phase 1 of getting real data in without a vendor contract. The parser is
//  heuristic, so nothing is saved until the driver has seen what was read
//  next to the image it came from and confirmed it. Every field is editable
//  and every alternative reading is one tap away.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ImportScreenshotView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]
    @Query private var profiles: [DriverProfile]

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var parsed: ParsedEarnings?
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var showsAllLines = false

    // Confirmed values
    @State private var selectedPlatform: String = ""
    @State private var amountText = ""
    @State private var unitsText = ""
    @State private var hoursText = ""
    @State private var milesText = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.appsWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                        if parsed == nil {
                            intro
                            picker
                        } else {
                            reviewHeader
                            imagePreview
                            platformCard
                            figuresCard
                            if let parsed, !parsed.allLines.isEmpty { rawTextCard(parsed) }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .gpText(GP.Typo.footnote, color: GP.Palette.amber)
                                .padding(.horizontal, 6)
                        }
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }

                if isReading { readingOverlay }
            }
            .navigationTitle("Import screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
                if parsed != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .foregroundStyle(canSave ? GP.Palette.violet400 : GP.Ink.muted)
                            .disabled(!canSave)
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Intro

    private var intro: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Read a shift off a screenshot")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                Text("Open your gig app's earnings screen, screenshot it, and pick it here. GigPilot reads the figures and shows you what it found before anything is saved.")
                    .gpText(.system(size: 14, weight: .regular), color: GP.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 11) {
                    Circle().fill(GP.Palette.mint)
                        .frame(width: 6, height: 6).padding(.top, 7)
                    Text("The image never leaves your phone — the text is read on-device.")
                        .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 11) {
                    Circle().fill(GP.Palette.amber)
                        .frame(width: 6, height: 6).padding(.top, 7)
                    Text("Reading a screenshot is guesswork, so check every figure before saving. Anything wrong here quietly skews your hourly rate and tax set-aside.")
                        .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 8) {
                PlusGlyph()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 16, height: 16)
                Text("Choose a screenshot")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(GP.Gradients.brandMark, in: Capsule())
        }
    }

    private var readingOverlay: some View {
        ZStack {
            GP.Palette.screen.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(GP.Palette.violet400)
                Text("Reading the screenshot…")
                    .gpText(GP.Typo.captionMuted, color: GP.Ink.secondary)
            }
        }
    }

    // MARK: Review

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Check what was read")
                .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
            Text("Correct anything that's wrong. Tap a figure to see the other readings found.")
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous)
                        .strokeBorder(GP.Surface.stroke, lineWidth: 1)
                )
        }
    }

    private var platformCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Platform")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Spacer()
                    if parsed?.platformName == nil {
                        Text("not detected")
                            .gpText(GP.Typo.footnote, color: GP.Palette.amber)
                    }
                }

                let columns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(accounts.filter(\.isActive)) { account in
                        platformChip(account)
                    }
                }
            }
        }
    }

    private func platformChip(_ account: PlatformAccount) -> some View {
        let isSelected = account.name == selectedPlatform
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { selectedPlatform = account.name }
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
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? GP.Ink.primary : GP.Ink.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(isSelected ? GP.Surface.glassBright : GP.Surface.glassFaint,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? GP.Palette.violet400.opacity(0.5) : GP.Surface.stroke,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var figuresCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                figureRow("Gross", text: $amountText, prefix: "$",
                          alternatives: (parsed?.amounts ?? []).map {
                              (String(format: "%.2f", $0.value), $0.source)
                          })
                RowDivider()
                figureRow("Units", text: $unitsText, prefix: "",
                          alternatives: (parsed?.units ?? []).map { ("\($0.value)", $0.source) })
                RowDivider()
                figureRow("Hours", text: $hoursText, prefix: "",
                          required: true,
                          alternatives: (parsed?.hours ?? []).map {
                              (String(format: "%.2f", $0.value), $0.source)
                          })

                if missingHours {
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
                          alternatives: (parsed?.miles ?? []).map {
                              (String(format: "%.0f", $0.value), $0.source)
                          })
                RowDivider()
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(GP.Palette.violet400)
                    .padding(.vertical, 6)
            }
        }
    }

    private func figureRow(_ label: String, text: Binding<String>, prefix: String,
                           required: Bool = false,
                           alternatives: [(String, String)]) -> some View {
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

            // Other readings, so a wrong pick is one tap to fix rather than
            // a retype.
            if alternatives.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(alternatives.prefix(5).enumerated()), id: \.offset) { _, alt in
                            Button {
                                text.wrappedValue = alt.0
                            } label: {
                                Text(alt.0)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(text.wrappedValue == alt.0
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

    private func rawTextCard(_ parsed: ParsedEarnings) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { showsAllLines.toggle() }
                } label: {
                    HStack {
                        Text(showsAllLines ? "Hide what was read" : "Show what was read")
                            .gpText(.system(size: 14, weight: .medium), color: GP.Palette.violet400)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if showsAllLines {
                    Text(parsed.allLines.joined(separator: "\n"))
                        .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Actions

    /// Hours are required, not optional.
    ///
    /// They used to default to one when the screenshot didn't show them,
    /// which turned $185.27 of Spark earnings into $185.27 per hour. An
    /// invented denominator is worse than a missing figure: the app can't
    /// tell it's wrong, and neither can the driver reading the dashboard.
    private var canSave: Bool {
        !selectedPlatform.isEmpty
            && (Double(amountText) ?? 0) > 0
            && (Double(hoursText) ?? 0) > 0
    }

    private var missingHours: Bool {
        (Double(hoursText) ?? 0) <= 0
    }

    private func load(_ item: PhotosPickerItem) async {
        isReading = true
        errorMessage = nil
        defer { isReading = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            errorMessage = TextRecognizer.Failure.unreadableImage.localizedDescription
            return
        }

        image = uiImage

        do {
            let lines = try TextRecognizer.recognise(in: cgImage)
            let result = EarningsParser.parse(lines)
            parsed = result
            prefill(from: result)

            if !result.foundAnything {
                errorMessage = "Nothing recognisable was found. You can still fill the figures in by hand."
            }
        } catch {
            errorMessage = error.localizedDescription
            parsed = ParsedEarnings()
        }
    }

    private func prefill(from result: ParsedEarnings) {
        let best = result.best
        selectedPlatform = result.platformName
            ?? accounts.first(where: \.isActive)?.name
            ?? ""
        if let amount = best.amount { amountText = String(format: "%.2f", amount) }
        if let units = best.units { unitsText = "\(units)" }
        if let hours = best.hours { hoursText = String(format: "%.2f", hours) }
        if let miles = best.miles { milesText = String(format: "%.0f", miles) }
        if let parsedDate = best.date { date = parsedDate }
    }

    private func save() {
        guard canSave,
              let account = accounts.first(where: { $0.name == selectedPlatform })
        else { return }

        // `canSave` already guarantees this is above zero — the block is only
        // ever as long as the hours the driver confirmed.
        let hours = Double(hoursText) ?? 0
        guard hours > 0 else { return }

        let start = Calendar.gigPilot.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        let end = start.addingTimeInterval(hours * 3600)

        let shift = Shift(start: start, end: end, miles: Double(milesText) ?? 0)
        context.insert(shift)

        let earning = PlatformEarning(
            account: account,
            gross: Double(amountText) ?? 0,
            trips: Int(unitsText) ?? 0
        )
        context.insert(earning)
        earning.shift = shift
        shift.earnings.append(earning)
        shift.note = "Imported from screenshot"

        try? context.save()
        dismiss()
    }
}

#Preview("Import screenshot") {
    ImportScreenshotView()
        .modelContainer(.preview)
}
