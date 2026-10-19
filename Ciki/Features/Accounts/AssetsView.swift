import SwiftUI
import CoreData

/// Nakit varlık: kendi hesaplardaki ve eldeki paranın güncel bakiyesi, ödenmemiş borçlar düşülünce kalan.
struct AssetsView: View {
    @Environment(RateService.self) private var rates

    @FetchRequest(sortDescriptors: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)],
                  predicate: NSPredicate(format: "isOwn == YES"))
    private var accounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder)])
    private var items: FetchedResults<LedgerItem>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    /// Bakiye ya da kayıt değişince toplamların yenilenmesi için.
    private let changes = ContextVersion()

    @State private var editing: AccountsView.AccountRoute?

    var body: some View {
        let _ = changes.version
        let position = Ledger.cash(in: accounts, rates: rates.table)
        let unpaid = Self.unpaid(through: .current, items: items, rates: rates.table)

        List {
            Section {
                AssetsCard(position: position, unpaid: unpaid)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if accounts.isEmpty {
                ContentUnavailableView {
                    Label("Henüz hesap yok", systemImage: "banknote")
                } description: {
                    Text("Banka hesaplarınızı ve elinizdeki nakdi ekleyip bakiyelerini girin. Toplam, ödenmemiş borçlarla birlikte burada ve Özet'te görünür.")
                } actions: {
                    Button("Hesap ekle") { editing = .new }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            ForEach(people, id: \.objectID) { person in
                section(Text(verbatim: person.displayName), accounts.filter { $0.owner == person })
            }
            section(Text("Ortak"), accounts.filter { $0.owner == nil })
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .readableWidth()
        .background(Color.zemin)
        .navigationTitle("Varlıklar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Hesap ekle", systemImage: "plus") { editing = .new }
            }
        }
        .sheet(item: $editing) { route in
            switch route {
            case .new: AccountEditorView(account: nil, isOwnByDefault: true)
            case .edit(let account): AccountEditorView(account: account)
            }
        }
    }

    @ViewBuilder
    private func section(_ header: Text, _ accounts: [Account]) -> some View {
        if !accounts.isEmpty {
            Section {
                ForEach(accounts, id: \.objectID) { account in
                    BalanceRow(account: account)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = .edit(account) }
                }
            } header: {
                header
            }
        }
    }

    /// O ay ve önceki aylardan ödenmemiş kalan giderlerin gösterim birimindeki toplamı (pozitif).
    static func unpaid(through month: Month, items: some Sequence<LedgerItem>, rates: RateTable) -> Decimal {
        let thisMonth = Ledger.summary(of: Ledger.lines(for: month, items: items, rates: rates)).unpaidExpense
        // Kalan giderler eksi işaretlidir.
        let earlier = Ledger.carryOver(before: month, items: items, rates: rates)
            .compactMap(\.remainingSignedValue).reduce(0, +)
        return thisMonth - earlier
    }
}

/// Nakit toplamı, ödenmemişler ve ikisinin farkı.
struct AssetsCard: View {
    let position: CashPosition
    /// Pozitif tutulur.
    let unpaid: Decimal

    var body: some View {
        let after = position.total - unpaid
        VStack(alignment: .leading, spacing: 10) {
            Text("Nakit varlık")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.ikincil)

            if position.accountCount == 0 {
                Text("Hesaplarınızın bakiyesini girin")
                    .font(.headline)
                Text("Bankadaki ve elinizdeki parayı girdiğinizde ödenmemiş borçlar düşülünce ne kaldığını görürsünüz.")
                    .font(.footnote)
                    .foregroundStyle(Color.ikincil)
            } else {
                Text(Money.string(position.total, fractions: false))
                    .font(.amount(30))
                    .contentTransition(.numericText())

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ödenmemiş").font(.caption2.weight(.semibold)).foregroundStyle(Color.ikincil)
                        Text(Money.string(-unpaid, fractions: false))
                            .font(.amount(15, weight: .semibold))
                            .foregroundStyle(unpaid > 0 ? Color.gider : Color.ikincil)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Ödemelerden sonra").font(.caption2.weight(.semibold)).foregroundStyle(Color.ikincil)
                        Text(Money.string(after, sign: .always, fractions: false))
                            .font(.amount(15, weight: .semibold))
                            .foregroundStyle(Color.amount(after))
                    }
                }

                // Bir haftadan eski bakiye varsa güncellemesi hatırlatılır.
                if let oldest = position.oldestUpdate, oldest < .now.addingTimeInterval(-7 * 24 * 3600) {
                    Label("Bazı bakiyeler \(oldest.formatted(.relative(presentation: .named).locale(Money.locale))) güncellendi.",
                          systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(Color.ikincil)
                }
                if position.missingRateCount > 0 {
                    Label("\(position.missingRateCount) döviz hesabı kur olmadığı için toplama girmedi.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.uyari)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.kart, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct BalanceRow: View {
    /// Nesne izlenir: başka cihazdan iCloud ile gelen bakiye değişikliğinde satır yenilenir.
    @ObservedObject var account: Account

    var body: some View {
        HStack(spacing: 12) {
            BankBadge(bank: account.bankName, symbol: account.iban?.isEmpty == false ? "building.columns.fill" : "banknote.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.ikincil)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let balance = account.balanceValue {
                Text(Money.string(balance, currency: account.currency))
                    .font(.amount(15, weight: .semibold))
                    .foregroundStyle(Color.amount(balance))
            } else {
                Text("Bakiye gir")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.petrol)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let bank = account.bankName { parts.append(bank) }
        if let updated = account.balanceUpdatedAt {
            parts.append(updated.formatted(.dateTime.day().month(.abbreviated).locale(Money.locale)))
        }
        return parts.isEmpty ? String(localized: "Bakiye girilmedi") : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack { AssetsView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(AppState())
        .environment(RateService())
}
