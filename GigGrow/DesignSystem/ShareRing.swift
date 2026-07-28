//
//  ShareRing.swift
//  GigGrow
//
//  A ring that answers one question: how was the money split?
//
//  Deliberately not a general chart. It draws shares of a whole and nothing
//  else, because the bug it replaces was a bar sized by one measure with a
//  number from another printed at the end of it. A component that can only
//  express proportions can't be handed a rate by mistake.
//
//  The total sits in the middle so the ring is legible without a legend —
//  and so the parts visibly belong to something.
//

import SwiftUI

struct ShareRing: View {

    /// Shares of the whole, 0…1, in the order they should be drawn.
    var slices: [(share: Double, colour: Color)]
    var centreTop: String
    var centreBottom: String

    /// Thick enough to read at 132pt, thin enough to leave room for the
    /// total. Below about a fifth of the radius the arcs start to look like
    /// hairlines on a small phone.
    private var thickness: CGFloat = 18

    init(slices: [(share: Double, colour: Color)],
         centreTop: String,
         centreBottom: String) {
        self.slices = slices
        self.centreTop = centreTop
        self.centreBottom = centreBottom
    }

    /// Running start angle for each slice, as a fraction of the circle.
    private var offsets: [Double] {
        var running = 0.0
        return slices.map { slice in
            defer { running += max(slice.share, 0) }
            return running
        }
    }

    var body: some View {
        ZStack {
            // The track shows through where shares don't add to 1 — which
            // happens when a platform is filtered out, and should look like
            // a gap rather than like the ring silently rescaling itself.
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: thickness)

            ForEach(Array(zip(slices.indices, offsets)), id: \.0) { index, start in
                let share = max(slices[index].share, 0)
                Circle()
                    .trim(from: start, to: min(start + share, 1))
                    .stroke(
                        slices[index].colour,
                        style: StrokeStyle(lineWidth: thickness, lineCap: .butt)
                    )
                    // Trim starts at three o'clock; a split people read
                    // starts at the top.
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 1) {
                Text(centreTop)
                    .ggText(.system(size: 19, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(centreBottom)
                    .ggText(.system(size: 10.5, weight: .regular), color: GG.Ink.muted)
            }
            .padding(.horizontal, thickness + 6)
        }
        .accessibilityHidden(true)   // the legend rows carry the numbers
    }
}
