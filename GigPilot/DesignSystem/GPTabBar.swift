//
//  GPTabBar.swift
//  GigPilot
//
//  Custom tab bar. The design's bar is a translucent slab with a gradient
//  fade into the screen above it, which UITabBar can't reproduce, so it's
//  rebuilt here and laid over the content.
//

import SwiftUI

struct GPTabBar: View {
    @Binding var selection: GPIcon

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GPIcon.allCases) { icon in
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
                // Frosting behind the fade, so content scrolling under the bar
                // blurs rather than simply dimming.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)

                // `linear-gradient(to top, rgba(8,8,13,.96), rgba(8,8,13,.6) 60%, transparent)`
                LinearGradient(
                    stops: [
                        .init(color: GP.Palette.screen.opacity(0.0), location: 0.0),
                        .init(color: GP.Palette.screen.opacity(0.60), location: 0.40),
                        .init(color: GP.Palette.screen.opacity(0.96), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabItem(_ icon: GPIcon) -> some View {
        let isSelected = icon == selection
        return VStack(spacing: 5) {
            GPIconView(icon: icon, size: 24)
            Text(icon.title)
                .font(isSelected ? GP.Typo.tabLabelActive : GP.Typo.tabLabel)
        }
        .foregroundStyle(isSelected ? GP.Palette.violet400 : GP.Ink.muted)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(icon.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Tab bar") {
    ZStack(alignment: .bottom) {
        Color(hex: 0x08080D).ignoresSafeArea()
        GPTabBar(selection: .constant(.dashboard))
    }
}
