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
//  Four ways out, because the first version had one and it didn't work:
//  the close button, a tap on the backdrop, swipe down, and swipe down
//  again after zooming. A full-screen cover with no visible chrome is a
//  trap if any single dismissal path fails.
//

import SwiftUI

struct ScreenshotViewer: View {
    let image: UIImage

    /// Passed in rather than taken from the environment. `dismiss` depends on
    /// presentation state resolving correctly; a closure the caller owns
    /// cannot fail to fire.
    var onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    /// How far the whole view has been dragged down to dismiss.
    @State private var dismissDrag: CGFloat = 0

    private let maxScale: CGFloat = 6
    private let dismissThreshold: CGFloat = 120

    private var isZoomed: Bool { scale > 1.01 }

    var body: some View {
        ZStack {
            // Tapping anywhere off the image closes it, the way every photo
            // viewer on the phone already behaves.
            Color.black
                .opacity(1 - min(dismissDrag / 400, 0.45))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height + dismissDrag)
                .gesture(magnification)
                .simultaneousGesture(drag)
                .onTapGesture(count: 2) { toggleZoom() }

            controls
        }
        .statusBarHidden()
    }

    // MARK: Chrome

    private var controls: some View {
        VStack {
            HStack {
                if isZoomed {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { resetZoom() }
                    } label: {
                        Text("Fit")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        // Generous padding: this is the way out, and a
                        // 44-point target is the minimum that reliably works.
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(isZoomed ? "Swipe down or tap ✕ to close"
                          : "Pinch or double-tap to zoom · swipe down to close")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Above the image, so the gestures on it can never swallow the button.
        .zIndex(1)
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

    /// One drag gesture doing two jobs, decided by zoom level: panning around
    /// a zoomed image, or pulling the whole thing down to dismiss.
    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                if isZoomed {
                    offset = CGSize(width: committedOffset.width + value.translation.width,
                                    height: committedOffset.height + value.translation.height)
                } else {
                    // Downward only. Dragging up should do nothing rather
                    // than something unexplained.
                    dismissDrag = max(value.translation.height, 0)
                }
            }
            .onEnded { value in
                if isZoomed {
                    committedOffset = offset
                    return
                }
                if value.translation.height > dismissThreshold {
                    onClose()
                } else {
                    withAnimation(.easeOut(duration: 0.22)) { dismissDrag = 0 }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            if isZoomed { resetZoom() } else { scale = 3; committedScale = 3 }
        }
    }

    private func resetZoom() {
        scale = 1
        committedScale = 1
        resetPan()
    }

    private func resetPan() {
        offset = .zero
        committedOffset = .zero
    }
}
