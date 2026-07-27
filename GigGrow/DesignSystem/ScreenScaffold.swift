//
//  ScreenScaffold.swift
//  GigGrow
//
//  Every screen is the same shape: an ambient radial wash over the near-black
//  base, a scrolling column of cards inset 20pt, and clearance at the bottom
//  for the floating tab bar.
//

import SwiftUI

struct ScreenScaffold<Wash: View, Content: View>: View {
    @ViewBuilder var wash: Wash
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                content
            }
            .padding(.horizontal, GG.Layout.screenInset)
            .padding(.top, 8)
            .padding(.bottom, GG.Layout.tabBarHeight + GG.Layout.scrollBottomPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The background goes on as a modifier, not as a ZStack sibling.
        // As siblings, `ignoresSafeArea()` on the base and the wash expanded
        // the stack itself, and the scroll content came up with it — the
        // screen title ended up against the Dynamic Island.
        .background {
            ZStack {
                GG.Palette.screen
                wash
            }
            .ignoresSafeArea()
        }
    }
}

/// Large screen title — "This week", "Apps", "Analytics", "Vehicle", "Settings".
struct ScreenTitle: View {
    let text: String
    /// Optional trailing element, e.g. the dashboard's avatar.
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(text)
                .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)
            if let trailing {
                Spacer(minLength: 12)
                trailing
            }
        }
    }
}

/// Circular monogram used in the dashboard header.
struct Monogram: View {
    let letter: String
    var size: CGFloat = 34
    var gradient: LinearGradient? = nil

    var body: some View {
        ZStack {
            if let gradient {
                Circle().fill(gradient)
            } else {
                Circle().fill(Color.white.opacity(0.07))
                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            Text(letter)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(gradient == nil ? Color.white.opacity(0.7) : .white)
        }
        .frame(width: size, height: size)
    }
}

/// A two-column row of equal-width tiles.
struct TilePair<Left: View, Right: View>: View {
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(alignment: .top, spacing: GG.Layout.gridGap) {
            left
            right
        }
    }
}
