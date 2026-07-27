//
//  StatePickerView.swift
//  GigGrow
//
//  Picking where you drive, in the CDLGenius onboarding style: a full-width
//  wheel with a thin selection band as the only chrome, so it reads as a big
//  dial the rows scroll through rather than a control sitting in a card.
//
//  `StateWheel` is the control itself, used inline during onboarding — one
//  fewer layer on the first screen someone ever sees. `StatePickerView` wraps
//  it in a sheet for Settings, where it's reached from a row and a sheet is
//  what a row implies.
//
//  CDLGenius confirms the choice by naming the agency whose manual it will
//  use. Same shape here, different payoff: the line under the wheel names
//  what the state does to your tax hold-back, because that's what the choice
//  actually changes.
//

import SwiftUI

// MARK: - The wheel

struct StateWheel: View {
    @Binding var selection: String
    /// Shorter inline, taller in a sheet where there's room.
    var height: CGFloat = 200
    /// Fired whenever the selection lands on a real state.
    var onChange: (USState) -> Void = { _ in }

    private var chosen: USState? { StateDirectory.state(code: selection) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // The band is the only chrome. No box, so the rows feel like
                // they're passing through a dial rather than sitting in a field.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GG.Palette.violet500.opacity(0.16))
                    .frame(height: 42)

                Picker("State", selection: $selection) {
                    Text("Select your state").tag("")
                    ForEach(StateDirectory.all) { state in
                        Text(state.name).tag(state.code)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: height)
                .clipped()
                .accessibilityLabel("Choose the state where you drive")
            }
            .frame(maxWidth: .infinity)
            .onChange(of: selection) { _, new in
                if let state = StateDirectory.state(code: new) { onChange(state) }
            }

            confirmation
                .frame(minHeight: 40)
        }
    }

    @ViewBuilder
    private var confirmation: some View {
        if let state = chosen {
            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(state.hasIncomeTax
                                  ? GG.Palette.violet500.opacity(0.2)
                                  : Color(hex: 0x34D399, opacity: 0.18))
                        CheckGlyph()
                            .stroke(state.hasIncomeTax ? GG.Palette.violet300 : GG.Palette.mint,
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .frame(width: 10, height: 10)
                    }
                    .frame(width: 20, height: 20)

                    Text(state.hasIncomeTax
                         ? "\(Int(state.suggestedTaxRate))% suggested hold-back"
                         : "No state income tax · \(Int(state.suggestedTaxRate))% suggested")
                        .ggText(.system(size: 13.5, weight: .semibold),
                                color: state.hasIncomeTax ? GG.Palette.violet300 : GG.Palette.mint)
                }

                Text("A starting point, not tax advice. Editable in Settings.")
                    .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        } else {
            Text("Spin to pick your state — nothing is chosen yet.")
                .ggText(GG.Typo.captionMuted, color: GG.Ink.tertiary)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Sheet wrapper

/// The same wheel behind Cancel/Continue, for the Settings row.
struct StatePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String
    var onConfirm: (USState) -> Void = { _ in }

    @State private var draft = ""

    private var chosen: USState? { StateDirectory.state(code: draft) }

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.settingsWash().ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where do you drive?")
                            .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)
                        Text("Sets your starting tax hold-back — it varies a lot by state.")
                            .ggText(GG.Typo.subtitle, color: Color.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Spacer(minLength: 4)

                    StateWheel(selection: $draft, height: 260)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 0)

                    Button {
                        guard let state = chosen else { return }
                        selection = state.code
                        onConfirm(state)
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                chosen == nil
                                    ? AnyShapeStyle(Color.white.opacity(0.10))
                                    : AnyShapeStyle(GG.Gradients.brandMark),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(chosen == nil)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GG.Ink.secondary)
                }
            }
            .onAppear { draft = selection }
        }
        .preferredColorScheme(.dark)
    }
}

// CheckGlyph lives in UpgradeView.swift — same module, reused here.

#Preview("Inline wheel") {
    ZStack {
        GG.Palette.screen.ignoresSafeArea()
        StateWheel(selection: .constant("AZ"))
            .padding(.horizontal, 20)
    }
}

#Preview("Sheet") {
    StatePickerView(selection: .constant(""))
}
