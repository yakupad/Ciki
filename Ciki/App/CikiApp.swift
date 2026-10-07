import SwiftUI
import CoreData
import Combine

@main
struct CikiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let persistence = PersistenceController.shared
    @State private var appState = AppState()
    @State private var rates = RateService()
    @State private var lock = AppLock()
    @State private var reminders = ReminderScheduler()
    @State private var rescheduleTask: Task<Void, Never>?
    @State private var resolveTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    private let lockWindow = LockWindow()

    init() {
        Self.skipOnboardingForExistingData(in: PersistenceController.shared.viewContext)
    }

    /// Önceki sürümlerden gelen ya da kişisi olan kurulumlarda karşılama ekranı gösterilmez.
    private static func skipOnboardingForExistingData(in context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: OnboardingView.completedKey) else { return }
        let people = (try? context.count(for: NSFetchRequest<Person>(entityName: "Person"))) ?? 0
        let items = (try? context.count(for: NSFetchRequest<LedgerItem>(entityName: "LedgerItem"))) ?? 0
        var skip = people + items > 0
        #if DEBUG
        skip = skip || CommandLine.arguments.contains("-loadSampleData")
        #endif
        if skip { defaults.set(true, forKey: OnboardingView.completedKey) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(appState)
                .environment(rates)
                .environment(lock)
                .environment(reminders)
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .background:
                        lock.lock()
                    case .active:
                        appearance.apply()
                        Task { await lock.unlock() }
                        scheduleReminders()
                    default:
                        break
                    }
                    updateLockWindow()
                }
                .onChange(of: appearance) { _, newValue in newValue.apply() }
                .onChange(of: lock.isLocked) { updateLockWindow() }
                .onChange(of: lock.isEnabled) {
                    updateLockWindow()
                    scheduleReminders()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSManagedObjectContext.didSaveObjectsNotification)) { _ in
                    scheduleReminders()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                    resolveHouseholds()
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudSharing.didAcceptShare)) { _ in
                    resolveHouseholds()
                }
                .onChange(of: reminders.isEnabled) { scheduleReminders() }
                .onChange(of: reminders.daysBefore) { scheduleReminders() }
                .onChange(of: reminders.hour) { scheduleReminders() }
                .onChange(of: reminders.hidesAmounts) { scheduleReminders() }
                .task {
                    persistence.viewContext.currentHousehold()
                    #if DEBUG
                    if CommandLine.arguments.contains("-loadSampleData") {
                        SampleData.wipe(persistence.viewContext)
                        SampleData.load(into: persistence.viewContext)
                    }
                    if CommandLine.arguments.contains("-simulateRemoteChange") {
                        SampleData.simulateRemoteChange(in: persistence.container)
                    }
                    #endif
                    await rates.refreshIfStale()
                }
        }
    }
}

extension CikiApp {
    /// Kilit açıkken arka planda ya da kilitliyken tutarlar gizlenir.
    private func updateLockWindow() {
        lockWindow.update(visible: lock.isEnabled && (lock.isLocked || scenePhase != .active), lock: lock)
    }

    /// iCloud'dan gelen değişikliklerden sonra fazladan hane kayıtlarını birleştirir.
    private func resolveHouseholds() {
        resolveTask?.cancel()
        resolveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            if case .localDataNeedsDecision(let id) = HouseholdSync.resolve(in: persistence.viewContext) {
                appState.localHouseholdToResolve = id
            }
        }
    }

    /// Kayıt değişikliklerinde art arda gelen çağrıları birleştirip widget özetini ve hatırlatmaları yeniler.
    private func scheduleReminders() {
        rescheduleTask?.cancel()
        rescheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            WidgetPublisher.publish(context: persistence.viewContext, rates: rates.table, isPrivate: lock.isEnabled)
            await reminders.reschedule(context: persistence.viewContext, rates: rates.table)
        }
    }
}

