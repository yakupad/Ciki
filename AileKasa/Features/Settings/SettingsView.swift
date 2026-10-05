import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(RateService.self) private var rates

    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Household.createdAt)])
    private var households: FetchedResults<Household>
    @FetchRequest(sortDescriptors: [])
    private var accounts: FetchedResults<Account>

    @State private var confirmWipe = false
    @State private var personToDelete: Person?

    var body: some View {
        @Bindable var rates = rates
        NavigationStack {
            Form {
                if let household = households.first {
                    Section("Hane") {
                        TextField("Hane adı", text: binding(household, \.name))
                    }
                }

                Section {
                    ForEach(people, id: \.objectID) { person in
                        HStack {
                            TextField("İsim", text: binding(person, \.name))
                            ColorPicker("Renk", selection: colorBinding(person), supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                    .onDelete { offsets in
                        personToDelete = offsets.first.map { people[$0] }
                    }
                    .onMove(perform: movePeople)
                    Button("Kişi ekle", systemImage: "person.badge.plus", action: addPerson)
                } header: {
                    HStack {
                        Text("Kişiler")
                        Spacer()
                        if people.count > 1 {
                            EditButton().font(.footnote)
                        }
                    }
                } footer: {
                    Text("Kişi renkleri özet, liste ve tabloda kullanılır. Silinen kişinin kalemleri Ortak'a geçer.")
                }

                Section {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        LabeledContent {
                            Text("\(accounts.count)")
                                .monospacedDigit()
                        } label: {
                            Label("Hesaplar ve IBAN'lar", systemImage: "building.columns")
                        }
                    }
                } footer: {
                    Text("Kişilerin kendi hesapları ve ödeme yapılan kişi ya da kurumların IBAN'ları. Dokununca IBAN kopyalanır.")
                }

                Section {
                    Picker("Gösterim para birimi", selection: $rates.baseCurrency) {
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
                    RateCard()
                } header: {
                    Text("Para birimi")
                } footer: {
                    if rates.baseCurrency != .tl && rates.table.tryRate(for: rates.baseCurrency) == nil {
                        Text("\(rates.baseCurrency.title) kuru henüz alınamadı. Toplamlar kur gelene kadar eksik görünebilir.")
                            .foregroundStyle(Color.gider)
                    } else {
                        Text("Özet, rapor ve toplamlar bu para biriminde gösterilir. Kalemler kendi para biriminde kalır. Çevrim TCMB kurlarıyla yapılır.")
                    }
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        LabeledContent("Uygulama dili") {
                            HStack(spacing: 4) {
                                Text(verbatim: AppLanguage.current == .english ? "English" : "Türkçe")
                                Image(systemName: "arrow.up.forward.app")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Dil, iOS Ayarlar'da uygulamanın sayfasından değiştirilir. Türkçe ve İngilizce desteklenir.")
                }

                Section("iCloud") {
                    Label("Eşinizle paylaşım bir sonraki aşamada eklenecek. Şu an veriler yalnızca bu cihazda.", systemImage: "icloud.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Section {
                    Button("Excel örnek verisini yükle") {
                        SampleData.load(into: context)
                    }
                    Button("Tüm kalemleri sil", role: .destructive) { confirmWipe = true }
                } header: {
                    Text("Geliştirici")
                } footer: {
                    Text("Örnek veri Excel tablonuzun Ağustos–Kasım 2026 sütunlarından alınmıştır.")
                }
                #endif
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") {
                        context.saveIfNeeded()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Kişi silinsin mi?", isPresented: Binding(
                get: { personToDelete != nil },
                set: { if !$0 { personToDelete = nil } }
            ), titleVisibility: .visible, presenting: personToDelete) { person in
                Button("\(person.displayName) kişisini sil", role: .destructive) { delete(person) }
            } message: { person in
                let count = (person.items as? Set<LedgerItem>)?.count ?? 0
                Text("\(person.displayName) adına \(count) kalem var. Kalemler ve kayıtları silinmez, Ortak'a geçer.")
            }
            .confirmationDialog("Tüm kalemler ve kayıtlar silinsin mi?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Hepsini sil", role: .destructive) { SampleData.wipe(context) }
            }
        }
    }

    private func binding<Object: NSManagedObject>(_ object: Object,
                                                  _ keyPath: ReferenceWritableKeyPath<Object, String?>) -> Binding<String> {
        Binding(
            get: { object[keyPath: keyPath] ?? "" },
            set: { object[keyPath: keyPath] = $0 }
        )
    }

    /// Yeni kişiye sıradaki paletten, kullanılmayan bir renk verilir.
    private func addPerson() {
        let palette = ["3D5FD9", "C23F7B", "D9822B", "2E9E6B", "7A4FD1", "1F8FB0", "B5452E", "6B7A2E"]
        let used = Set(people.compactMap { $0.colorHex?.uppercased() })
        let person = Person(context: context)
        person.uuid = UUID()
        person.name = ""
        person.colorHex = palette.first { !used.contains($0) } ?? palette[people.count % palette.count]
        person.sortOrder = Int16((people.map(\.sortOrder).max() ?? -1) + 1)
        person.household = households.first ?? context.currentHousehold()
        context.saveIfNeeded()
    }

    private func movePeople(from source: IndexSet, to destination: Int) {
        var ordered = Array(people)
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, person) in ordered.enumerated() {
            person.sortOrder = Int16(index)
        }
        context.saveIfNeeded()
    }

    private func delete(_ person: Person) {
        context.delete(person)
        context.saveIfNeeded()
        personToDelete = nil
    }

    private func colorBinding(_ person: Person) -> Binding<Color> {
        Binding(
            get: { person.color },
            set: { person.colorHex = $0.hexString }
        )
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(RateService())
}
