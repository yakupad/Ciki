import SwiftUI
import CoreData

/// Tüm kalemler: düzenli ödemeler, düzenli gelirler, diğerleri ve arşiv.
struct ItemsView: View {
    @Environment(RateService.self) private var rates
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder), SortDescriptor(\LedgerItem.createdAt)])
    private var items: FetchedResults<LedgerItem>

    @State private var route: EditorRoute?

    var body: some View {
        let active = items.filter { !$0.isArchived }
        let recurringExpense = active.filter { $0.isRecurring && $0.direction == .expense }
        let recurringIncome = active.filter { $0.isRecurring && $0.direction != .expense }
        let others = active.filter { !$0.isRecurring }
        let archived = items.filter(\.isArchived)

        List {
            Section {
                RateCard()
            }

            if items.isEmpty {
                ContentUnavailableView {
                    Label("Henüz kalem yok", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Her kart, kredi, kira, maaş ya da düzenli gönderim bir kalemdir.")
                } actions: {
                    Button("Kalem ekle") { route = .newItem }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }

            section("Düzenli ödemeler", recurringExpense)
            section("Düzenli gelirler", recurringIncome)
            section("Diğer kalemler", others, showsReorderHint: true)
            section("Arşiv", archived)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .readableWidth()
        .background(Color.zemin)
        .navigationTitle("Kalemler")
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Yeni kalem", systemImage: "plus") { route = .newItem }
                    .labelStyle(.titleAndIcon)
            }
        }
        .sheet(item: $route) { EditorSheet(route: $0) }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ items: [LedgerItem], showsReorderHint: Bool = false) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.objectID) { item in
                    Button { route = .item(item) } label: { ItemRow(item: item, rates: rates.table) }
                        .buttonStyle(.plain)
                }
                .onMove { source, destination in
                    move(items, from: source, to: destination)
                }
            } header: {
                Text(title).foregroundStyle(Color.ikincil)
            } footer: {
                if showsReorderHint {
                    Text("Sırayı değiştirmek için Düzenle'ye dokunup kalemleri sürükleyin. Aylar ve Tablo ekranları bu sırayı kullanır.")
                }
            }
        }
    }
}

extension ItemsView {
    /// Bölüm içindeki yeni sırayı tüm kalemlerin `sortOrder` değerine yazar.
    private func move(_ subset: [LedgerItem], from source: IndexSet, to destination: Int) {
        let ordered = Ledger.reorder(Array(items), subset: subset, from: source, to: destination)
        for (index, item) in ordered.enumerated() where item.sortOrder != Int32(index + 1) {
            item.sortOrder = Int32(index + 1)
        }
        context.saveIfNeeded()
    }
}

private struct ItemRow: View {
    let item: LedgerItem
    let rates: RateTable

    var body: some View {
        HStack(spacing: 12) {
            ItemBadge(item: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fullTitle).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Color.ikincil).lineLimit(2)
            }
            Spacer()
            if item.isRecurring, let amount = item.recurringAmount(in: .current) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.string(amount * item.direction.sign, currency: item.currency, sign: .always))
                        .font(.amount(14, weight: .semibold))
                        .foregroundStyle(item.direction == .expense ? Color.gider : Color.gelir)
                    if item.currency != rates.base, let rate = rates.rate(for: item.currency) {
                        Text("≈ " + Money.string(amount * rate, fractions: false))
                            .font(.caption2)
                            .foregroundStyle(Color.ikincil)
                            .monospacedDigit()
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = [item.ownerName]
        if item.isRecurring {
            parts.append(item.dueDay > 0
                         ? String(localized: "her ayın \(Int(item.dueDay)). günü")
                         : String(localized: "her ay"))
            if let next = item.amountChanges.first(where: { $0.month > .current }) {
                let amount = Money.string(next.amount, currency: item.currency)
                parts.append(String(localized: "\(next.month.shortTitle) itibarıyla \(amount)"))
            }
            if item.recurringEnd != 0 {
                parts.append(String(localized: "son ay: \(Month(key: item.recurringEnd).title)"))
            }
        } else {
            parts.append(item.kind.title)
            if item.dueDay > 0 { parts.append(String(localized: "SÖT \(Int(item.dueDay))")) }
        }
        return parts.joined(separator: " · ")
    }
}

/// Kalemlerde kullanılan dövizlerin güncel kuru; dokununca tüm kurlar açılır.
struct RateCard: View {
    @Environment(RateService.self) private var rates

    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "currencyCode != %@ AND isArchived == NO", "TRY"))
    private var foreignItems: FetchedResults<LedgerItem>

    /// USD ve EUR her zaman, ardından kalemlerde kullanılan diğer dövizler.
    private var shown: [Currency] {
        var list: [Currency] = [.usd, .eur, .tl]
        for item in foreignItems where !list.contains(item.currency) {
            list.append(item.currency)
        }
        return list.filter { $0 != rates.baseCurrency }
    }

    var body: some View {
        HStack(alignment: .center) {
            NavigationLink {
                AllRatesView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Döviz kuru · TCMB satış")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.ikincil)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) { rateTexts }
                        VStack(alignment: .leading, spacing: 2) { rateTexts }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if let error = rates.errorMessage {
                        Text(error).font(.caption).foregroundStyle(Color.gider)
                    } else if let updated = rates.updatedAt {
                        let date = updated.formatted(.dateTime.day().month().hour().minute().locale(Money.locale))
                        Text("Güncellendi: \(date)")
                            .font(.caption)
                            .foregroundStyle(Color.ikincil)
                    }
                }
            }
            if rates.isLoading {
                ProgressView()
            } else {
                Button("Kuru yenile", systemImage: "arrow.clockwise") {
                    Task { await rates.refresh() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var rateTexts: some View {
        ForEach(shown) { currency in
            Text(verbatim: "\(currency.symbol) \(rates.table.rate(for: currency).map { Money.string($0) } ?? "—")")
                .font(.amount(16, weight: .semibold))
        }
    }
}

/// TCMB'nin yayımladığı tüm kurlar, aranabilir.
struct AllRatesView: View {
    @Environment(RateService.self) private var rates
    @State private var query = ""

    var body: some View {
        let list = Currency.all.filter { $0 != rates.baseCurrency }.filter { currency in
            query.isEmpty
                || currency.code.localizedCaseInsensitiveContains(query)
                || currency.name.localizedCaseInsensitiveContains(query)
        }

        List {
            Section {
                ForEach(list) { currency in
                    HStack {
                        CurrencyLabel(currency: currency)
                        Spacer()
                        Text(verbatim: rates.table.rate(for: currency).map(format) ?? "—")
                            .font(.amount(15, weight: .semibold))
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1 birim döviz için TCMB döviz satış kuru. Satış kuru yayımlanmayan birimlerde efektif satış kullanılır.")
                    if rates.baseCurrency != .tl {
                        Text("Kurlar \(rates.baseCurrency.title) karşılığı olarak, TCMB kurlarından çapraz hesaplanır.")
                    }
                }
            }
        }
        .searchable(text: $query, prompt: Text("Para birimi ara"))
        .navigationTitle("Döviz kurları")
        .refreshable { await rates.refresh() }
    }

    /// Küçük kurlarda (KRW 0,0366) dört ondalığa kadar gösterilir.
    private func format(_ value: Decimal) -> String {
        let digits = value < 1 ? 4 : 2
        let number = value.formatted(.number.locale(Money.locale).precision(.fractionLength(0...digits)))
        return "\(number) \(rates.baseCurrency.symbol)"
    }
}

#Preview {
    NavigationStack { ItemsView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(RateService())
}
