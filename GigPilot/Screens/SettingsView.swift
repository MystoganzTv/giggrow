//
//  SettingsView.swift
//  GigPilot
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

    @State private var isUpgrading = false
    @State private var route: Route?

    private var entitlement: Entitlement { snapshot.entitlement }
    private var profile: DriverProfile? { profiles.first }

    /// One case per destination, so a row can't be added without deciding
    /// where it goes.
    private enum Route: String, Identifiable {
        case profile, taxRate, maintenanceRate, mileageRate, idleThreshold, privacy
        var id: String { rawValue }
    }

    var body: some View {
        ScreenScaffold {
            GP.Gradients.settingsWash()
        } content: {
            Text("Settings")
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)

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
                             gradient: GP.Gradients.brandMark)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.driver.name)
                            .gpText(GP.Typo.title3, tracking: GP.Typo.title3Tracking)
                        Text(snapshot.driver.detail)
                            .gpText(.system(size: 13.5, weight: .regular), color: GP.Ink.tertiary)
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
            HeroCard(radius: GP.Radius.card,
                     padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                     gradient: GP.Gradients.heroPro) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entitlement.isPro ? "GigPilot Pro" : "Upgrade to Pro")
                            .gpText(.system(size: 17, weight: .semibold), tracking: -0.26)
                        Text(subscriptionCaption)
                            .gpText(.system(size: 13.5, weight: .regular),
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
            SettingsRow(label: "Tax set-aside",
                        value: percent(profile?.taxRate ?? snapshot.taxRate)) { route = .taxRate }
            RowDivider(color: GP.Surface.dividerSoft)
            SettingsRow(label: "Maintenance set-aside",
                        value: percent(profile?.maintenanceRate ?? snapshot.maintenanceRate)) {
                route = .maintenanceRate
            }
            RowDivider(color: GP.Surface.dividerSoft)
            SettingsRow(label: "Mileage rate",
                        value: String(format: "$%.2f / mi", profile?.mileageRate ?? 0.70)) {
                route = .mileageRate
            }
            RowDivider(color: GP.Surface.dividerSoft)
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
            SettingsRow(label: "Idle threshold",
                        value: "\(profile?.idleThresholdMinutes ?? 8) min") {
                route = .idleThreshold
            }

            // Automatic tracking isn't built. Showing a switch here — or worse,
            // "On" — would stop drivers logging miles they'd then lose.
            if !TrackingCapability.hasAnyAutomation {
                RowDivider(color: GP.Surface.dividerSoft)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Automatic mileage & shift detection")
                            .gpText(GP.Typo.rowLabel, color: GP.Ink.tertiary)
                        Spacer(minLength: 12)
                        Text(TrackingCapability.notYetLabel)
                            .gpText(.system(size: 14.5, weight: .regular), color: GP.Ink.muted)
                    }
                    Text("Not built yet. Log shifts by hand for now — GigPilot won't pretend it's recording when it isn't.")
                        .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 15)
            }
        }
    }

    // MARK: General

    private var generalGroup: some View {
        SettingsGroup(title: "General") {
            // ShareLink is the row, so it works without a chevron that lies.
            ShareLink(
                item: CSVDocument(name: "gigpilot-shifts", text: CSVExport.shifts(shifts)),
                preview: SharePreview("GigPilot shifts")
            ) {
                shareRowLabel("Export shifts", value: "\(shifts.count) logged")
            }
            .disabled(shifts.isEmpty)

            RowDivider(color: GP.Surface.dividerSoft)

            ShareLink(
                item: CSVDocument(name: "gigpilot-expenses", text: CSVExport.expenses(expenses)),
                preview: SharePreview("GigPilot expenses")
            ) {
                shareRowLabel("Export expenses", value: "\(expenses.count) logged")
            }
            .disabled(expenses.isEmpty)

            RowDivider(color: GP.Surface.dividerSoft)

            SettingsRow(label: "Privacy", value: "") { route = .privacy }
        }
    }

    private func shareRowLabel(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .gpText(GP.Typo.rowLabel)
            Spacer(minLength: 12)
            Text(value)
                .gpText(.system(size: 14.5, weight: .regular), color: GP.Ink.tertiary)
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

            case .idleThreshold:
                StepperEditor(
                    title: "Idle threshold",
                    explanation: "How long you can sit without a ping before the time counts as idle rather than active. Used as the default when you log a shift.",
                    unit: "minutes",
                    value: profile.idleThresholdMinutes,
                    bounds: 1...60
                ) { profile.idleThresholdMinutes = $0; save() }

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

    private func openSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            openURL(url)
        }
    }

    // MARK: Debug

    #if DEBUG
    private var debugSection: some View {
        SettingsGroup(title: "Debug", tint: GP.Palette.amber.opacity(0.8)) {
            SettingsRow(label: "Load demo week", value: "", showsChevron: false) {
                Seed.loadDemoData(context)
            }
            RowDivider(color: GP.Surface.dividerSoft)
            SettingsRow(label: "Toggle Pro",
                        value: entitlement.isPro ? "on" : "off",
                        showsChevron: false) {
                profile?.planTierRaw = entitlement.isPro
                    ? PlanTier.free.rawValue
                    : PlanTier.pro.rawValue
                save()
            }
            RowDivider(color: GP.Surface.dividerSoft)
            SettingsRow(label: "Erase everything", value: "",
                        showsChevron: false, destructive: true) {
                Seed.wipe(context)
            }
        }
    }
    #endif

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            GigPilotLogo(size: 34, glow: false)
                .opacity(0.55)
            Text("GigPilot \(appVersion) · Built for drivers")
                .gpText(GP.Typo.footnote, color: GP.Ink.faint)
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
                    .gpText(GP.Typo.rowLabel,
                            color: destructive ? Color(hex: 0xFB7185) : GP.Ink.primary)

                Spacer(minLength: 12)

                HStack(spacing: 9) {
                    if !value.isEmpty {
                        Text(value)
                            .gpText(.system(size: 14.5, weight: .regular), color: GP.Ink.tertiary)
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
    var tint: Color = GP.Ink.muted
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .gpText(GP.Typo.groupLabel, tracking: GP.Typo.groupLabelTracking, color: tint)
                .padding(.leading, 6)

            GlassCard(radius: GP.Radius.tile,
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
