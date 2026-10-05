import CoreData
import Testing
@testable import AileKasa

@MainActor
struct LedgerTests {
    let context = PersistenceController(inMemory: true).viewContext
    let rates = RateTable(usd: 40, eur: 50)
    let october = Month(year: 2026, month: 10)

    private func makeItem(kind: ItemKind = .card, currency: Currency = .tl,
                          recurring: Decimal? = nil, start: Month? = nil, end: Month? = nil) -> LedgerItem {
        let item = LedgerItem(context: context)
        item.uuid = UUID()
        item.kind = kind
        item.direction = kind.defaultDirection
        item.currency = currency
        if let recurring {
            item.isRecurring = true
            item.recurringAmountValue = recurring
            item.recurringStart = start?.key ?? 0
            item.recurringEnd = end?.key ?? 0
        }
        return item
    }

    @Test func monthArithmeticCrossesYearBoundary() {
        let december = Month(year: 2026, month: 12)
        #expect(december.adding(1) == Month(year: 2027, month: 1))
        #expect(december.adding(1).title(in: .turkish) == "Ocak 2027")
        #expect(Month(year: 2027, month: 1).adding(-1).title(in: .turkish) == "Aralık 2026")
        #expect(december.title(in: .english) == "December 2026")
        #expect(october.distance(to: december) == 2)
    }

    @Test func recurringItemIsProjectedOnlyWithinItsRange() {
        let item = makeItem(kind: .housing, recurring: 47875, start: october, end: october.adding(2))
        #expect(Ledger.line(for: item, month: october.adding(-1), rates: rates) == nil)
        #expect(Ledger.line(for: item, month: october.adding(3), rates: rates) == nil)

        let line = Ledger.line(for: item, month: october.adding(1), rates: rates)
        #expect(line?.isProjected == true)
        #expect(line?.signedValue == -47875)
    }

    @Test func entryOverridesRecurringAmount() {
        let item = makeItem(kind: .salary, recurring: 42320, start: october)
        context.upsertEntry(item: item, month: october, amount: 210000, status: .paid, rates: rates)
        let line = Ledger.line(for: item, month: october, rates: rates)
        #expect(line?.isProjected == false)
        #expect(line?.signedValue == 210000)
    }

    @Test func excludedEntriesDoNotCountAndPaidEntriesDo() {
        let card = makeItem()
        let housing = makeItem(kind: .housing)
        let salary = makeItem(kind: .salary)
        context.upsertEntry(item: card, month: october, amount: 1000, status: .paid, rates: rates)
        context.upsertEntry(item: housing, month: october, amount: 47875, status: .excluded, rates: rates)
        context.upsertEntry(item: salary, month: october, amount: 5000, status: .pending, rates: rates)

        let summary = Ledger.summary(of: Ledger.lines(for: october, items: [card, housing, salary], rates: rates))
        #expect(summary.expense == 1000)
        #expect(summary.income == 5000)
        #expect(summary.net == 4000)
        #expect(summary.unpaidExpense == 0)
    }

    @Test func foreignCurrencyUsesCurrentRateUntilPaid() {
        let item = makeItem(kind: .family, currency: .eur, recurring: 52319, start: october)
        #expect(Ledger.line(for: item, month: october, rates: rates)?.signedValue == -57500)

        let line = Ledger.line(for: item, month: october, rates: rates)!
        context.setStatus(.paid, for: line, rates: rates)

        // Kur sonradan değişse de ödenmiş kayıt ödeme günündeki kurla kalır.
        let laterRates = RateTable(usd: 45, eur: 60)
        #expect(Ledger.line(for: item, month: october, rates: laterRates)?.signedValue == -57500)
        #expect(Ledger.line(for: item, month: october.adding(1), rates: laterRates)?.signedValue == -69000)
    }

    @Test func missingRateIsReportedInsteadOfCounted() {
        let item = makeItem(kind: .family, currency: .usd, recurring: 30, start: october)
        let summary = Ledger.summary(of: Ledger.lines(for: october, items: [item], rates: RateTable()))
        #expect(summary.missingRateCount == 1)
        #expect(summary.net == 0)
    }

    @Test func installmentsSplitWithoutLosingKurus() {
        let parts = Ledger.split(1000, into: 3)
        #expect(parts == [333.33, 333.33, 333.34])
        #expect(parts.reduce(0, +) == 1000)
        #expect(Ledger.split(500, into: 1) == [500])
    }

