//
//  RootView.swift
//  GigPilot
//
//  Decides between onboarding and the app, then hosts the five screens
//  behind the custom tab bar and rebuilds the snapshot when data changes.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context

    @State private var selection: GPIcon = .dashboard
    @State private var isLoggingShift = false
    @State private var isLoggingExpense = false
    @State private var isShowingExpenses = false
    @State private var isShowingHistory = false
    @State private var isShowingProfile = false
    @State private var isImporting = false
    @State private var analyticsRange: AnalyticsRange = .week

    /// Re-running the projection on every change is what keeps all five
    /// screens live. @Query supplies the change notification; the work
    /// happens in `EarningsSnapshot.build`.
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]
    @Query private var expenses: [Expense]
    @Query(sort: \PlatformAccount.sortIndex) private var accounts: [PlatformAccount]
    @Query private var profiles: [DriverProfile]
    @Query private var vehicles: [VehicleRecord]

    /// A profile exists only after onboarding, so its absence is the flag.
    private var needsOnboarding: Bool { profiles.isEmpty }

    /// The week. Four of the five screens read this — the dashboard says
    /// "This week" in the design, and it means it.
    private var snapshot: EarningsSnapshot? {
        build(range: .week)
    }

    /// Analytics gets its own, built for whatever the picker is set to.
    /// Two projections rather than one shared mutable range: the dashboard
    /// shouldn't silently switch to yearly figures because you tapped a pill
    /// on another tab.
    private var analyticsSnapshot: EarningsSnapshot? {
        build(range: analyticsRange)
    }

    private func build(range kind: AnalyticsRange) -> EarningsSnapshot? {
        guard let profile = profiles.first else { return nil }
        return EarningsSnapshot.build(
            shifts: shifts,
            expenses: expenses,
            accounts: accounts.filter(\.isActive),
            profile: profile,
            vehicle: vehicles.first,
            range: kind.window(containing: .now),
            rangeKind: kind
        )
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else if let snapshot {
                main(snapshot)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.25), value: needsOnboarding)
        .task {
            // The platform catalogue is reference data, not user data, so it
            // is safe to create before onboarding runs.
            Seed.bootstrapPlatformsIfNeeded(context)
        }
    }

    // MARK: App

    private func main(_ snapshot: EarningsSnapshot) -> some View {
        ZStack(alignment: .bottom) {
            GP.Palette.screen.ignoresSafeArea()

            screen(snapshot)
                .transition(.opacity)

            GPTabBar(selection: $selection)

            logButton(snapshot)
        }
        .sheet(isPresented: $isLoggingShift) { LogShiftView() }
        .sheet(isPresented: $isLoggingExpense) { LogExpenseView() }
        .sheet(isPresented: $isShowingExpenses) { ExpensesView() }
        .sheet(isPresented: $isShowingHistory) { ShiftHistoryView() }
        .sheet(isPresented: $isImporting) { ImportScreenshotView() }
        .sheet(isPresented: $isShowingProfile) {
            if let profile = profiles.first {
                ProfileEditor(profile: profile)
            }
        }
    }

    @ViewBuilder
    private func screen(_ snapshot: EarningsSnapshot) -> some View {
        switch selection {
        case .dashboard: DashboardView(snapshot: snapshot,
                                       onLogShift: { isLoggingShift = true },
                                       onShowHistory: { isShowingHistory = true },
                                       onShowProfile: { isShowingProfile = true },
                                       onImport: { isImporting = true })
        case .apps:      AppsView(snapshot: snapshot,
                                  onLogShift: { isImporting = true })
        case .analytics: AnalyticsView(snapshot: analyticsSnapshot ?? snapshot,
                                       range: $analyticsRange,
                                       onShowExpenses: { isShowingExpenses = true })
        case .vehicle:   VehicleView(snapshot: snapshot)
        case .settings:  SettingsView(snapshot: snapshot)
        }
    }

    /// Floating action button. Hidden on Settings, and on the empty dashboard
    /// where a full-width prompt does the job better.
    @ViewBuilder
    private func logButton(_ snapshot: EarningsSnapshot) -> some View {
        let hiddenOnEmptyDashboard = selection == .dashboard && !snapshot.hasData

        if selection != .settings && !hiddenOnEmptyDashboard {
            // A menu rather than two buttons: logging a shift is the common
            // case and stays one tap from the label, while expenses get a
            // home without adding a second floating control.
            Menu {
                // Screenshot first: it's the faster route and the one worth
                // forming a habit around.
                Button("Import screenshot") { isImporting = true }
                Button("Enter shift by hand") { isLoggingShift = true }
                Button("Add expense") { isLoggingExpense = true }
                Divider()
                Button("Shift history") { isShowingHistory = true }
                Button("All expenses") { isShowingExpenses = true }
            } label: {
                HStack(spacing: 7) {
                    PlusGlyph()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .frame(width: 16, height: 16)
                    Text("Log")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(GP.Gradients.brandMark, in: Capsule())
                .shadow(color: Color(hex: 0x5C3CDC, opacity: 0.55), radius: 18, y: 8)
            } primaryAction: {
                isImporting = true
            }
            .padding(.bottom, GP.Layout.tabBarHeight + 18)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview("GigPilot — with data") {
    RootView()
        .modelContainer(.preview)
}

#Preview("GigPilot — first launch") {
    RootView()
        .modelContainer(.previewEmpty)
}
