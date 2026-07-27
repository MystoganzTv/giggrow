//
//  TrackTripView.swift
//  GigGrow
//
//  Start and stop a trip by hand.
//
//  Automatic tracking covers the ordinary day, but it has two gaps this
//  closes. A driver who won't leave location on all the time still deserves
//  a way to record miles, and a drive that matters — a long delivery run, a
//  trip to the parts shop — is worth starting deliberately so it can't be
//  missed by a motion classifier having a bad minute.
//
//  The screen is deliberately one decision wide. Start, then a number that
//  goes up, then Stop.
//

import SwiftUI

struct TrackTripView: View {
    @Environment(\.dismiss) private var dismiss

    var tracker: MileageTracker?

    /// Drives the elapsed readout. Location updates arrive irregularly — the
    /// clock shouldn't stutter because the car is stopped at a light.
    @State private var tick = Date.now
    @State private var outcome: Outcome?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// What to say after Stop. A trip that disappears into nothing is the
    /// fastest way to make someone distrust the feature.
    private enum Outcome: Identifiable {
        case saved(miles: Double)
        case tooShort(miles: Double)
        var id: String {
            switch self {
            case .saved(let m):    return "saved-\(m)"
            case .tooShort(let m): return "short-\(m)"
            }
        }
    }

    private var isRecording: Bool { tracker?.status == .recording }

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.settingsWash().ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RouteIllustration(isActive: isRecording)
                        .frame(width: 240, height: 190)
                    Spacer(minLength: 0)
                    controlCard
                }
            }
            .navigationTitle("Track a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Wording matches the stakes: leaving mid-trip would
                    // throw the miles away, so it says so.
                    Button(isRecording ? "Cancel trip" : "Cancel") { cancel() }
                        .foregroundStyle(isRecording ? GG.Palette.amber : GG.Ink.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(timer) { now in
            // Only while something is being timed. A 1Hz redraw of a static
            // screen is wasted battery on a phone that's also running three
            // other apps.
            if isRecording { tick = now }
        }
        .alert(item: $outcome) { outcome in
            switch outcome {
            case .saved(let miles):
                return Alert(
                    title: Text("Trip saved"),
                    message: Text(String(format: "%.1f miles recorded. Mark it business or personal to count it.", miles)),
                    dismissButton: .default(Text("Done")) { dismiss() }
                )
            case .tooShort(let miles):
                return Alert(
                    title: Text("Too short to save"),
                    message: Text(String(format: "%.2f miles is below the 0.3 mile floor, which exists so GPS drift can't turn into a deduction.", miles)),
                    dismissButton: .default(Text("OK")) { dismiss() }
                )
            }
        }
    }

    // MARK: Control

    @ViewBuilder
    private var controlCard: some View {
        GlassCard(radius: GG.Radius.hero,
                  padding: EdgeInsets(top: 22, leading: 20, bottom: 22, trailing: 20)) {
            switch tracker?.status {
            case .denied:
                blocked("Location is off for GigGrow. Turn it on in iOS Settings and this will work.")
            case .restricted:
                blocked("Location is restricted on this device, so a trip can't be measured.")
            case .recording:
                running
            default:
                idle
            }
        }
        .padding(.horizontal, GG.Layout.screenInset)
        .padding(.bottom, 22)
    }

    private var idle: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Start tracking your trip")
                    .ggText(GG.Typo.cardTitle, tracking: GG.Typo.cardTitleTracking)
                Text("GigGrow follows you from A to B and works out the distance. Keep the app open, or allow location “Always” to leave it running in your pocket.")
                    .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button { tracker?.startManualTrip() } label: {
                Text("Start")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background(GG.Gradients.brandMark, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(tracker == nil)
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                PulsingDot()
                Text("Recording")
                    .ggText(.system(size: 12.5, weight: .semibold), tracking: 0.6,
                            color: GG.Palette.mint)
                Spacer(minLength: 0)
                Text(elapsed)
                    .ggText(.system(size: 15, weight: .medium).monospacedDigit(),
                            color: GG.Ink.tertiary)
            }

            // The number the driver is here for, at the size that says so —
            // unless there's no fix yet, in which case saying so is more use
            // than a confident zero.
            if tracker?.hasFix == false {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finding you…")
                        .ggText(GG.Typo.heroAmountSmall,
                                tracking: GG.Typo.heroAmountSmallTracking,
                                color: GG.Ink.secondary)
                    Text("GPS can take a moment, especially indoors or in a garage.")
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", tracker?.currentMiles ?? 0))
                        .ggText(GG.Typo.heroAmount, tracking: GG.Typo.heroAmountTracking)
                        .monospacedDigit()
                    Text("mi")
                        .ggText(.system(size: 20, weight: .medium), color: GG.Ink.tertiary)
                }
            }

            Button { stop() } label: {
                Text("Stop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(GG.Surface.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func blocked(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Can't track this trip")
                .ggText(GG.Typo.cardTitle, tracking: GG.Typo.cardTitleTracking)
            Text(message)
                .ggText(GG.Typo.footnote, color: GG.Palette.amber.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func stop() {
        guard let tracker else { return }
        let metres = tracker.finishNow()
        let miles = metres / 1_609.344
        // 0.3 is the same floor the automatic path uses, so the two can't
        // disagree about what counts as a trip.
        outcome = miles >= 0.3 ? .saved(miles: miles) : .tooShort(miles: miles)
    }

    private func cancel() {
        if isRecording { tracker?.discardCurrentTrip() }
        dismiss()
    }

    /// Recomputed each tick rather than stored, so it can't drift.
    private var elapsed: String {
        let seconds = Int(tracker?.currentDuration ?? 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%d:%02d", minutes, seconds % 60)
    }
}

// MARK: - Illustration

/// Two pins and a route between them, drawn rather than shipped as an asset
/// so it inherits the palette and doesn't need a second copy for light mode.
private struct RouteIllustration: View {
    var isActive: Bool

    /// How much of the route is drawn, 0…1.
    @State private var progress: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            GridPaper()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)

            // The full route, faint — so the road ahead is visible and the
            // drawn part reads as progress along it rather than as a line
            // growing into nothing.
            RoutePath()
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.white.opacity(0.07))

            RoutePath()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(GG.Gradients.brandMark)

            // The car, riding the head of the drawn line.
            RoutePath()
                .trim(from: max(progress - 0.001, 0), to: progress)
                .stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .foregroundStyle(GG.Palette.mint)
                .shadow(color: GG.Palette.mint.opacity(0.7), radius: 8)
                .opacity(progress > 0.01 && progress < 0.99 ? 1 : 0)

            Pin(color: GG.Palette.violet500)
                .frame(width: 30, height: 38)
                .position(x: 58, y: 44)

            Pin(color: GG.Palette.mint)
                .frame(width: 30, height: 38)
                .position(x: 196, y: 128)
                // The destination lands when the route reaches it.
                .scaleEffect(progress > 0.95 ? 1 : 0.82)
                .opacity(progress > 0.95 ? 1 : 0.45)
                .animation(.spring(response: 0.35, dampingFraction: 0.55), value: progress > 0.95)

            if isActive {
                // Only while recording — a halo that breathes on an idle
                // screen is decoration; here it means "this is running".
                Circle()
                    .stroke(GG.Palette.mint.opacity(pulse ? 0 : 0.5), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.9 : 1)
                    .position(x: 196, y: 128)
            }
        }
        .frame(width: 240, height: 190)
        .onAppear { start() }
        .onChange(of: isActive) { _, _ in start() }
    }

    private func start() {
        // Reset without animating, or SwiftUI animates the jump back to zero
        // as well and the two runs stack into a stutter. This is what made it
        // look broken: a repeatForever started on top of one already running
        // never settles.
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            progress = 0
            pulse = false
        }

        // A beat, so the reset commits before the loop begins.
        DispatchQueue.main.async {
            // Slower once recording: the animation is then reporting
            // something real and shouldn't race ahead of a car in traffic.
            let duration = isActive ? 3.4 : 2.2
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: false)) {
                progress = 1
            }
            guard isActive else { return }
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

