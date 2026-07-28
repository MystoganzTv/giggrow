//
//  VehicleEditorView.swift
//  GigGrow
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
    @State private var customMake = ""
    @State private var customModel = ""
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
                  && !make.trimmingCharacters(in: .whitespaces).isEmpty
                  && !resolvedMake.isEmpty
                  && !resolvedModel.isEmpty,
            onCancel: { dismiss() },
            onSave: save
        ) {
            GlassCard {
                VStack(spacing: 0) {
                    vehicleWheels

                    if make == VehicleCatalog.other {
                        RowDivider()
                        field("Other make", text: $customMake, placeholder: "Vehicle make")
                    }
                    if model == VehicleCatalog.other {
                        RowDivider()
                        field("Other model", text: $customModel, placeholder: "Vehicle model")
                    }

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
                                suffix: "/ mile", decimal: true, prefix: "$")
                    RowDivider()
                    numberField(fuelType.efficiencyTitle, text: $efficiencyText,
                                suffix: fuelType.efficiencyUnit,
                                decimal: !fuelType.burnsFuel,
                                placeholder: fuelType.efficiencyPlaceholder)

                    if let warning = efficiencyWarning {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(GG.Palette.amber)
                                .frame(width: 6, height: 6).padding(.top, 6)
                            Text(warning)
                                .ggText(GG.Typo.footnote, color: GG.Palette.amber.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 14)
                    }
                }
            }

            Text(editing == nil
                 ? "Adding a vehicle sets up a service schedule from this odometer, and starts the maintenance reserve tracking against it."
                 : "The odometer counts forward from here as you log miles, so only change it if you're correcting a reading.")
                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            if editing != nil { deleteButton }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: make) { oldValue, newValue in
            handleMakeChange(oldValue, newValue)
        }
        .onChange(of: customMake) { _, newValue in
            guard make == VehicleCatalog.other,
                  let inferred = FuelType.unambiguousType(make: newValue) else { return }
            fuelType = inferred
        }
    }

    // MARK: Fields

    private var resolvedMake: String {
        (make == VehicleCatalog.other ? customMake : make)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedModel: String {
        (model == VehicleCatalog.other ? customModel : model)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var modelOptions: [String] {
        guard !make.isEmpty, make != VehicleCatalog.other else {
            return ["", VehicleCatalog.other]
        }
        return [""] + VehicleCatalog.models(for: make) + [VehicleCatalog.other]
    }

    private var vehicleWheels: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Text("Make")
                    .frame(maxWidth: .infinity)
                Text("Model")
                    .frame(maxWidth: .infinity)
            }
            .ggText(GG.Typo.captionMuted, color: GG.Ink.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GG.Palette.violet500.opacity(0.15))
                    .frame(height: 42)

                HStack(spacing: 6) {
                    Picker("Make", selection: $make) {
                        Text("Choose make").tag("")
                        ForEach(VehicleCatalog.makeNames, id: \.self) {
                            Text($0).tag($0)
                        }
                        Text(VehicleCatalog.other).tag(VehicleCatalog.other)
                    }
                    .accessibilityLabel("Vehicle make")

                    Picker("Model", selection: $model) {
                        Text(make.isEmpty ? "Choose make first" : "Choose model").tag("")
                        ForEach(modelOptions.filter { !$0.isEmpty }, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .disabled(make.isEmpty)
                    .accessibilityLabel("Vehicle model")
                }
                .pickerStyle(.wheel)
                .frame(height: 156)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    private func handleMakeChange(_ oldValue: String, _ newValue: String) {
        guard loaded, oldValue != newValue else { return }

        let currentModel = resolvedModel
        let modelStillBelongsToMake = newValue != VehicleCatalog.other
            && VehicleCatalog.canonicalModel(
                matching: currentModel,
                for: newValue
            ) != nil
        let preservingStoredCustomModel = oldValue.isEmpty
            && model == VehicleCatalog.other
            && !customModel.isEmpty

        if !modelStillBelongsToMake && !preservingStoredCustomModel {
            model = ""
            customModel = ""
        }

        let selectedMake = newValue == VehicleCatalog.other ? customMake : newValue
        if let inferred = FuelType.unambiguousType(make: selectedMake) {
            fuelType = inferred
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .ggText(GG.Typo.rowLabel)
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
                    .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

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
                                .foregroundStyle(option == fuelType ? GG.Ink.primary : GG.Ink.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(option == fuelType ? GG.Surface.glassBright
                                                              : GG.Surface.glassFaint,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(option == fuelType
                                                      ? GG.Palette.violet400.opacity(0.5)
                                                      : GG.Surface.stroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(fuelType.burnsFuel
                     ? "Enter what fuel costs to drive one mile and the car's average miles per gallon."
                     : "Enter what electricity costs to drive one mile and how many miles the car travels per kWh.")
                    .ggText(GG.Typo.footnote, color: GG.Ink.muted)
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
            : "\(value) miles/kWh looks off for an EV — most sit between 2 and 5."
    }

    private func numberField(_ label: String, text: Binding<String>, suffix: String,
                             decimal: Bool, prefix: String = "",
                             placeholder: String = "0") -> some View {
        HStack {
            Text(label)
                .ggText(GG.Typo.rowLabel)
            Spacer(minLength: 12)
            if !prefix.isEmpty {
                Text(prefix)
                    .ggText(.system(size: 15, weight: .medium), color: GG.Ink.muted)
            }
            TextField(placeholder, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 90)
            Text(suffix)
                .ggText(GG.Typo.footnote, color: GG.Ink.muted)
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
                            in: RoundedRectangle(cornerRadius: GG.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: Load & save

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let vehicle = editing else { return }

        let storedMake = vehicle.make.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedModel = vehicle.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if let canonicalMake = VehicleCatalog.canonicalMake(matching: storedMake) {
            make = canonicalMake
            if let canonicalModel = VehicleCatalog.canonicalModel(
                matching: storedModel,
                for: canonicalMake
            ) {
                model = canonicalModel
            } else if !storedModel.isEmpty {
                model = VehicleCatalog.other
                customModel = storedModel
            }
        } else if !storedMake.isEmpty {
            make = VehicleCatalog.other
            customMake = storedMake
            if !storedModel.isEmpty {
                model = VehicleCatalog.other
                customModel = storedModel
            }
        }
        yearText = vehicle.year > 0 ? "\(vehicle.year)" : ""
        plate = vehicle.plate
        fuelType = vehicle.fuelType

        // Records created before the fields were split carry everything in
        // one line; drop it into Model so nothing is lost on first edit.
        if make.isEmpty && model.isEmpty && !vehicle.name.isEmpty {
            model = VehicleCatalog.other
            customModel = vehicle.name
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

        vehicle.make = resolvedMake
        vehicle.model = resolvedModel
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
            for record in Seed.defaultService(baseOdometer: odometer,
                                              fuelType: fuelType) {
                context.insert(record)
                record.vehicle = vehicle
            }
        }
        Seed.removeInapplicableService(for: vehicle, in: context)

        try? context.save()
        dismiss()
    }
}

#Preview("Add vehicle") {
    VehicleEditorView()
        .modelContainer(.previewEmpty)
}
