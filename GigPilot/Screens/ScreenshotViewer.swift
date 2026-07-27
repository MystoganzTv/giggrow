//
//  ScreenshotViewer.swift
//  GigPilot
//
//  The screenshot, full size, zoomable.
//
//  Checking a parsed figure against the image it came from used to mean
//  leaving GigPilot, opening Photos, finding the screenshot, and coming
//  back — by which point the import sheet had been dismissed and every
//  correction made so far was gone. That is a good enough reason not to
//  bother checking, which defeats the point of showing the numbers for
//  review at all.
//
//  So the source stays one tap away, and going back loses nothing.
//

import SwiftUI

struct ScreenshotViewer: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let maxScale: CGFloat = 6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnification)
                .simultaneousGesture(drag)
                // Double tap is the gesture everyone already knows for this.
                .onTapGesture(count: 2) { toggleZoom() }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(11)
                            .background(Color.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                if scale <= 1.01 {
                    Text("Pinch or double-tap to zoom")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.bottom, 6)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .statusBarHidden()
    }

    // MARK: Gestures

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(committedScale * value, 1), maxScale)
            }
            .onEnded { _ in
                committedScale = scale
                if scale <= 1 { resetPan() }
            }
    }

    /// Panning only does anything while zoomed in; at fit-to-screen there is
    /// nowhere to pan to and dragging the image around just feels broken.
    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: committedOffset.width + value.translation.width,
                                height: committedOffset.height + value.translation.height)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            if scale > 1.01 {
                scale = 1
                committedScale = 1
                resetPan()
            } else {
                scale = 3
                committedScale = 3
            }
        }
    }

    private func resetPan() {
        offset = .zero
        committedOffset = .zero
    }
}