    @Test func ownerTotalsSeparateSharedItems() {
        let household = context.currentHousehold()
        let deniz = household.peopleArray[0]
        let card = makeItem()
        card.owner = deniz
        let receivable = makeItem(kind: .receivable)
        context.upsertEntry(item: card, month: october, amount: 18989, status: .pending, rates: rates)
        context.upsertEntry(item: receivable, month: october, amount: 44542, status: .pending, rates: rates)

        let summary = Ledger.summary(of: Ledger.lines(for: october, items: [card, receivable], rates: rates))
        #expect(summary.net(for: deniz) == -18989)
        #expect(summary.net(for: nil) == 44542)
    }

    @Test func moneyFormatsInTurkish() {
        let turkish = Locale(identifier: "tr_TR")
        #expect(Money.string(-18989, locale: turkish) == "−18989 ₺")
        #expect(Money.string(42320, sign: .always, locale: turkish) == "+42320 ₺")
        #expect(Money.string(52319, currency: .eur, locale: turkish) == "52319 €")
        #expect(Money.compact(-30099, locale: turkish) == "−45653")
        #expect(Money.string(-18989, locale: Locale(identifier: "en_US")) == "−18989 ₺")
    }

    @Test func copyEntriesSkipsRecurringAndExisting() {
        let card = makeItem()
        let housing = makeItem(kind: .housing, recurring: 47875, start: october)
        context.upsertEntry(item: card, month: october, amount: 1200, status: .paid, rates: rates)
        context.upsertEntry(item: housing, month: october, amount: 47875, status: .paid, rates: rates)

        let copied = context.copyEntries(from: october, to: october.adding(1), items: [card, housing], rates: rates)
        #expect(copied == 1)
        #expect(card.entry(for: october.adding(1))?.status == .pending)
        #expect(housing.entry(for: october.adding(1)) == nil)
    }

    @Test func tcmbParserReadsForexSelling() throws {
        let xml = """
        <Tarih_Date Tarih="05.10.2026">
          <Currency CrossOrder="0" Kod="USD" CurrencyCode="USD"><Unit>1</Unit><ForexBuying>41.10</ForexBuying><ForexSelling>41.2034</ForexSelling></Currency>
          <Currency CrossOrder="9" Kod="EUR" CurrencyCode="EUR"><Unit>1</Unit><ForexBuying>48.20</ForexBuying><ForexSelling>48.3012</ForexSelling></Currency>
        </Tarih_Date>
        """
        let table = try TCMBParser.parse(Data(xml.utf8))
        #expect(table.usd == Decimal(string: "41.2034"))
        #expect(table.eur == Decimal(string: "48.3012"))
    }

    @Test func suggestionsOfferPreviousMonthAverageAndRecurring() {
        let item = makeItem(kind: .housing, recurring: 47875, start: october.adding(-3))
        context.upsertEntry(item: item, month: october.adding(-3), amount: 1000, status: .paid, rates: rates)
        context.upsertEntry(item: item, month: october.adding(-2), amount: 2000, status: .paid, rates: rates)
        context.upsertEntry(item: item, month: october.adding(-1), amount: 3000, status: .paid, rates: rates)
        context.upsertEntry(item: item, month: october, amount: 9999, status: .pending, rates: rates)

        let suggestions = Ledger.suggestions(for: item, before: october)
        #expect(suggestions.map(\.amount) == [3000, 2000, 47875])
        #expect(suggestions.first?.label == String(localized: "Geçen ay"))
    }

    @Test func suggestionsSkipExcludedAndDuplicateAmounts() {
        let item = makeItem()
        context.upsertEntry(item: item, month: october.adding(-2), amount: 500, status: .excluded, rates: rates)
        context.upsertEntry(item: item, month: october.adding(-1), amount: 700, status: .paid, rates: rates)

        let suggestions = Ledger.suggestions(for: item, before: october)
        #expect(suggestions.map(\.amount) == [700])
    }

    @Test func reorderWithinSubsetKeepsOtherSlots() {
        // a, B, c, D, e: büyük harfler bir bölüm. D'yi B'nin önüne taşı.
        let all = ["a", "B", "c", "D", "e"]
        let result = Ledger.reorder(all, subset: ["B", "D"], from: IndexSet(integer: 1), to: 0)
        #expect(result == ["a", "D", "c", "B", "e"])
    }

    @Test func totalsGroupDebtByBankAndTrackPending() {
        let card = makeItem()
        card.bank = "YapıKredi"
        let rent = makeItem(kind: .rent)
        let salary = makeItem(kind: .salary)
        context.upsertEntry(item: card, month: october, amount: 1000, status: .pending, rates: rates)
        context.upsertEntry(item: rent, month: october, amount: 500, status: .paid, rates: rates)
        context.upsertEntry(item: salary, month: october, amount: 3000, status: .paid, rates: rates)

        let totals = Ledger.totals(for: [october], items: [card, rent, salary], rates: rates)[0]
        #expect(totals.expense == 1500)
        #expect(totals.incoming == 3000)
        #expect(totals.net == 1500)
        #expect(totals.debtByBank == ["YapıKredi": 1000])
        #expect(totals.pendingExpense == 1000)
    }

