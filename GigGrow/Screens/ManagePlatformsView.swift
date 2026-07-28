//
//  ManagePlatformsView.swift
//  GigGrow
//
//  Turn platforms on and off after onboarding.
//
//  Closes two findings at once: the "Connect another platform" button was an
//  empty closure nothing wired, and the set of apps chosen during onboarding
//  could never be changed. A driver who picks up Instacart next month had no
//  way to tell the app.
//
//  Named "manage", not "connect": nothing is connected to anything. These are
//  the apps you drive for and log by hand.
//

import SwiftUI
import SwiftData

struct ManagePlatformsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]
    @State private var isAddingPlatform = false

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.appsWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                        Text("Turn on every app you drive for. You can log a shift across several at once.")
                            .ggText(GG.Typo.subtitle, color: Color.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)

                        GlassCard {
                            VStack(spacing: 0) {
                                ForEach(accounts) { account in
                                    row(account)
                                    if account.id != accounts.last?.id {
                                        RowDivider(color: GG.Surface.dividerSoft)
                                    }
                                }
                            }
                        }

                        Button {
                            isAddingPlatform = true
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "plus")
                                Text("Add another platform")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GG.Palette.violet300)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                GG.Surface.glassFaint,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(GG.Palette.violet500.opacity(0.35),
                                                  style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                            )
                        }
                        .buttonStyle(.plain)

                        Text("Turning one off hides it from new shifts. Anything you already logged for it stays in your totals.")
                            .ggText(GG.Typo.footnote, color: GG.Ink.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, GG.Layout.screenInset)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Your apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GG.Palette.violet400)
                }
            }
        }
        .sheet(isPresented: $isAddingPlatform) {
            AddPlatformView()
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ account: PlatformAccount) -> some View {
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
                .opacity(account.isActive ? 1 : 0.32)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .ggText(GG.Typo.rowLabel,
                            color: account.isActive ? GG.Ink.primary : GG.Ink.tertiary)
                if !account.earningItems.isEmpty {
                    // Says what switching it off does, on the row where the
                    // switch is. Turning off an app you've earned on looks
                    // like it might delete the earnings, so people either
                    // don't do it or do it and worry.
                    Text("\(account.earningItems.count) shift\(account.earningItems.count == 1 ? "" : "s") logged"
                         + (account.isActive ? "" : " · kept"))
                        .ggText(GG.Typo.footnote, color: GG.Ink.muted)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { account.isActive },
                set: { account.isActive = $0; try? context.save() }
            ))
            .labelsHidden()
            .tint(GG.Palette.violet500)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(account.name)
    }
}

private struct AddPlatformView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unitNoun = "jobs"
    @State private var errorMessage: String?
    @FocusState private var isEditingName: Bool

    private let unitOptions = ["trips", "rides", "deliveries", "orders", "batches", "blocks", "jobs"]

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.appsWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                        Text("Use this for Roadie, Shipt, Gopuff, a local courier, or any platform that isn't in the built-in list.")
                            .ggText(GG.Typo.subtitle, color: GG.Ink.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 18) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("Platform name")
                                        .ggText(GG.Typo.rowLabel)
                                    TextField("Example: Roadie", text: $name)
                                        .textInputAutocapitalization(.words)
                                        .autocorrectionDisabled()
                                        .focused($isEditingName)
                                        .ggText(.system(size: 16, weight: .medium))
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 12)
                                        .background(
                                            GG.Surface.glassFaint,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 7) {
                                    Text("What does it count?")
                                        .ggText(GG.Typo.rowLabel)

                                    Picker("Work unit", selection: $unitNoun) {
                                        ForEach(unitOptions, id: \.self) {
                                            Text($0.capitalized).tag($0)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(GG.Palette.violet300)
                                }

                                if let errorMessage {
                                    Text(errorMessage)
                                        .ggText(GG.Typo.footnote, color: Color.red.opacity(0.9))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, GG.Layout.screenInset)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add platform")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addPlatform() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditingName = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func addPlatform() {
        do {
            try Seed.addCustomPlatform(name: name, unitNoun: unitNoun, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Manage platforms") {
    ManagePlatformsView()
        .modelContainer(.preview)
}
