import CoreData

/// Bu telefonu kullanan kişi. Değişikliklerde "kim yaptı" bilgisi için cihaza özel saklanır.
enum DeviceOwner {
    static let key = "device.personUUID"

    static func person(in context: NSManagedObjectContext) -> Person? {
        guard let raw = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: raw) else { return nil }
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    static func name(in context: NSManagedObjectContext) -> String? {
        person(in: context)?.displayName
    }
}
