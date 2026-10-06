import CoreData
import WidgetKit

/// Bu ayın özetini widget'ın okuyacağı App Group alanına yazar.
enum WidgetPublisher {
    static func publish(context: NSManagedObjectContext, rates: RateTable, isPrivate: Bool) {
        let request = NSFetchRequest<LedgerItem>(entityName: "LedgerItem")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        let items = (try? context.fetch(request)) ?? []
        let current = Month.current
        // Saat için geçmiş 3 ve gelecek 6 ay.
        let months = (-3...6).map { summary(of: current.adding($0), items: items, rates: rates, isCurrent: $0 == 0) }
        let now = months.first(where: \.isCurrent)!

        let snapshot = WidgetSnapshot(
            monthTitle: now.title,
            net: now.net,
            netIsNegative: now.netIsNegative,
            incoming: now.incoming,
            expense: now.expense,
            unpaid: now.unpaid,
            upcoming: Array(now.payments.prefix(6)),
            isPrivate: isPrivate,
            updatedAt: .now,
            months: months
        )
        guard snapshot != WidgetSnapshot.load().map({ var old = $0; old.updatedAt = snapshot.updatedAt; return old }) else {
            return
        }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        #if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
        WatchSync.shared.send(snapshot)
        #endif
    }

    /// Bir ayın özeti ve o ay bekleyen ödemeleri (en fazla 12).
    private static func summary(of month: Month, items: [LedgerItem], rates: RateTable, isCurrent: Bool) -> WidgetSnapshot.MonthSummary {
        let lines = Ledger.lines(for: month, items: items, rates: rates)
        let summary = Ledger.summary(of: lines)
        let payments = lines
            .filter { $0.direction == .expense && $0.status == .pending && $0.amount > 0 && $0.item.dueDay > 0 }
            .compactMap { line -> WidgetSnapshot.Payment? in
                let day = month.clampedDay(Int(line.item.dueDay))
                guard let due = Calendar.current.date(from: DateComponents(year: month.year, month: month.month, day: day)) else {
                    return nil
                }
                let key = "\(line.item.objectID.uriRepresentation().absoluteString)|\(line.month.key)"
                return WidgetSnapshot.Payment(key: key, title: line.item.fullTitle, owner: line.item.ownerName,
                                              amount: Money.string(-line.amount, currency: line.currency),
                                              dueDate: due)
            }
            .sorted { $0.dueDate < $1.dueDate }
        return WidgetSnapshot.MonthSummary(
            key: month.key, title: month.title,
            net: Money.string(summary.net, sign: .always, fractions: false),
            netIsNegative: summary.net < 0,
            incoming: Money.string(summary.income + summary.receivable, fractions: false),
            expense: Money.string(summary.expense, fractions: false),
            unpaid: Money.string(summary.unpaidExpense, fractions: false),
            payments: Array(payments.prefix(12)),
            isCurrent: isCurrent)
    }
}
