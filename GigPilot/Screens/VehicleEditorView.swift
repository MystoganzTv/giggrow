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

    @State private var name = ""
    @State private var detail = ""
    @State private var odometerText = ""
    @State private var fuelCostText = ""
    @State private var mpgText = ""
    @State private var loaded = false

    var body: some View {
        EditorScaffold(
            title: editing == nil ? "Add vehicle" : "Vehicle",
            canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { dismiss() },
            onSave: save
        ) {
            GlassCard {
                VStack(spacing: 0) {
                    field("Vehicle", text: $name, placeholder: "2022 Toyota RAV4")
                    RowDivider()
                    field("Details", text: $detail, placeholder: "Hybrid · 7KJD812")
                }
            }

            GlassCard {
                VStack(spacing: 0) {
                    numberField("Odometer", text: $odometerText, suffix: "mi", decimal: false)
                    RowDivider()
                    numberField("Fuel cost", text: $fuelCostText, suffix: "/ mi", decimal: true, prefix: "$")
                    RowDivider()
                    numberField("Average", text: $mpgText, suffix: "mpg", decimal: false)
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

    private func numberField(_ label: String, text: Binding<String>, suffix: String,
                             decimal: Bool, prefix: String = "") -> some View {
        HStack {
            Text(label)
                .gpText(GP.Typo.rowLabel)
            Spacer(minLength: 12)
            if !prefix.isEmpty {
                Text(prefix)
                    .gpText(.system(size: 15, weight: .medium), color: GP.Ink.muted)
            }
            TextField("0", text: text)
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
        name = vehicle.name
        detail = vehicle.detail
        odometerText = "\(vehicle.odometerBaseline)"
        fuelCostText = vehicle.fuelCostPerMile > 0
            ? String(format: "%.2f", vehicle.fuelCostPerMile) : ""
        mpgText = vehicle.averageMPG > 0 ? "\(vehicle.averageMPG)" : ""
    }

    private func save() {
        let odometer = Int(odometerText.filter(\.isNumber)) ?? 0

        if let vehicle = editing {
            vehicle.name = name.trimmingCharacters(in: .whitespaces)
            vehicle.detail = detail.trimmingCharacters(in: .whitespaces)
            // Re-baseline: the reading is true as of now, so miles logged
            // before this edit must not be added on top of it again.
            if odometer != vehicle.odometerBaseline {
                vehicle.odometerBaseline = odometer
                vehicle.odometerAsOf = .now
            }
            vehicle.fuelCostPerMile = Double(fuelCostText) ?? 0
            vehicle.averageMPG = Int(mpgText.filter(\.isNumber)) ?? 0
        } else {
            let vehicle = VehicleRecord(
                name: name.trimmingCharacters(in: .whitespaces),
                detail: detail.trimmingCharacters(in: .whitespaces),
                odometerBaseline: odometer,
                odometerAsOf: .now,
                fuelCostPerMile: Double(fuelCostText) ?? 0,
                averageMPG: Int(mpgText.filter(\.isNumber)) ?? 0
            )
            context.insert(vehicle)

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
