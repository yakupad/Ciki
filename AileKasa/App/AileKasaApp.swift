import SwiftUI
import CoreData
import Combine

@main
struct AileKasaApp: App {
    private let persistence = PersistenceController.shared
    @State private var appState = AppState()
    @State private var rates = RateService()
    @State private var lock = AppLock()
    @State private var reminders = ReminderScheduler()
    @State private var rescheduleTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    private let lockWindow = LockWindow()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(appState)
                .environment(rates)
                .environment(lock)
                .environment(reminders)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .background:
                        lock.lock()
                    case .active:
                        Task { await lock.unlock() }
                        scheduleReminders()
                    default:
                        break
                    }
                    updateLockWindow()
                }
                .onChange(of: lock.isLocked) { updateLockWindow() }
                .onChange(of: lock.isEnabled) {
                    updateLockWindow()
                    scheduleReminders()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSManagedObjectContext.didSaveObjectsNotification)) { _ in
                    scheduleReminders()
                }
                .onChange(of: reminders.isEnabled) { scheduleReminders() }
                .onChange(of: reminders.daysBefore) { scheduleReminders() }
                .onChange(of: reminders.hour) { scheduleReminders() }
                .task {
                    persistence.viewContext.currentHousehold()
                    #if DEBUG
                    if CommandLine.arguments.contains("-loadSampleData") {
                        SampleData.wipe(persistence.viewContext)
                        SampleData.load(into: persistence.viewContext)
                    }
                    #endif
                    await rates.refreshIfStale()
                }
        }
    }
}

extension AileKasaApp {
    /// Kilit açıkken arka planda ya da kilitliyken tutarlar gizlenir.
    private func updateLockWindow() {
        lockWindow.update(visible: lock.isEnabled && (lock.isLocked || scenePhase != .active), lock: lock)
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
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var route: EditorRoute?
    @State private var tab = RootView.initialTab

    /// DEBUG derlemede `-startTab 3` ile açılış sekmesi seçilebilir (ekran görüntüsü için).
    private static var initialTab: Int {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-startTab"), index + 1 < arguments.count {
            return Int(arguments[index + 1]) ?? 0
        }
        #endif
        return 0
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
        .tabBarMinimizeBehavior(.onScrollDown)
        // Yeni kayıt her sekmede aynı yerde: sekme çubuğunun üstünde.
        .tabViewBottomAccessory {
            NewEntryAccessory(month: app.month) {
                route = .entry(item: nil, month: app.month)
            }
        }
        .sheet(item: $route) { EditorSheet(route: $0) }
        .tint(.petrol)
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
                        .foregroundStyle(.secondary)
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
