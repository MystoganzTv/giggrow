//
//  LogExpenseView.swift
//  GigPilot
//
//  Add or edit one expense.
//
//  The sheet tells the driver where the money comes from: maintenance is paid
//  out of the reserve they've been building, everything else out of take-home.
//  That distinction is the whole reason the reserve exists, so it's stated on
//  screen rather than buried in the maths.
//

import SwiftUI
import SwiftData

struct LogExpenseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Editing an existing expense, or nil when creating one.
    var editing: Expense?

    @State private var date = Date.now
    @State private var category: ExpenseCategory = .fuel
    @State private var amountText = ""
    @State private var note = ""
    @State private var isDeductible = true
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                GP.Palette.screen.ignoresSafeArea()
                GP.Gradients.vehicleWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GP.Layout.stackSpacing) {
                        amountCard
                        categoryCard
                        detailsCard
                        sourceNote

                        if editing != nil { deleteButton }
                    }
                    .padding(.horizontal, GP.Layout.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(editing == nil ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GP.Palette.screen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GP.Ink.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? GP.Palette.violet400 : GP.Ink.muted)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Amount

    private var amountCard: some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Amount".uppercased())
                    .gpText(GP.Typo.heroEyebrow,
                            tracking: GP.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .gpText(.system(size: 34, weight: .semibold),
                                color: Color.white.opacity(0.5))
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(GP.Typo.heroAmountSmall)
                        .tracking(GP.Typo.heroAmountSmallTracking)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: Category

    private var categoryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Category")
                    .gpText(GP.Typo.rowTitle, tracking: GP.Typo.rowTitleTracking)

                // Two columns rather than a picker wheel — seven options fit,
                // and tapping once beats scrolling.
                let columns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(ExpenseCategory.allCases) { option in
                        categoryChip(option)
                    }
                }
            }
        }
    }

    private func categoryChip(_ option: ExpenseCategory) -> some View {
        let isSelected = option == category

        return Button {
            withAnimation(.easeOut(duration: 0.14)) { category = option }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(option.drawsFromMaintenanceFund ? GP.Palette.blue400 : GP.Palette.violet400)
                    .frame(width: 7, height: 7)
                    .opacity(isSelected ? 1 : 0.45)

                Text(option.label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? GP.Ink.primary : GP.Ink.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                isSelected ? GP.Surface.glassBright : GP.Surface.glassFaint,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? GP.Palette.violet400.opacity(0.5) : GP.Surface.stroke,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Details

    private var detailsCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(GP.Palette.violet400)
                    .padding(.vertical, 4)

                RowDivider()

                HStack {
                    Text("Note")
                        .gpText(GP.Typo.rowLabel)
                    Spacer(minLength: 12)
                    TextField("optional", text: $note)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 15)

                RowDivider()

                Toggle(isOn: $isDeductible) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tax deductible")
                            .gpText(GP.Typo.rowLabel)
                        Text("Counts against your taxable income")
                            .gpText(GP.Typo.footnote, color: GP.Ink.muted)
                    }
                }
                .tint(GP.Palette.violet500)
                .padding(.vertical, 12)
            }
        }
    }

    /// States plainly which pot this comes out of.
    private var sourceNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(category.drawsFromMaintenanceFund ? GP.Palette.blue400 : GP.Palette.violet400)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(category.drawsFromMaintenanceFund
                 ? "Paid from your maintenance reserve — this is what you've been setting aside for. It won't reduce your take-home."
                 : "Paid out of take-home, so it comes off your net profit for the period.")
                .gpText(GP.Typo.footnote, color: GP.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }

    /// The list uses a context menu to delete, which is easy to miss, so the
    /// edit sheet carries the same action somewhere obvious.
    private var deleteButton: some View {
        Button(role: .destructive) {
            if let expense = editing {
                context.delete(expense)
                try? context.save()
            }
            dismiss()
        } label: {
            Text("Delete expense")
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

    // MARK: Logic

    private var amount: Double { Double(amountText) ?? 0 }
    private var canSave: Bool { amount > 0 }

    private func loadIfNeeded() {
        guard !loaded, let expense = editing else { loaded = true; return }
        loaded = true
        date = expense.date
        category = expense.category
        amountText = String(format: "%.2f", expense.amount)
        note = expense.note ?? ""
        isDeductible = expense.isDeductible
    }

    private func save() {
        guard canSave else { return }

        if let expense = editing {
            expense.date = date
            expense.amount = amount
            expense.category = category
            expense.note = note.isEmpty ? nil : note
            expense.isDeductible = isDeductible
        } else {
            let expense = Expense(
                date: date,
                amount: amount,
                category: category,
                note: note.isEmpty ? nil : note,
                isDeductible: isDeductible
            )
            context.insert(expense)
        }

        try? context.save()
        dismiss()
    }
}

#Preview("Add expense") {
    LogExpenseView()
        .modelContainer(.preview)
}
