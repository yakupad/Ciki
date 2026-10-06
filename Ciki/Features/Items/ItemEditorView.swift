import SwiftUI
import CoreData

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: FetchedResults<Account>

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
    @State private var changes: [EditableAmountChange]
    @State private var isArchived: Bool
    @State private var payee: Account?
    @State private var isCreatingAccount: Bool
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
        self.changes = (item?.amountChanges ?? []).map { EditableAmountChange(month: $0.month, amount: $0.amount) }
        self.isArchived = item?.isArchived ?? false
        self.payee = item?.payee
        self.isCreatingAccount = false
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
                            Text(person.displayNameWithRelation).tag(Optional(person))
                        }
                        Text("Ortak").tag(Person?.none)
                    }
                    Picker("Yön", selection: $direction) {
                        ForEach(Direction.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Para birimi", selection: $currency) {
                        Section {
                            ForEach(Currency.common) { CurrencyLabel(currency: $0).tag($0) }
                        }
                        Section {
                            ForEach(Currency.all.filter { !Currency.common.contains($0) }) {
                                CurrencyLabel(currency: $0).tag($0)
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("Son ödeme günü", selection: $dueDay) {
                        Text("Yok").tag(0)
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                }

                if direction == .expense {
                    Section {
                        Picker("Ödeme hesabı", selection: $payee) {
                            Text("Yok").tag(Account?.none)
                            ForEach(accounts, id: \.objectID) { account in
                                Text(verbatim: account.displayTitle).tag(Optional(account))
                            }
                        }
                        if let payee, let iban = payee.iban, !iban.isEmpty {
                            Text(verbatim: IBAN.formatted(iban))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Color.ikincil)
                        }
                        Button("Yeni hesap ekle", systemImage: "plus.circle") { isCreatingAccount = true }
                    } header: {
                        Text("Ödeme bilgisi")
                    } footer: {
                        Text("Kira, aidat ya da gönderim gibi ödemelerde alıcının IBAN'ını seçin. Kayıt ekranında tek dokunuşla kopyalanır.")
                    }
                }

                Section {
                    Toggle("Her ay tekrarla", isOn: $isRecurring.animation())
                    if isRecurring {
                        HStack {
                            Text("Aylık tutar")
                            Spacer()
                            AmountField(value: $recurringAmount)
                            Text(currency.symbol).foregroundStyle(Color.ikincil)
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

                if isRecurring {
                    Section {
                        ForEach($changes) { $change in
                            VStack(spacing: 10) {
                                MonthStepperRow(title: "Şu aydan itibaren", month: $change.month)
                                HStack {
                                    Text("Yeni tutar")
                                    Spacer()
                                    AmountField(value: $change.amount)
                                    Text(currency.symbol).foregroundStyle(Color.ikincil)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { changes.remove(atOffsets: $0) }
                        Button("Tutar değişikliği ekle", systemImage: "plus.circle") { addChange() }
                    } header: {
                        Text("Tutar değişiklikleri")
                    } footer: {
                        Text(changesFooter)
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
            .navigationTitle(item == nil ? String(localized: "Yeni kalem") : String(localized: "Kalemi düzenle"))
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
            .sheet(isPresented: $isCreatingAccount) {
                AccountEditorView(account: nil)
            }
            .confirmationDialog("Kalem ve tüm kayıtları silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { delete() }
            }
        }
    }

    /// Yeni değişiklik: son dönemden sonraki ilk gelecek aydan, son tutarla başlar.
    private func addChange() {
        let lastMonth = changes.map(\.month).max() ?? recurringStart
        let lastAmount = changes.last { $0.month == lastMonth }?.amount ?? recurringAmount
        let month = max(lastMonth.adding(1), Month.current.adding(1))
        withAnimation {
            changes.append(EditableAmountChange(month: month, amount: lastAmount))
        }
    }

    /// Kaydedilecek değişiklikler: tutarı girilmiş, başlangıçtan sonra ve (varsa) son aydan önce; ay başına bir tane.
    private var validChanges: [AmountChange] {
        var byMonth: [Int32: Decimal] = [:]
        for change in changes {
            guard let amount = change.amount, change.month > recurringStart else { continue }
            if hasEnd, change.month > recurringEnd { continue }
            byMonth[change.month.key] = amount
        }
        return byMonth.map { AmountChange(from: $0.key, amount: $0.value) }.sorted { $0.from < $1.from }
    }

    /// Dönemlerin özeti: "Eki 2026 – Ara 2026: 100.000 ₺ · Oca 2027 – Haz 2027: 125.000 ₺".
    private var changesFooter: String {
        let valid = validChanges
        guard !valid.isEmpty, let first = recurringAmount else {
            return String(localized: "Tutar belli bir aydan sonra değişiyorsa ekleyin. Ör. yılbaşına kadar 100.000, sonra 6 ay 125.000.")
        }
        var periods: [(start: Month, amount: Decimal)] = [(recurringStart, first)]
        periods += valid.map { ($0.month, $0.amount) }
        var lines: [String] = []
        for (index, period) in periods.enumerated() {
            let end: Month? = index + 1 < periods.count ? periods[index + 1].start.adding(-1) : (hasEnd ? recurringEnd : nil)
            let amount = Money.string(period.amount, currency: currency)
            if let end {
                lines.append(end == period.start
                             ? "\(period.start.title): \(amount)"
                             : "\(period.start.title) – \(end.title): \(amount)")
            } else {
                lines.append(String(localized: "\(period.start.title) ve sonrası: \(amount)"))
            }
        }
        return lines.joined(separator: "\n")
    }

    private var recurringFooter: String {
        let start = recurringStart.title
        guard hasEnd else { return String(localized: "\(start) ayından itibaren her ay tahmini olarak görünür.") }
        let end = recurringEnd.title
        let count = recurringStart.distance(to: recurringEnd) + 1
        return String(localized: "\(start) – \(end), toplam \(count) ay.")
    }

    private func save() {
        let target = item ?? {
            let created = LedgerItem(context: context)
            created.uuid = UUID()
            created.createdAt = .now
            created.sortOrder = context.nextItemSortOrder()
            let household = context.currentHousehold()
            context.place(created, in: household)
            created.household = household
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
        target.amountChanges = isRecurring ? validChanges : []
        target.isArchived = isArchived
        target.updatedAt = .now
        target.updatedBy = DeviceOwner.name(in: context)
        target.payee = direction == .expense ? payee : nil
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

/// "€  EUR · Euro"
struct CurrencyLabel: View {
    let currency: Currency

    var body: some View {
        // Dar yerlerde (ör. seçicinin sağındaki değer) yalnızca simge ve kod gösterilir.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                symbol
                Text(verbatim: currency.title).fontWeight(.semibold)
                Text(verbatim: currency.name).foregroundStyle(Color.ikincil).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(verbatim: currency.symbol)
                Text(verbatim: currency.title).fontWeight(.semibold)
            }
        }
    }

    private var symbol: some View {
        Text(currency.symbol)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(minWidth: 36, alignment: .leading)
    }
}

/// Düzenleme sırasında bir tutar değişikliği; ay değiştirilebildiği için kimliği ayrı tutulur.
struct EditableAmountChange: Identifiable {
    let id = UUID()
    var month: Month
    var amount: Decimal?
}
