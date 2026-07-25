//
//  SettingsView.swift
//  GigPilot
//
//  Screen 05 — profile, subscription, and the grouped preference lists.
//

import SwiftUI

struct SettingsView: View {
    let snapshot: EarningsSnapshot
    var appVersion: String = "3.2.1"

    var body: some View {
        ScreenScaffold {
            GP.Gradients.settingsWash()
        } content: {
            Text("Settings")
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)

            profileCard
            subscriptionCard

            ForEach(snapshot.settingGroups) { group in
                settingGroup(group)
            }

            footer
        }
    }

    // MARK: Profile

    private var profileCard: some View {
        GlassCard {
            HStack(spacing: 15) {
                Monogram(letter: snapshot.driver.initial,
                         size: 54,
                         gradient: GP.Gradients.brandMark)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.driver.name)
                        .gpText(GP.Typo.title3, tracking: GP.Typo.title3Tracking)
                    Text(snapshot.driver.detail)
                        .gpText(.system(size: 13.5, weight: .regular), color: GP.Ink.tertiary)
                }

                Spacer(minLength: 8)

                Chevron(size: 18, color: Color.white.opacity(0.30))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Subscription

    private var subscriptionCard: some View {
        HeroCard(radius: GP.Radius.card,
                 padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                 gradient: GP.Gradients.heroPro) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GigPilot Pro")
                        .gpText(.system(size: 17, weight: .semibold), tracking: -0.26)
                    Text("$20 / month · renews Aug 12")
                        .gpText(.system(size: 13.5, weight: .regular),
                                color: Color.white.opacity(0.55))
                }

                Spacer(minLength: 8)

                Text("Manage")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            }
        }
    }

    // MARK: Grouped rows

    private func settingGroup(_ group: SettingGroup) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(group.title.uppercased())
                .gpText(GP.Typo.groupLabel,
                        tracking: GP.Typo.groupLabelTracking,
                        color: GP.Ink.muted)
                .padding(.leading, 6)

            GlassCard(radius: GP.Radius.tile,
                      padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                        HStack {
                            Text(row.label)
                                .gpText(GP.Typo.rowLabel)

                            Spacer(minLength: 12)

                            HStack(spacing: 9) {
                                if !row.value.isEmpty {
                                    Text(row.value)
                                        .gpText(.system(size: 14.5, weight: .regular),
                                                color: GP.Ink.tertiary)
                                }
                                Chevron()
                            }
                        }
                        .padding(.vertical, 15)
                        .contentShape(Rectangle())

                        if index < group.rows.count - 1 {
                            RowDivider(color: GP.Surface.dividerSoft)
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            GigPilotLogo(size: 34, glow: false)
                .opacity(0.55)

            Text("GigPilot \(appVersion) · Built for drivers")
                .gpText(GP.Typo.footnote, color: GP.Ink.faint)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 14)
    }
}

#Preview("Settings") {
    SettingsView(snapshot: .mock)
        .preferredColorScheme(.dark)
}
