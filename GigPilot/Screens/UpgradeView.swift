//
//  UpgradeView.swift
//  GigPilot
//
//  The paywall. It leads with the maintenance reserve, not with sync:
//  automatic earnings sync is bought from the same aggregator by every app
//  in this category, so it's the price of entry rather than a reason to pay.
//  The reserve is the part nobody else offers.
//

import SwiftUI
import SwiftData

struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// What the reserve would already hold, shown to make the abstract concrete.
    var previewReserve: Double?

    @State private var selected: PlanPrice = Plan.proAnnual

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.dashboardWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                        header
                        if let previewReserve, previewReserve > 0 { reserveHook(previewReserve) }
                        features
                        planPicker
                        purchaseButton
                        smallPrint
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            GigPilotLogo(size: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text("GigPilot Pro")
                    .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)
                Text("Your car is the business. Run it like one.")
                    .gpText(GP.Typo.subtitle, color: Color.white.opacity(0.5))
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
                    .gpText(GP.Typo.heroEyebrow,
                            tracking: GP.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                Text(Money.whole(amount))
                    .gpText(GP.Typo.heroAmountSmall, tracking: GP.Typo.heroAmountSmallTracking)

                Text("A transmission costs about $2,500. Most drivers find that out the week it happens.")
                    .gpText(.system(size: 13.5, weight: .regular),
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
                                .fill(GP.Palette.violet500.opacity(0.18))
                            CheckGlyph()
                                .stroke(GP.Palette.violet300,
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 12, height: 12)
                        }
                        .frame(width: 26, height: 26)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title)
                                .gpText(GP.Typo.rowLabel)
                            Text(feature.detail)
                                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Plans

    private var planPicker: some View {
        VStack(spacing: GP.Layout.gridGap) {
            planRow(Plan.proAnnual,
                    caption: "\(Plan.proAnnual.monthlyEquivalent) / month, billed yearly",
                    badge: "Save \(Plan.annualSavingPercent)%")
            planRow(Plan.proMonthly, caption: "Cancel any time", badge: nil)
        }
    }

    private func planRow(_ price: PlanPrice, caption: String, badge: String?) -> some View {
        let isSelected = price == selected

        return Button {
            withAnimation(.easeOut(duration: 0.16)) { selected = price }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? GP.Palette.violet400 : Color.white.opacity(0.22),
                                      lineWidth: isSelected ? 6 : 1.5)
                }
                .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(price.perPeriodLabel)
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    Text(caption)
                        .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                }

                Spacer(minLength: 8)

                if let badge {
                    Pill(text: badge,
                         foreground: GP.Palette.mint,
                         background: Color(hex: 0x34D399, opacity: 0.16))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? GP.Surface.glassBright : GP.Surface.glassFaint,
                in: RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous)
                    .strokeBorder(isSelected ? GP.Palette.violet400.opacity(0.55) : GP.Surface.stroke,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Purchase

    private var purchaseButton: some View {
        Button(action: startPurchase) {
            Text("Start 7-day free trial")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(GP.Gradients.brandMark, in: Capsule())
                .shadow(color: Color(hex: 0x5C3CDC, opacity: 0.5), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var smallPrint: some View {
        VStack(spacing: 6) {
            Text("Manual tracking, taxes and analytics stay free, forever.")
                .gpText(GP.Typo.footnote, color: GP.Ink.muted)
            Text("Cancel any time from Settings.")
                .gpText(GP.Typo.footnote, color: GP.Ink.faint)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 6)
    }

    // MARK: Actions

    /// Placeholder for the StoreKit purchase. Flipping the stored tier is
    /// deliberately the only thing that happens here — when StoreKit lands,
    /// this method is the seam, and nothing else in the app changes.
    private func startPurchase() {
        guard let profile = try? context.fetch(FetchDescriptor<DriverProfile>()).first else {
            dismiss(); return
        }
        profile.planTierRaw = PlanTier.pro.rawValue
        profile.planRenewsOn = Calendar.gigPilot.date(
            byAdding: selected.period == .year ? .year : .month,
            value: 1,
            to: .now
        )
        try? context.save()
        dismiss()
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
        .modelContainer(.preview)
}
