//
//  VehicleView.swift
//  GigGrow
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
    @Environment(\.ggUsesWideLayout) private var usesWideLayout
    @Query private var vehicles: [VehicleRecord]
    @Query(sort: \Shift.start) private var shifts: [Shift]

    @State private var isEditingVehicle = false
    @State private var addingService = false
    @State private var editingService: ServiceRecord?

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
        ScreenScaffold(
            maxContentWidth: usesWideLayout
                ? GG.Layout.tabletContentMaxWidth
                : GG.Layout.contentMaxWidth
        ) {
            GG.Gradients.vehicleWash()
        } content: {
            header

            if let vehicle {
                if usesWideLayout {
                    tabletVehicleContent(vehicle)
                } else {
                    phoneVehicleContent(vehicle)
                }
            } else {
                EmptyStateCard(
                    title: "No vehicle yet",
                    message: "Add your car and GigGrow tracks what it costs per mile, what to set aside for repairs, and when it's next due for service.",
                    actionTitle: "Add your vehicle",
                    action: { isEditingVehicle = true }
                )
                .frame(maxWidth: GG.Layout.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
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

    private func phoneVehicleContent(_ vehicle: VehicleRecord) -> some View {
        VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
            vehicleCard(vehicle)
            maintenanceFundCard
            serviceCard
            efficiencyTiles(vehicle)
        }
    }

    /// Car identity and costs are one visual group; the service schedule is
    /// the second. This makes the iPad screen scan like a garage dashboard
    /// instead of a long phone feed with oversized rows.
    private func tabletVehicleContent(_ vehicle: VehicleRecord) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                vehicleCard(vehicle)
                maintenanceFundCard
                efficiencyTiles(vehicle)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            serviceCard
                .frame(minWidth: 330, idealWidth: 390, maxWidth: 430,
                       alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack {
            Text("Vehicle")
                .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)
            Spacer()
            if vehicle != nil {
                Button("Edit") { isEditingVehicle = true }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GG.Palette.violet400)
            }
        }
    }

    // MARK: Vehicle header

    private func vehicleCard(_ vehicle: VehicleRecord) -> some View {
        HeroCard(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22),
                 gradient: GG.Gradients.heroVehicle) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Composed from make/model/year and fuel type, falling
                        // back to the legacy free-text line for older records.
                        Text(vehicle.displayName)
                            .ggText(GG.Typo.headline, tracking: GG.Typo.headlineTracking)
                        if !vehicle.displayDetail.isEmpty {
                            Text(vehicle.displayDetail)
                                .ggText(.system(size: 13.5, weight: .medium), color: GG.Ink.secondary)
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
                            .ggText(GG.Typo.metricSmall, tracking: GG.Typo.metricSmallTracking)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "This week", color: Color.white.opacity(0.5))
                        Text("\(Num.grouped(snapshot.mileage)) mi")
                            .ggText(GG.Typo.metricSmall, tracking: GG.Typo.metricSmallTracking)
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
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                    Spacer()
                    Text("Goal \(Money.whole(snapshot.maintenanceGoal))")
                        .ggText(GG.Typo.captionMuted, color: GG.Ink.tertiary)
                }

                Text(Money.whole(snapshot.maintenanceFund))
                    .ggText(GG.Typo.bigAmount, tracking: GG.Typo.bigAmountTracking)

                ProgressBar(progress: snapshot.maintenanceProgress,
                            height: 10,
                            fill: GG.Gradients.maintenance)

                Text("\(Money.whole(snapshot.maintenanceThisWeek)) added this week · \(Int((snapshot.maintenanceProgress * 100).rounded()))% of goal")
                    .ggText(.system(size: 13.5, weight: .medium), color: GG.Ink.eyebrow)
            }
        }
    }

    // MARK: Service

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("SERVICE")
                    .ggText(GG.Typo.groupLabel,
                            tracking: GG.Typo.groupLabelTracking,
                            color: GG.Ink.muted)
                Spacer()
                Button {
                    addingService = true
                } label: {
                    HStack(spacing: 5) {
                        PlusGlyph()
                            .stroke(GG.Palette.violet400,
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .frame(width: 12, height: 12)
                        Text("Add")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GG.Palette.violet400)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)

            GlassCard(padding: EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20)) {
                if service.isEmpty {
                    Text("Nothing scheduled. Add oil changes, tyres, registration — anything you'd rather not be surprised by.")
                        .ggText(GG.Typo.footnote, color: GG.Ink.muted)
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
                        .ggText(GG.Typo.rowLabel)
                    Text(record.dueDescription(currentMileage: odometer))
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
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
            // Both labels come from the fuel type: an EV is charged, not
            // fuelled, and its efficiency has no gallons in it.
            StatTile(
                eyebrow: vehicle.fuelType.costPerMileTitle,
                value: vehicle.fuelCostPerMile > 0
                    ? String(format: "$%.2f", vehicle.fuelCostPerMile) : "—",
                valueFont: GG.Typo.metricSmall,
                valueTracking: GG.Typo.metricSmallTracking
            )
        } right: {
            StatTile(
                eyebrow: vehicle.fuelType.efficiencyTitle,
                value: vehicle.efficiencyLabel,
                valueFont: GG.Typo.metricSmall,
                valueTracking: GG.Typo.metricSmallTracking
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
