//
//  VehicleView.swift
//  GigPilot
//
//  Screen 04 — the car, the fund that keeps it running, and what's due.
//
//  Service rows are queried from the store rather than taken off the
//  snapshot. Coming through the snapshot they were display-only values with
//  no route back to the record — the same shape that left every Settings
//  chevron dead.
//

import SwiftUI
import SwiftData

struct VehicleView: View {
    let snapshot: EarningsSnapshot

    @Environment(\.modelContext) private var context
    @Query private var vehicles: [VehicleRecord]
    @Query(sort: \Shift.start) private var shifts: [Shift]

    @State private var isUpgrading = false
    @State private var isEditingVehicle = false
    @State private var addingService = false
    @State private var editingService: ServiceRecord?

    private var entitlement: Entitlement { snapshot.entitlement }
    private var vehicle: VehicleRecord? { vehicles.first }

    /// Baseline plus everything driven since it was recorded. Same rule the
    /// projection uses, so the two can't disagree.
    private var odometer: Int {
        guard let vehicle else { return 0 }
        let since = shifts
            .filter { $0.start >= vehicle.odometerAsOf }
            .reduce(0.0) { $0 + $1.miles }
        return vehicle.odometerBaseline + Int(since.rounded())
    }

    private var service: [ServiceRecord] {
        (vehicle?.service ?? []).sorted {
            $0.status(currentMileage: odometer).urgency
                < $1.status(currentMileage: odometer).urgency
        }
    }

    var body: some View {
        ScreenScaffold {
            GP.Gradients.vehicleWash()
        } content: {
            header

            if let vehicle {
                vehicleCard(vehicle)

                ProLock(isLocked: !entitlement.allows(.maintenanceReserve)) {
                    isUpgrading = true
                } content: {
                    maintenanceFundCard
                }

                serviceCard

                ProLock(isLocked: !entitlement.allows(.costPerMile)) {
                    isUpgrading = true
                } content: {
                    efficiencyTiles(vehicle)
                }
            } else {
                EmptyStateCard(
                    title: "No vehicle yet",
                    message: "Add your car and GigPilot tracks what it costs per mile, what to set aside for repairs, and when it's next due for service.",
                    actionTitle: "Add your vehicle",
                    action: { isEditingVehicle = true }
                )
            }
        }
        .sheet(isPresented: $isUpgrading) {
            UpgradeView(previewReserve: snapshot.maintenanceFund)
        }
        .sheet(isPresented: $isEditingVehicle) {
            VehicleEditorView(editing: vehicle)
        }
        .sheet(isPresented: $addingService) {
            ServiceEditorView(vehicle: vehicle, currentMileage: odometer)
        }
        .sheet(item: $editingService) { record in
            ServiceEditorView(editing: record, vehicle: vehicle, currentMileage: odometer)
        }
    }

    private var header: some View {
        HStack {
            Text("Vehicle")
                .gpText(GP.Typo.screenTitle, tracking: GP.Typo.screenTitleTracking)
            Spacer()
            if vehicle != nil {
                Button("Edit") { isEditingVehicle = true }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GP.Palette.violet400)
            }
        }
    }

    // MARK: Vehicle header

    private func vehicleCard(_ vehicle: VehicleRecord) -> some View {
        HeroCard(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22),
                 gradient: GP.Gradients.heroVehicle) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vehicle.name)
                            .gpText(GP.Typo.headline, tracking: GP.Typo.headlineTracking)
                        if !vehicle.detail.isEmpty {
                            Text(vehicle.detail)
                                .gpText(.system(size: 13.5, weight: .medium), color: GP.Ink.secondary)
                        }
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
                        Text(Num.grouped(odometer))
                            .gpText(GP.Typo.metricSmall, tracking: GP.Typo.metricSmallTracking)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "This week", color: Color.white.opacity(0.5))
                        Text("\(Num.grouped(snapshot.mileage)) mi")
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
                    if !entitlement.allows(.maintenanceReserve) { ProBadge() }
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

    // MARK: Service

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("SERVICE")
                    .gpText(GP.Typo.groupLabel,
                            tracking: GP.Typo.groupLabelTracking,
                            color: GP.Ink.muted)
                Spacer()
                Button {
                    addingService = true
                } label: {
                    HStack(spacing: 5) {
                        PlusGlyph()
                            .stroke(GP.Palette.violet400,
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .frame(width: 12, height: 12)
                        Text("Add")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GP.Palette.violet400)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)

            GlassCard(padding: EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20)) {
                if service.isEmpty {
                    Text("Nothing scheduled. Add oil changes, tyres, registration — anything you'd rather not be surprised by.")
                        .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(service.enumerated()), id: \.element.id) { index, record in
                            serviceRow(record)
                            if index < service.count - 1 { RowDivider() }
                        }
                    }
                }
            }
        }
    }

    private func serviceRow(_ record: ServiceRecord) -> some View {
        let status = record.status(currentMileage: odometer)

        return Button {
            editingService = record
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.name)
                        .gpText(GP.Typo.rowLabel)
                    Text(record.dueDescription(currentMileage: odometer))
                        .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                }

                Spacer(minLength: 12)

                Pill(text: status.label,
                     foreground: status.tint,
                     background: status.background)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Mark done today") {
                record.markDone(currentMileage: odometer)
                try? context.save()
            }
            Button("Edit") { editingService = record }
            Button("Delete", role: .destructive) {
                context.delete(record)
                try? context.save()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.name), \(status.label), \(record.dueDescription(currentMileage: odometer))")
    }

    // MARK: Efficiency

    private func efficiencyTiles(_ vehicle: VehicleRecord) -> some View {
        TilePair {
            StatTile(
                eyebrow: "Fuel cost / mi",
                value: vehicle.fuelCostPerMile > 0
                    ? String(format: "$%.2f", vehicle.fuelCostPerMile) : "—",
                valueFont: GP.Typo.metricSmall,
                valueTracking: GP.Typo.metricSmallTracking
            )
        } right: {
            StatTile(
                eyebrow: "Avg efficiency",
                value: vehicle.averageMPG > 0 ? "\(vehicle.averageMPG) mpg" : "—",
                valueFont: GP.Typo.metricSmall,
                valueTracking: GP.Typo.metricSmallTracking
            )
        }
    }
}

/// Most urgent first in the vehicle list.
extension ServiceStatus {
    var urgency: Int {
        switch self {
        case .dueNow:    return 0
        case .scheduled: return 1
        case .healthy:   return 2
        }
    }
}

#Preview("Vehicle") {
    VehicleView(snapshot: .mock)
        .modelContainer(.preview)
}

#Preview("Vehicle — no car") {
    VehicleView(snapshot: .empty)
        .modelContainer(.previewEmpty)
}
