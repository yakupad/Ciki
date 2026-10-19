import SwiftUI
import CoreData
import UIKit

struct MonthView: View {
    @Environment(AppState.self) private var app
    @Environment(RateService.self) private var rates
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder)])
    private var items: FetchedResults<LedgerItem>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    /// Kayıt değişikliklerinde (durum, tutar) ekranın yenilenmesi için.
    private let changes = ContextVersion()

    @State private var filter: OwnerFilter = .all
    @State private var route: EditorRoute?
    @State private var copyMessage: String?

    var body: some View {
        @Bindable var app = app
        let _ = changes.version
        let lines = Ledger.lines(for: app.month, items: items.filter(filter.includes), rates: rates.table)
        let groups = Self.groups(from: lines)
        let summary = Ledger.summary(of: lines)
        let carried = Ledger.carryOver(before: app.month, items: items.filter(filter.includes), rates: rates.table)

        List {
            Section {
                OwnerFilterPicker(selection: $filter, people: Array(people))
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if !carried.isEmpty {
                carryOverSection(carried)
            }

            if lines.isEmpty {
                ContentUnavailableView {
                    Label("\(app.month.title) boş", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Bu ay için kayıt yok. Alttaki Yeni kayıt düğmesini kullanın ya da geçen ayın tutarlarını kopyalayın.")
                } actions: {
                    Button("Geçen aydan kopyala") { copyFromPrevious() }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.lines) { line in
                        EntryRow(line: line, showOwner: filter == .all)
                            .contentShape(Rectangle())
                            .onTapGesture { route = .entry(item: line.item, month: line.month) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if line.status == .paid {
                                    Button("Geri al", systemImage: "arrow.uturn.backward") {
                                        context.setStatus(.pending, for: line, rates: rates.table)
                                    }
                                    .tint(.odendi)
                                } else {
                                    Button("Ödendi", systemImage: "checkmark") {
                                        context.setStatus(.paid, for: line, rates: rates.table)
                                    }
                                    .tint(.gelir)
                                    if line.status == .pending && line.direction == .expense {
                                        Button("Kısmi öde", systemImage: "circle.lefthalf.filled") {
                                            route = .entry(item: line.item, month: line.month)
                                        }
                                        .tint(.petrol)
                                    }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if line.status == .excluded {
                                    Button("Dahil et", systemImage: "plus.circle") {
                                        context.setStatus(.pending, for: line, rates: rates.table)
                                    }
                                    .tint(.petrol)
                                } else {
                                    Button("Bu ay hariç", systemImage: "minus.circle") {
                                        context.setStatus(.excluded, for: line, rates: rates.table)
                                    }
                                    .tint(.odendi)
                                }
                            }
                            .contextMenu {
                                if let iban = line.item.payee?.iban, !iban.isEmpty {
                                    Button("IBAN'ı kopyala", systemImage: "doc.on.doc") {
                                        UIPasteboard.general.string = IBAN.normalized(iban)
                                    }
                                }
                                Button("Kalemi düzenle", systemImage: "pencil") { route = .item(line.item) }
                            }
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text(Money.string(group.total))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.ikincil)
                }
            }

            if !lines.isEmpty {
                Section {
                    HStack {
                        Text("Ay neti").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Money.string(summary.net, sign: .always))
                            .font(.amount(17))
                            .foregroundStyle(Color.amount(summary.net))
                    }
                } footer: {
                    Text("Sola kaydırın: ödendi ya da kısmi öde. Sağa kaydırın: bu ay hesaba katma. Düzenli kalemler kayıt girilene kadar tahmini görünür.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .readableWidth()
        .background(Color.zemin)
        .navigationTitle(app.month.title)
        .toolbar {
            MonthNavigator(month: $app.month)
            ToolbarItem(placement: .topBarLeading) {
                Button("Geçen aydan kopyala", systemImage: "doc.on.doc") { copyFromPrevious() }
            }
        }
        .sheet(item: $route) { EditorSheet(route: $0) }
        .alert("Kopyalama", isPresented: Binding(get: { copyMessage != nil }, set: { if !$0 { copyMessage = nil } })) {
            Button("Tamam") { copyMessage = nil }
        } message: {
            Text(copyMessage ?? "")
        }
    }

    /// Önceki aylarda ödenmemiş kalanlar: ödenebilir ya da bu aya devredilebilir.
    private func carryOverSection(_ lines: [LedgerLine]) -> some View {
        let total = lines.compactMap(\.remainingSignedValue).reduce(0, +)
        return Section {
            ForEach(lines, id: \.entry?.objectID) { line in
                EntryRow(line: line, showOwner: filter == .all, showsMonth: true)
                    .contentShape(Rectangle())
                    .onTapGesture { route = .entry(item: line.item, month: line.month) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Ödendi", systemImage: "checkmark") {
                            context.setStatus(.paid, for: line, rates: rates.table)
                        }
                        .tint(.gelir)
                        Button("Bu aya devret", systemImage: "arrow.turn.down.right") {
                            context.carryOver(line, to: app.month, rates: rates.table)
                        }
                        .tint(.uyari)
                    }
                    .contextMenu {
                        Button("Bu aya devret", systemImage: "arrow.turn.down.right") {
                            context.carryOver(line, to: app.month, rates: rates.table)
                        }
                        Button("Ödendi", systemImage: "checkmark") {
                            context.setStatus(.paid, for: line, rates: rates.table)
                        }
                        Button("Kısmi öde", systemImage: "circle.lefthalf.filled") {
                            route = .entry(item: line.item, month: line.month)
                        }
                    }
            }
        } header: {
            HStack {
                Label("Önceki aylardan kalan", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.uyari)
                Spacer()
                Text(Money.string(total))
                    .monospacedDigit()
                    .foregroundStyle(Color.ikincil)
            }
        } footer: {
            Text("Ödenmemiş ya da kısmen ödenmiş kayıtlar. Sola kaydırın: ödendi ya da \(app.month.name) ayına devret. Devredilen kalan eski ayın toplamından düşer, bu ayın kaydına eklenir.")
        }
    }

    private func copyFromPrevious() {
        let count = context.copyEntries(from: app.month.adding(-1), to: app.month,
                                        items: items.filter(filter.includes), rates: rates.table)
        let source = app.month.adding(-1).name
        copyMessage = count == 0
            ? String(localized: "\(source) ayında kopyalanacak yeni kayıt yok.")
            : String(localized: "\(count) kayıt \(source) ayından kopyalandı. Tutarları ekstreye göre güncelleyin.")
    }

    struct Group: Identifiable {
        let key: String
        let title: String
        var lines: [LedgerLine]
        var id: String { key }
        var total: Decimal { lines.filter(\.counts).compactMap(\.signedValue).reduce(0, +) }
    }

    /// Giderler bankaya göre, gelir ve alacaklar ayrı grupta toplanır.
    /// Banka adlarında büyük/küçük harf ve boşluk farkı yok sayılır; başlıkta ilk görülen yazım kullanılır.
    static func groups(from lines: [LedgerLine]) -> [Group] {
        let incomeKey = "#income"
        let otherKey = "#other"
        var order: [String] = []
        var titles: [String: String] = [
            incomeKey: String(localized: "Gelir ve alacaklar"),
            otherKey: String(localized: "Diğer giderler"),
        ]
        var map: [String: [LedgerLine]] = [:]
        for line in lines {
            let key: String
            if line.direction != .expense {
                key = incomeKey
            } else if let bank = line.item.bankName {
                key = Banks.key(bank)
                if titles[key] == nil { titles[key] = bank }
            } else {
                key = otherKey
            }
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(line)
        }
        let sorted = order.filter { $0 != otherKey && $0 != incomeKey }
            + [otherKey, incomeKey].filter { map[$0] != nil }
        return sorted.map { Group(key: $0, title: titles[$0] ?? $0, lines: map[$0] ?? []) }
    }
}

struct EntryRow: View {
    let line: LedgerLine
    var showOwner = true
    /// Önceki aylardan kalanlarda kaydın ayı ve yalnızca kalan tutar gösterilir.
    var showsMonth = false
    /// Nesne izlenir: başka cihazdan iCloud ile gelen değişiklikte satır kendiliğinden yenilenir.
    @ObservedObject private var item: LedgerItem

    init(line: LedgerLine, showOwner: Bool = true, showsMonth: Bool = false) {
        self.line = line
        self.showOwner = showOwner
        self.showsMonth = showsMonth
        self._item = ObservedObject(wrappedValue: line.item)
    }

    var body: some View {
        HStack(spacing: 12) {
            ItemBadge(item: line.item)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.item.fullTitle)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(line.status == .paid)
                    .foregroundStyle(line.status == .paid ? Color.odendi : .primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.ikincil)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.string((showsMonth ? line.remaining : line.amount) * line.direction.sign,
                                  currency: line.currency, sign: .always))
                    .font(.amount(15, weight: .semibold))
                    .strikethrough(line.status != .pending, pattern: line.status == .excluded ? .dash : .solid)
                    .foregroundStyle(amountColor)
                if line.isPartiallyPaid && !showsMonth {
                    Text("Kalan \(Money.string(line.remaining, currency: line.currency, fractions: false))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.uyari)
                        .monospacedDigit()
                } else if line.currency != Money.baseCurrency, let value = line.signedValue {
                    Text("≈ " + Money.string(value, fractions: false))
                        .font(.caption2)
                        .foregroundStyle(Color.ikincil)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(line.status.title)
    }

    private var amountColor: Color {
        switch line.status {
        case .paid, .excluded: .odendi
        case .pending:
            // Kalanı sonraki aya devredilmiş kayıt bu ay için kapanmıştır.
            if !line.isProjected && line.remaining == 0 && (line.entry?.carriedOutValue ?? 0) > 0 {
                .odendi
            } else {
                line.direction == .expense ? .gider : .gelir
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsMonth { parts.append(line.month.title) }
        switch line.status {
        case .paid:
            if let date = line.entry?.paidAt {
                let day = date.formatted(.dateTime.day().month(.abbreviated).locale(Money.locale))
                parts.append(String(localized: "Ödendi · \(day)"))
            } else {
                parts.append(String(localized: "Ödendi"))
            }
        case .excluded: parts.append(String(localized: "Bu ay hariç"))
        case .pending:
            if line.isProjected { parts.append(String(localized: "Düzenli · tahmini")) }
            if line.isPartiallyPaid {
                parts.append(String(localized: "Kısmi · \(Money.string(line.paid, currency: line.currency, fractions: false)) ödendi"))
            }
            if let entry = line.entry, entry.carriedOutValue > 0, entry.remainingValue == 0 {
                parts.append(String(localized: "\(Month(key: entry.carriedToKey).shortTitle) ayına devredildi"))
            }
        }
        if let carriedIn = line.entry?.carriedInValue, carriedIn > 0 {
            parts.append(String(localized: "Devreden \(Money.string(carriedIn, currency: line.currency, fractions: false))"))
        }
        if showOwner { parts.append(line.item.ownerName) }
        if line.item.dueDay > 0 { parts.append(String(localized: "SÖT \(Int(line.item.dueDay))")) }
        if let note = line.entry?.note, !note.isEmpty { parts.append(note) }
        if parts.isEmpty { parts.append(line.item.kind.title) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack { MonthView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(AppState())
        .environment(RateService())
}
