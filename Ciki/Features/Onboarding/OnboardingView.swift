import SwiftUI
import CoreData

/// İlk açılış: tanıtım, hane ve kişiler, gizlilik tercihleri. Eşi tarafından davet edilen kişi
/// kişi oluşturmadan geçer; davet kabul edilince ortak hane gelir.
struct OnboardingView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(AppLock.self) private var lock
    @Environment(ReminderScheduler.self) private var reminders
    @AppStorage(OnboardingView.completedKey) private var isCompleted = false
    @AppStorage(DeviceOwner.key) private var deviceOwnerID = ""

    static let completedKey = "onboarding.completed"

    enum Step { case welcome, people, privacy, invited }

    @State private var step = OnboardingView.initialStep

    /// DEBUG'da "-onboardingStep people" ile istenen adımdan başlanır (ekran görüntüsü için).
    private static var initialStep: Step {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "onboardingStep") {
        case "people": return .people
        case "privacy": return .privacy
        case "invited": return .invited
        default: return .welcome
        }
        #else
        return .welcome
        #endif
    }
    @State private var householdName = ""
    @State private var names = ["", ""]
    @State private var relations: [PersonRelation?] = [nil, nil]
    @FocusState private var focusedField: Int?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .people: people
                case .privacy: privacy
                case .invited: invited
                }
            }
            .background(Color.zemin)
            .animation(.default, value: step)
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Hoş geldiniz

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 76, height: 76)
                        .accessibilityHidden(true)
                    Text("Çıkı'ya hoş geldiniz")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Ortak bütçe, borç ve ödeme takibi. Excel tablosuna gerek kalmadan.")
                        .font(.title3)
                        .foregroundStyle(Color.ikincil)
                }

                VStack(alignment: .leading, spacing: 20) {
                    Feature(symbol: "calendar", title: "Her ay tek bakışta",
                            text: "Kartlar, krediler, kira ve maaşlar; geçmiş, bu ay ve gelecek aylar.")
                    Feature(symbol: "person.2.fill", title: "Birlikte kullanın",
                            text: "Eşiniz, aileniz ya da ev arkadaşlarınız iCloud ile aynı kayıtları görür ve düzenler.")
                    Feature(symbol: "lock.shield.fill", title: "Verileriniz sizde",
                            text: "Kayıtlar yalnızca cihazınızda ve kendi iCloud hesabınızda durur. Reklam ya da analiz yok.")
                }

                Text("Çıkı: eskiden paranın bağlanıp saklandığı düğümlü mendil.")
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(Color.ikincil)
            }
            .padding(24)
            .readableWidth(560)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                PrimaryButton("Başla") { step = .people }
                Button("Bir davet aldım") { step = .invited }
                    .font(.body.weight(.semibold))
            }
            .padding(24)
            .readableWidth(560)
            .background(Color.zemin)
        }
    }

    // MARK: - Kişiler

    private var people: some View {
        Form {
            Section {
                TextField("Hane adı", text: $householdName, prompt: Text("Evimiz"))
                    .textContentType(.organizationName)
            } header: {
                Text("Hane")
            } footer: {
                Text("Paylaşım davetlerinde bu ad görünür.")
            }

            Section {
                ForEach(names.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hexString: Person.palette[index % Person.palette.count]) ?? .petrol)
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        TextField(placeholder(for: index), text: $names[index])
                            .textContentType(index == 0 ? .givenName : .none)
                            .focused($focusedField, equals: index)
                            .submitLabel(.next)
                            .onSubmit { focusedField = index + 1 < names.count ? index + 1 : nil }
                        if index > 0 {
                            Menu {
                                Picker("Yakınlık", selection: $relations[index]) {
                                    Text("Belirtilmedi").tag(PersonRelation?.none)
                                    ForEach(PersonRelation.allCases) { Text(verbatim: $0.title).tag(Optional($0)) }
                                }
                            } label: {
                                Text(verbatim: relations[index]?.title ?? String(localized: "Yakınlık"))
                                    .font(.subheadline)
                                    .foregroundStyle(relations[index] == nil ? Color.ikincil : Color.petrol)
                                    .frame(minHeight: 44)
                            }
                            .accessibilityLabel(Text("Yakınlık"))
                        }
                    }
                }
                .onDelete { offsets in
                    names.remove(atOffsets: offsets)
                    relations.remove(atOffsets: offsets)
                    if names.isEmpty { names = [""]; relations = [nil] }
                }
                Button("Kişi ekle", systemImage: "person.badge.plus") {
                    names.append("")
                    relations.append(nil)
                    focusedField = names.count - 1
                }
            } header: {
                Text("Kişiler")
            } footer: {
                Text("İlk kişi bu telefonu kullanan kişi olarak seçilir. Kişileri sonra Ayarlar'dan değiştirebilirsiniz.")
            }
        }
        .navigationTitle("Hanede kimler var?")
        .navigationBarTitleDisplayMode(.large)
        .scrollContentBackground(.hidden)
        .readableWidth(640)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Devam") { createHousehold() }
                .disabled(names.first?.isBlank ?? true)
                .padding(24)
                .readableWidth(560)
                .background(Color.zemin)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Geri", systemImage: "chevron.left") { step = .welcome }
            }
        }
        .onAppear { focusedField = 0 }
    }

    private func placeholder(for index: Int) -> String {
        switch index {
        case 0: String(localized: "Adınız")
        case 1: String(localized: "Diğer kişinin adı (isteğe bağlı)")
        default: String(localized: "Ad")
        }
    }

    // MARK: - Gizlilik

    private var privacy: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { lock.isEnabled },
                                     set: { enabled in Task { await lock.setEnabled(enabled) } })) {
                    Label("\(lock.methodName) ile kilitle", systemImage: "lock.fill")
                }
            } footer: {
                if let error = lock.errorMessage {
                    Text(error).foregroundStyle(Color.gider)
                } else {
                    Text("Uygulama her açılışta kimliğinizi sorar. Uygulama değiştiricide ve widget'ta tutarlar gizlenir.")
                }
            }

            Section {
                Toggle(isOn: Binding(get: { reminders.isEnabled },
                                     set: { enabled in Task { await reminders.setEnabled(enabled) } })) {
                    Label("Ödeme hatırlatmaları", systemImage: "bell.badge")
                }
            } footer: {
                Text("Son ödeme gününden bir gün önce saat 09:00'da bildirim gelir. Zamanı Ayarlar'dan değiştirebilirsiniz.")
            }
        }
        .navigationTitle("Gizlilik ve bildirimler")
        .navigationBarTitleDisplayMode(.large)
        .scrollContentBackground(.hidden)
        .readableWidth(640)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Bitir") { isCompleted = true }
                .padding(24)
                .readableWidth(560)
                .background(Color.zemin)
        }
    }

    // MARK: - Davet

    private var invited: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.petrol)
                    .accessibilityHidden(true)
                Text("Davet bağlantısını açın")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Size Mesajlar, WhatsApp ya da e-postayla gönderilen davet bağlantısına bu telefonda dokunun. Ortak hane birkaç saniye içinde gelir.")
                    .font(.body)
                Text("Davet gelmediyse haneyi kuran kişiden Çıkı'da Ayarlar → iCloud ile ortak kullanım → Kişi davet et adımını yapmasını isteyin. İki telefonda da iCloud'a giriş yapılmış olmalı.")
                    .font(.callout)
                    .foregroundStyle(Color.ikincil)
            }
            .padding(24)
            .readableWidth(560)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                PrimaryButton("Tamam") { isCompleted = true }
                Button("Kendi hanemi oluşturayım") { step = .people }
                    .font(.body.weight(.semibold))
            }
            .padding(24)
            .readableWidth(560)
            .background(Color.zemin)
        }
    }

    // MARK: - Kaydet

    private func createHousehold() {
        let household = context.currentHousehold()
        if let name = householdName.trimmedOrNil { household.name = name }
        let people = zip(names, relations).compactMap { name, relation -> Person? in
            guard let name = name.trimmedOrNil else { return nil }
            let person = context.addPerson(named: name, to: household)
            person.relation = relation
            return person
        }
        context.saveIfNeeded()
        if let me = people.first?.uuid?.uuidString { deviceOwnerID = me }
        step = .privacy
    }
}

private struct Feature: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.petrol)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(Color.ikincil)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.petrol)
    }
}

#Preview {
    OnboardingView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(AppLock())
        .environment(ReminderScheduler())
}
