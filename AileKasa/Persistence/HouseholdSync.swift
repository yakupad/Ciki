import CoreData

/// iCloud eşitlemesinden sonra birden fazla hane kaydı oluşursa onları tek haneye indirir.
enum HouseholdSync {
    enum Outcome: Equatable {
        case nothing
        /// Eşin hanesine katıldık ama bu cihazda kendi kayıtlarımız var; kullanıcıya sorulmalı.
        case localDataNeedsDecision(NSManagedObjectID)
    }

    /// - Eşin paylaştığı hane varsa: bu cihazdaki boş haneler silinir; dolu hane için karar istenir.
    /// - Yoksa: aynı depodaki fazladan haneler (ör. ikinci cihazda ilk açılışta oluşan) en eskisine taşınır.
    @discardableResult
    static func resolve(in context: NSManagedObjectContext) -> Outcome {
        let request = NSFetchRequest<Household>(entityName: "Household")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let households = (try? context.fetch(request)) ?? []
        guard households.count > 1 else { return .nothing }

        if households.contains(where: \.isInSharedStore) {
            var outcome = Outcome.nothing
            for local in households where !local.isInSharedStore {
                if local.hasUserData {
                    outcome = .localDataNeedsDecision(local.objectID)
                } else {
                    context.delete(local)
                }
            }
            context.saveIfNeeded()
            return outcome
        }

        let keep = households.max { lhs, rhs in
            // En çok kalemi olan; eşitse en eski.
            (lhs.itemsArray.count, rhs.createdAt ?? .distantFuture) < (rhs.itemsArray.count, lhs.createdAt ?? .distantFuture)
        } ?? households[0]
        for duplicate in households where duplicate != keep && duplicate.objectID.persistentStore == keep.objectID.persistentStore {
            merge(duplicate, into: keep, in: context)
        }
        context.saveIfNeeded()
        return .nothing
    }

    /// Aynı depodaki iki haneyi birleştirir: kayıtlar taşınır, aynı adlı kişiler tek kişi olur.
    static func merge(_ source: Household, into target: Household, in context: NSManagedObjectContext) {
        let people = target.peopleArray
        for person in source.peopleArray {
            if let match = people.first(where: { Banks.key($0.displayName) == Banks.key(person.displayName) }) {
                for item in (person.items as? Set<LedgerItem>) ?? [] { item.owner = match }
                for account in (person.accounts as? Set<Account>) ?? [] { account.owner = match }
                context.delete(person)
            } else {
                person.household = target
            }
        }
        for item in source.itemsArray { item.household = target }
        for account in source.accountsArray { account.household = target }
        context.delete(source)
    }

    /// Farklı depolardaki haneler arasında kopyalama: bu cihazdaki kayıtlar eşin paylaştığı haneye kopyalanır,
    /// ardından yerel hane silinir. Depolar arası ilişki kurulamadığı için nesneler taşınmaz, kopyalanır.
    static func copy(_ source: Household, into target: Household, in context: NSManagedObjectContext) {
        var people: [NSManagedObjectID: Person] = [:]
        for person in source.peopleArray {
            if let match = target.peopleArray.first(where: { Banks.key($0.displayName) == Banks.key(person.displayName) }) {
                people[person.objectID] = match
            } else {
                let clone: Person = duplicate(person, in: context, household: target)
                clone.household = target
                clone.sortOrder = Int16(target.peopleArray.count)
                people[person.objectID] = clone
            }
        }

        var accounts: [NSManagedObjectID: Account] = [:]
        for account in source.accountsArray {
            let clone: Account = duplicate(account, in: context, household: target)
            clone.household = target
            clone.owner = account.owner.flatMap { people[$0.objectID] }
            accounts[account.objectID] = clone
        }

        var order = (target.itemsArray.map(\.sortOrder).max() ?? 0)
        for item in source.itemsArray {
            let clone: LedgerItem = duplicate(item, in: context, household: target)
            order += 1
            clone.sortOrder = order
            clone.household = target
            clone.owner = item.owner.flatMap { people[$0.objectID] }
            clone.payee = item.payee.flatMap { accounts[$0.objectID] }
            for entry in item.entriesArray {
                let entryClone: LedgerEntry = duplicate(entry, in: context, household: target)
                entryClone.item = clone
            }
        }
        context.delete(source)
        context.saveIfNeeded()
    }

    /// Özniteliklerin hepsi kopyalanır, kimlik (uuid) yenilenir; ilişkiler çağıran tarafından kurulur.
    private static func duplicate<T: NSManagedObject>(_ object: T, in context: NSManagedObjectContext,
                                                      household: Household) -> T {
        let clone = T(entity: object.entity, insertInto: context)
        context.place(clone, in: household)
        for name in object.entity.attributesByName.keys {
            clone.setValue(object.value(forKey: name), forKey: name)
        }
        clone.setValue(UUID(), forKey: "uuid")
        return clone
    }
}
