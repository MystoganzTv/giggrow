//
//  VehicleEditorView.swift
//  GigPilot
//
//  Add or edit the car.
//
//  The onboarding vehicle step is skippable, and until now skipping it was
//  permanent: the Vehicle tab and the maintenance reserve — the one thing
//  neither competitor offers — became unreachable for the life of the
//  install. This is the way back.
//

import SwiftUI
import SwiftData

struct VehicleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Existing car, or nil to add one.
    var editing: VehicleRecord?

    @State private var make = ""
    @State private var model = ""
    @State private var yearText = ""
    @State private var plate = ""
    @State private var fuelType: FuelType = .gasoline
    @State private var odometerText = ""
    @State private var fuelCostText = ""
    @State private var efficiencyText = ""
    @State private var loaded = false

    var body: some View {
        EditorScaffold(
            title: editing == nil ? "Add vehicle" : "Vehicle",
            canSave: !model.trimmingCharacters(in: .whitespaces).isEmpty
                  || !make.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { dismiss() },
            onSave: save
        ) {
            GlassCard {
                VStack(spacing: 0) {
                    field("Make", text: $make, placeholder: "Tesla")
                    RowDivider()
                    field("Model", text: $model, placeholder: "Model Y")
                    RowDivider()
                    numberField("Year", text: $yearText, suffix: "", decimal: false)
                    RowDivider()
                    field("Plate", text: $plate, placeholder: "SVERIGE")
                }
            }

            fuelTypeCard

            GlassCard {
                VStack(spacing: 0) {
                    numberField("Odometer", text: $odometerText, suffix: "mi", decimal: false)
                    RowDivider()
                    numberField(fuelType.costPerMileTitle, text: $fuelCostText,
                                suffix: "/ mi", decimal: true, prefix: "$")
                    RowDivider()
                    numberField(fuelType.efficiencyTitle, text: $efficiencyText,
                                suffix: fuelType.efficiencyUnit,
                                decimal: !fuelType.burnsFuel,
                                placeholder: fuelType.efficiencyPlaceholder)

                    if let warning = efficiencyWarning {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(GP.Palette.amber)
                                .frame(width: 6, height: 6).padding(.top, 6)
                            Text(warning)
                                .gpText(GP.Typo.footnote, color: GP.Palette.amber.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 14)
                    }
                }
            }

            Text(editing == nil
                 ? "Adding a vehicle sets up a service schedule from this odometer, and starts the maintenance reserve tracking against it."
                 : "The odometer counts forward from here as you log miles, so only change it if you're correcting a reading.")
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            if editing != nil { deleteButton }
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: Fields

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .gpText(GP.Typo.rowLabel)
            Spacer(minLength: 12)
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 15)
    }

    /// Fuel type changes the arithmetic downstream, so it's a visible choice
    /// rather than a word buried in a free-text subtitle.
    private var fuelTypeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Runs on")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                let columns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(FuelType.allCases) { option in
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) { fuelType = option }
                        } label: {
                            Text(option.label)
                                .font(.system(size: 13.5,
                                              weight: option == fuelType ? .semibold : .medium))
                                .foregroundStyle(option == fuelType ? GP.Ink.primary : GP.Ink.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(option == fuelType ? GP.Surface.glassBright
                                                              : GP.Surface.glassFaint,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(option == fuelType
                                                      ? GP.Palette.violet400.opacity(0.5)
                                                      : GP.Surface.stroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(fuelType.burnsFuel
                     ? "Efficiency in \(fuelType.efficiencyUnit), and the per-mile cost is fuel."
                     : "No mpg on an EV — efficiency is \(fuelType.efficiencyUnit), and the per-mile cost is charging.")
                    .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Catches an mpg typed into an EV, and the reverse.
    private var efficiencyWarning: String? {
        guard let value = Double(efficiencyText), value > 0 else { return nil }
        guard !fuelType.isPlausibleEfficiency(value) else { return nil }
        return fuelType.burnsFuel
            ? "\(Int(value)) mpg looks off for a \(fuelType.label.lowercased()) car."
            : "\(value) mi/kWh looks off for an EV — most sit between 2 and 5."
    }

    private func numberField(_ label: String, text: Binding<String>, suffix: String,
                             decimal: Bool, prefix: String = "",
                             placeholder: String = "0") -> some View {
        HStack {
            Text(label)
                .gpText(GP.Typo.rowLabel)
            Spacer(minLength: 12)
            if !prefix.isEmpty {
                Text(prefix)
                    .gpText(.system(size: 15, weight: .medium), color: GP.Ink.muted)
            }
            TextField(placeholder, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 90)
            Text(suffix)
                .gpText(GP.Typo.footnote, color: GP.Ink.muted)
        }
        .padding(.vertical, 15)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if let vehicle = editing {
                let records = vehicle.service
                vehicle.service = []
                for record in records { context.delete(record) }
                context.delete(vehicle)
                try? context.save()
            }
            dismiss()
        } label: {
            Text("Remove vehicle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFB7185))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color(hex: 0xFB7185, opacity: 0.10),
                            in: RoundedRectangle(cornerRadius: GP.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: Load & save

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let vehicle = editing else { return }

        make = vehicle.make
        model = vehicle.model
        yearText = vehicle.year > 0 ? "\(vehicle.year)" : ""
        plate = vehicle.plate
        fuelType = vehicle.fuelType

        // Records created before the fields were split carry everything in
        // one line; drop it into Model so nothing is lost on first edit.
        if make.isEmpty && model.isEmpty && !vehicle.name.isEmpty {
            model = vehicle.name
        }

        odometerText = "\(vehicle.odometerBaseline)"
        fuelCostText = vehicle.fuelCostPerMile > 0
            ? String(format: "%.2f", vehicle.fuelCostPerMile) : ""
        if vehicle.averageMPG > 0 {
            efficiencyText = vehicle.fuelType.burnsFuel
                ? "\(vehicle.averageMPG)"
                : String(format: "%.1f", vehicle.efficiency)
        }
    }

    private func save() {
        let odometer = Int(odometerText.filter(\.isNumber)) ?? 0
        let vehicle = editing ?? VehicleRecord(odometerBaseline: odometer)
        let isNew = editing == nil
        if isNew { context.insert(vehicle) }

        vehicle.make = make.trimmingCharacters(in: .whitespaces)
        vehicle.model = model.trimmingCharacters(in: .whitespaces)
        vehicle.year = Int(yearText.filter(\.isNumber)) ?? 0
        vehicle.plate = plate.trimmingCharacters(in: .whitespaces).uppercased()
        vehicle.fuelType = fuelType

        // Keep the legacy fields in step so anything still reading them
        // shows the same thing.
        vehicle.name = vehicle.displayName
        vehicle.detail = vehicle.displayDetail

        // Re-baseline: the reading is true as of now, so miles logged before
        // this edit must not be added on top of it again.
        if odometer != vehicle.odometerBaseline || isNew {
            vehicle.odometerBaseline = odometer
            vehicle.odometerAsOf = .now
        }

        vehicle.fuelCostPerMile = Double(fuelCostText) ?? 0
        if let value = Double(efficiencyText), value > 0 {
            if fuelType.burnsFuel {
                vehicle.averageMPG = Int(value.rounded())
            } else {
                vehicle.efficiency = value
            }
        } else {
            vehicle.averageMPG = 0
        }

        if isNew {
            for record in Seed.defaultService(baseOdometer: odometer) {
                context.insert(record)
                record.vehicle = vehicle
            }
        }

        try? context.save()
        dismiss()
    }
}

#Preview("Add vehicle") {
    VehicleEditorView()
        .modelContainer(.previewEmpty)
}
