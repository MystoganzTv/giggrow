//
//  RangeBar.swift
//  GigPilot
//
//  Pick a period, and pick *which* one.
//
//  The app could only ever show the current week, month or year. That is fine
//  until you import a screenshot of June in July: the figures save correctly
//  and every screen carries on saying "This week", which reads exactly like
//  the import having failed. A driver checking what they made last month, or
//  on a particular Saturday, had nowhere to do it.
//
//  So the segmented control chooses the size of the window and the arrows
//  choose which window. Forward is disabled at the present, because there is
//  nothing to see in a week that hasn't happened.
//

import SwiftUI

struct RangeBar: View {
    @Binding var selection: RangeSelection

    /// Which sizes to offer. The dashboard shows all four; a screen that only
    /// makes sense weekly can narrow it.
    var options: [AnalyticsRange] = AnalyticsRange.allCases

    var body: some View {
        VStack(spacing: 10) {
            segments
            stepper
        }
    }

    // MARK: Size

    private var segments: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isSelected = option == selection.range
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection.use(option) }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : GP.Ink.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? AnyShapeStyle(GP.Gradients.segment)
                                               : AnyShapeStyle(Color.clear),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Which one

    private var stepper: some View {
        HStack(spacing: 12) {
            arrow(-1, systemName: "chevron.left", enabled: true)

            VStack(spacing: 1) {
                Text(selection.title)
                    .gpText(.system(size: 15, weight: .semibold), tracking: -0.2)
                if !selection.isCurrent {
                    // Says how to get back, since the title stops naming the
                    // present the moment you step away from it.
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { selection.anchor = .now }
                    } label: {
                        Text("Back to \(selection.range.possessive.lowercased())")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(GP.Palette.violet300)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.16), value: selection.isCurrent)

            // Nothing has happened in a period that hasn't started, so
            // stepping into it would only ever show zeroes.
            arrow(1, systemName: "chevron.right", enabled: !selection.isCurrent)
        }
    }

    private func arrow(_ delta: Int, systemName: String, enabled: Bool) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { selection.step(delta) }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? GP.Ink.secondary : GP.Ink.faint)
                .frame(width: 38, height: 38)
                .background(enabled ? GP.Surface.glassFaint : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

#Preview("Range bar") {
    struct Harness: View {
        @State private var selection = RangeSelection()
        var body: some View {
            VStack(spacing: 30) {
                RangeBar(selection: $selection)
                Text(selection.title).gpText(GP.Typo.footnote, color: GP.Ink.muted)
            }
            .padding()
            .background(GP.Palette.screen)
        }
    }
    return Harness().preferredColorScheme(.dark)
}
