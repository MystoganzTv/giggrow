//
//  GGTabBar.swift
//  GigGrow
//
//  Custom tab bar. The design's bar is a translucent slab with a gradient
//  fade into the screen above it, which UITabBar can't reproduce, so it's
//  rebuilt here and laid over the content.
//

import SwiftUI

struct GGTabBar: View {
    @Binding var selection: GGIcon

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GGIcon.tabs) { icon in
                Button {
                    // A quick fade rather than a slide keeps the tab switch
                    // feeling like the same surface reflowing.
                    withAnimation(.easeOut(duration: 0.18)) { selection = icon }
                } label: {
                    tabItem(icon)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: GG.Layout.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .background(alignment: .top) {
            // Hairline at the very top of the bar.
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
        .background {
            ZStack {
                // Full-strength material. At 0.55 the numbers scrolling
                // underneath read straight through the labels — a driver
                // glancing down saw "$38.61" printed across "Dashboard".
                Rectangle()
                    .fill(.ultraThinMaterial)

                // The design's fade, but reaching opacity much sooner. The
                // gradient only has to soften the top edge; from a third of
                // the way down it needs to be solid or the labels compete
                // with whatever card is passing behind them.
                LinearGradient(
                    stops: [
                        .init(color: GG.Palette.screen.opacity(0.0), location: 0.0),
                        .init(color: GG.Palette.screen.opacity(0.82), location: 0.30),
                        .init(color: GG.Palette.screen.opacity(0.97), location: 0.55),
                        .init(color: GG.Palette.screen, location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabItem(_ icon: GGIcon) -> some View {
        let isSelected = icon == selection
        return VStack(spacing: 5) {
            GGIconView(icon: icon, size: 24)
            Text(icon.title)
                .font(isSelected ? GG.Typo.tabLabelActive : GG.Typo.tabLabel)
        }
        // The design specified 0.35 for inactive items. That reads on a
        // static mockup and not on a phone in daylight, so it's lifted —
        // this is a bar people tap while parked in the sun.
        .foregroundStyle(isSelected ? GG.Palette.violet400 : GG.Ink.tabInactive)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(icon.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Tab bar") {
    ZStack(alignment: .bottom) {
        Color(hex: 0x08080D).ignoresSafeArea()
        GGTabBar(selection: .constant(.dashboard))
    }
}
