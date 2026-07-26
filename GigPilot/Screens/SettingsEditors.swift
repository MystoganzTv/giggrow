//
//  SettingsEditors.swift
//  GigPilot
//
//  The sheets behind the Settings chevrons.
//
//  Each one edits a draft and writes on save, so backing out leaves the
//  profile untouched. Every editor explains what the value actually does —
//  a driver changing their tax set-aside is making a real financial decision
//  and shouldn't have to guess at the consequence.
//

import SwiftUI
import SwiftData

// MARK: - Percentage

/// Set-aside percentages. A slider plus common presets, with a live preview
/// of what the choice means against the current week.
struct PercentageEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let explanation: String
    /// Weekly gross used for the preview line.
    let previewBase: Double
    let presets: [Double]
    let range: ClosedRange<Double>

    @State private var value: Double
    let onSave: (Double) -> Void

    init(
        title: String,
        explanation: String,
        value: Double,
        previewBase: Double = 0,
        presets: [Double] = [],
        range: ClosedRange<Double> = 0...50,
        onSave: @escaping (Double) -> Void
    ) {
        self.title = title
        self.explanation = explanation
        self.previewBase = previewBase
        self.presets = presets
        self.range = range
        self._value = State(initialValue: value)
        self.onSave = onSave
    }

    var body: some View {
        EditorScaffold(title: title, onCancel: { dismiss() }) {
            onSave(value)
            dismiss()
        } content: {
            HeroCard(glow: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .gpText(GP.Typo.heroEyebrow,
                                tracking: GP.Typo.heroEyebrowTracking,
                                color: Color.white.opacity(0.55))
                    Text(formatted)
                        .gpText(GP.Typo.heroAmount, tracking: GP.Typo.heroAmountTracking)

                    if previewBase > 0 {
                        Text("\(Money.whole(previewBase * value / 100)) out of this week's \(Money.whole(previewBase))")
                            .gpText(.system(size: 13.5, weight: .regular),
                                    color: Color.white.opacity(0.6))
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Slider(value: $value, in: range, step: 0.5)
                        .tint(GP.Palette.violet400)

                    if !presets.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { preset in
                                presetChip(preset)
                            }
                        }
                    }
                }
            }

            Text(explanation)
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }

    private var formatted: String {
        value == value.rounded() ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    private func presetChip(_ preset: Double) -> some View {
        let isSelected = abs(preset - value) < 0.01
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { value = preset }
        } label: {
            Text(preset == preset.rounded() ? "\(Int(preset))%" : String(format: "%.1f%%", preset))
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : GP.Ink.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isSelected ? AnyShapeStyle(GP.Gradients.segment)
                               : AnyShapeStyle(GP.Surface.glassFaint),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Decimal

/// Mileage rate and anything else that is a plain currency figure.
struct DecimalEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let explanation: String
    let prefix: String
    let suffix: String

    @State private var text: String
    let onSave: (Double) -> Void

    init(title: String, explanation: String, prefix: String = "$", suffix: String = "",
         value: Double, onSave: @escaping (Double) -> Void) {
        self.title = title
        self.explanation = explanation
        self.prefix = prefix
        self.suffix = suffix
        self._text = State(initialValue: String(format: "%.2f", value))
        self.onSave = onSave
    }

    var body: some View {
        EditorScaffold(title: title, canSave: Double(text) != nil, onCancel: { dismiss() }) {
            if let v = Double(text) { onSave(v) }
            dismiss()
        } content: {
            HeroCard(glow: true) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(prefix)
                        .gpText(.system(size: 34, weight: .semibold),
                                color: Color.white.opacity(0.5))
                    TextField("0.00", text: $text)
                        .keyboardType(.decimalPad)
                        .font(GP.Typo.heroAmountSmall)
                        .foregroundStyle(.white)
                    if !suffix.isEmpty {
                        Text(suffix)
                            .gpText(.system(size: 17, weight: .medium),
                                    color: Color.white.opacity(0.45))
                    }
                }
            }

            Text(explanation)
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }
}

// MARK: - Stepper

