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
            }

            section("Düzenli ödemeler", recurringExpense)
            section("Düzenli gelirler", recurringIncome)
            section("Diğer kalemler", others)
            section("Arşiv", archived)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
    private func section(_ title: String, _ items: [LedgerItem]) -> some View {
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
                Text(title)
            } footer: {
                if title == "Diğer kalemler" {
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
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.isRecurring, let amount = item.recurringAmountValue {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.string(amount * item.direction.sign, currency: item.currency, sign: .always))
                        .font(.amount(14, weight: .semibold))
                        .foregroundStyle(item.direction == .expense ? Color.gider : Color.gelir)
                    if item.currency != .tl, let rate = rates.rate(for: item.currency) {
                        Text("≈ " + Money.string(amount * rate, fractions: false))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = [item.owner?.displayName ?? "Ortak"]
        if item.isRecurring {
            parts.append(item.dueDay > 0 ? "her ayın \(item.dueDay)'i" : "her ay")
            if item.recurringEnd != 0 {
                parts.append("\(Month(key: item.recurringEnd).title)'a kadar")
            }
        } else {
            parts.append(item.kind.title)
            if item.dueDay > 0 { parts.append("SÖT \(item.dueDay)") }
        }
        return parts.joined(separator: " · ")
    }
}

struct RateCard: View {
    @Environment(RateService.self) private var rates

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Döviz kuru · TCMB satış")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    rate("$", rates.table.usd)
                    rate("€", rates.table.eur)
                }
                if let error = rates.errorMessage {
                    Text(error).font(.caption).foregroundStyle(Color.gider)
                } else if let updated = rates.updatedAt {
                    Text("Güncellendi: " + updated.formatted(.dateTime.day().month().hour().minute().locale(Money.locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if rates.isLoading {
                ProgressView()
            } else {
                Button("Kuru yenile", systemImage: "arrow.clockwise") {
                    Task { await rates.refresh() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
    }

    private func rate(_ symbol: String, _ value: Decimal?) -> some View {
        Text("\(symbol) \(value.map { Money.string($0, fractions: true) } ?? "—")")
            .font(.amount(16, weight: .semibold))
    }
}

#Preview {
    NavigationStack { ItemsView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(RateService())
}
