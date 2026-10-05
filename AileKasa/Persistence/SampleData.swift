import CoreData

/// Önizlemeler ve geliştirme için Excel tablosunun Ağustos–Kasım 2026 sütunlarından örnek veri.
enum SampleData {
    static func load(into context: NSManagedObjectContext) {
        let household = context.currentHousehold()
        let people = household.peopleArray
        let deniz = people.first
        let ece = people.dropFirst().first
        let rates = RateTable(usd: 49.06, eur: 55.18)

        let aug = Month(year: 2026, month: 8)
        let sep = aug.adding(1)
        let oct = aug.adding(2)
        let nov = aug.adding(3)

        var order: Int32 = 0
        func item(_ name: String?, bank: String? = nil, kind: ItemKind, owner: Person?,
                  dueDay: Int16 = 0, currency: Currency = .tl,
                  recurring: Decimal? = nil, from start: Month? = nil) -> LedgerItem {
            order += 1
            let item = LedgerItem(context: context)
            item.uuid = UUID()
            item.createdAt = .now
            item.name = name
            item.bank = bank
            item.kind = kind
            item.direction = kind.defaultDirection
            item.currency = currency
            item.owner = owner
            item.dueDay = dueDay
            item.sortOrder = order
            context.place(item, in: household)
            item.household = household
            if let recurring {
                item.isRecurring = true
                item.recurringAmountValue = recurring
                item.recurringStart = start?.key ?? 0
            }
            return item
        }

        func add(_ item: LedgerItem, _ month: Month, _ amount: Decimal, _ status: EntryStatus = .pending) {
            context.upsertEntry(item: item, month: month, amount: amount, status: status, rates: rates)
        }

        // Deniz
        let ykCard = item(nil, bank: "YapıKredi", kind: .card, owner: deniz, dueDay: 5)
        add(ykCard, aug, 16767, .paid); add(ykCard, sep, 17878, .paid)
        add(ykCard, oct, 18989); add(ykCard, nov, 20100)

        let ykAdvance = item(nil, bank: "YapıKredi", kind: .cashAdvance, owner: deniz, dueDay: 5)
        add(ykAdvance, oct, 10101)

        let isCard = item(nil, bank: "İşBankası", kind: .card, owner: deniz, dueDay: 5)
        add(isCard, aug, 21211, .paid); add(isCard, sep, 22322, .paid)
        add(isCard, oct, 23433); add(isCard, nov, 27877)

        let garantiAdvance = item(nil, bank: "Garanti", kind: .cashAdvance, owner: deniz, dueDay: 3)
        add(garantiAdvance, aug, 53430, .paid)

        let akCard = item(nil, bank: "Akbank", kind: .card, owner: deniz, dueDay: 15)
        add(akCard, aug, 24544, .paid); add(akCard, sep, 24544, .paid); add(akCard, oct, 0, .paid)

        let enpara = item(nil, bank: "Enpara", kind: .card, owner: deniz)
        add(enpara, aug, 890); add(enpara, oct, 32321, .paid)

        let rent = item(nil, kind: .rent, owner: deniz, dueDay: 1)
        add(rent, aug, 46764, .paid); add(rent, sep, 46764, .paid); add(rent, nov, 46764)

        let birikim = item("Birikim", kind: .housing, owner: deniz, dueDay: 20, recurring: 47875, from: aug)
        add(birikim, aug, 47875, .paid); add(birikim, sep, 47875, .paid); add(birikim, oct, 47875, .excluded)

        let konut = item("Konut", kind: .housing, owner: deniz, dueDay: 20, recurring: 40098, from: aug)
        add(konut, aug, 40098, .paid); add(konut, sep, 40098, .paid)

        let denizSalary = item(nil, kind: .salary, owner: deniz, recurring: 42320, from: oct)
        add(denizSalary, aug, 41209, .paid); add(denizSalary, sep, 41209, .paid)

        // Ece
        let tYkCard = item(nil, bank: "YapıKredi", kind: .card, owner: ece, dueDay: 7)
        add(tYkCard, sep, 51208, .paid); add(tYkCard, oct, 28988)

        let tYkAdvance = item(nil, bank: "YapıKredi", kind: .cashAdvance, owner: ece, dueDay: 7)
        add(tYkAdvance, aug, 11212, .paid); add(tYkAdvance, sep, 50097, .paid)

        let tGaranti = item(nil, bank: "Garanti", kind: .card, owner: ece, dueDay: 23)
        add(tGaranti, aug, 25655, .paid)

        _ = item(nil, kind: .salary, owner: ece, recurring: 33432, from: aug)

        // Ortak
        let alacak = item("Alacak", kind: .receivable, owner: nil)
        add(alacak, aug, 43431); add(alacak, sep, 43431)
        add(alacak, oct, 44542); add(alacak, nov, 43431)

        _ = item("Harçlık", kind: .family, owner: nil, dueDay: 5, currency: .eur, recurring: 52319, from: nov)

        context.saveIfNeeded()
    }

    /// Hane dışındaki tüm kalemleri ve kayıtları siler.
    static func wipe(_ context: NSManagedObjectContext) {
        let request = NSFetchRequest<LedgerItem>(entityName: "LedgerItem")
        for item in (try? context.fetch(request)) ?? [] {
            context.delete(item)
        }
        context.saveIfNeeded()
    }
}
