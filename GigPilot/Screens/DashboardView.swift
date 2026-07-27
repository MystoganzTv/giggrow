//
//  DashboardView.swift
//  GigPilot
//
//  Screen 01 — the week at a glance.
//

import SwiftUI

struct DashboardView: View {
    let snapshot: EarningsSnapshot
    /// The dashboard was hard-wired to the current week. Nothing about "at a
    /// glance" requires that it can only ever be *this* glance.
    @Binding var selection: RangeSelection
    var onLogShift: () -> Void = {}
    var onShowHistory: () -> Void = {}
    var onShowProfile: () -> Void = {}
    var onImport: () -> Void = {}

    var body: some View {
        ScreenScaffold {
            GP.Gradients.dashboardWash()
        } content: {
            RangeBar(selection: $selection)
            header

            if snapshot.hasData {
                heroCard
                setAsideTiles
                earningsByApp
                rateTiles
                hoursCard
                trendTiles
            } else {
                emptyState
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
            // The screenshot is the fast path, so it gets the primary button.
            // Typing eight figures in is the fallback, not the headline.
            // "No shifts yet this week" is true and useless when you have
            // just imported June and it's July: it reads as the import having
            // failed. Say which it is.
            if snapshot.hasEverLoggedShift {
                Button(action: onShowHistory) {
                    GlassCard(radius: GP.Radius.tile,
                              padding: EdgeInsets(top: 16, leading: 18,
                                                  bottom: 16, trailing: 18)) {
                        HStack(alignment: .top, spacing: 11) {
                            Circle().fill(GP.Palette.violet400)
                                .frame(width: 6, height: 6).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Nothing this week, but you have earlier shifts")
                                    .gpText(.system(size: 13.5, weight: .semibold))
                                Text("Imported a past week? It saved — this screen only ever shows the current one. Tap to see everything.")
                                    .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Chevron(size: 15, color: Color.white.opacity(0.28))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            EmptyStateCard(
                title: "No shifts yet this week",
                message: "Screenshot your gig app's earnings screen and GigPilot reads the figures off it. Faster than typing, and you're not transcribing numbers by hand.",
                actionTitle: "Import a screenshot",
                action: onImport,
                showsLogo: true
            )

            Button(action: onLogShift) {
                HStack(spacing: 9) {
                    Text("Or enter a shift by hand")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GP.Palette.violet300)
                    Spacer(minLength: 0)
                    Chevron(size: 15, color: GP.Palette.violet300.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(GP.Palette.violet500.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous)
                        .strokeBorder(GP.Palette.violet400.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // The set-asides are the reason to bother, so name them up front
            // rather than showing two tiles reading $0.
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What happens after you log")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                    explainerRow(
                        "\(Int(snapshot.taxRate))% held for taxes",
                        "Nothing owed in April that you haven't already put away."
                    )
                    RowDivider()
                    explainerRow(
                        "\(Int(snapshot.maintenanceRate))% held for the car",
                        "The next repair is paid for before it happens."
                    )
                    RowDivider()
                    explainerRow(
                        "Real hourly rate",
                        "Hours counted once, even with three apps running at the same time."
                    )
                }
            }
        }
    }

    private func explainerRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .gpText(GP.Typo.rowLabel)
            Text(detail)
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    // MARK: Header

    /// Names the driver rather than the period. A dashboard is the one screen
    /// that should feel like it belongs to someone.
    private var greeting: String {
        let hour = Calendar.gigPilot.component(.hour, from: .now)
        let name = snapshot.driver.name.split(separator: " ").first.map(String.init) ?? ""
        let part = hour < 12 ? "Morning" : (hour < 18 ? "Afternoon" : "Evening")
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Was "This week", directly under a RangeBar already saying
            // "This week". The period is the bar's job; the title's job is to
            // say which screen you're on.
            Text(greeting)
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)

            Spacer()

            // The dashboard is where a wrong figure gets noticed, so the way
            // back to the shift that caused it belongs here.
            if snapshot.hasData {
                Button(action: onShowHistory) {
                    HStack(spacing: 5) {
                        Text("History")
                            .font(.system(size: 13.5, weight: .medium))
                        Chevron(size: 13, color: GP.Ink.muted)
                    }
                    .foregroundStyle(GP.Ink.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(GP.Surface.glass, in: Capsule())
                    .overlay(Capsule().strokeBorder(GP.Surface.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shift history")
            }

            // An avatar in the corner reads as a profile button in every app
            // a driver already uses. It should behave like one.
            Button(action: onShowProfile) {
                Monogram(letter: snapshot.driver.initial)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Total earnings".uppercased())
                    .gpText(GP.Typo.heroEyebrow,
                            tracking: GP.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                HStack(alignment: .bottom, spacing: 10) {
                    Text(Money.cents(snapshot.weeklyTotal))
                        .gpText(GP.Typo.heroAmount, tracking: GP.Typo.heroAmountTracking)

                    Pill(text: snapshot.weeklyChange.replacingOccurrences(of: "+", with: ""),
                         foreground: GP.Palette.mint,
                         background: Color(hex: 0x34D399, opacity: 0.16),
                         font: .system(size: 13, weight: .semibold),
                         horizontalPadding: 9,
                         showsTrendArrow: true)
                        .padding(.bottom, 7)
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    HeroAreaChart(
                        points: snapshot.series.cumulative
                            .chartPoints(box: ChartData.weekTrendBox),
                        box: ChartData.weekTrendBox
                    )
                    AxisLabels(labels: ChartData.weekdayNames, color: Color.white.opacity(0.42))
                }
                .padding(.top, 18)
            }
        }
    }

    // MARK: Tax / maintenance

    private var setAsideTiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Taxes to save",
                value: Money.whole(snapshot.taxesToSave),
                footnote: "\(Int(snapshot.taxRate))% set aside",
                footnoteColor: GP.Palette.violet300.opacity(0.85),
                fill: GP.Surface.glassBright
            )
        } right: {
            StatTile(
                eyebrow: "Maintenance",
                value: Money.whole(snapshot.maintenanceThisWeek),
                footnote: "Fund \(Money.whole(snapshot.maintenanceFund))",
                footnoteColor: GP.Palette.blue300.opacity(0.85),
                fill: GP.Surface.glassBright
            )
        }
    }

    // MARK: Earnings by app

    private var earningsByApp: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Earnings by app")
                        .gpText(GP.Typo.cardTitle, tracking: GP.Typo.cardTitleTracking)
                    Spacer()
                    // Not "connected" — nothing is connected to anything.
                    // These are apps the driver logged by hand.
                    Text("\(snapshot.platforms.count) this week")
                        .gpText(GP.Typo.captionMuted, color: Color.white.opacity(0.40))
                }

                ForEach(snapshot.platforms) { platform in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(platform.name)
                                .gpText(GP.Typo.body, color: GP.Ink.body)
                            Spacer()
                            Text(Money.cents(snapshot.amount(for: platform)))
                                .gpText(.system(size: 14.5, weight: .semibold), tracking: -0.15)
                        }
                        ProgressBar(
                            progress: snapshot.normalisedShare(for: platform),
                            height: 6,
                            fill: platform.barGradient
                        )
                    }
                }
            }
        }
    }

    // MARK: Rates

    private var rateTiles: some View {
        TilePair {
            StatTile(eyebrow: "Per hour", value: snapshot.perHourLabel)
        } right: {
            StatTile(
                eyebrow: "Per mile",
                value: snapshot.perMileLabel,
                footnote: snapshot.mileage == 0 ? "Add miles to a shift" : nil,
                footnoteColor: GP.Ink.muted
            )
        }
    }

    // MARK: Hours & mileage

    private var hoursCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Online hours")
                        unitValue(Hours.clock(snapshot.onlineHours), unit: "")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Eyebrow(text: "Mileage")
                        unitValue(Num.grouped(snapshot.mileage), unit: " mi")
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    // The bar only means something when idle time is actually
                    // known. With no split it sits permanently full, which
                    // looks like a measurement of "100% productive".
                    if snapshot.idleHours > 0 {
                        SplitBar(activeShare: snapshot.activeShare)
                    }
                    // Was "Active 4h 22m · Idle 0m". No gig app publishes the
                    // split — Uber gives online time and nothing else — so idle
                    // was zero on every imported shift and the pair read as a
                    // measurement rather than as an empty field. Online time is
                    // the right denominator anyway: waiting for a ping is part
                    // of the job, and dividing by "booked" hours only would
                    // flatter the rate.
                    Text("Time online, waiting included")
                        .gpText(.system(size: 12.5, weight: .regular), color: GP.Ink.muted)
                }
            }
        }
    }

    /// Big figure with a smaller, dimmer unit suffix.
    private func unitValue(_ value: String, unit: String) -> some View {
        (
            Text(value)
                .font(GP.Typo.metricLarge)
                .foregroundColor(.white)
            + Text(unit)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color.white.opacity(0.45))
        )
        .tracking(GP.Typo.metricLargeTracking)
    }

    // MARK: Trends

    private var trendTiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Weekly trend",
                value: snapshot.weeklyChange,
                valueFont: GP.Typo.headline,
                valueTracking: GP.Typo.headlineTracking,
                valueColor: GP.Palette.mint
            ) {
                Sparkline(points: snapshot.series.daily
                            .chartPoints(box: ChartData.sparklineBox),
                          color: GP.Palette.mint.opacity(0.8))
                    .padding(.top, 8)
            }
        } right: {
            StatTile(
                eyebrow: "Monthly trend",
                value: snapshot.monthlyChange,
                valueFont: GP.Typo.headline,
                valueTracking: GP.Typo.headlineTracking,
                valueColor: GP.Palette.blue300
            ) {
                Sparkline(points: snapshot.series.monthly
                            .chartPoints(box: ChartData.sparklineBox),
                          color: GP.Palette.blue300.opacity(0.8))
                    .padding(.top, 8)
            }
        }
    }
}

#Preview("Dashboard") {
    DashboardView(snapshot: .mock, selection: .constant(RangeSelection()))
        .preferredColorScheme(.dark)
}

#Preview("Dashboard — empty") {
    DashboardView(snapshot: .empty, selection: .constant(RangeSelection()))
        .preferredColorScheme(.dark)
}
