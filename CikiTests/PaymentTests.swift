import CoreData
import Testing
@testable import Ciki

/// Kısmi ödeme, önceki aylardan devreden kalan ve nakit varlık.
@MainActor
struct PaymentTests {
    let context = PersistenceController(inMemory: true).viewContext
    let rates = RateTable(usd: 40, eur: 50)
    let september = Month(year: 2026, month: 9)
    var october: Month { september.adding(1) }

    private func makeItem(kind: ItemKind = .card, recurring: Decimal? = nil) -> LedgerItem {
        let item = LedgerItem(context: context)
        item.uuid = UUID()
        item.kind = kind
        item.direction = kind.defaultDirection
        item.currency = .tl
        if let recurring {
            item.isRecurring = true
            item.recurringAmountValue = recurring
        }
        return item
    }

    private func line(_ item: LedgerItem, _ month: Month) -> LedgerLine {
        Ledger.line(for: item, month: month, rates: rates)!
    }

    @Test func partialPaymentLeavesRemainderPending() {
        let card = makeItem()
        context.upsertEntry(item: card, month: october, amount: 50000, status: .pending, rates: rates)
        context.addPayment(30000, to: line(card, october), rates: rates)

        let partial = line(card, october)
        #expect(partial.status == .pending)
        #expect(partial.isPartiallyPaid)
        #expect(partial.paid == 30000)
        #expect(partial.remaining == 20000)
        // Ay gideri tam tutardır; ödenmemiş yalnızca kalan.
        let summary = Ledger.summary(of: [partial])
        #expect(summary.expense == 50000)
        #expect(summary.unpaidExpense == 20000)

        context.addPayment(20000, to: partial, rates: rates)
        let paid = line(card, october)
        #expect(paid.status == .paid)
        #expect(paid.remaining == 0)
        #expect(Ledger.summary(of: [paid]).unpaidExpense == 0)
    }

    @Test func removingPaymentReopensPaidEntry() {
        let card = makeItem()
        context.upsertEntry(item: card, month: october, amount: 1000, status: .pending, rates: rates)
        let entry = context.addPayment(1000, to: line(card, october), rates: rates)
        #expect(entry.status == .paid)

        context.removePayment(entry.paymentList[0], from: entry, rates: rates)
        #expect(entry.status == .pending)
        #expect(entry.remainingValue == 1000)
    }

    @Test func unpaidEntriesFromEarlierMonthsAreListed() {
        let card = makeItem()
        let rent = makeItem(kind: .rent)
        context.upsertEntry(item: card, month: september, amount: 50000, status: .pending, rates: rates)
        context.addPayment(30000, to: line(card, september), rates: rates)
        context.upsertEntry(item: rent, month: september, amount: 20000, status: .paid, rates: rates)

        let carried = Ledger.carryOver(before: october, items: [card, rent], rates: rates)
        #expect(carried.count == 1)
        #expect(carried.first?.item == card)
        #expect(carried.first?.remainingSignedValue == -20000)
        // Gelecekteki ya da aynı aydaki kayıtlar devreden sayılmaz.
        #expect(Ledger.carryOver(before: september, items: [card, rent], rates: rates).isEmpty)
    }

    @Test func carryingOverMovesRemainderWithoutDoubleCounting() {
        let card = makeItem()
        context.upsertEntry(item: card, month: september, amount: 50000, status: .pending, rates: rates)
        context.addPayment(30000, to: line(card, september), rates: rates)
        context.upsertEntry(item: card, month: october, amount: 45000, status: .pending, rates: rates)

        context.carryOver(line(card, september), to: october, rates: rates)

        let source = line(card, september)
        #expect(source.amount == 30000)
        #expect(source.remaining == 0)
        let target = line(card, october)
        #expect(target.amount == 65000)
        #expect(target.remaining == 65000)
        #expect(Ledger.carryOver(before: october, items: [card], rates: rates).isEmpty)
        // İki ayın toplam gideri ilk tutarların toplamıdır.
        let total = Ledger.summary(of: [source]).expense + Ledger.summary(of: [target]).expense
        #expect(total == 95000)
    }

    @Test func carryingIntoEmptyMonthCreatesEntryAndUndoRemovesIt() {
        let card = makeItem()
        context.upsertEntry(item: card, month: september, amount: 12000, status: .pending, rates: rates)
        context.carryOver(line(card, september), to: october, rates: rates)
        #expect(card.entry(for: october)?.dueValue == 12000)

        let source = card.entry(for: september)!
        context.undoCarry(of: source, rates: rates)
        #expect(card.entry(for: october) == nil)
        #expect(source.remainingValue == 12000)
        #expect(source.carriedToKey == 0)
    }

    @Test func carryingIntoRecurringMonthKeepsItsAmount() {
        let loan = makeItem(kind: .loan, recurring: 6850)
        context.upsertEntry(item: loan, month: september, amount: 6850, status: .pending, rates: rates)
        context.carryOver(line(loan, september), to: october, rates: rates)
        #expect(line(loan, october).amount == 13700)
        #expect(line(loan, october).isProjected == false)
    }

    @Test func deletingTargetReturnsCarriedAmountToSource() {
        let card = makeItem()
        context.upsertEntry(item: card, month: september, amount: 5000, status: .pending, rates: rates)
        context.carryOver(line(card, september), to: october, rates: rates)
        context.deleteEntry(card.entry(for: october)!, rates: rates)

        #expect(card.entry(for: september)?.remainingValue == 5000)
        #expect(card.entry(for: september)?.carriedToKey == 0)
    }

    @Test func pendingIncomingCountsOnlyWhatHasNotArrived() {
        let salary = makeItem(kind: .salary)
        let receivable = makeItem(kind: .receivable)
        let rent = makeItem(kind: .rent)
        context.upsertEntry(item: salary, month: october, amount: 80000, status: .paid, rates: rates)
        context.upsertEntry(item: receivable, month: october, amount: 10000, status: .pending, rates: rates)
        context.addPayment(4000, to: line(receivable, october), rates: rates)
        context.upsertEntry(item: rent, month: october, amount: 20000, status: .pending, rates: rates)

        let summary = Ledger.summary(of: Ledger.lines(for: october, items: [salary, receivable, rent], rates: rates))
        #expect(summary.income + summary.receivable == 90000)
        #expect(summary.pendingIncoming == 6000)
        #expect(summary.unpaidExpense == 20000)
    }

    @Test func cashPositionSumsOwnBalancesInDisplayCurrency() {
        func account(_ balance: Decimal?, _ currency: Currency = .tl, own: Bool = true) {
            let account = Account(context: context)
            account.isOwn = own
            account.currency = currency
            account.balanceValue = balance
            account.balanceUpdatedAt = balance == nil ? nil : .now
        }
        account(10000)
        account(100, .usd)
        account(nil)
        account(99999, own: false)
        account(5, Currency(code: "CHF"))

        let request = NSFetchRequest<Account>(entityName: "Account")
        let position = Ledger.cash(in: (try? context.fetch(request)) ?? [], rates: rates)
        #expect(position.total == 14000)
        #expect(position.accountCount == 3)
        #expect(position.missingRateCount == 1)
    }
}
