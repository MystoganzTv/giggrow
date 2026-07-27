//
//  LogExpenseView.swift
//  GigGrow
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
import PhotosUI

struct LogExpenseView: View {

    /// The number pad has no return key; see KeyboardDoneBar.
    @FocusState private var isEditingField: Bool
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

    // Receipt scanning. Same on-device Vision pass as the earnings importer:
    // the photo never leaves the phone, and nothing is filled in without the
    // driver seeing it first.
    @State private var pickerItem: PhotosPickerItem?
    @State private var receiptImage: UIImage?
    @State private var receipt: ParsedReceipt?
    @State private var isReading = false
    @State private var readError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                GG.Palette.screen.ignoresSafeArea()
                GG.Gradients.vehicleWash().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                        if editing == nil { receiptCard }
                        amountCard
                        categoryCard
                        detailsCard
                        deductionNote
                        sourceNote

                        if editing != nil { deleteButton }
                    }
                    .padding(.horizontal, GG.Layout.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(editing == nil ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GG.Palette.screen, for: .navigationBar)
            .keyboardDoneBar($isEditingField)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await read(item) }
            }
            .overlay {
                if isReading {
                    ZStack {
                        GG.Palette.screen.opacity(0.75).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().tint(GG.Palette.violet400)
                            Text("Reading the receipt…")
                                .ggText(GG.Typo.captionMuted, color: GG.Ink.secondary)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GG.Ink.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? GG.Palette.violet400 : GG.Ink.muted)
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
                    .ggText(GG.Typo.heroEyebrow,
                            tracking: GG.Typo.heroEyebrowTracking,
                            color: Color.white.opacity(0.55))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .ggText(.system(size: 34, weight: .semibold),
                                color: Color.white.opacity(0.5))
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isEditingField)
                        .font(GG.Typo.heroAmountSmall)
                        .tracking(GG.Typo.heroAmountSmallTracking)
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
                    .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

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
                    .fill(option.drawsFromMaintenanceFund ? GG.Palette.blue400 : GG.Palette.violet400)
                    .frame(width: 7, height: 7)
                    .opacity(isSelected ? 1 : 0.45)

                Text(option.label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? GG.Ink.primary : GG.Ink.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                isSelected ? GG.Surface.glassBright : GG.Surface.glassFaint,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? GG.Palette.violet400.opacity(0.5) : GG.Surface.stroke,
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
                    .tint(GG.Palette.violet400)
                    .padding(.vertical, 4)

                RowDivider()

                HStack {
                    Text("Note")
                        .ggText(GG.Typo.rowLabel)
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
                            .ggText(GG.Typo.rowLabel)
                        Text("Counts against your taxable income")
                            .ggText(GG.Typo.footnote, color: GG.Ink.muted)
                    }
                }
                .tint(GG.Palette.violet500)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: Receipt

    /// Photograph the till receipt instead of typing it.
    ///
    /// Not a shortcut so much as the thing that makes logging happen at all:
    /// a receipt entered at the pump takes ten seconds, and one entered from
    /// a glovebox full of paper in April never gets entered.
    private var receiptCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if let receiptImage {
                    HStack(spacing: 12) {
                        Image(uiImage: receiptImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(GG.Surface.stroke, lineWidth: 1))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(receipt?.merchant ?? "Receipt")
                                .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                            // Reading a receipt is guesswork, and the figure
                            // ends up in a tax total, so it says so.
                            Text("Check every figure against the paper.")
                                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            receiptImage = nil
                            receipt = nil
                        } label: {
                            Text("Remove")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: 0xFB7185))
                        }
                        .buttonStyle(.plain)
                    }

                    if let alternatives = receipt?.amounts, alternatives.count > 1 {
                        Text("Other amounts on this receipt")
                            .ggText(.system(size: 11.5, weight: .medium), color: GG.Ink.muted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(Array(alternatives.prefix(5).enumerated()),
                                        id: \.offset) { _, candidate in
                                    let text = String(format: "%.2f", candidate.value)
                                    Button { amountText = text } label: {
                                        Text(Money.cents(candidate.value))
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(amountText == text
                                                             ? GG.Palette.violet300
                                                             : GG.Ink.secondary)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(GG.Surface.glassFaint, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .images,
                                 photoLibrary: .shared()) {
                        HStack(spacing: 9) {
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Scan a receipt")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer(minLength: 0)
                            Chevron(size: 14, color: Color.white.opacity(0.3))
                        }
                        .foregroundStyle(GG.Palette.violet300)
                    }

                    Text("Reads the amount, date and shop off the photo, on this phone. Faster than typing, and the paper can go in the bin.")
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let readError {
                    Text(readError)
                        .ggText(GG.Typo.footnote, color: GG.Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        isReading = true
        readError = nil
        defer { isReading = false; pickerItem = nil }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            readError = "That image couldn't be opened."
            return
        }

        do {
            let parsed = ReceiptParser.parse(try TextRecognizer.recognise(in: cgImage))
            receiptImage = image
            receipt = parsed

            // Filled in, never decided. Anything the parser missed is left
            // for the driver rather than guessed at.
            if let total = parsed.total { amountText = String(format: "%.2f", total) }
            if let found = parsed.date { date = found }
            if let suggested = parsed.suggestedCategory { category = suggested }
            if note.isEmpty, let merchant = parsed.merchant { note = merchant }

            if !parsed.foundAnything {
                readError = "Nothing readable on that one — fill it in by hand, or try a straighter photo."
            }
        } catch {
            readError = "That receipt couldn't be read: \(error.localizedDescription)"
        }
    }

    /// Says whether this is actually deductible, where the choice is made.
    ///
    /// The standard mileage rate already pays for petrol, insurance and
    /// repairs. A driver who logs a $60 fill-up and expects it off their tax
    /// bill is going to be disappointed at best and double-claiming at worst,
    /// and the moment to say so is while they're picking the category — not
    /// silently, months later, by omitting it from a total.
    private var deductionNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(category.isCoveredByMileageRate ? GG.Palette.amber : GG.Palette.mint)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.deductionNote)
                    .ggText(GG.Typo.footnote,
                            color: category.isCoveredByMileageRate
                                ? GG.Palette.amber.opacity(0.9) : GG.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if category.isCoveredByMileageRate {
                    Text("Still worth logging — it's what tells you whether the mileage rate is beating your real costs.")
                        .ggText(.system(size: 11.5, weight: .regular), color: GG.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    /// States plainly which pot this comes out of.
    private var sourceNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(category.drawsFromMaintenanceFund ? GG.Palette.blue400 : GG.Palette.violet400)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(category.drawsFromMaintenanceFund
                 ? "Paid from your maintenance reserve — this is what you've been setting aside for. It won't reduce your take-home."
                 : "Paid out of take-home, so it comes off your net profit for the period.")
                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
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
                            in: RoundedRectangle(cornerRadius: GG.Radius.tile, style: .continuous))
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
