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
                if !account.earnings.isEmpty {
                    Text("\(account.earnings.count) shift\(account.earnings.count == 1 ? "" : "s") logged")
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

#Preview("Manage platforms") {
    ManagePlatformsView()
        .modelContainer(.preview)
}
