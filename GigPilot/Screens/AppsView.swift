//
//  AppsView.swift
//  GigPilot
//
//  Screen 02 — the six connected platforms.
//

import SwiftUI

struct AppsView: View {
    let snapshot: EarningsSnapshot

    @State private var isManagingPlatforms = false

    var body: some View {
        ScreenScaffold {
            GP.Gradients.appsWash()
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apps")
                    .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)
                Text(subtitle)
                    .gpText(GP.Typo.subtitle, color: Color.white.opacity(0.45))
            }

            if snapshot.hasData {
                combinedCard

                ForEach(snapshot.platforms) { platform in
                    platformRow(platform)
                }
            } else {
                EmptyStateCard(
                    title: "Nothing logged yet",
                    message: "Once you log a shift, each app you drove for shows up here with what it paid, its share of the week, and its own hourly rate."
                )
            }

            connectRow
        }
        .sheet(isPresented: $isManagingPlatforms) { ManagePlatformsView() }
    }

    /// Honest about state instead of asserting a sync that hasn't happened.
    private var subtitle: String {
        guard snapshot.hasData else {
            return "Every platform you drive for, side by side."
        }
        let count = snapshot.platforms.count
        return "\(count) platform\(count == 1 ? "" : "s") active this week."
    }

    // MARK: Combined week

    private var combinedCard: some View {
        HeroCard(radius: GP.Radius.card,
                 padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                 gradient: GP.Gradients.heroBlue) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Combined week".uppercased())
                        .gpText(GP.Typo.heroEyebrow,
                                tracking: GP.Typo.heroEyebrowTracking,
                                color: Color.white.opacity(0.55))

                    Text(Money.cents(snapshot.weeklyTotal))
                        .gpText(GP.Typo.heroAmountSmall, tracking: GP.Typo.heroAmountSmallTracking)

                    Text("\(snapshot.tripCount) trips · \(snapshot.platforms.count) platforms")
                        .gpText(.system(size: 13.5, weight: .medium), color: GP.Ink.secondary)
                }

                Spacer(minLength: 12)

                ZStack {
                    Circle().fill(Color.white.opacity(0.12))
                    Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    RefreshGlyph()
                        .stroke(Color.white,
                                style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                }
                .frame(width: 52, height: 52)
            }
        }
    }

    // MARK: Platform row

    private func platformRow(_ platform: Platform) -> some View {
        GlassCard(radius: GP.Radius.tile,
                  padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
            HStack(spacing: 14) {
                Text(platform.initial)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.17)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        platform.brandGradient,
                        in: RoundedRectangle(cornerRadius: GP.Radius.badge, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.name)
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Text(platform.meta)
                        .gpText(.system(size: 13, weight: .regular), color: GP.Ink.tertiary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(Money.cents(snapshot.amount(for: platform)))
                        .gpText(.system(size: 17, weight: .semibold), tracking: -0.34)
                    Text(platform.delta)
                        .gpText(.system(size: 11.5, weight: .semibold), color: GP.Palette.mint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Connect

    private var connectRow: some View {
        Button {
            isManagingPlatforms = true
        } label: {
            HStack(spacing: 9) {
                PlusGlyph()
                    .stroke(Color.white.opacity(0.55),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 18, height: 18)
                // "Connect" would promise a link that doesn't exist. This
                // toggles which apps you log against.
                Text("Manage your apps")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(
                GP.Surface.glassFaint,
                in: RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous)
                    .strokeBorder(
                        GP.Surface.strokeDashed,
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Apps") {
    AppsView(snapshot: .mock)
        .preferredColorScheme(.dark)
}