    @Test func tcmbParserHandlesUnitsAndBanknoteFallback() throws {
        let xml = """
        <Tarih_Date>
          <Currency Kod="JPY"><Unit>100</Unit><ForexSelling>31.1917</ForexSelling><BanknoteSelling>31.3102</BanknoteSelling></Currency>
          <Currency Kod="AED"><Unit>1</Unit><ForexSelling></ForexSelling><BanknoteSelling>13.4322</BanknoteSelling></Currency>
          <Currency Kod="XDR"><Unit>1</Unit><ForexSelling></ForexSelling><BanknoteSelling></BanknoteSelling></Currency>
        </Tarih_Date>
        """
        let table = try TCMBParser.parse(Data(xml.utf8))
        #expect(table.rate(for: Currency(code: "JPY")) == Decimal(string: "0.311917"))
        #expect(table.rate(for: Currency(code: "AED")) == Decimal(string: "13.4322"))
        #expect(table.rates["XDR"] == nil)
        #expect(table.rate(for: .tl) == 1)
    }

    @Test func anyCurrencyConvertsWithItsRate() {
        let item = makeItem(kind: .family, currency: .gbp, recurring: 100, start: october)
        let table = RateTable(rates: ["GBP": 65])
        #expect(Ledger.line(for: item, month: october, rates: table)?.signedValue == -6500)
        #expect(item.currencyCode == "GBP")
    }

    @Test func baseCurrencyConvertsTotalsThroughCrossRates() {
        let table = RateTable(rates: ["EUR": 50, "USD": 40], base: .eur)
        let card = makeItem()
        context.upsertEntry(item: card, month: october, amount: 5000, status: .pending, rates: table)
        let euroItem = makeItem(kind: .family, currency: .eur, recurring: 52319, start: october)
        let dollarItem = makeItem(kind: .family, currency: .usd, recurring: 100, start: october)

        #expect(Ledger.line(for: card, month: october, rates: table)?.signedValue == -100)
        #expect(Ledger.line(for: euroItem, month: october, rates: table)?.signedValue == -52319)
        #expect(Ledger.line(for: dollarItem, month: october, rates: table)?.signedValue == -80)
        #expect(table.rate(for: .tl) == Decimal(string: "0.02"))
    }

    @Test func paidEntryKeepsItsRateInAnyBaseCurrency() {
        let tlTable = RateTable(rates: ["EUR": 50, "USD": 40])
        let dollarItem = makeItem(kind: .family, currency: .usd, recurring: 100, start: october)
        let line = Ledger.line(for: dollarItem, month: october, rates: tlTable)!
        context.setStatus(.paid, for: line, rates: tlTable)
        #expect(dollarItem.entry(for: october)?.rateValue == 40)

        // Dolar sonradan 45 olsa da ödenen 4.000 TL sabit; Euro gösteriminde güncel Euro kuruyla çevrilir.
        let later = RateTable(rates: ["EUR": 50, "USD": 45], base: .eur)
        #expect(Ledger.line(for: dollarItem, month: october, rates: later)?.signedValue == -80)
        // Gösterim birimi kalemin kendi birimiyse tutar aynen kalır.
        let usdBase = RateTable(rates: ["EUR": 50, "USD": 45], base: .usd)
        #expect(Ledger.line(for: dollarItem, month: october, rates: usdBase)?.signedValue == -100)
    }

    @Test func missingBaseRateLeavesValuesUnknown() {
        let table = RateTable(rates: ["EUR": 50], base: .gbp)
        let card = makeItem()
        context.upsertEntry(item: card, month: october, amount: 1000, status: .pending, rates: table)
        let summary = Ledger.summary(of: Ledger.lines(for: october, items: [card], rates: table))
        #expect(summary.missingRateCount == 1)
    }

    @Test func ibanValidationAndFormatting() {
        #expect(IBAN.validate("TR33 0006 1005 1978 6457 8413 26") == .valid)
        #expect(IBAN.validate("tr330006100519786457841326") == .valid)
        #expect(IBAN.validate("TR330006100519786457841327") == .invalid)
        #expect(IBAN.validate("TR3300061") == .incomplete(expected: 26))
        #expect(IBAN.validate("DE89370400440532013000") == .valid)
        #expect(IBAN.validate("") == .empty)
        #expect(IBAN.formatted("TR330006100519786457841326") == "TR33 0006 1005 1978 6457 8413 26")
        #expect(IBAN.normalized(" tr33-0006 1005 ") == "TR3300061005")
    }

