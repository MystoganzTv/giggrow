//
//  OnboardingView.swift
//  GigPilot
//
//  Four steps: who you are, where you drive, what you drive, which apps.
//
//  One question per screen. Name and state shared a screen at first, and a
//  text field next to a wheel doesn't work: the keyboard takes half the
//  display and squeezes the wheel until it looks like an empty gap.
//
//  Only the vehicle step is skippable. The state sets the tax hold-back and
//  the platform list is what the whole app is organised around, so neither
//  can be guessed.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    // No completion closure: RootView decides what to show from whether a
    // DriverProfile exists, and @Query pushes that change the moment
    // `completeOnboarding` saves. A callback here would be a second source
    // of truth for the same fact.

    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]

    @State private var step = 0

    /// Which field the keyboard is on. Without this the first screen asks for
    /// a name and then sits there until you tap the field, which reads as the
    /// app being stuck rather than waiting.
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case name, vehicle, odometer
    }

    // Step 1
    @State private var name = ""

    // Step 2
    @State private var stateCode = ""
    @State private var taxRate: Double = 25

    // Step 3
    @State private var vehicleName = ""
    @State private var vehicleDetail = ""
    @State private var odometerText = ""

    // Step 4
    @State private var selectedPlatforms: Set<String> = []

    /// Four steps, each asking one thing.
    ///
    /// Name and state used to share a screen. A text field and a wheel don't
    /// belong together: the keyboard takes half the screen and squeezes the
    /// wheel down to nothing, so on first launch the wheel looked like an
    /// empty gap. CDLGenius gives the state its own step, which is right.
    private let stepCount = 4

    var body: some View {
        ZStack {
            GP.Palette.screen.ignoresSafeArea()
            GP.Gradients.dashboardWash().ignoresSafeArea()

            VStack(spacing: 0) {
                progress

                ScrollView {
                    VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                        switch step {
                        case 0: nameStep
                        case 1: stateStep
                        case 2: vehicleStep
                        default: platformStep
                        }
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }

                footer
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // A beat for the field to exist before focusing it — set too
            // early and the keyboard never appears at all.
            //
            // This was 350ms, which is long enough to read as the app being
            // slow rather than as a transition. One run-loop turn plus a
            // little is enough in practice; the cost of being marginally too
            // early is a keyboard that needs a tap, not a broken screen.
            try? await Task.sleep(for: .milliseconds(60))
            if step == 0 { focused = .name }
        }
        .onChange(of: step) { _, newStep in
            // Only the typing steps take the keyboard. It must be down on the
            // state step or it covers the wheel.
            switch newStep {
            case 0: focused = .name
            case 2: focused = .vehicle
            default: focused = nil
            }
        }
    }

    // MARK: Progress

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? GP.Palette.violet400 : Color.white.opacity(0.12))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, GP.Layout.screenInset)
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.2), value: step)
    }

    // MARK: Step 1 — identity

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
            stepHeader(
                title: "Welcome to GigPilot",
                subtitle: "Every app you drive for, in one ledger. Let's set it up — takes a minute."
            )

            // One field. There was a City box here; nothing in the app read
            // it, so it asked for typing on the first screen and gave nothing
            // back.
            GlassCard {
                field("Your name", text: $name, placeholder: "Marco")
                    .focused($focused, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { advance() }
            }

            Text("Only stored on this device.")
                .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                .padding(.leading, 6)
        }
    }

    // MARK: Step 2 — state

    /// Its own screen, so the wheel gets the room it needs and no keyboard
    /// ever covers it.
    private var stateStep: some View {
        VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
            stepHeader(
                title: "Where do you drive?",
                subtitle: "This sets your starting tax hold-back. State income tax runs from nothing to over 13%, so it makes a real difference."
            )

            StateWheel(selection: $stateCode, height: 240) { state in
                // Adopt the suggestion as the wheel lands, so the number and
                // the sentence explaining it never disagree.
                taxRate = state.suggestedTaxRate
            }
        }
    }

    // MARK: Step 3 — vehicle

    private var vehicleStep: some View {
        VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
            stepHeader(
                title: "What do you drive?",
                subtitle: "GigPilot tracks the car as part of the business — what it costs, and what to set aside for repairs."
            )

            GlassCard {
                VStack(spacing: 0) {
                    field("Vehicle", text: $vehicleName, placeholder: "2022 Toyota RAV4", optional: true)
                    RowDivider()
                    field("Details", text: $vehicleDetail, placeholder: "Hybrid · 7KJD812", optional: true)
                    RowDivider()
                    numberField("Odometer", text: $odometerText, suffix: "mi")
                }
            }

            Text("The odometer sets your service schedule. You can add this later from the Vehicle tab.")
                .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                .padding(.leading, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Step 4 — platforms

    private var platformStep: some View {
        VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
            stepHeader(
                title: "Which apps do you drive for?",
                subtitle: "Pick every one you use. Running two at once is normal — GigPilot is built for it."
            )

            GlassCard {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        platformRow(account)
                        if account.id != accounts.last?.id { RowDivider() }
                    }
                }
            }

            Text("You can change this any time.")
                .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                .padding(.leading, 6)
        }
    }

    private func platformRow(_ account: PlatformAccount) -> some View {
        let isOn = selectedPlatforms.contains(account.name)

        return Button {
            if isOn {
                selectedPlatforms.remove(account.name)
            } else {
                selectedPlatforms.insert(account.name)
            }
        } label: {
            HStack(spacing: 13) {
                Text(account.initial)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: account.gradientStart), Color(hex: account.gradientEnd)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .opacity(isOn ? 1 : 0.32)

                Text(account.name)
                    .gpText(GP.Typo.rowLabel, color: isOn ? GP.Ink.primary : GP.Ink.tertiary)

                Spacer()

                ZStack {
                    Circle()
                        .strokeBorder(isOn ? Color.clear : Color.white.opacity(0.20), lineWidth: 1.5)
                    if isOn {
                        Circle().fill(GP.Palette.violet500)
                        CheckGlyph()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                            .frame(width: 11, height: 11)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isOn)
    }

    // MARK: Chrome

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if step == 0 {
                GigPilotLogo(size: 52)
                    .padding(.bottom, 6)
            }
            Text(title)
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)
            Text(subtitle)
                .gpText(GP.Typo.subtitle, color: Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(_ label: String, text: Binding<String>,
                       placeholder: String, optional: Bool = false) -> some View {
        HStack {
            Text(label)
                .gpText(GP.Typo.rowLabel)
            if optional {
                Text("optional")
                    .gpText(.system(size: 11, weight: .medium), color: GP.Ink.faint)
            }
            Spacer(minLength: 12)
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 15)
    }

    private func numberField(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label)
                .gpText(GP.Typo.rowLabel)
            Spacer(minLength: 12)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 100)
            Text(suffix)
                .gpText(GP.Typo.footnote, color: GP.Ink.muted)
        }
        .padding(.vertical, 15)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: advance) {
                Text(step == stepCount - 1 ? "Start tracking" : "Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        canAdvance ? AnyShapeStyle(GP.Gradients.brandMark)
                                   : AnyShapeStyle(Color.white.opacity(0.10)),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)

            if step > 0 {
                Button("Back") {
                    withAnimation(.easeOut(duration: 0.18)) { step -= 1 }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(GP.Ink.secondary)
            }
        }
        .padding(.horizontal, GP.Layout.screenInset)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(GP.Palette.screen.opacity(0.9))
    }

    // MARK: Logic

    private var canAdvance: Bool {
        switch step {
        case 0:  return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1:  return !stateCode.isEmpty         // drives the tax hold-back
        case 2:  return true                       // the vehicle step is optional
        default: return !selectedPlatforms.isEmpty // the one thing we can't guess
        }
    }

    private func advance() {
        guard canAdvance else { return }
        if step < stepCount - 1 {
            withAnimation(.easeOut(duration: 0.18)) { step += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        // The state's full name reads better in the profile than its code.
        let place = StateDirectory.state(code: stateCode)?.name ?? ""

        Seed.completeOnboarding(
            context,
            name: name.trimmingCharacters(in: .whitespaces),
            location: place,
            vehicleName: vehicleName.trimmingCharacters(in: .whitespaces),
            vehicleDetail: vehicleDetail.trimmingCharacters(in: .whitespaces),
            odometer: Int(odometerText) ?? 0,
            activePlatformNames: selectedPlatforms,
            taxRate: taxRate,
            stateCode: stateCode
        )
        // Nothing else to do — the profile now exists, and RootView's @Query
        // swaps onboarding for the app on the next render.
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .modelContainer(.previewEmpty)
}
