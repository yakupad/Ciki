import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Household.createdAt)])
    private var households: FetchedResults<Household>

    @State private var confirmWipe = false

    var body: some View {
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
                } header: {
                    Text("Kişiler")
                } footer: {
                    Text("Kişi renkleri özet, liste ve tabloda kullanılır.")
                }

                Section {
                    RateCard()
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
