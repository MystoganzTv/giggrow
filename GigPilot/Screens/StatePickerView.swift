//
//  StatePickerView.swift
//  GigPilot
//
//  Picking where you drive.
//
//  A wheel picker hides 50 options behind a scroll and shows three at a time.
//  This is a searchable grid of abbreviation tiles: everything is on screen,
//  typing two letters narrows it instantly, and the tiles are big enough to
//  hit without looking — which matters for an app used in a parked car.
//
//  The panel underneath is the point. Choosing a state changes what GigPilot
//  suggests holding back, so the consequence is shown at the moment of the
//  choice rather than buried in Settings afterwards.
//

import SwiftUI

struct StatePickerView: View {
    @Environment(\.dismiss) private var dismiss

    /// Currently selected USPS code, or empty.
    @Binding var selection: String
    /// Called with the state's suggested rate when the driver confirms, so
    /// the caller can offer to apply it.
    var onConfirm: (USState) -> Void = { _ in }

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [USState] { StateDirectory.search(query) }
    private var chosen: USState? { StateDirectory.state(code: selection) }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.settingsWash().ignoresSafeArea()

                VStack(spacing: 0) {
                    searchField

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(results) { state in
                                tile(state)
                            }
                        }
                        .padding(.horizontal, GP.Layout.screenInset)
                        .padding(.top, 4)
                        .padding(.bottom, 20)

                        if results.isEmpty {
                            Text("No state matches “\(query)”.")
                                .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                                .padding(.top, 40)
                        }
                    }

                    if let chosen { consequencePanel(chosen) }
                }
            }
            .navigationTitle("Where do you drive?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 10) {
            SearchGlyph()
                .stroke(GP.Ink.muted, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 16)

            TextField("Search states", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GP.Palette.violet400)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(GP.Surface.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(GP.Surface.stroke, lineWidth: 1))
        .padding(.horizontal, GP.Layout.screenInset)
        .padding(.vertical, 12)
    }

    // MARK: Tile

    private func tile(_ state: USState) -> some View {
        let isSelected = state.code == selection

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selection = state.code
                searchFocused = false
            }
        } label: {
            VStack(spacing: 6) {
                Text(state.code)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? .white : GP.Ink.body)

                Text(state.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : GP.Ink.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                // A quiet marker on the nine states where the set-aside is
                // materially lower. Visible without being a claim.
                Circle()
                    .fill(state.hasIncomeTax ? Color.clear : GP.Palette.mint)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSelected ? AnyShapeStyle(GP.Gradients.brandMark)
                           : AnyShapeStyle(GP.Surface.glass),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : GP.Surface.stroke, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color(hex: 0x5C3CDC, opacity: 0.4) : .clear,
                    radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.name)
        .accessibilityValue(state.hasIncomeTax ? "" : "No state income tax")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Consequence

    private func consequencePanel(_ state: USState) -> some View {
        VStack(spacing: 14) {
            HeroCard(radius: GP.Radius.card, glow: true) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(state.name)
                            .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                        if !state.hasIncomeTax {
                            Pill(text: "No state income tax",
                                 foreground: GP.Palette.mint,
                                 background: Color(hex: 0x34D399, opacity: 0.16),
                                 font: .system(size: 11, weight: .semibold))
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(Int(state.suggestedTaxRate))%")
                            .gpText(GP.Typo.metricLarge, tracking: GP.Typo.metricLargeTracking)
                        Text("suggested set-aside")
                            .gpText(GP.Typo.captionMuted, color: Color.white.opacity(0.6))
                    }

                    Text(state.taxNote)
                        .gpText(GP.Typo.footnote, color: Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("A starting point, not tax advice — you can change it any time in Settings, and it's worth confirming with a tax professional.")
                .gpText(.system(size: 11.5, weight: .regular), color: GP.Ink.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onConfirm(state)
                dismiss()
            } label: {
                Text("Use \(state.code)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(GP.Gradients.brandMark, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, GP.Layout.screenInset)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(GP.Palette.screen.opacity(0.94))
    }
}

// MARK: - Glyph

/// Magnifying glass for the search field.
struct SearchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var p = Path()
        p.addEllipse(in: CGRect(x: 3 * s, y: 3 * s, width: 13 * s, height: 13 * s))
        p.move(to: CGPoint(x: 15.5 * s, y: 15.5 * s))
        p.addLine(to: CGPoint(x: 21 * s, y: 21 * s))
        return p
    }
}

#Preview("State picker") {
    StatePickerView(selection: .constant("TX"))
}

#Preview("State picker — nothing chosen") {
    StatePickerView(selection: .constant(""))
}
