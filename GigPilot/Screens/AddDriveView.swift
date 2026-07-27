//
//  AddDriveView.swift
//  GigPilot
//
//  A drive entered by hand.
//
//  This exists for the days tracking was off, the phone was dead, or the
//  drive happened before the app was installed. The IRS wants a
//  contemporaneous log; a driver reconstructing last Tuesday from memory is
//  doing something weaker than that, and the screen says so rather than
//  letting a guess sit in the record looking like a GPS reading.
//

import SwiftUI
import SwiftData

struct AddDriveView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var milesText = ""
    @State private var minutesText = ""
    @State private var purpose: DrivePurpose = .business
    /// One focus state, not two. Two `.focused` modifiers on the same field
    /// fight each other and neither wins reliably.
    @FocusState private var focus: Field?

    private enum Field { case miles, minutes }

    private var miles: Double { Double(milesText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var minutes: Int { Int(minutesText) ?? 0 }
    private var canSave: Bool { miles >= 0.3 }

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.vehicleWash().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: GP.Layout.stackSpacing) {
                        entryCard
                        purposeCard
                        if miles > 0 { valueCard }
                        note
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add a drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    // Neither pad has a return key.
                    Button("Done") { focus = nil }
                        .fontWeight(.semibold)
                        .foregroundStyle(GP.Palette.violet300)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(canSave ? GP.Palette.violet300 : GP.Ink.muted)
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { focus = .miles }
    }

    // MARK: Cards

    private var entryCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                HStack {
                    Text("Miles")
                        .gpText(GP.Typo.rowLabel)
                    Spacer(minLength: 12)
                    TextField("0.0", text: $milesText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .miles)
                        .multilineTextAlignment(.trailing)
                        .gpText(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: 120)
                }
                .padding(.vertical, 14)

                RowDivider(color: GP.Surface.dividerSoft)

                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .tint(GP.Palette.violet300)
                    .gpText(GP.Typo.rowLabel)
                    .padding(.vertical, 8)

                RowDivider(color: GP.Surface.dividerSoft)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Minutes")
                            .gpText(GP.Typo.rowLabel)
                        Text("Optional — only affects how the drive reads back")
                            .gpText(.system(size: 11.5, weight: .regular), color: GP.Ink.muted)
                    }
                    Spacer(minLength: 12)
                    TextField("0", text: $minutesText)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .minutes)
                        .multilineTextAlignment(.trailing)
                        .gpText(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: 80)
                }
                .padding(.vertical, 14)
            }
        }
    }

    private var purposeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("What was it for")
                    .gpText(GP.Typo.cardTitle, tracking: GP.Typo.cardTitleTracking)

                HStack(spacing: 9) {
                    // Unclassified isn't offered. If you're typing a drive in
                    // by hand you already know what it was for.
                    ForEach([DrivePurpose.business, .personal]) { option in
                        chip(option)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chip(_ option: DrivePurpose) -> some View {
        let isSelected = purpose == option
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { purpose = option }
        } label: {
            Text(option.label)
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : GP.Ink.tertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    isSelected
                        ? AnyShapeStyle(GP.Gradients.brandMark)
                        : AnyShapeStyle(GP.Surface.glassFaint),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(
                    isSelected ? Color.clear : GP.Surface.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Shows the money before saving, at the rate for the chosen date — so a
    /// driver who back-dates a drive across 1 July sees the figure change and
    /// understands why.
    private var valueCard: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "Worth")
                    Text(purpose.isDeductible ? Money.cents(miles * MileageRates.rate(on: date)) : "$0.00")
                        .gpText(.system(size: 22, weight: .semibold), tracking: -0.5,
                                color: purpose.isDeductible ? GP.Palette.mint : GP.Ink.tertiary)
                }
                Spacer(minLength: 8)
                Text(purpose.isDeductible
                     ? "at \(MileageRates.formatted(MileageRates.rate(on: date)))/mi"
                     : "Personal miles aren't deductible")
                    .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var note: some View {
        Text("A drive typed in later isn't the contemporaneous record the IRS asks for. Keep whatever backs it up — a delivery receipt, a calendar entry — in case the number is ever questioned.")
            .gpText(GP.Typo.footnote, color: GP.Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }

    // MARK: Save

    private func save() {
        guard canSave else { return }
        let end = date.addingTimeInterval(TimeInterval(max(minutes, 0) * 60))
        let record = DriveRecord(
            start: date,
            end: end,
            distanceMeters: miles * 1_609.344,
            purpose: purpose
        )
        context.insert(record)
        try? context.save()
        dismiss()
    }
}

#Preview("Add a drive") {
    AddDriveView()
        .modelContainer(.preview)
}
