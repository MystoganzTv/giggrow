//
//  ServiceEditorView.swift
//  GigGrow
//
//  Add, edit, complete or remove a service item.
//
//  "Mark done" is the point of the whole screen. Without it the schedule was
//  a list of accusations a driver could never answer: you change the oil, the
//  row still says overdue, and eventually you stop reading it.
//

import SwiftUI
import SwiftData

struct ServiceEditorView: View {

    /// The number pad has no return key; see KeyboardDoneBar.
    @FocusState private var isEditingField: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Existing item, or nil to add one.
    var editing: ServiceRecord?
    /// Vehicle the new item attaches to.
    var vehicle: VehicleRecord?
    /// Live odometer, used for both the due maths and marking done.
    let currentMileage: Int

    private enum Basis: String, CaseIterable, Identifiable {
        case mileage = "Mileage"
        case date = "Date"
        var id: String { rawValue }
    }

    @State private var name = ""
    @State private var basis: Basis = .mileage
    @State private var intervalMilesText = ""
    @State private var intervalMonthsText = ""
    @State private var dueOn = Date.now
    @State private var loaded = false

    var body: some View {
        EditorScaffold(
            title: editing == nil ? "Add service item" : "Service item",
            canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { dismiss() },
            onSave: save
        ) {
            GlassCard {
                field("Item", text: $name, placeholder: "Oil change")
            }

            basisPicker

            GlassCard {
                if basis == .mileage {
                    VStack(alignment: .leading, spacing: 12) {
                        numberField("Every", text: $intervalMilesText, suffix: "miles")
                        Text(duePreview)
                            .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("Next due", selection: $dueOn, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(GG.Palette.violet400)
                        RowDivider()
                        numberField("Repeats every", text: $intervalMonthsText, suffix: "months")
                        Text("Leave the repeat at zero for a one-off.")
                            .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                    }
                }
            }

            if let record = editing { markDoneCard(record) }
            if editing != nil { deleteButton }
        }
        .onAppear(perform: loadIfNeeded)
        .keyboardDoneBar($isEditingField)
    }

    // MARK: Basis

    private var basisPicker: some View {
        HStack(spacing: 7) {
            ForEach(Basis.allCases) { option in
                let isSelected = option == basis
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { basis = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : GG.Ink.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            isSelected ? AnyShapeStyle(GG.Gradients.segment)
                                       : AnyShapeStyle(Color.clear),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Mark done

    private func markDoneCard(_ record: ServiceRecord) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if let mileage = record.lastDoneAtMileage {
                    Text("Last done at \(Num.grouped(mileage)) mi")
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                }

                Button {
                    record.markDone(currentMileage: currentMileage)
                    try? context.save()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        CheckGlyph()
                            .stroke(Color.white,
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .frame(width: 14, height: 14)
                        Text("Mark done today")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(GG.Gradients.brandMark, in: Capsule())
                }
                .buttonStyle(.plain)

                Text(record.isRecurring
                     ? "Records it at \(Num.grouped(currentMileage)) mi and schedules the next one from today — not from when it was due, so being late doesn't shorten the next interval."
                     : "Records it at \(Num.grouped(currentMileage)) mi. Set an interval above if it should come round again.")
                    .ggText(GG.Typo.footnote, color: GG.Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Fields

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

    private func numberField(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label)
                .ggText(GG.Typo.rowLabel)
            Spacer(minLength: 12)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .focused($isEditingField)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 90)
            Text(suffix)
                .ggText(GG.Typo.footnote, color: GG.Ink.muted)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if let record = editing {
                context.delete(record)
                try? context.save()
            }
            dismiss()
        } label: {
            Text("Remove item")
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

    private var duePreview: String {
        let interval = Int(intervalMilesText.filter(\.isNumber)) ?? 0
        guard interval > 0 else { return "Set an interval and the next due reading is worked out for you." }
        if let record = editing, record.dueAtMileage > 0 {
            let remaining = record.dueAtMileage - currentMileage
            return remaining >= 0
                ? "Next due at \(Num.grouped(record.dueAtMileage)) mi — \(Num.grouped(remaining)) to go."
                : "Overdue by \(Num.grouped(-remaining)) mi."
        }
        return "First one due at \(Num.grouped(currentMileage + interval)) mi."
    }

    // MARK: Load & save

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let record = editing else { return }
        name = record.name
        basis = record.dueAtMileage > 0 ? .mileage : .date
        intervalMilesText = record.intervalMiles > 0 ? "\(record.intervalMiles)" : ""
        intervalMonthsText = record.intervalMonths > 0 ? "\(record.intervalMonths)" : ""
        dueOn = record.dueOn ?? .now
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let miles = Int(intervalMilesText.filter(\.isNumber)) ?? 0
        let months = Int(intervalMonthsText.filter(\.isNumber)) ?? 0

        let record = editing ?? ServiceRecord(name: trimmed)
        if editing == nil {
            context.insert(record)
            record.vehicle = vehicle
        }

        record.name = trimmed

        if basis == .mileage {
            record.intervalMiles = miles
            record.intervalMonths = 0
            record.dueOn = nil
            if record.dueAtMileage == 0 {
                record.dueAtMileage = currentMileage + Swift.max(miles, 1)
            }
        } else {
            record.intervalMiles = 0
            record.intervalMonths = months
            record.dueAtMileage = 0
            record.dueOn = dueOn
        }

        try? context.save()
        dismiss()
    }
}

#Preview("Service item") {
    ServiceEditorView(currentMileage: 84_210)
        .modelContainer(.preview)
}
