import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(RateService.self) private var rates
    @Environment(AppLock.self) private var lock
    @Environment(ReminderScheduler.self) private var reminders

    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Household.createdAt)])
    private var households: FetchedResults<Household>
    @FetchRequest(sortDescriptors: [])
    private var accounts: FetchedResults<Account>

    @State private var confirmWipe = false
    @State private var confirmErase = false
    @AppStorage(DeviceOwner.key) private var deviceOwnerID = ""
    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    @State private var personToDelete: Person?

    var body: some View {
        @Bindable var rates = rates
        @Bindable var reminders = reminders
        NavigationStack {
            Form {
                if let household = households.first(where: \.isInSharedStore) ?? households.first {
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
                    Picker("Bu telefonu kullanan", selection: $deviceOwnerID) {
                        Text("Seçilmedi").tag("")
                        ForEach(people, id: \.objectID) { person in
                            if let id = person.uuid?.uuidString {
                                Text(verbatim: person.displayName).tag(id)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Kişiler")
                        Spacer()
                        if people.count > 1 {
                            EditButton().font(.footnote)
                        }
                    }
                } footer: {
                    Text("Kişi renkleri özet, liste ve tabloda kullanılır. Silinen kişinin kalemleri Ortak'a geçer. Bu telefonu kullanan kişiyi seçerseniz yaptığınız değişikliklerde adınız görünür.")
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
                    Picker("Görünüm", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Görünüm")
                } footer: {
                    Text("Sistem seçiliyse telefonun açık ya da koyu mod ayarı izlenir. Bu ayar yalnızca bu telefon için geçerlidir.")
                }

                #if targetEnvironment(macCatalyst)
                Section {
                    LabeledContent("Uygulama dili") {
                        Text(verbatim: AppLanguage.current == .english ? "English" : "Türkçe")
                    }
                } footer: {
                    Text("Mac'te dil, Sistem Ayarları → Genel → Dil ve Bölge → Uygulamalar bölümünden değiştirilir.")
                }
                #else
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
                #endif

                Section {
                    Toggle(isOn: Binding(
                        get: { lock.isEnabled },
                        set: { enabled in Task { await lock.setEnabled(enabled) } }
                    )) {
                        Label("\(lock.methodName) ile kilitle", systemImage: "lock.fill")
                    }
                } header: {
                    Text("Güvenlik")
                } footer: {
                    if let error = lock.errorMessage {
                        Text(error).foregroundStyle(Color.gider)
                    } else {
                        Text("Uygulama arka plana geçince kilitlenir. Uygulama değiştiricide tutarlar ve IBAN'lar gizlenir.")
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { reminders.isEnabled },
                        set: { enabled in Task { await reminders.setEnabled(enabled) } }
                    )) {
                        Label("Ödeme hatırlatmaları", systemImage: "bell.badge")
                    }
                    if reminders.isEnabled {
                        Picker("Ne zaman", selection: $reminders.daysBefore) {
                            Text("Son ödeme günü").tag(0)
                            Text("1 gün önce").tag(1)
                            Text("2 gün önce").tag(2)
                            Text("3 gün önce").tag(3)
                            Text("1 hafta önce").tag(7)
                        }
                        Picker("Saat", selection: $reminders.hour) {
                            ForEach(7...22, id: \.self) { hour in
                                Text(verbatim: String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        Toggle("Bildirimde tutarı gizle", isOn: $reminders.hidesAmounts)
                    }
                } header: {
                    Text("Hatırlatmalar")
                } footer: {
                    if let error = reminders.errorMessage {
                        Text(error).foregroundStyle(Color.gider)
                    } else {
                        Text("Son ödeme günü girilmiş ve ödenmemiş giderler için bildirim gelir. Ödendi işaretlenen kayıtların bildirimi iptal olur.")
                    }
                }

                Section {
                    NavigationLink {
                        ExportView()
                    } label: {
                        Label("Dışa aktar (CSV)", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Kayıtları ya da aylık tabloyu Excel, Numbers veya Google E-Tablolar'da açmak için.")
                }

                SharingSection()

                Section {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Verileriniz nerede?", systemImage: "hand.raised.fill")
                    }
                    Button("Tüm verilerimi sil", systemImage: "trash", role: .destructive) { confirmErase = true }
                } header: {
                    Text("Gizlilik")
                } footer: {
                    Text("Silme işlemi bu cihazdaki ve iCloud'unuzdaki kalemleri, kayıtları, kişileri ve hesapları kaldırır. Geri alınamaz.")
                }

                Section {
                    NavigationLink {
                        ActivityView()
                    } label: {
                        Label("Son değişiklikler", systemImage: "clock.arrow.circlepath")
                    }
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
            .confirmationDialog("Tüm verileriniz silinsin mi?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Tüm verilerimi sil", role: .destructive) {
                    DataEraser.eraseOwnData(in: context)
                    dismiss()
                }
            } message: {
                Text("Kalemler, kayıtlar, kişiler ve IBAN'lar bu cihazdan ve iCloud'unuzdan silinir. Haneyi eşinizle paylaştıysanız onun telefonundan da kalkar. Eşinizin size paylaştığı hane silinmez. Bu işlem geri alınamaz.")
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

    private func addPerson() {
        context.addPerson(named: "", to: context.currentHousehold())
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
        .environment(AppLock())
        .environment(ReminderScheduler())
}
