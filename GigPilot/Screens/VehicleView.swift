//
//  VehicleView.swift
//  GigPilot
//
//  Screen 04 — the car, the fund that keeps it running, and what's due.
//

import SwiftUI

struct VehicleView: View {
    let snapshot: EarningsSnapshot

    @State private var isUpgrading = false

    private var vehicle: Vehicle { snapshot.vehicle }
    private var entitlement: Entitlement { snapshot.entitlement }

    /// Onboarding lets the vehicle step be skipped, so this can be false.
    private var hasVehicle: Bool { vehicle.odometer > 0 || vehicle.name != "No vehicle" }

    var body: some View {
        ScreenScaffold {
            GP.Gradients.vehicleWash()
        } content: {
            Text("Vehicle")
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)

            if hasVehicle {
                vehicleCard
            } else {
                EmptyStateCard(
                    title: "No vehicle yet",
                    message: "Add your car and GigPilot tracks what it costs per mile and when it's next due for service."
                )
            }

            // The reserve is the differentiator, so free users see the figure
            // they would have banked rather than an empty locked box.
            ProLock(isLocked: !entitlement.allows(.maintenanceReserve)) {
                isUpgrading = true
            } content: {
                maintenanceFundCard
            }

            if !snapshot.service.isEmpty {
                serviceCard
            }

            if hasVehicle {
                ProLock(isLocked: !entitlement.allows(.costPerMile)) {
                    isUpgrading = true
                } content: {
                    efficiencyTiles
                }
            }
        }
        .sheet(isPresented: $isUpgrading) {
            UpgradeView(previewReserve: snapshot.maintenanceFund)
        }
    }

    // MARK: Vehicle header

    private var vehicleCard: some View {
        HeroCard(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22),
                 gradient: GP.Gradients.heroVehicle) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vehicle.name)
                            .gpText(GP.Typo.headline, tracking: GP.Typo.headlineTracking)
                        Text(vehicle.detail)
                            .gpText(.system(size: 13.5, weight: .medium), color: GP.Ink.secondary)
                    }

                    Spacer(minLength: 12)

                    VehicleGlyph()
                        .stroke(Color.white.opacity(0.75),
                                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 26, height: 26)
                }

                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Odometer", color: Color.white.opacity(0.5))
                        Text(Num.grouped(vehicle.odometer))
                            .gpText(GP.Typo.metricSmall, tracking: GP.Typo.metricSmallTracking)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "This week", color: Color.white.opacity(0.5))
                        Text("\(Num.grouped(vehicle.milesThisWeek)) mi")
                            .gpText(GP.Typo.metricSmall, tracking: GP.Typo.metricSmallTracking)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Maintenance fund

    private var maintenanceFundCard: some View {
        GlassCard(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Maintenance fund")
                        .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)
                    if !entitlement.allows(.maintenanceReserve) {
                        ProBadge()
                    }
                    Spacer()
                    Text("Goal \(Money.whole(snapshot.maintenanceGoal))")
                        .gpText(GP.Typo.captionMuted, color: GP.Ink.tertiary)
                }

                Text(Money.whole(snapshot.maintenanceFund))
                    .gpText(GP.Typo.bigAmount, tracking: GP.Typo.bigAmountTracking)

                ProgressBar(progress: snapshot.maintenanceProgress,
                            height: 10,
                            fill: GP.Gradients.maintenance)

                Text("\(Money.whole(snapshot.maintenanceThisWeek)) added this week · \(Int((snapshot.maintenanceProgress * 100).rounded()))% of goal")
                    .gpText(.system(size: 13.5, weight: .medium), color: GP.Ink.eyebrow)
            }
        }
    }

    // MARK: Service schedule

    private var serviceCard: some View {
        GlassCard(padding: EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20)) {
            VStack(spacing: 0) {
                ForEach(Array(snapshot.service.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .gpText(GP.Typo.rowLabel)
                            Text(item.due)
                                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                        }

                        Spacer(minLength: 12)

                        Pill(text: item.status.label,
                             foreground: item.status.tint,
                             background: item.status.background)
                    }
                    .padding(.vertical, 16)

                    if index < snapshot.service.count - 1 {
                        RowDivider()
                    }
                }
            }
        }
    }

    // MARK: Efficiency

    private var efficiencyTiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Fuel cost / mi",
                value: String(format: "$%.2f", vehicle.fuelCostPerMile),
                valueFont: GP.Typo.metricSmall,
                valueTracking: GP.Typo.metricSmallTracking
            )
        } right: {
            StatTile(
                eyebrow: "Avg efficiency",
                value: "\(vehicle.averageMPG) mpg",
                valueFont: GP.Typo.metricSmall,
                valueTracking: GP.Typo.metricSmallTracking
            )
        }
    }
}

#Preview("Vehicle") {
    VehicleView(snapshot: .mock)
        .preferredColorScheme(.dark)
}
