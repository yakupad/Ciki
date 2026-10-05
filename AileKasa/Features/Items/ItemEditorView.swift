import SwiftUI
import CoreData

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>

    private let item: LedgerItem?
    private let onSave: ((LedgerItem) -> Void)?

    @State private var name: String
    @State private var bank: String
    @State private var kind: ItemKind
    @State private var direction: Direction
    @State private var owner: Person?
    @State private var currency: Currency
    @State private var dueDay: Int
    @State private var isRecurring: Bool
    @State private var recurringAmount: Decimal?
    @State private var recurringStart: Month
    @State private var hasEnd: Bool
    @State private var recurringEnd: Month
    @State private var isArchived: Bool
    @State private var confirmDelete: Bool

    init(item: LedgerItem?, defaultDirection: Direction? = nil, onSave: ((LedgerItem) -> Void)? = nil) {
        self.item = item
        self.onSave = onSave
        let startKind: ItemKind = switch defaultDirection {
        case .income: .salary
        case .receivable: .receivable
        default: .card
        }
        self.name = item?.name ?? ""
        self.bank = item?.bank ?? ""
        self.kind = item?.kind ?? startKind
        self.direction = item?.direction ?? defaultDirection ?? startKind.defaultDirection
        self.owner = item?.owner
        self.currency = item?.currency ?? .tl
        self.dueDay = Int(item?.dueDay ?? 0)
        self.isRecurring = item?.isRecurring ?? false
        self.recurringAmount = item?.recurringAmountValue
        let start = item.flatMap { $0.recurringStart == 0 ? nil : Month(key: $0.recurringStart) } ?? .current
        self.recurringStart = start
        self.hasEnd = (item?.recurringEnd ?? 0) != 0
        self.recurringEnd = item.flatMap { $0.recurringEnd == 0 ? nil : Month(key: $0.recurringEnd) } ?? start.adding(11)
        self.isArchived = item?.isArchived ?? false
        self.confirmDelete = false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kalem") {
                    Picker("Tür", selection: $kind) {
                        ForEach(ItemKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    TextField(kind.title, text: $name, prompt: Text("Ad (boşsa: \(kind.title))"))
                    if kind.isBankProduct || !bank.isEmpty {
                        HStack {
                            TextField("Banka", text: $bank)
                            Menu("Banka seç", systemImage: "chevron.up.chevron.down") {
                                ForEach(Banks.all, id: \.self) { name in
                                    Button(name) { bank = name }
                                }
                                Divider()
                                Button("Banka yok") { bank = "" }
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }

                Section("Kime ait") {
                    Picker("Kişi", selection: $owner) {
                        ForEach(people, id: \.objectID) { person in
                            Text(person.displayName).tag(Optional(person))
                        }
                        Text("Ortak").tag(Person?.none)
                    }
                    Picker("Yön", selection: $direction) {
                        ForEach(Direction.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Para birimi", selection: $currency) {
                        ForEach(Currency.allCases) { Text("\($0.symbol) \($0.title)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Son ödeme günü", selection: $dueDay) {
                        Text("Yok").tag(0)
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                }

                Section {
                    Toggle("Her ay tekrarla", isOn: $isRecurring.animation())
                    if isRecurring {
                        HStack {
                            Text("Aylık tutar")
                            Spacer()
                            TextField("0", value: $recurringAmount, format: .number.locale(Money.locale))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.amount(17, weight: .semibold))
                            Text(currency.symbol).foregroundStyle(.secondary)
                        }
                        MonthStepperRow(title: "Başlangıç", month: $recurringStart)
                        Toggle("Bitiş ayı var", isOn: $hasEnd.animation())
                        if hasEnd {
                            MonthStepperRow(title: "Son ay", month: $recurringEnd)
                        }
                    }
                } header: {
                    Text("Düzenli")
                } footer: {
                    if isRecurring {
                        Text(recurringFooter)
                    } else {
                        Text("Kira, kredi taksidi, maaş ve döviz gönderimleri gibi her ay tekrar eden kalemler için açın.")
                    }
                }

                if item != nil {
                    Section {
                        Toggle("Arşivle", isOn: $isArchived)
                        Button("Kalemi sil", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Arşivlenen kalem yeni aylarda görünmez, geçmiş kayıtları kalır. Silmek tüm aylardaki kayıtlarını da siler.")
                    }
                }
            }
            .navigationTitle(item == nil ? "Yeni kalem" : "Kalemi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(isRecurring && recurringAmount == nil)
                }
            }
            .onChange(of: kind) { _, newKind in
                direction = newKind.defaultDirection
                if !newKind.isBankProduct { bank = "" }
            }
            .onChange(of: recurringStart) { _, start in
                if recurringEnd < start { recurringEnd = start }
            }
            .confirmationDialog("Kalem ve tüm kayıtları silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { delete() }
            }
        }
    }

    private var recurringFooter: String {
        guard hasEnd else { return "\(recurringStart.title) ayından itibaren her ay tahmini olarak görünür." }
        let count = recurringStart.distance(to: recurringEnd) + 1
        return "\(recurringStart.title) – \(recurringEnd.title), toplam \(count) ay."
    }

    private func save() {
        let target = item ?? {
            let created = LedgerItem(context: context)
            created.uuid = UUID()
            created.createdAt = .now
            created.sortOrder = context.nextItemSortOrder()
            created.household = context.currentHousehold()
            return created
        }()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBank = bank.trimmingCharacters(in: .whitespaces)
        target.name = trimmedName.isEmpty ? nil : trimmedName
        target.bank = trimmedBank.isEmpty ? nil : trimmedBank
        target.kind = kind
        target.direction = direction
        target.owner = owner
        target.currency = currency
        target.dueDay = Int16(dueDay)
        target.isRecurring = isRecurring
        target.recurringAmountValue = isRecurring ? recurringAmount : nil
        target.recurringStart = isRecurring ? recurringStart.key : 0
        target.recurringEnd = isRecurring && hasEnd ? recurringEnd.key : 0
        target.isArchived = isArchived
        context.saveIfNeeded()
        onSave?(target)
        dismiss()
    }

    private func delete() {
        if let item { context.delete(item) }
        context.saveIfNeeded()
        dismiss()
    }
}

#Preview {
    ItemEditorView(item: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
