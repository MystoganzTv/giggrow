//
//  RootView.swift
//  GigPilot
//
//  Hosts the five screens behind the custom tab bar, and rebuilds the
//  snapshot whenever the stored data changes.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context

    @State private var selection: GPIcon = .dashboard
    @State private var isLoggingShift = false

    /// Re-running the projection on every shift/expense change is what keeps
    /// all five screens live. @Query gives us the change notification; the
    /// heavy lifting happens in `EarningsSnapshot.build`.
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]
    @Query private var expenses: [Expense]
    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]
    @Query private var profiles: [DriverProfile]
    @Query private var vehicles: [VehicleRecord]

    private var snapshot: EarningsSnapshot {
        guard let profile = profiles.first else { return .mock }
        return EarningsSnapshot.build(
            shifts: shifts,
            expenses: expenses,
            accounts: accounts,
            profile: profile,
            vehicle: vehicles.first
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GP.Palette.screen.ignoresSafeArea()

            screen
                .transition(.opacity)

            GPTabBar(selection: $selection)

            logButton
        }
        .preferredColorScheme(.dark)
        .task {
            // First launch only; a no-op once a profile exists.
            Seed.bootstrapIfNeeded(context)
        }
        .sheet(isPresented: $isLoggingShift) {
            LogShiftView()
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch selection {
        case .dashboard: DashboardView(snapshot: snapshot)
        case .apps:      AppsView(snapshot: snapshot)
        case .analytics: AnalyticsView(snapshot: snapshot)
        case .vehicle:   VehicleView(snapshot: snapshot)
        case .settings:  SettingsView(snapshot: snapshot)
        }
    }

    /// Floating action button, tucked just above the tab bar. Hidden on
    /// Settings, where there's nothing to add.
    @ViewBuilder
    private var logButton: some View {
        if selection != .settings {
            Button {
                isLoggingShift = true
            } label: {
                HStack(spacing: 7) {
                    PlusGlyph()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .frame(width: 16, height: 16)
                    Text("Log shift")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(GP.Gradients.brandMark, in: Capsule())
                .shadow(color: Color(hex: 0x5C3CDC, opacity: 0.55), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.bottom, GP.Layout.tabBarHeight + 18)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview("GigPilot") {
    RootView()
        .modelContainer(.preview)
}
