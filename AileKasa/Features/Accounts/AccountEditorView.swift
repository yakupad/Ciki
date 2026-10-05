import SwiftUI
import CoreData

struct AccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>

    private let account: Account?

    @State private var isOwn: Bool
    @State private var owner: Person?
    @State private var title: String
    @State private var holderName: String
    @State private var iban: String
    @State private var bank: String
    @State private var currency: Currency
    @State private var note: String
    @State private var confirmDelete: Bool
    /// Banka adı IBAN'dan otomatik dolduysa, IBAN değişince yeniden doldurulur.
    @State private var bankFromIBAN: Bool

    init(account: Account?) {
        self.account = account
        self.isOwn = account?.isOwn ?? false
        self.owner = account?.owner
        self.title = account?.title ?? ""
        self.holderName = account?.holderName ?? ""
        self.iban = IBAN.formatted(account?.iban ?? "")
        self.bank = account?.bank ?? ""
        self.currency = account?.currency ?? .tl
        self.note = account?.note ?? ""
        self.confirmDelete = false
        self.bankFromIBAN = (account?.bank ?? "").isEmpty
    }

    private var validity: IBAN.Validity { IBAN.validate(iban) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Hesap türü", selection: $isOwn) {
                        Text("Ödeme yapılan").tag(false)
                        Text("Bizim hesap").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Hesap adı", text: $title, prompt: Text(isOwn ? "Ör. Maaş hesabı" : "Ör. Ev sahibi, Aidat"))
                    TextField("Alıcı adı", text: $holderName, prompt: Text("Ad soyad ya da unvan"))
                        .textContentType(.name)
                    if isOwn {
                        Picker("Kişi", selection: $owner) {
                            ForEach(people, id: \.objectID) { person in
                                Text(verbatim: person.displayName).tag(Optional(person))
                            }
                            Text("Ortak").tag(Person?.none)
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("IBAN", text: $iban, prompt: Text(verbatim: "TR00 0000 0000 0000 0000 0000 00"))
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first { iban = IBAN.formatted(first) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                    }
                    HStack {
                        TextField("Banka", text: $bank)
                            .onChange(of: bank) { _, newValue in
                                if newValue != Banks.name(forIBAN: iban) { bankFromIBAN = newValue.isEmpty }
                            }
                        Menu("Banka seç", systemImage: "chevron.up.chevron.down") {
                            ForEach(Banks.all, id: \.self) { name in
                                Button(name) { bank = name }
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                    Picker("Para birimi", selection: $currency) {
                        ForEach(Currency.all) { CurrencyLabel(currency: $0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Banka bilgisi")
                } footer: {
                    validityText
                }

                Section("Not") {
                    TextField("Ör. açıklamaya daire numarasını yaz", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let account, !account.itemsArray.isEmpty {
                    Section {
                        ForEach(account.itemsArray, id: \.objectID) { item in
                            Text(verbatim: "\(item.fullTitle) · \(item.ownerName)")
                        }
                    } header: {
                        Text("Bu hesaba ödenen kalemler")
                    }
                }

                if account != nil {
                    Section {
                        Button("Hesabı sil", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(account == nil ? String(localized: "Yeni hesap") : String(localized: "Hesabı düzenle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(title.isBlank && holderName.isBlank && iban.isBlank)
                }
            }
            .onChange(of: iban) { _, newValue in
                let formatted = IBAN.formatted(newValue)
                if formatted != newValue { iban = formatted }
                if bankFromIBAN || bank.isEmpty, let detected = Banks.name(forIBAN: formatted) {
                    bank = detected
                    bankFromIBAN = true
                }
            }
            .confirmationDialog("Hesap silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { delete() }
            } message: {
                Text("Bağlı kalemler silinmez, yalnızca ödeme hesabı bağlantısı kalkar.")
            }
        }
    }

    @ViewBuilder
    private var validityText: some View {
        switch validity {
        case .empty:
            Text("IBAN'ı yazın ya da yapıştırın. TR IBAN'larında banka otomatik bulunur.")
        case .incomplete(let expected):
            Text("\(IBAN.normalized(iban).count)/\(expected) karakter")
        case .valid:
            Label("IBAN geçerli", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Color.gelir)
        case .invalid:
            Label("IBAN hatalı görünüyor. Rakamları kontrol edin.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.gider)
        }
    }

    private func save() {
        let target = account ?? {
            let created = Account(context: context)
            created.uuid = UUID()
            created.createdAt = .now
            let household = context.currentHousehold()
            context.place(created, in: household)
            created.household = household
            return created
        }()
        target.isOwn = isOwn
        target.owner = isOwn ? owner : nil
        target.title = title.trimmedOrNil
        target.holderName = holderName.trimmedOrNil
        target.iban = IBAN.normalized(iban).nilIfEmpty
        target.bank = bank.trimmedOrNil
        target.currency = currency
        target.note = note.trimmedOrNil
        context.saveIfNeeded()
        dismiss()
    }

    private func delete() {
        if let account { context.delete(account) }
        context.saveIfNeeded()
        dismiss()
    }
}

nonisolated extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    AccountEditorView(account: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
