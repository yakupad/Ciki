import CoreData

/// Önizlemeler, deneme ve tanıtım görselleri için **tamamen kurgusal** örnek hane: Deniz ve Ece.
/// İsimler, bankalar ve tutarlar uydurmadır; gerçek kişi ya da kurumlarla ilgisi yoktur.
/// Aylar ve ödeme günleri bugüne göre hesaplanır, böylece görseller hangi gün alınırsa alınsın
/// "bu ay ödenecekler" listesinde bugün ve yakın günler görünür.
enum SampleData {
    static func load(into context: NSManagedObjectContext) {
        let household = context.currentHousehold()
        household.name = String(localized: "Evimiz")
        // Önceki kişiler (gerçek isimler olabilir) tanıtım görsellerine sızmasın diye her zaman kurgusal haneyle başla.
        wipe(context)
        for person in household.peopleArray {
            context.delete(person)
        }
        context.processPendingChanges()
        context.addPerson(named: "Deniz", to: household).relation = nil
        context.addPerson(named: "Ece", to: household).relation = .partner
        let people = household.peopleArray
        let deniz = people.first
        let ece = people.dropFirst().first
        let rates = RateTable(usd: 41, eur: 48)

        let now = Month.current
        let today = Calendar.current.component(.day, from: .now)
        /// Bugünden `offset` gün sonraki ayın günü (1…28).
        func due(_ offset: Int) -> Int16 { Int16(min(max(today + offset, 1), 28)) }

        var order: Int32 = 0
        func item(_ name: String?, bank: String? = nil, kind: ItemKind, owner: Person?,
                  dueDay: Int16 = 0, currency: Currency = .tl,
                  recurring: Decimal? = nil, from start: Month? = nil) -> LedgerItem {
            order += 1
            let item = LedgerItem(context: context)
            context.place(item, in: household)
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
            item.household = household
            if let recurring {
                item.isRecurring = true
                item.recurringAmountValue = recurring
                item.recurringStart = start?.key ?? 0
            }
            return item
        }

        /// Geçmiş aylar ödenmiş; bu ay, günü geçmişse ödenmiş, değilse bekliyor.
        func add(_ item: LedgerItem, _ offset: Int, _ amount: Decimal, _ status: EntryStatus? = nil) {
            let month = now.adding(offset)
            let resolved = status ?? (offset < 0 || (offset == 0 && Int(item.dueDay) < today && item.dueDay > 0) ? .paid : .pending)
            context.upsertEntry(item: item, month: month, amount: amount, status: resolved, rates: rates)
        }

        // Deniz
        let maviCard = item(nil, bank: "Mavi Bank", kind: .card, owner: deniz, dueDay: due(0))
        for (offset, amount) in [(-5, 7_840.20), (-4, 9_215.60), (-3, 6_480.00), (-2, 8_420.50), (-1, 9_115.30), (0, 11_240.75), (1, 4_180.00)] {
            add(maviCard, offset, Decimal(amount))
        }
        let adaCard = item(nil, bank: "Ada Bank", kind: .card, owner: deniz, dueDay: due(3))
        for (offset, amount) in [(-4, 2_150.00), (-3, 3_480.90), (-2, 3_250.00), (-1, 2_980.40), (0, 3_615.20), (1, 1_240.00)] {
            add(adaCard, offset, Decimal(amount))
        }
        let adaLoan = item("İhtiyaç kredisi", bank: "Ada Bank", kind: .loan, owner: deniz, dueDay: due(6),
                           recurring: 6_850, from: now.adding(-5))
        for offset in -5...(-1) { add(adaLoan, offset, 6_850) }

        let denizSalary = item(nil, kind: .salary, owner: deniz, recurring: 68_500, from: now.adding(-5))
        for offset in -5...(-1) { add(denizSalary, offset, 68_500) }

        // Ece
        let yildizCard = item(nil, bank: "Yıldız Bank", kind: .card, owner: ece, dueDay: due(1))
        for (offset, amount) in [(-5, 4_120.00), (-4, 3_870.45), (-3, 5_015.00), (-2, 4_640.80), (-1, 5_430.00), (0, 6_210.90), (1, 2_350.00)] {
            add(yildizCard, offset, Decimal(amount))
        }
        let eceSalary = item(nil, kind: .salary, owner: ece, recurring: 54_000, from: now.adding(-5))
        for offset in -5...(-1) { add(eceSalary, offset, 54_000) }

        // Ortak
        let rent = item(nil, kind: .rent, owner: nil, dueDay: 1, recurring: 24_000, from: now.adding(-5))
        for offset in -5...0 { add(rent, offset, 24_000) }

        let savings = item("Ev birikimi", kind: .housing, owner: nil, dueDay: due(8), recurring: 10_000, from: now.adding(-5))
        for offset in -5...(-1) { add(savings, offset, 10_000) }
        add(savings, 0, 10_000, .excluded)

        let dues = item("Aidat", kind: .bill, owner: nil, dueDay: due(4), recurring: 1_850, from: now.adding(-5))
        for offset in -5...(-1) { add(dues, offset, 1_850) }

        let electricity = item("Elektrik", kind: .bill, owner: nil, dueDay: due(2))
        for (offset, amount) in [(-5, 1_420.00), (-4, 1_265.40), (-3, 980.00), (-2, 1_140.60), (-1, 1_012.30), (0, 1_065.00)] {
            add(electricity, offset, Decimal(amount))
        }
        let internet = item("İnternet", kind: .bill, owner: nil, dueDay: due(5), recurring: 649, from: now.adding(-5))
        for offset in -5...(-1) { add(internet, offset, 649) }

        let allowance = item("Kardeş harçlığı", kind: .family, owner: nil, dueDay: due(7),
                             currency: .eur, recurring: 150, from: now.adding(-3))
        for offset in -3...(-1) { add(allowance, offset, 150) }

        let receivable = item("Emre'den alacak", kind: .receivable, owner: nil)
        add(receivable, -1, 5_000)
        add(receivable, 0, 7_500, .pending)

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

    #if DEBUG
    /// Başka bir cihazdan iCloud ile gelmiş gibi bir değişiklik: 8 saniye sonra arka plan bağlamında
    /// "Kira" kaleminin düzenli tutarı 26.000 yapılır. Ekranların kendiliğinden yenilendiğini sınamak için.
    static func simulateRemoteChange(in container: NSPersistentCloudKitContainer) {
        let rentKind = ItemKind.rent.rawValue
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            container.performBackgroundTask { @Sendable context in
                let request = NSFetchRequest<LedgerItem>(entityName: "LedgerItem")
                request.predicate = NSPredicate(format: "kindRaw == %@", rentKind)
                guard let rent = try? context.fetch(request).first else { return }
                rent.recurringAmount = NSDecimalNumber(value: 26_000)
                try? context.save()
            }
        }
    }
    #endif
}
