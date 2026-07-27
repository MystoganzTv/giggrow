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
    @State private var isShowingMileage = false
    /// One selection per screen. Tapping "Year" on Analytics shouldn't
    /// silently reframe the dashboard, and vice versa.
    @State private var dashboardSelection = RangeSelection(range: .week)
    @State private var analyticsSelection = RangeSelection(range: .week)

    /// One tracker for the whole app. It owns a CLLocationManager, so a second
    /// instance would mean a second set of permission prompts and duplicate
    /// drives. Settings gets this one handed to it rather than making its own.
    @State private var tracker = MileageTracker()

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
    ///
    /// Cached, not computed. As a computed property this ran on every single
    /// body evaluation — every keystroke, every tab change, every frame of an
    /// animation — and each run walks every shift, every earning and every
    /// expense in the store. That is the app being slow: not the phone, and
    /// not the amount of data, but recomputing all of it hundreds of times
    /// for one screen that didn't change.
    @State private var snapshot: EarningsSnapshot?

    /// Analytics gets its own, built for whatever the picker is set to.
    /// Two projections rather than one shared mutable range: the dashboard
    /// shouldn't silently switch to yearly figures because you tapped a pill
    /// on another tab.
    ///
    /// Only rebuilt while Analytics is on screen. It used to be computed
    /// alongside the weekly one, so four of the five tabs paid for a second
    /// full projection they never displayed.
    @State private var analyticsSnapshot: EarningsSnapshot?

    private func build(_ selection: RangeSelection) -> EarningsSnapshot? {
        guard let profile = profiles.first else { return nil }
        return EarningsSnapshot.build(
            shifts: shifts,
            expenses: expenses,
            accounts: accounts.filter(\.isActive),
            profile: profile,
            vehicle: vehicles.first,
            // The window the driver is pointing at, not always the present.
            range: selection.window,
            rangeKind: selection.range
        )
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else if let ready = snapshot ?? build(dashboardSelection) {
                // Falls through to building it inline when the cache hasn't
                // caught up. Caching the projection introduced a window right
                // after onboarding where the profile existed but the snapshot
                // was still nil, and the app rendered nothing at all — a black
                // screen at the exact moment someone finishes signing up.
                main(ready)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.25), value: needsOnboarding)
        .task {
            // The platform catalogue is reference data, not user data, so it
            // is safe to create before onboarding runs.
            Seed.bootstrapPlatformsIfNeeded(context)
            configureTracker()
            rebuild()
        }
        // Rebuilt when the data actually changes, rather than when SwiftUI
        // happens to re-evaluate the view. @Query publishes on every save,
        // which is exactly the signal wanted and nothing more.
        .onChange(of: dataFingerprint) { _, _ in rebuild() }
        .onChange(of: analyticsSelection) { _, _ in rebuildAnalytics() }
        .onChange(of: dashboardSelection) { _, _ in rebuild() }
        .onChange(of: selection) { _, tab in
            // Analytics is the only screen that needs the second projection.
            if tab == .analytics { rebuildAnalytics() }
        }
        .onChange(of: profiles.first?.idleThresholdMinutes) { _, _ in
            configureTracker()
        }
    }

    /// A cheap value that changes whenever anything the projection reads
    /// changes.
    ///
    /// Watching the arrays themselves isn't enough: editing a shift's gross
    /// leaves the array identical, so the dashboard would keep showing the
    /// old figure. Hashing the values catches edits as well as insertions,
    /// and hashing a few thousand doubles is orders of magnitude cheaper than
    /// the bucketing, attribution and date work the projection does.
    private var dataFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(shifts.count)
        hasher.combine(expenses.count)
        hasher.combine(accounts.count)

        for shift in shifts {
            hasher.combine(shift.start)
            hasher.combine(shift.end)
            hasher.combine(shift.miles)
            hasher.combine(shift.idleMinutes)
            hasher.combine(shift.recordedHours)
            hasher.combine(shift.earnings.count)
            for earning in shift.earnings {
                hasher.combine(earning.gross)
                hasher.combine(earning.tips)
                hasher.combine(earning.promotions)
                hasher.combine(earning.trips)
            }
        }
        for expense in expenses {
            hasher.combine(expense.date)
            hasher.combine(expense.amount)
        }
        for account in accounts {
            hasher.combine(account.name)
            hasher.combine(account.isActive)
        }
        if let profile = profiles.first {
            hasher.combine(profile.taxRate)
            hasher.combine(profile.maintenanceRate)
            hasher.combine(profile.mileageRate)
            hasher.combine(profile.maintenanceOpeningBalance)
            hasher.combine(profile.planTierRaw)
        }
        if let vehicle = vehicles.first {
            hasher.combine(vehicle.odometerBaseline)
            hasher.combine(vehicle.fuelCostPerMile)
        }
        return hasher.finalize()
    }

    private func rebuild() {
        snapshot = build(dashboardSelection)
        if selection == .analytics { rebuildAnalytics() }
    }

    private func rebuildAnalytics() {
        analyticsSnapshot = build(analyticsSelection)
    }

    /// Hands the tracker its context and the driver's idle threshold, then
    /// re-arms it if tracking was on when the app was last closed. Permission
    /// is never requested here — only `enable()` from the switch does that,
    /// and `enable()` no-ops into `.denied` if the driver said no.
    private func configureTracker() {
        guard let profile = profiles.first else { return }
        tracker.configure(context: context, idleMinutes: profile.idleThresholdMinutes)
        if profile.autoMileageTracking && tracker.status == .off {
            tracker.enable()
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
        .sheet(isPresented: $isShowingMileage) { MileageView(tracker: tracker) }
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
                                       onImport: { isImporting = true },
                                       onShowMileage: { isShowingMileage = true })
        case .taxes:     TaxView(embedded: true)
        case .analytics: AnalyticsView(snapshot: analyticsSnapshot ?? snapshot,
                                       selection: $analyticsSelection,
                                       onShowExpenses: { isShowingExpenses = true })
        case .vehicle:   VehicleView(snapshot: snapshot)
        case .settings:  SettingsView(snapshot: snapshot, tracker: tracker)
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
