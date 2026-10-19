import SwiftUI
import CoreData
import Combine

/// Bağlamdaki herhangi bir nesne değiştiğinde artan sayaç.
///
/// `@FetchRequest` yalnızca ekleme ve silmede ekranı yeniler; var olan bir kaydın durumu ya da tutarı
/// değişince (ör. ödendi → bekliyor) toplamlar ve satırlar eski kalır. Gövdede `version` okunursa
/// her değişiklikte, iCloud'dan gelenler dahil, ekran yeniden hesaplanır.
struct ContextVersion: DynamicProperty {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var tracker = Tracker()

    var version: Int { tracker.version }

    func update() {
        tracker.observe(context)
    }

    final class Tracker: ObservableObject {
        @Published private(set) var version = 0
        private weak var context: NSManagedObjectContext?
        private var subscription: AnyCancellable?

        func observe(_ context: NSManagedObjectContext) {
            guard context !== self.context else { return }
            self.context = context
            subscription = NotificationCenter.default
                .publisher(for: NSManagedObjectContext.didChangeObjectsNotification, object: context)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.version += 1 }
        }
    }
}