    @Test func bankIsDetectedFromTurkishIBAN() {
        #expect(Banks.name(forIBAN: "TR71 0006 7012 3456 7890 1234 56") == "YapıKredi")
        #expect(Banks.name(forIBAN: "DE89370400440532013000") == nil)
    }

    @Test func bankNamesIgnoreCaseAndSpaces() {
        #expect(Banks.key("Yapı Kredi") == Banks.key("YapıKredi"))
        #expect(Banks.key(" İş Bankası ") == Banks.key("İşBankası"))
        #expect(Banks.canonical("yapı kredi") == "YapıKredi")
        #expect(Banks.canonical("Benim Bankam") == "Benim Bankam")
    }

    @Test func monthGroupsMergeDifferentBankSpellings() {
        let first = makeItem()
        first.bank = "Yapı Kredi"
        let second = makeItem(kind: .cashAdvance)
        second.bank = "YAPIKREDİ"
        let custom1 = makeItem()
        custom1.bank = "Benim Bankam"
        let custom2 = makeItem()
        custom2.bank = "benimbankam"
        for item in [first, second, custom1, custom2] {
            context.upsertEntry(item: item, month: october, amount: 100, status: .pending, rates: rates)
        }
        let groups = MonthView.groups(from: Ledger.lines(for: october, items: [first, second, custom1, custom2], rates: rates))
        #expect(groups.map(\.title) == ["YapıKredi", "Benim Bankam"])
        #expect(groups.map(\.lines.count) == [2, 2])
    }

    @Test func remindersSkipPaidPastAndUndatedItems() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!

        let due7 = makeItem(); due7.bank = "YapıKredi"; due7.dueDay = 7
        let due3 = makeItem(); due3.dueDay = 3            // geçmişte kaldı
        let paid = makeItem(); paid.dueDay = 20
        let undated = makeItem()                          // ödeme günü yok
        let salary = makeItem(kind: .salary); salary.dueDay = 15
        for item in [due7, due3, undated, salary] {
            context.upsertEntry(item: item, month: october, amount: 100, status: .pending, rates: rates)
        }
        context.upsertEntry(item: paid, month: october, amount: 100, status: .paid, rates: rates)

        let lines = Ledger.lines(for: october, items: [due7, due3, paid, undated, salary], rates: rates)
        let plan = Reminders.plan(lines: lines, daysBefore: 1, hour: 9, now: now, calendar: calendar)
        #expect(plan.count == 1)
        let reminder = try #require(plan.first)
        #expect(reminder.title == "YapıKredi Kart" || reminder.title == "YapıKredi Card")
        #expect(calendar.dateComponents([.month, .day, .hour], from: reminder.date) == DateComponents(month: 10, day: 6, hour: 9))
    }

    @Test func reminderDueDayClampsToMonthLength() throws {
        let calendar = Calendar(identifier: .gregorian)
        let february = Month(year: 2027, month: 2)
        let item = makeItem(); item.dueDay = 31
        context.upsertEntry(item: item, month: february, amount: 100, status: .pending, rates: rates)
        let lines = Ledger.lines(for: february, items: [item], rates: rates)
        let plan = Reminders.plan(lines: lines, daysBefore: 0, hour: 9, now: .distantPast, calendar: calendar)
        let reminder = try #require(plan.first)
        #expect(calendar.component(.day, from: reminder.date) == 28)
    }

    @Test func csvEscapesFieldsAndUsesTurkishNumbers() {
        let format = CSVExport.Format(separator: ";", locale: Locale(identifier: "tr_TR"))
        let text = CSVExport.csv([["Ad", "Not"], ["Kira; Ekim", "\"özel\" not"]], format)
        #expect(text == "Ad;Not\r\n\"Kira; Ekim\";\"\"\"özel\"\" not\"")
        #expect(CSVExport.number(-18989, format) == "-18989")
        #expect(CSVExport.number(52319, CSVExport.Format(separator: ",", locale: Locale(identifier: "en_US"))) == "52319")
    }

    @Test func csvTableSumsNetAndLeavesExcludedBlank() {
        let format = CSVExport.Format(separator: ";", locale: Locale(identifier: "tr_TR"))
        let card = makeItem(); card.bank = "Akbank"
        let salary = makeItem(kind: .salary)
        context.upsertEntry(item: card, month: october, amount: 300, status: .paid, rates: rates)
        context.upsertEntry(item: card, month: october.adding(1), amount: 50, status: .excluded, rates: rates)
        context.upsertEntry(item: salary, month: october, amount: 1000, status: .paid, rates: rates)

        let rows = CSVExport.table(items: [card, salary], months: [october, october.adding(1)], rates: rates, format: format)
            .components(separatedBy: "\r\n")
        #expect(rows.count == 4)
        #expect(rows[1].hasSuffix(";-300;"))
        #expect(rows[3].hasSuffix(";700;0"))
    }
}
