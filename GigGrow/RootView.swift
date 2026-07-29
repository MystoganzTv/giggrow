//
//  RootView.swift
//  GigGrow
//
//  Decides between onboarding and the app, then hosts the five screens
//  behind the custom tab bar and rebuilds the snapshot when data changes.
//

import SwiftUI
import SwiftData
import UserNotifications

struct RootView: View {
    @Environment(\.modelContext) private var context

    @State private var selection: GGIcon = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-GGScreenshotTab"),
           arguments.indices.contains(flag + 1),
           let tab = GGIcon(rawValue: arguments[flag + 1]),
           GGIcon.tabs.contains(tab) {
            return tab
        }
        #endif
        return .dashboard
    }()
    @State private var isLoggingShift = false
    @State private var isLoggingExpense = false
    @State private var isShowingExpenses = false
    @State private var isShowingHistory = false
    @State private var isImporting = false
    @State private var isShowingMileage = false
    /// A brand-new install gets a short iCloud grace period before local
    /// reference data is created. This avoids racing a private CloudKit
    /// restore and briefly producing two copies of every platform.
    @State private var isPreparingStore = true

    /// Kept alive for the whole app run: UNUserNotificationCenter holds its
    /// delegate weakly, so a local one would be deallocated and taps would
    /// silently stop routing anywhere.
    @State private var notificationDelegate = TripNotificationDelegate()
    /// One selection per screen. Tapping "Year" on Analytics shouldn't
    /// silently reframe the dashboard, and vice versa.
    @State private var dashboardScope: DashboardScope = .week
    /// Which week or year the dashboard is showing. Scope alone can only say
    /// "a week"; the anchor is what lets the driver move to the week they
    /// actually want to inspect.
    @State private var dashboardAnchor: Date = .now
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

    /// The dashboard projection for its selected Week / Year / Total scope.
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
        build(range: selection.window, rangeKind: selection.range)
    }

    private func buildDashboard() -> EarningsSnapshot? {
        let dates = shifts.map(\.start) + expenses.map(\.date)
        return build(
            range: dashboardScope.window(
                recordDates: dates,
                now: dashboardAnchor
            ),
            rangeKind: dashboardScope.rangeKind
        )
    }

    private func build(
        range: Range<Date>,
        rangeKind: AnalyticsRange
    ) -> EarningsSnapshot? {
        guard let profile = profiles.first else { return nil }
        return EarningsSnapshot.build(
            shifts: shifts,
            expenses: expenses,
            // Historical earnings do not disappear because a platform was
            // later switched off. SnapshotBuilder already omits accounts
            // with no activity in the selected period.
            accounts: accounts,
            profile: profile,
            vehicle: vehicles.first,
            // The window the driver is pointing at, not always the present.
            range: range,
            rangeKind: rangeKind
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let usesWideLayout = proxy.size.width >= GG.Layout.wideLayoutMinimumWidth
            let usesSidebarLayout = proxy.size.width >= GG.Layout.sidebarLayoutMinimumWidth

            Group {
                if isPreparingStore {
                    ZStack {
                        GG.Palette.screen.ignoresSafeArea()
                        VStack(spacing: 16) {
                            GigGrowLogo(size: 52)
                            ProgressView()
                                .tint(GG.Palette.violet400)
                            Text("Checking iCloud…")
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                        }
                    }
                } else if needsOnboarding {
                    OnboardingView()
                        .transition(.opacity)
                } else if let ready = snapshot ?? buildDashboard() {
                    // Falls through to building it inline when the cache hasn't
                    // caught up. Caching the projection introduced a window right
                    // after onboarding where the profile existed but the snapshot
                    // was still nil, and the app rendered nothing at all — a black
                    // screen at the exact moment someone finishes signing up.
                    main(
                        ready,
                        usesSidebarLayout: usesSidebarLayout
                    )
                }
            }
            .environment(\.ggUsesWideLayout, usesWideLayout)
            .environment(\.ggUsesSidebarLayout, usesSidebarLayout)
        }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.25), value: needsOnboarding)
        .task {
            // Existing installs open immediately. An entirely empty store
            // waits briefly for CloudKit's first import before creating the
            // built-in platform catalogue.
            if profiles.isEmpty && accounts.isEmpty && shifts.isEmpty
                && expenses.isEmpty && vehicles.isEmpty {
                try? await Task.sleep(for: .seconds(2))
            }
            Seed.reconcileDuplicatePlatforms(context)
            Seed.bootstrapPlatformsIfNeeded(context)
            Seed.repairKnownVehicleDefaults(context)
            isPreparingStore = false
            configureTracker()
            rebuild()
            UNUserNotificationCenter.current().delegate = notificationDelegate
        }
        // Tapping "Trip recorded" opens the log rather than dumping you on
        // whatever screen you happened to leave the app on.
        .onReceive(NotificationCenter.default.publisher(for: TripNotifier.openMileageLog)) { _ in
            isShowingMileage = true
        }
        // Rebuilt when the data actually changes, rather than when SwiftUI
        // happens to re-evaluate the view. @Query publishes on every save,
        // which is exactly the signal wanted and nothing more.
        .onChange(of: dataFingerprint) { _, _ in rebuild() }
        .onChange(of: platformFingerprint) { _, _ in
            // CloudKit imports records asynchronously. Reconcile after the
            // batch has had time to settle rather than once per inserted row.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if Seed.reconcileDuplicatePlatforms(context) > 0 {
                    rebuild()
                }
            }
        }
        .onChange(of: analyticsSelection) { _, _ in rebuildAnalytics() }
        .onChange(of: dashboardScope) { _, _ in rebuild() }
        .onChange(of: dashboardAnchor) { _, _ in rebuild() }
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
            hasher.combine(shift.earningItems.count)
            for earning in shift.earningItems {
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

    private var platformFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(accounts.count)
        for account in accounts {
            hasher.combine(account.name.lowercased())
            hasher.combine(account.isActive)
            hasher.combine(account.earningItems.count)
        }
        return hasher.finalize()
    }

    private func rebuild() {
        snapshot = buildDashboard()
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

    private func main(
        _ snapshot: EarningsSnapshot,
        usesSidebarLayout: Bool
    ) -> some View {
        Group {
            if usesSidebarLayout {
                HStack(spacing: 0) {
                    GGNavigationRail(selection: $selection)

                    ZStack(alignment: .bottomTrailing) {
                        GG.Palette.screen.ignoresSafeArea()
                        screen(snapshot)
                            .transition(.opacity)
                        logButton(snapshot, usesSidebarLayout: true)
                    }
                }
            } else {
                ZStack(alignment: .bottom) {
                    GG.Palette.screen.ignoresSafeArea()
                    screen(snapshot)
                        .transition(.opacity)
                    GGTabBar(selection: $selection)
                    logButton(snapshot, usesSidebarLayout: false)
                }
            }
        }
        .sheet(isPresented: $isLoggingShift) { LogShiftView() }
        .sheet(isPresented: $isLoggingExpense) { LogExpenseView() }
        .sheet(isPresented: $isShowingExpenses) { ExpensesView() }
        .sheet(isPresented: $isShowingHistory) { ShiftHistoryView() }
        .sheet(isPresented: $isImporting) { ImportScreenshotView() }
        .sheet(isPresented: $isShowingMileage) { MileageView(tracker: tracker) }
    }

    @ViewBuilder
    private func screen(_ snapshot: EarningsSnapshot) -> some View {
        switch selection {
        case .dashboard:
            DashboardView(snapshot: snapshot,
                          scope: $dashboardScope,
                          anchor: $dashboardAnchor,
                          onLogShift: { isLoggingShift = true },
                          onShowHistory: { isShowingHistory = true },
                          onImport: { isImporting = true },
                          onShowMileage: { isShowingMileage = true },
                          onShowExpenses: { isShowingExpenses = true },
                          onAddExpense: { isLoggingExpense = true })
        case .taxes:     TaxView(embedded: true)
        case .analytics: AnalyticsView(snapshot: analyticsSnapshot ?? snapshot,
                                       selection: $analyticsSelection,
                                       onShowExpenses: { isShowingExpenses = true })
        case .vehicle:   VehicleView(snapshot: snapshot)
        case .expenses:  ExpensesView(embedded: true)
        case .settingsGear:
            SettingsView(snapshot: snapshot, tracker: tracker)
        }
    }

    /// Floating action button. Hidden on Settings, and on the empty dashboard
    /// where a full-width prompt does the job better.
    @ViewBuilder
    private func logButton(
        _ snapshot: EarningsSnapshot,
        usesSidebarLayout: Bool
    ) -> some View {
        let hiddenOnEmptyDashboard = selection == .dashboard && !snapshot.hasData

        if selection != .expenses
            && selection != .settingsGear
            && !hiddenOnEmptyDashboard {
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
                .background(GG.Gradients.brandMark, in: Capsule())
                .shadow(color: Color(hex: 0x5C3CDC, opacity: 0.55), radius: 18, y: 8)
            } primaryAction: {
                isImporting = true
            }
            .padding(.trailing, usesSidebarLayout ? 26 : 0)
            .padding(.bottom, usesSidebarLayout ? 24 : GG.Layout.tabBarHeight + 18)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview("GigGrow — with data") {
    RootView()
        .modelContainer(.preview)
}

#Preview("GigGrow — first launch") {
    RootView()
        .modelContainer(.previewEmpty)
}
