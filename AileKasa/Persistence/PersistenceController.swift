import CoreData
import CloudKit
#if targetEnvironment(macCatalyst)
import Security
#endif

final class PersistenceController {
    static let shared = PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        SampleData.load(into: controller.container.viewContext)
        return controller
    }()

    static let cloudContainerID = "iCloud.com.yakupad.AileKasa"
    /// Başkasının paylaştığı hanenin tutulduğu depo dosyası.
    nonisolated static let sharedStoreFileName = "AileKasa-shared.sqlite"

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

    /// Uygulama iCloud yetkisiyle imzalanmış mı. Yetkisiz bir Mac derlemesinde CloudKit başlatılırsa
    /// macOS uygulamayı kapatır; bu durumda veriler yalnızca yerel tutulur.
    static let isCloudKitAvailable: Bool = {
        #if targetEnvironment(macCatalyst)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains(cloudContainerID) == true
        #else
        return true
        #endif
    }()

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    var viewContext: NSManagedObjectContext { container.viewContext }
    var cloudContainer: CKContainer { CKContainer(identifier: Self.cloudContainerID) }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "AileKasa", managedObjectModel: Self.model)

        guard let privateDescription = container.persistentStoreDescriptions.first else {
            fatalError("Kalıcı depo tanımı bulunamadı")
        }
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if inMemory {
            privateDescription.url = URL(fileURLWithPath: "/dev/null")
            privateDescription.cloudKitContainerOptions = nil
        } else if !Self.isCloudKitAvailable {
            privateDescription.cloudKitContainerOptions = nil
        } else {
            // Kendi verilerimiz: iCloud özel veritabanı. Mevcut AileKasa.sqlite dosyası aynen kullanılır.
            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerID)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions

            // Başkasının bizimle paylaştığı hane: iCloud paylaşılan veritabanı, ayrı dosyada.
            guard let sharedDescription = privateDescription.copy() as? NSPersistentStoreDescription,
                  let directory = privateDescription.url?.deletingLastPathComponent() else {
                fatalError("Paylaşılan depo tanımı oluşturulamadı")
            }
            sharedDescription.url = directory.appending(path: Self.sharedStoreFileName)
            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerID)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions

            container.persistentStoreDescriptions = [privateDescription, sharedDescription]
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Veri deposu açılamadı: \(error)")
            }
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            if store.url?.lastPathComponent == Self.sharedStoreFileName {
                sharedStore = store
            } else {
                privateStore = store
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.transactionAuthor = "app"
    }
}

extension NSManagedObjectContext {
    /// Etkin hane: paylaşılan bir hane varsa o, yoksa bu cihazdaki en eski hane.
    /// Hiç yoksa boş olarak oluşturulur; kişiler ilk açılış ekranında eklenir.
    @discardableResult
    func currentHousehold() -> Household {
        let request = NSFetchRequest<Household>(entityName: "Household")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let households = (try? fetch(request)) ?? []
        if let shared = households.first(where: \.isInSharedStore) {
            return shared
        }
        if let existing = households.first {
            return existing
        }

        let household = Household(context: self)
        household.uuid = UUID()
        household.name = String(localized: "Evimiz")
        household.createdAt = .now
        saveIfNeeded()
        return household
    }

    /// Haneye kişi ekler; renk, diğer kişilerin kullanmadığı paletten seçilir.
    @discardableResult
    func addPerson(named name: String, to household: Household) -> Person {
        let used = Set(household.peopleArray.compactMap { $0.colorHex?.uppercased() })
        let person = Person(context: self)
        place(person, in: household)
        person.uuid = UUID()
        person.name = name
        person.colorHex = Person.palette.first { !used.contains($0) } ?? Person.palette[household.peopleArray.count % Person.palette.count]
        person.sortOrder = Int16((household.peopleArray.map(\.sortOrder).max() ?? -1) + 1)
        person.household = household
        return person
    }

    /// Yeni nesneyi hanenin bulunduğu depoya yerleştirir. Depolar arası ilişki kurulamadığı için
    /// paylaşılan haneye eklenen her kayıt paylaşılan depoya yazılmalıdır.
    func place(_ object: NSManagedObject, in household: Household?) {
        guard let store = household?.objectID.persistentStore, object.objectID.isTemporaryID else { return }
        assign(object, to: store)
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

nonisolated extension Household {
    var isInSharedStore: Bool {
        objectID.persistentStore?.url?.lastPathComponent == PersistenceController.sharedStoreFileName
    }

    var itemsArray: [LedgerItem] {
        ((items as? Set<LedgerItem>) ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var accountsArray: [Account] {
        ((accounts as? Set<Account>) ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Kullanıcının girdiği bir şey var mı (otomatik oluşan iki kişi sayılmaz).
    var hasUserData: Bool {
        !itemsArray.isEmpty || !accountsArray.isEmpty
    }
}
