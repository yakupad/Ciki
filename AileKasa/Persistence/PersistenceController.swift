import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        SampleData.load(into: controller.container.viewContext)
        return controller
    }()

    /// Model bir kez yüklenir; aynı süreçte birden fazla container (testler, önizlemeler)
    /// aynı NSManagedObject alt sınıflarını paylaşabilsin diye.
    private static let model: NSManagedObjectModel = {
        let bundle = Bundle(for: PersistenceController.self)
        guard let url = bundle.url(forResource: "AileKasa", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("AileKasa.momd bulunamadı")
        }
        return model
    }()

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "AileKasa", managedObjectModel: Self.model)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Kalıcı depo tanımı bulunamadı")
        }
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        // iCloud eşitlemesi Aşama 3'te açılacak (CloudKit container ve yetkiler gerekiyor).
        description.cloudKitContainerOptions = nil
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Veri deposu açılamadı: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }
}

extension NSManagedObjectContext {
    /// Hanenin tek kaydı. İlk açılışta iki kişiyle birlikte oluşturulur.
    @discardableResult
    func currentHousehold() -> Household {
        let request = NSFetchRequest<Household>(entityName: "Household")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.fetchLimit = 1
        if let existing = try? fetch(request).first {
            return existing
        }

        let household = Household(context: self)
        household.uuid = UUID()
        household.name = "Evimiz"
        household.createdAt = .now

        for (index, (name, color)) in [("Deniz", "3D5FD9"), ("Ece", "C23F7B")].enumerated() {
            let person = Person(context: self)
            person.uuid = UUID()
            person.name = name
            person.colorHex = color
            person.sortOrder = Int16(index)
            person.household = household
        }
        saveIfNeeded()
        return household
    }

    func saveIfNeeded() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            rollback()
            print("Kaydedilemedi: \(error)")
        }
    }

    func nextItemSortOrder() -> Int32 {
        let request = NSFetchRequest<LedgerItem>(entityName: "LedgerItem")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
        request.fetchLimit = 1
        return ((try? fetch(request).first?.sortOrder) ?? 0) + 1
    }
}