private struct GridPaper: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 30
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        return path
    }
}

/// A route that turns like a street grid rather than a straight line — the
/// same shape a city drive actually makes.
private struct RoutePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 58, y: 62))
        path.addLine(to: CGPoint(x: 58, y: 100))
        path.addLine(to: CGPoint(x: 122, y: 100))
        path.addLine(to: CGPoint(x: 122, y: 152))
        path.addLine(to: CGPoint(x: 196, y: 152))
        path.addLine(to: CGPoint(x: 196, y: 146))
        return path
    }
}

private struct Pin: View {
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                PinShape()
                    .fill(color)
                    .shadow(color: color.opacity(0.45), radius: 10, y: 4)
                Circle()
                    .fill(GG.Palette.screen)
                    .frame(width: w * 0.34, height: w * 0.34)
                    .position(x: w / 2, y: h * 0.36)
            }
        }
    }
}

private struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let radius = w / 2
        let centre = CGPoint(x: rect.midX, y: rect.minY + radius)

        var path = Path()
        path.addArc(center: centre, radius: radius,
                    startAngle: .degrees(160), endAngle: .degrees(20),
                    clockwise: true)
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + h))
        path.closeSubpath()
        return path
    }
}

/// A dot that breathes, so a recording screen left face-up still reads as
/// live from across the cab.
private struct PulsingDot: View {
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .fill(GG.Palette.mint)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(GG.Palette.mint.opacity(isExpanded ? 0 : 0.6), lineWidth: 2)
                    .scaleEffect(isExpanded ? 2.6 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    isExpanded = true
                }
            }
    }
}

#Preview("Track a trip") {
    TrackTripView()
}
