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
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>

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
    /// Yeni kayıtta kalem seçmek yerine tek seferlik bir harcama girilir; kalem arka planda oluşur.
    @State private var isOneOff: Bool
    @State private var oneOffName: String
    @State private var oneOffOwner: Person?
    @State private var confirmDelete: Bool

    init(item: LedgerItem?, month: Month) {
        let entry = item?.entry(for: month)
        self.existing = entry
        self.direction = item?.direction ?? .expense
        self.item = item
        self.amount = entry?.amountValue ?? item?.recurringAmount(in: month)
        self.month = month
        self.status = entry?.status ?? .pending
        self.note = entry?.note ?? ""
        self.splitIntoInstallments = false
        self.installmentCount = 3
        self.isCreatingItem = false
        self.isOneOff = false
        self.oneOffName = ""
        self.oneOffOwner = nil
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
                        AmountField(value: $amount, size: 40, weight: .bold, alignment: .center,
                                    color: UIColor(direction == .expense ? Color.gider : Color.gelir), autofocus: isNew)
                        Text(amountCaption)
                            .font(.footnote)
                            .foregroundStyle(Color.ikincil)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    if let item, !suggestions(for: item).isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions(for: item)) { suggestion in
                                    SuggestionChip(suggestion: suggestion, currency: currency,
                                                   isSelected: amount == suggestion.amount) {
                                        amount = suggestion.amount
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section {
                    if isNew {
                        Picker("Kalem türü", selection: $isOneOff.animation()) {
                            Text("Kayıtlı kalem").tag(false)
                            Text("Tek seferlik").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if isOneOff {
                            TextField("Ne için?", text: $oneOffName, prompt: Text("Ör. Kombi tamiri"))
                            Picker("Kişi", selection: $oneOffOwner) {
                                Text("Ortak").tag(Person?.none)
                                ForEach(people, id: \.objectID) { person in
                                    Text(verbatim: person.displayName).tag(Optional(person))
                                }
                            }
                        } else {
                            Picker("Kalem", selection: $item) {
                                Text("Seçin").tag(LedgerItem?.none)
                                ForEach(items.filter { $0.direction == direction }, id: \.objectID) { item in
                                    Text(verbatim: "\(item.fullTitle) · \(item.ownerName)")
                                        .tag(Optional(item))
                                }
                            }
                            Button("Yeni kalem oluştur", systemImage: "plus.circle") { isCreatingItem = true }
                        }
                    } else if let item {
                        LabeledContent("Kalem", value: item.fullTitle)
                        LabeledContent("Kişi", value: item.ownerName)
                    }
                    MonthStepperRow(title: splitIntoInstallments ? "İlk taksit" : "Ay", month: $month)
                        .disabled(!isNew)
                } footer: {
                    if isNew && isOneOff {
                        Text("Yalnızca bu aya (ya da taksitlerine) yazılır. Kalemler listesinde Arşiv'de durur, yeni aylarda görünmez.")
                    }
                }

                if let payee = item?.payee {
                    Section("Ödeme bilgisi") {
                        PayeeCard(account: payee)
                    }
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

                if let existing {
                    Section {
                        Button("Bu ayın kaydını sil", role: .destructive) { confirmDelete = true }
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            if item?.isRecurring == true {
                                Text("Düzenli kalemlerde kayıt silinirse tahmini tutar geri gelir. O ayı saymamak için durumu Hariç yapın.")
                            }
                            if let changed = existing.updatedAt {
                                let when = changed.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Money.locale))
                                if let who = existing.updatedBy {
                                    Text("Son değişiklik: \(who) · \(when)")
                                } else {
                                    Text("Son değişiklik: \(when)")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "Yeni kayıt") : month.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: direction) { _, newValue in
                if item?.direction != newValue { item = nil }
            }
            .onChange(of: isOneOff) { _, oneOff in
                if oneOff { item = nil }
            }
            .onAppear {
                // Bu yönde hiç kalem yoksa doğrudan tek seferlik girişle başlar.
                if isNew, item == nil, !items.contains(where: { $0.direction == direction }) { isOneOff = true }
            }
            .onChange(of: item) { _, newValue in
                if isNew, amount == nil, let recurring = newValue?.recurringAmount(in: month) {
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
        }
    }

    private func suggestions(for item: LedgerItem) -> [AmountSuggestion] {
        Ledger.suggestions(for: item, before: month)
    }

    private var amountCaption: String {
        guard let amount, amount > 0 else {
            return String(localized: "Tutarı \(currency.title) olarak girin")
        }
        var parts: [String] = []
        if splitIntoInstallments {
            let parts2 = Ledger.split(amount, into: installmentCount)
            let part = Money.string(parts2[0], currency: currency)
            parts.append(String(localized: "\(installmentCount) taksit × \(part)"))
        }
        if currency != rates.table.base, let rate = rates.table.rate(for: currency) {
            parts.append("≈ " + Money.string(amount * rate, fractions: false))
        }
        return parts.isEmpty ? Money.string(amount, currency: currency) : parts.joined(separator: " · ")
    }

    private var canSave: Bool {
        guard let amount, amount > 0 else { return false }
        if isNew && isOneOff { return !oneOffName.trimmingCharacters(in: .whitespaces).isEmpty }
        return item != nil
    }

    /// Tek seferlik harcama için kalem: tekrarlamaz ve arşivlenmiş olarak oluşur, kaydı o ayda görünür.
    private func makeOneOffItem() -> LedgerItem {
        let created = LedgerItem(context: context)
        created.uuid = UUID()
        created.createdAt = .now
        created.updatedAt = .now
        created.updatedBy = DeviceOwner.name(in: context)
        created.sortOrder = context.nextItemSortOrder()
        let household = context.currentHousehold()
        context.place(created, in: household)
        created.household = household
        created.name = oneOffName.trimmingCharacters(in: .whitespaces)
        created.kind = direction == .receivable ? .receivable : .other
        created.direction = direction
        created.currency = .tl
        created.owner = oneOffOwner
        created.isArchived = true
        return created
    }

    private func save() {
        let item = isNew && isOneOff ? (canSave ? makeOneOffItem() : nil) : self.item
        guard let item, let amount else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew && splitIntoInstallments {
            for (index, part) in Ledger.split(amount, into: installmentCount).enumerated() {
                let label = String(localized: "Taksit \(index + 1)/\(installmentCount)") + (trimmedNote.isEmpty ? "" : " · \(trimmedNote)")
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

private struct SuggestionChip: View {
    let suggestion: AmountSuggestion
    let currency: Currency
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                Text(Money.string(suggestion.amount, currency: currency))
                    .font(.amount(13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.petrol : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(suggestion.label): \(Money.string(suggestion.amount, currency: currency))")
    }
}

#Preview {
    EntryEditorView(item: nil, month: .current)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(RateService())
}
