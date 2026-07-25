//
//  RootView.swift
//  GigPilot
//
//  Hosts the five screens behind the custom tab bar.
//

import SwiftUI

struct RootView: View {
    @State private var selection: GPIcon = .dashboard

    /// Single source of truth for all five screens. Swap this for a live
    /// store when the platform integrations land.
    private let snapshot = EarningsSnapshot.mock

    var body: some View {
        ZStack(alignment: .bottom) {
            GP.Palette.screen.ignoresSafeArea()

            screen
                .transition(.opacity)

            GPTabBar(selection: $selection)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
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
}

#Preview("GigPilot") {
    RootView()
}