/// Sekmeler arasında paylaşılan seçili ay.
@Observable
final class AppState {
    var month: Month = .current
    /// Paylaşılan bir haneye katıldıktan sonra bu cihazda kalan, kayıt içeren yerel hane.
    var localHouseholdToResolve: NSManagedObjectID?
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(AppLock.self) private var lock
    @Environment(ReminderScheduler.self) private var reminders
    @State private var route: EditorRoute?
    @AppStorage(OnboardingView.completedKey) private var isOnboarded = false
    @State private var tab = RootView.initialTab

    /// DEBUG derlemede `-startTab 3` ile açılış sekmesi seçilebilir (ekran görüntüsü için).
    private static var initialTab: Int {
        #if DEBUG
        // "-startTab 1" başlatma argümanı UserDefaults'un argüman alanına düşer.
        return UserDefaults.standard.integer(forKey: "startTab")
        #else
        return 0
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Özet", systemImage: "square.grid.2x2.fill", value: 0) {
                NavigationStack { SummaryView() }
            }
            Tab("Aylar", systemImage: "calendar", value: 1) {
                NavigationStack { MonthView() }
            }
            Tab("Tablo", systemImage: "tablecells", value: 2) {
                NavigationStack { GridView() }
            }
            Tab("Kalemler", systemImage: "list.bullet.rectangle", value: 3) {
                NavigationStack { ItemsView() }
            }
        }
        .measuresWideLayout()
        .dismissesKeyboardOnTap()
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Yeni kayıt her sekmede aynı yerde: sekme çubuğunun üstünde.
        .tabViewBottomAccessory {
            NewEntryAccessory(month: app.month) {
                route = .entry(item: nil, month: app.month)
            }
        }
        .sheet(item: $route) { EditorSheet(route: $0) }
        .modifier(LocalHouseholdDecision())
        .fullScreenCover(isPresented: Binding(get: { !isOnboarded }, set: { isOnboarded = !$0 })) {
            // Mac Catalyst'te tam ekran sunum ortam nesnelerini devralmıyor; açıkça aktarılır.
            OnboardingView()
                .environment(lock)
                .environment(reminders)
        }
        .tint(.petrol)
    }
}

/// Paylaşılan bir haneye katılınca bu cihazdaki eski kayıtlar için karar.
private struct LocalHouseholdDecision: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.managedObjectContext) private var context

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Bu cihazdaki kayıtlar",
            isPresented: Binding(get: { app.localHouseholdToResolve != nil },
                                 set: { if !$0 { app.localHouseholdToResolve = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ortak haneye kopyala") { resolve(copy: true) }
            Button("Bu cihazdakileri sil", role: .destructive) { resolve(copy: false) }
            Button("Sonra karar ver", role: .cancel) {}
        } message: {
            Text("Paylaşılan bir haneye katıldınız. Bu cihazda daha önce girdiğiniz kalemler ya da hesaplar var. Ortak haneye kopyalarsanız hanedeki herkes görür; silerseniz yalnızca ortak hane kalır.")
        }
    }

    private func resolve(copy: Bool) {
        guard let id = app.localHouseholdToResolve,
              let local = try? context.existingObject(with: id) as? Household else { return }
        let shared = context.currentHousehold()
        if copy, shared != local {
            HouseholdSync.copy(local, into: shared, in: context)
        } else {
            context.delete(local)
            context.saveIfNeeded()
        }
        app.localHouseholdToResolve = nil
    }
}

private struct NewEntryAccessory: View {
    let month: Month
    let action: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.petrol)
                Text("Yeni kayıt")
                    .fontWeight(.semibold)
                if placement != .inline {
                    Spacer()
                    Text(month.title)
                        .foregroundStyle(Color.ikincil)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Yeni kayıt, \(month.title)")
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(AppState())
        .environment(RateService())
        .environment(AppLock())
        .environment(ReminderScheduler())
}
