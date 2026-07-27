//
//  UpgradeView.swift
//  GigGrow
//
//  Launch-access explainer.
//
//  GigGrow 1.0 does not have App Store products configured. This view remains
//  as a safe destination for older navigation state and previews, but it
//  never pretends that changing a local value is a purchase.
//

import SwiftUI

struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss

    /// What the reserve would already hold, shown to make the abstract concrete.
    var previewReserve: Double?

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.dashboardWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                        header
                        if let previewReserve, previewReserve > 0 { reserveHook(previewReserve) }
                        features
                        launchNotice
                        doneButton
                    }
                    .padding(.horizontal, GG.Layout.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GG.Ink.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            GigGrowLogo(size: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text("Everything is included")
                    .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)
                Text("All GigGrow 1.0 features are available without a subscription.")
                    .ggText(GG.Typo.subtitle, color: Color.white.opacity(0.5))
            }
        }
        .padding(.top, 4)
    }

    /// The single most persuasive thing available: the number the driver
    /// would already have banked if they'd been on Pro.
    private func reserveHook(_ amount: Double) -> some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("You'd have set aside".uppercased())
                    .ggText(GG.Typo.heroEyebrow,
                            tracking: GG.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                Text(Money.whole(amount))
                    .ggText(GG.Typo.heroAmountSmall, tracking: GG.Typo.heroAmountSmallTracking)

                Text("A transmission costs about $2,500. Most drivers find that out the week it happens.")
                    .ggText(.system(size: 13.5, weight: .regular),
                            color: Color.white.opacity(0.6))
            }
        }
    }

    // MARK: Features

    private var features: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(ProFeature.orderedForPaywall) { feature in
                    HStack(alignment: .top, spacing: 13) {
                        ZStack {
                            Circle()
                                .fill(GG.Palette.violet500.opacity(0.18))
                            CheckGlyph()
                                .stroke(GG.Palette.violet300,
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 12, height: 12)
                        }
                        .frame(width: 26, height: 26)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title)
                                .ggText(GG.Typo.rowLabel)
                            Text(feature.detail)
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var launchNotice: some View {
        GlassCard {
            Text("There is no subscription or in-app purchase in this version.")
                .ggText(GG.Typo.rowLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var doneButton: some View {
        Button(action: dismiss.callAsFunction) {
            Text("Continue")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(GG.Gradients.brandMark, in: Capsule())
                .shadow(color: Color(hex: 0x5C3CDC, opacity: 0.5), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - Glyph

/// Tick mark used in the feature list.
struct CheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var p = Path()
        p.move(to: CGPoint(x: 4 * s, y: 13 * s))
        p.addLine(to: CGPoint(x: 9.5 * s, y: 18.5 * s))
        p.addLine(to: CGPoint(x: 20 * s, y: 6 * s))
        return p
    }
}

#Preview("Upgrade") {
    UpgradeView(previewReserve: 2_684)
}
