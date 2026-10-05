import SwiftUI
import CoreData

/// Bir kalemin bir aydaki tutarını girer ya da düzenler. Yeni kayıtta taksitlendirme yapılabilir.
struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(RateService.self) private var rates

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder)],
                  predicate: NSPredicate(format: "isArchived == NO"))
    private var items: FetchedResults<LedgerItem>

    private let existing: LedgerEntry?

    @State private var direction: Direction
    @State private var item: LedgerItem?
    @State private var amount: Decimal?
    @State private var month: Month
    @State private var status: EntryStatus
    @State private var note: String
    @State private var splitIntoInstallments: Bool
    @State private var installmentCount: Int
    @State private var isCreatingItem: Bool
    @State private var confirmDelete: Bool

    @FocusState private var amountFocused: Bool

    init(item: LedgerItem?, month: Month) {
        let entry = item?.entry(for: month)
        self.existing = entry
        self.direction = item?.direction ?? .expense
        self.item = item
        self.amount = entry?.amountValue ?? item?.recurringAmountValue
        self.month = month
        self.status = entry?.status ?? .pending
        self.note = entry?.note ?? ""
        self.splitIntoInstallments = false
        self.installmentCount = 3
        self.isCreatingItem = false
        self.confirmDelete = false
    }

    private var isNew: Bool { existing == nil }
    private var currency: Currency { item?.currency ?? .tl }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section {
                        Picker("Yön", selection: $direction) {
                            ForEach(Direction.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    VStack(spacing: 6) {
                        TextField("0", value: $amount, format: .number.locale(Money.locale))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.amount(40))
                            .foregroundStyle(direction == .expense ? Color.gider : Color.gelir)
                            .focused($amountFocused)
                        Text(amountCaption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section {
                    if isNew {
                        Picker("Kalem", selection: $item) {
                            Text("Seçin").tag(LedgerItem?.none)
                            ForEach(items.filter { $0.direction == direction }, id: \.objectID) { item in
                                Text("\(item.fullTitle) · \(item.owner?.displayName ?? "Ortak")")
                                    .tag(Optional(item))
                            }
                        }
                        Button("Yeni kalem oluştur", systemImage: "plus.circle") { isCreatingItem = true }
                    } else if let item {
                        LabeledContent("Kalem", value: item.fullTitle)
                        LabeledContent("Kişi", value: item.owner?.displayName ?? "Ortak")
                    }
                    MonthStepperRow(title: splitIntoInstallments ? "İlk taksit" : "Ay", month: $month)
                        .disabled(!isNew)
                }

                Section {
                    Picker("Durum", selection: $status) {
                        ForEach(EntryStatus.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Not (isteğe bağlı)", text: $note)
                } footer: {
                    if status == .excluded {
                        Text("Hariç kayıtlar silinmez ama o ayın toplamına girmez.")
                    }
                }

                if isNew {
                    Section {
                        Toggle("Taksitlendir", isOn: $splitIntoInstallments.animation())
                        if splitIntoInstallments {
                            Stepper("\(installmentCount) taksit", value: $installmentCount, in: 2...36)
                        }
                    } footer: {
                        if splitIntoInstallments {
                            Text("Tutar \(installmentCount) aya bölünür: \(month.title) – \(month.adding(installmentCount - 1).title). İlk taksit dışındakiler bekliyor olarak eklenir.")
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("Bu ayın kaydını sil", role: .destructive) { confirmDelete = true }
                    } footer: {
                        if item?.isRecurring == true {
                            Text("Düzenli kalemlerde kayıt silinirse tahmini tutar geri gelir. O ayı saymamak için durumu Hariç yapın.")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Yeni kayıt" : month.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(item == nil || amount == nil)
                }
            }
            .onChange(of: direction) { _, newValue in
                if item?.direction != newValue { item = nil }
            }
            .onChange(of: item) { _, newValue in
                if isNew, amount == nil, let recurring = newValue?.recurringAmountValue {
                    amount = recurring
                }
            }
            .sheet(isPresented: $isCreatingItem) {
                ItemEditorView(item: nil, defaultDirection: direction) { created in
                    item = created
                }
            }
            .confirmationDialog("Bu ayın kaydı silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { deleteEntry() }
            }
            .onAppear { if isNew { amountFocused = true } }
        }
    }

    private var amountCaption: String {
        guard let amount, amount > 0 else {
            return currency == .tl ? "Tutarı TL olarak girin" : "Tutarı \(currency.title) olarak girin"
        }
        var parts: [String] = []
        if splitIntoInstallments {
            let parts2 = Ledger.split(amount, into: installmentCount)
            parts.append("\(installmentCount) taksit × \(Money.string(parts2[0], currency: currency))")
        }
        if currency != .tl, let rate = rates.table.rate(for: currency) {
            parts.append("≈ " + Money.string(amount * rate, fractions: false))
        }
        return parts.isEmpty ? Money.string(amount, currency: currency) : parts.joined(separator: " · ")
    }

    private func save() {
        guard let item, let amount else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew && splitIntoInstallments {
            for (index, part) in Ledger.split(amount, into: installmentCount).enumerated() {
                let label = "Taksit \(index + 1)/\(installmentCount)" + (trimmedNote.isEmpty ? "" : " · \(trimmedNote)")
                context.upsertEntry(item: item, month: month.adding(index), amount: part,
                                    status: index == 0 ? status : .pending, note: label, rates: rates.table)
            }
        } else {
            context.upsertEntry(item: item, month: month, amount: amount, status: status,
                                note: trimmedNote, rates: rates.table)
        }
        context.saveIfNeeded()
        dismiss()
    }

    private func deleteEntry() {
        if let existing { context.delete(existing) }
        context.saveIfNeeded()
        dismiss()
    }
}

#Preview {
    EntryEditorView(item: nil, month: .current)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(RateService())
}
