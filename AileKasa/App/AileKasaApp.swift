import SwiftUI

@main
struct AileKasaApp: App {
    private let persistence = PersistenceController.shared
    @State private var appState = AppState()
    @State private var rates = RateService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(appState)
                .environment(rates)
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

/// Sekmeler arasında paylaşılan seçili ay.
@Observable
final class AppState {
    var month: Month = .current
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Özet", systemImage: "square.grid.2x2.fill") {
                NavigationStack { SummaryView() }
            }
            Tab("Aylar", systemImage: "calendar") {
                NavigationStack { MonthView() }
            }
            Tab("Tablo", systemImage: "tablecells") {
                NavigationStack { GridView() }
            }
            Tab("Kalemler", systemImage: "arrow.triangle.2.circlepath") {
                NavigationStack { ItemsView() }
            }
        }
        .tint(.petrol)
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(AppState())
        .environment(RateService())
}
