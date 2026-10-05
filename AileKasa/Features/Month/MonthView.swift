import SwiftUI
import CoreData

struct MonthView: View {
    @Environment(AppState.self) private var app
    @Environment(RateService.self) private var rates
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder)])
    private var items: FetchedResults<LedgerItem>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    @FetchRequest(sortDescriptors: [])
    private var entries: FetchedResults<LedgerEntry>

    @State private var filter: OwnerFilter = .all
    @State private var route: EditorRoute?
    @State private var copyMessage: String?

    var body: some View {
        @Bindable var app = app
        let _ = entries.count
        let lines = Ledger.lines(for: app.month, items: items.filter(filter.includes), rates: rates.table)
        let groups = Self.groups(from: lines)
        let summary = Ledger.summary(of: lines)

        List {
            Section {
                OwnerFilterPicker(selection: $filter, people: Array(people))
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if lines.isEmpty {
                ContentUnavailableView {
                    Label("\(app.month.title) boş", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Bu ay için kayıt yok. Yeni kayıt ekleyin ya da geçen ayın tutarlarını kopyalayın.")
                } actions: {
                    Button("Geçen aydan kopyala") { copyFromPrevious() }
                }
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
                    Text("Sola kaydırın: ödendi. Sağa kaydırın: bu ay hesaba katma. Düzenli kalemler kayıt girilene kadar tahmini görünür.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.zemin)
        .navigationTitle(app.month.title)
        .toolbar {
            MonthNavigator(month: $app.month)
            ToolbarItem(placement: .topBarLeading) {
                Menu("Diğer", systemImage: "ellipsis.circle") {
                    Button("Geçen aydan kopyala", systemImage: "doc.on.doc") { copyFromPrevious() }
                    Button("Yeni kalem", systemImage: "square.and.pencil") { route = .newItem }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Yeni kayıt", systemImage: "plus") {
                    route = .entry(item: nil, month: app.month)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(item: $route) { EditorSheet(route: $0) }
        .alert("Kopyalama", isPresented: Binding(get: { copyMessage != nil }, set: { if !$0 { copyMessage = nil } })) {
            Button("Tamam") { copyMessage = nil }
        } message: {
            Text(copyMessage ?? "")
        }
    }

    private func copyFromPrevious() {
        let count = context.copyEntries(from: app.month.adding(-1), to: app.month,
                                        items: items.filter(filter.includes), rates: rates.table)
        copyMessage = count == 0
            ? "\(app.month.adding(-1).name) ayında kopyalanacak yeni kayıt yok."
            : "\(count) kayıt \(app.month.adding(-1).name) ayından kopyalandı. Tutarları ekstreye göre güncelleyin."
    }

    struct Group: Identifiable {
        let title: String
        var lines: [LedgerLine]
        var id: String { title }
        var total: Decimal { lines.filter(\.counts).compactMap(\.signedTRY).reduce(0, +) }
    }

    /// Giderler bankaya göre, gelir ve alacaklar ayrı grupta toplanır.
    static func groups(from lines: [LedgerLine]) -> [Group] {
        var order: [String] = []
        var map: [String: [LedgerLine]] = [:]
        let incomeTitle = "Gelir ve alacaklar"
        let otherTitle = "Diğer giderler"
        for line in lines {
            let title: String
            if line.direction != .expense {
                title = incomeTitle
            } else {
                title = line.item.bankName ?? otherTitle
            }
            if map[title] == nil { order.append(title) }
            map[title, default: []].append(line)
        }
        let sorted = order.filter { $0 != otherTitle && $0 != incomeTitle }
            + [otherTitle, incomeTitle].filter { map[$0] != nil }
        return sorted.map { Group(title: $0, lines: map[$0] ?? []) }
    }
}

struct EntryRow: View {
    let line: LedgerLine
    var showOwner = true

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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.string(line.amount * line.direction.sign, currency: line.currency, sign: .always))
                    .font(.amount(15, weight: .semibold))
                    .strikethrough(line.status != .pending, pattern: line.status == .excluded ? .dash : .solid)
                    .foregroundStyle(amountColor)
                if line.currency != .tl, let value = line.signedTRY {
                    Text("≈ " + Money.string(value, fractions: false))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .opacity(line.status == .excluded ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(line.status.title)
    }

    private var amountColor: Color {
        switch line.status {
        case .paid, .excluded: .odendi
        case .pending: line.direction == .expense ? .gider : .gelir
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        switch line.status {
        case .paid:
            if let date = line.entry?.paidAt {
                parts.append("Ödendi · " + date.formatted(.dateTime.day().month(.abbreviated).locale(Money.locale)))
            } else {
                parts.append("Ödendi")
            }
        case .excluded: parts.append("Bu ay hariç")
        case .pending: if line.isProjected { parts.append("Düzenli · tahmini") }
        }
        if showOwner { parts.append(line.item.owner?.displayName ?? "Ortak") }
        if line.item.dueDay > 0 { parts.append("SÖT \(line.item.dueDay)") }
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