/// Idle threshold — a bounded integer, so a stepper beats a keyboard.
struct StepperEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let explanation: String
    let unit: String
    let bounds: ClosedRange<Int>

    @State private var value: Int
    let onSave: (Int) -> Void

    init(title: String, explanation: String, unit: String,
         value: Int, bounds: ClosedRange<Int> = 1...60,
         onSave: @escaping (Int) -> Void) {
        self.title = title
        self.explanation = explanation
        self.unit = unit
        self.bounds = bounds
        self._value = State(initialValue: value)
        self.onSave = onSave
    }

    var body: some View {
        EditorScaffold(title: title, onCancel: { dismiss() }) {
            onSave(value)
            dismiss()
        } content: {
            GlassCard {
                Stepper(value: $value, in: bounds) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(value)")
                            .gpText(GP.Typo.metricLarge, tracking: GP.Typo.metricLargeTracking)
                        Text(unit)
                            .gpText(.system(size: 17, weight: .medium), color: GP.Ink.secondary)
                    }
                }
                .tint(GP.Palette.violet500)
            }

            Text(explanation)
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }
}

// MARK: - Profile

struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let profile: DriverProfile

    @State private var name = ""
    @State private var payoutLast4 = ""
    @State private var loaded = false
    @State private var isPickingState = false

    var body: some View {
        EditorScaffold(
            title: "Profile",
            canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { dismiss() },
            onSave: save
        ) {
            // No city field: nothing in the app ever read it.
            GlassCard {
                VStack(spacing: 0) {
                    field("Name", text: $name, placeholder: "Your name")
                    RowDivider()
                    Button {
                        isPickingState = true
                    } label: {
                        HStack {
                            Text("State")
                                .gpText(GP.Typo.rowLabel)
                            Spacer(minLength: 12)
                            Text(StateDirectory.state(code: profile.stateCode)?.name ?? "Choose")
                                .gpText(.system(size: 15.5, weight: .medium),
                                        color: profile.stateCode.isEmpty ? GP.Ink.muted : GP.Ink.primary)
                            Chevron()
                        }
                        .padding(.vertical, 15)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    field("Payout account", text: $payoutLast4, placeholder: "last 4 digits")
                        .keyboardType(.numberPad)

                    Text("Last four digits only, as a label so you can tell accounts apart. GigPilot never connects to your bank and never asks for a full account number.")
                        .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = profile.name
            payoutLast4 = profile.payoutLast4
        }
        .sheet(isPresented: $isPickingState) {
            StatePickerView(selection: Binding(
                get: { profile.stateCode },
                set: { profile.stateCode = $0 }
            )) { state in
                if profile.taxRate == 25 { profile.taxRate = state.suggestedTaxRate }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .gpText(GP.Typo.rowLabel)
            Spacer(minLength: 12)
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 15)
    }

    private func save() {
        // Keep the "Since <year>" suffix the profile already carried.
        let since = profile.detail
            .components(separatedBy: " · ")
            .first { $0.hasPrefix("Since") }
            ?? "Since \(Calendar.gigPilot.component(.year, from: .now))"

        let place = StateDirectory.state(code: profile.stateCode)?.name ?? ""

        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.detail = place.isEmpty ? since : "\(place) · \(since)"
        profile.payoutLast4 = String(payoutLast4.filter(\.isNumber).suffix(4))

        try? context.save()
        dismiss()
    }
}

// MARK: - Scaffold

/// Shared chrome so every editor looks and behaves the same.
struct EditorScaffold<Content: View>: View {
    let title: String
    var canSave: Bool = true
    var onCancel: () -> Void
    var onSave: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.settingsWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                        content
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(GP.Ink.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? GP.Palette.violet400 : GP.Ink.muted)
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Privacy

struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.settingsWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Your data stays on this device")
                                    .gpText(GP.Typo.cardTitle, tracking: GP.Typo.cardTitleTracking)

                                point("No account, no sign-in, no server. Everything you log is stored locally on your iPhone.")
                                point("GigPilot has no analytics and no third-party trackers.")
                                point("Nothing is shared with anyone unless you export it yourself.")
                                point("Deleting the app deletes the data with it — export first if you want to keep it.")
                            }
                        }

                        Text("This describes the app as it stands today. If a future version connects to your gig platforms, that connection will be something you opt into explicitly, and this page will say so.")
                            .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GP.Palette.violet400)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(GP.Palette.violet400)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .gpText(.system(size: 14, weight: .regular), color: GP.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
