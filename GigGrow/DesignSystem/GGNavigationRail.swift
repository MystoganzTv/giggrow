//
//  GGNavigationRail.swift
//  GigGrow
//
//  Native wide-window navigation. iPad gets a persistent destination rail;
//  compact windows keep the thumb-friendly bottom tab bar.
//

import SwiftUI

struct GGNavigationRail: View {
    @Binding var selection: GGIcon

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                GigGrowIconTile(size: 38)
                Text("GigGrow")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 30)

            VStack(spacing: 7) {
                ForEach(GGIcon.allCases) { icon in
                    destination(icon)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("YOUR BUSINESS\nAT A GLANCE")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.15)
                .foregroundStyle(Color.white.opacity(0.24))
                .lineSpacing(3)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(width: GG.Layout.navigationRailWidth)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                GG.Palette.screen.opacity(0.97)
                LinearGradient(
                    colors: [
                        Color(hex: 0x8B5CF6, opacity: 0.13),
                        .clear,
                        Color(hex: 0x3B82F6, opacity: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 1)
        }
    }

    private func destination(_ icon: GGIcon) -> some View {
        let isSelected = selection == icon

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = icon
            }
        } label: {
            HStack(spacing: 12) {
                GGIconView(icon: icon, size: 22)
                Text(icon.title)
                    .font(.system(size: 14.5, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .white : GG.Ink.tabInactive)
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(GG.Gradients.segment.opacity(0.24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Navigation rail") {
    HStack(spacing: 0) {
        GGNavigationRail(selection: .constant(.analytics))
        GG.Palette.screen
    }
    .preferredColorScheme(.dark)
}
