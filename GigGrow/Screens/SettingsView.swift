//
//  SettingsView.swift
//  GigGrow
//
//  Screen 05 — profile, subscription, and the preference lists.
//
//  Every row here either does something or carries no chevron. A chevron in
//  iOS is a promise of navigation; the first version of this screen made that
//  promise eleven times and kept it zero times.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    let snapshot: EarningsSnapshot
    var appVersion: String = "3.2.1"

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context

    @Query private var profiles: [DriverProfile]
    @Query(sort: \Shift.start) private var shifts: [Shift]
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @Query private var drives: [DriveRecord]

    /// Injected from the root so the switch reflects the live tracker rather
    /// than a stored flag that could disagree with reality.
    var tracker: MileageTracker? = nil

    @State private var isUpgrading = false
    @State private var isShowingDrives = false
    @State private var isPickingState = false
    @State private var isConfirmingErase = false
    @State private var isManagingPlatforms = false
    @State private var route: Route?

    /// Bound to the profile so the picker writes straight through.
    private var stateBinding: Binding<String> {
        Binding(
            get: { profile?.stateCode ?? "" },
            set: { profile?.stateCode = $0; save() }
        )
    }

    private var entitlement: Entitlement { snapshot.entitlement }
    private var profile: DriverProfile? { profiles.first }

    /// One case per destination, so a row can't be added without deciding
    /// where it goes.
    private enum Route: String, Identifiable {
        case profile, taxRate, maintenanceRate, mileageRate, privacy
        var id: String { rawValue }
    }

    var body: some View {
        ScreenScaffold {
            GG.Gradients.settingsWash()
        } content: {
            Text("Settings")
                .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)

            profileCard
            subscriptionCard

            moneyGroup
            trackingGroup
            generalGroup

            #if DEBUG
            debugSection
            #endif

            footer
        }
        .sheet(isPresented: $isUpgrading) {
            UpgradeView(previewReserve: snapshot.maintenanceFund)
        }
        .sheet(item: $route) { destination in
            editor(for: destination)
        }
        .alert("Erase all data?", isPresented: $isConfirmingErase) {
            // Cancel first, so the default action is the safe one.
            Button("Cancel", role: .cancel) { }
            Button("Erase everything", role: .destructive) {
                Seed.wipe(context)
            }
        } message: {
            Text("Every shift, imported screenshot, weekly total, recorded drive, expense and vehicle record is deleted from this phone. Export first if you want to keep any of it — this can't be undone.")
        }
        .sheet(isPresented: $isManagingPlatforms) {
            ManagePlatformsView()
        }
        .sheet(isPresented: $isShowingDrives) {
            MileageView(tracker: tracker)
        }
        .sheet(isPresented: $isPickingState) {
            StatePickerView(selection: stateBinding) { state in
                // Offer the suggestion, don't impose it — the driver may have
                // deliberately set their own rate already.
                if let profile, profile.taxRate == 25 {
                    profile.taxRate = state.suggestedTaxRate
                    save()
                }
            }
        }
    }

    // MARK: Profile

    private var profileCard: some View {
        Button {
            if profile != nil { route = .profile }
        } label: {
            GlassCard {
                HStack(spacing: 15) {
                    Monogram(letter: snapshot.driver.initial,
                             size: 54,
                             gradient: GG.Gradients.brandMark)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.driver.name)
                            .ggText(GG.Typo.title3, tracking: GG.Typo.title3Tracking)
                        Text(snapshot.driver.detail)
                            .ggText(.system(size: 13.5, weight: .regular), color: GG.Ink.tertiary)
                    }

                    Spacer(minLength: 8)

                    Chevron(size: 18, color: Color.white.opacity(0.30))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Subscription

    private var subscriptionCard: some View {
        Button {
            if entitlement.isPro { openSubscriptionManagement() } else { isUpgrading = true }
        } label: {
            HeroCard(radius: GG.Radius.card,
                     padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                     gradient: GG.Gradients.heroPro) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entitlement.isPro ? "GigGrow Pro" : "Upgrade to Pro")
                            .ggText(.system(size: 17, weight: .semibold), tracking: -0.26)
                        Text(subscriptionCaption)
                            .ggText(.system(size: 13.5, weight: .regular),
                                    color: Color.white.opacity(0.55))
                    }

                    Spacer(minLength: 8)

                    Text(entitlement.isPro ? "Manage" : "See plans")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var subscriptionCaption: String {
        guard entitlement.isPro else {
            return "From \(Plan.proAnnual.monthlyEquivalent) / month"
        }
        guard let renews = snapshot.planRenewsOn else { return Plan.proMonthly.perPeriodLabel }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(Plan.proMonthly.perPeriodLabel) · renews \(f.string(from: renews))"
    }

    // MARK: Money

    private var moneyGroup: some View {
        SettingsGroup(title: "Money") {
            // Taking Apps out of the tab bar orphaned this — it was the only
            // way in, and without it there is no way to turn a platform on or
            // off. Losing a feature to a navigation change is the kind of
            // thing nobody notices until a driver asks where it went.
            SettingsRow(label: "Your apps", value: activePlatformSummary) {
                isManagingPlatforms = true
            }
            RowDivider(color: GG.Surface.dividerSoft)
            SettingsRow(label: "State",
                        value: StateDirectory.state(code: profile?.stateCode ?? "")?.name
                               ?? "Not set") {
                isPickingState = true
            }
            RowDivider(color: GG.Surface.dividerSoft)
            SettingsRow(label: "Tax set-aside",
                        value: percent(profile?.taxRate ?? snapshot.taxRate)) { route = .taxRate }
            RowDivider(color: GG.Surface.dividerSoft)
            SettingsRow(label: "Maintenance set-aside",
                        value: percent(profile?.maintenanceRate ?? snapshot.maintenanceRate)) {
                route = .maintenanceRate
            }
            RowDivider(color: GG.Surface.dividerSoft)
            SettingsRow(label: "Mileage rate", value: mileageRateLabel) {
                route = .mileageRate
            }
            RowDivider(color: GG.Surface.dividerSoft)
            SettingsRow(label: "Payout account",
                        value: (profile?.payoutLast4).flatMap { $0.isEmpty ? nil : "•••• \($0)" }
                               ?? "Not set") {
                route = .profile
            }
        }
    }

    // MARK: Tracking

    private var trackingGroup: some View {
        SettingsGroup(title: "Tracking") {
            if TrackingCapability.automaticMileage { mileageToggle }

            RowDivider(color: GG.Surface.dividerSoft)
            SettingsRow(label: "Mileage log",
                        value: mileageSummary) {
                isShowingDrives = true
            }



        }
    }

    /// What's in the log, in the terms it matters in: miles you can claim,
    /// and how many still need a decision.
    private var activePlatformSummary: String {
        let active = snapshot.platforms.count
        return active == 0 ? "None picked" : "\(active) active"
    }

    private var mileageSummary: String {
        guard !drives.isEmpty else { return "Empty" }
        let unsorted = drives.filter { $0.purpose == .unclassified }.count
        let businessMiles = drives.filter { $0.purpose.isDeductible }
            .reduce(0) { $0 + $1.miles }

        if unsorted > 0 {
            return "\(unsorted) to sort"
        }
        return String(format: "%.0f business mi", businessMiles)
    }

    private var mileageToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { tracker?.status.isArmed ?? false },
                set: { on in
                    profile?.autoMileageTracking = on
                    save()
                    if on { tracker?.enable() } else { tracker?.disable() }
                }
            )) {
                Text("Track miles automatically")
                    .ggText(GG.Typo.rowLabel)
            }
            .tint(GG.Palette.violet500)

            // Whatever the tracker actually reports, not what the switch says.
            // A denied permission with the switch left on is exactly the lie
            // this screen used to tell.
            if let tracker {
                switch tracker.status {
                case .denied:
                    trackingNote("Location is off for GigGrow. Turn it on in iOS Settings and drives will record again.",
                                 colour: GG.Palette.amber)
                case .restricted:
                    trackingNote("Location is restricted on this device, so miles can't be recorded automatically.",
                                 colour: GG.Palette.amber)
                case .recording:
                    trackingNote("Recording a drive now.", colour: GG.Palette.mint)
                case .waiting:
                    trackingNote("Watching for driving. GPS only switches on once you're moving, which is what keeps the battery cost down.",
                                 colour: GG.Ink.muted)
                case .off:
                    trackingNote("Off. Miles are whatever you enter by hand.", colour: GG.Ink.muted)
                }

                if let notice = tracker.notice {
                    trackingNote(notice, colour: GG.Palette.amber)
                }
            }
        }
        .padding(.vertical, 13)
    }

    private func trackingNote(_ text: String, colour: Color) -> some View {
        Text(text)
            .ggText(GG.Typo.footnote, color: colour)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: General

    private var generalGroup: some View {
        SettingsGroup(title: "General") {
            // ShareLink is the row, so it works without a chevron that lies.
            ShareLink(
                item: CSVDocument(name: "giggrow-shifts", text: CSVExport.shifts(shifts)),
                preview: SharePreview("GigGrow shifts")
            ) {
                shareRowLabel("Export shifts", value: "\(shifts.count) logged")
            }
            .disabled(shifts.isEmpty)

            RowDivider(color: GG.Surface.dividerSoft)

            ShareLink(
                item: CSVDocument(name: "giggrow-expenses", text: CSVExport.expenses(expenses)),
                preview: SharePreview("GigGrow expenses")
            ) {
                shareRowLabel("Export expenses", value: "\(expenses.count) logged")
            }
            .disabled(expenses.isEmpty)

            if !drives.isEmpty {
                RowDivider(color: GG.Surface.dividerSoft)

                ShareLink(
                    item: CSVDocument(
                        name: "giggrow-drives",
                        text: CSVExport.drives(drives, overrideRate: profile?.mileageRate ?? 0)
                    ),
                    preview: SharePreview("GigGrow drives")
                ) {
                    shareRowLabel("Export drives", value: "\(drives.count) recorded")
                }
            }

            RowDivider(color: GG.Surface.dividerSoft)

            SettingsRow(label: "Privacy", value: "") { route = .privacy }

            RowDivider(color: GG.Surface.dividerSoft)

            // Not a debug affordance. The privacy sheet says this data is
            // yours and lives on your phone; that only means something if
            // you can delete it without deleting the app.
            SettingsRow(label: "Erase all data",
                        value: storedSummary,
                        showsChevron: false,
                        destructive: true) {
                isConfirmingErase = true
            }
        }
    }

    /// Says what is about to go, in the driver's own numbers. "Erase all
    /// data" is abstract; "126 shifts, 340 drives" is not.
    private var storedSummary: String {
        var parts: [String] = []
        if !shifts.isEmpty   { parts.append("\(shifts.count) shift\(shifts.count == 1 ? "" : "s")") }
        if !drives.isEmpty   { parts.append("\(drives.count) drive\(drives.count == 1 ? "" : "s")") }
        if !expenses.isEmpty { parts.append("\(expenses.count) expense\(expenses.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing stored" : parts.joined(separator: " · ")
    }

    private func shareRowLabel(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .ggText(GG.Typo.rowLabel)
            Spacer(minLength: 12)
            Text(value)
                .ggText(.system(size: 14.5, weight: .regular), color: GG.Ink.tertiary)
            Chevron()
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    // MARK: Editors

    @ViewBuilder
    private func editor(for route: Route) -> some View {
        if let profile {
            switch route {
            case .profile:
                ProfileEditor(profile: profile)

            case .taxRate:
                PercentageEditor(
                    title: "Tax set-aside",
                    explanation: "Self-employment tax runs about 15.3% on top of income tax, so most drivers land between 20% and 30%. Set it too low and April hurts; too high and you're lending the government money for free.",
                    value: profile.taxRate,
                    previewBase: snapshot.weeklyTotal,
                    presets: [20, 25, 30],
                    range: 0...50
                ) { profile.taxRate = $0; save() }

            case .maintenanceRate:
                PercentageEditor(
                    title: "Maintenance set-aside",
                    explanation: "Covers tyres, brakes, oil and the repair you haven't had yet. High-mileage drivers often go above 10%. This money is held aside — spending it on maintenance won't reduce your take-home.",
                    value: profile.maintenanceRate,
                    previewBase: snapshot.weeklyTotal,
                    presets: [5, 8, 12],
                    range: 0...25
                ) { profile.maintenanceRate = $0; save() }

            case .mileageRate:
                DecimalEditor(
                    title: "Mileage rate",
                    explanation: "The IRS standard mileage rate for the current tax year, used to estimate your deduction. Check the current figure on irs.gov — it changes annually.",
                    suffix: "/ mi",
                    value: profile.mileageRate
                ) { profile.mileageRate = $0; save() }

            case .privacy:
                PrivacySheet()
            }
        } else {
            PrivacySheet()
        }
    }

    private func save() { try? context.save() }

    private func percent(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    /// Shows the rate actually in force, and says where it came from. A
    /// stored zero means "follow the IRS schedule", which changed mid-2026.
    private var mileageRateLabel: String {
        let override = profile?.mileageRate ?? 0
        if override > 0 { return String(format: "$%.2f / mi", override) }
        return "\(MileageRates.formatted(MileageRates.current)) / mi · IRS"
    }

    private func openSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            openURL(url)
        }
    }

    // MARK: Debug

    #if DEBUG
    private var debugSection: some View {
        SettingsGroup(title: "Debug", tint: GG.Palette.amber.opacity(0.8)) {
            SettingsRow(label: "Load demo week", value: "", showsChevron: false) {
                Seed.loadDemoData(context)
            }
            RowDivider(color: GG.Surface.dividerSoft)
            SettingsRow(label: "Toggle Pro",
                        value: entitlement.isPro ? "on" : "off",
                        showsChevron: false) {
                profile?.planTierRaw = entitlement.isPro
                    ? PlanTier.free.rawValue
                    : PlanTier.pro.rawValue
                save()
            }
        }
    }
    #endif

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            GigGrowLogo(size: 34, glow: false)
                .opacity(0.55)
            Text("GigGrow \(appVersion) · Built for drivers")
                .ggText(GG.Typo.footnote, color: GG.Ink.faint)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 14)
    }
}

// MARK: - Row components

/// A settings row. The chevron is tied to having an action, so one can't
/// appear without the other.
struct SettingsRow: View {
    let label: String
    let value: String
    var showsChevron: Bool = true
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .ggText(GG.Typo.rowLabel,
                            color: destructive ? Color(hex: 0xFB7185) : GG.Ink.primary)

                Spacer(minLength: 12)

                HStack(spacing: 9) {
                    if !value.isEmpty {
                        Text(value)
                            .ggText(.system(size: 14.5, weight: .regular), color: GG.Ink.tertiary)
                    }
                    if showsChevron { Chevron() }
                }
            }
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Titled group wrapper.
struct SettingsGroup<Content: View>: View {
    let title: String
    var tint: Color = GG.Ink.muted
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .ggText(GG.Typo.groupLabel, tracking: GG.Typo.groupLabelTracking, color: tint)
                .padding(.leading, 6)

            GlassCard(radius: GG.Radius.tile,
                      padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) { content }
            }
        }
        .padding(.top, 6)
    }
}

#Preview("Settings") {
    SettingsView(snapshot: .mock)
        .modelContainer(.preview)
}
