//
//  StatePickerView.swift
//  GigPilot
//
//  Picking where you drive, in the CDLGenius onboarding style: a full-width
//  wheel with a thin selection band as the only chrome, so it reads as a big
//  dial the rows scroll through rather than a control sitting in a card.
//
//  CDLGenius confirms the choice by naming the agency whose manual it will
//  use. The same idea applies here with a different payoff: the line under
//  the wheel names what the state does to your tax hold-back, because that's
//  the consequence of the choice.
//

import SwiftUI

struct StatePickerView: View {
    @Environment(\.dismiss) private var dismiss

    /// Currently selected USPS code, or empty.
    @Binding var selection: String
    /// Called with the state when confirmed, so the caller can adopt its
    /// suggested rate.
    var onConfirm: (USState) -> Void = { _ in }

    @State private var draft = ""

    private var chosen: USState? { StateDirectory.state(code: draft) }

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.settingsWash().ignoresSafeArea()

                VStack(spacing: 16) {
                    header

                    Spacer(minLength: 4)

                    wheel

                    // Confirms the choice by naming its consequence, the way
                    // CDLGenius names the agency.
                    confirmation
                        .frame(minHeight: 56)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 0)

                    continueButton
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
            }
            .onAppear { draft = selection }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where do you drive?")
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)
            Text("Sets your starting tax hold-back — it varies a lot by state.")
                .gpText(GP.Typo.subtitle, color: Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: Wheel

    private var wheel: some View {
        ZStack {
            // The band is the only chrome. No box, so the rows feel like
            // they're passing through a dial rather than sitting in a field.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GP.Palette.violet500.opacity(0.16))
                .frame(height: 46)
                .padding(.horizontal, 20)

            Picker("State", selection: $draft) {
                Text("Select your state").tag("")
                ForEach(StateDirectory.all) { state in
                    Text(state.name).tag(state.code)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 260)
            .clipped()
            .accessibilityLabel("Choose the state where you drive")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Confirmation

    @ViewBuilder
    private var confirmation: some View {
        if let state = chosen {
            VStack(spacing: 6) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(state.hasIncomeTax
                                  ? GP.Palette.violet500.opacity(0.2)
                                  : Color(hex: 0x34D399, opacity: 0.18))
                        CheckGlyph()
                            .stroke(state.hasIncomeTax ? GP.Palette.violet300 : GP.Palette.mint,
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .frame(width: 10, height: 10)
                    }
                    .frame(width: 20, height: 20)

                    Text(state.hasIncomeTax
                         ? "\(Int(state.suggestedTaxRate))% suggested hold-back"
                         : "No state income tax · \(Int(state.suggestedTaxRate))% suggested")
                        .gpText(.system(size: 13.5, weight: .semibold),
                                color: state.hasIncomeTax ? GP.Palette.violet300 : GP.Palette.mint)
                }

                Text("A starting point, not tax advice. Editable in Settings.")
                    .gpText(.system(size: 11.5, weight: .regular), color: GP.Ink.muted)
            }
            .multilineTextAlignment(.center)
        } else {
            Text("Spin to pick your state — nothing is chosen yet.")
                .gpText(GP.Typo.captionMuted, color: GP.Ink.tertiary)
        }
    }

    // MARK: Continue

    private var continueButton: some View {
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
                        : AnyShapeStyle(GP.Gradients.brandMark),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(chosen == nil)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

// CheckGlyph lives in UpgradeView.swift — same module, so it's reused here
// rather than declared twice.

#Preview("State picker") {
    StatePickerView(selection: .constant("AZ"))
}

#Preview("State picker — nothing chosen") {
    StatePickerView(selection: .constant(""))
}
