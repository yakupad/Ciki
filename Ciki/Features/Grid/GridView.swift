import SwiftUI
import CoreData

/// Excel düzeni: satırlar kalemler, sütunlar aylar. Kalem sütunu sabit kalır.
struct GridView: View {
    @Environment(AppState.self) private var app
    @Environment(RateService.self) private var rates

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder)])
    private var items: FetchedResults<LedgerItem>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    @FetchRequest(sortDescriptors: [])
    private var entries: FetchedResults<LedgerEntry>

    @State private var filter: OwnerFilter = .all
    @State private var route: EditorRoute?

    @Environment(\.isWideLayout) private var isWide

    // Yazı boyutu büyüdükçe satır ve sütunlar da büyür (Dynamic Type).
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var columnWidth: CGFloat = 92
    /// Kalem sütunu da yazı boyutuyla genişler; geniş ekranda (iPad, Mac, iPhone Duo iç ekranı) daha geniştir.
    @ScaledMetric(relativeTo: .caption) private var baseTitleWidth: CGFloat = 124
    private var titleWidth: CGFloat { isWide ? baseTitleWidth * 1.5 : baseTitleWidth }

    var body: some View {
        @Bindable var app = app
        let _ = entries.count
        let months = (-4...6).map { app.month.adding($0) }
        let table = buildTable(months: months)

        ScrollView(.vertical) {
            VStack(spacing: 12) {
                OwnerFilterPicker(selection: $filter, people: Array(people))

                if table.rows.isEmpty {
                    ContentUnavailableView("Gösterilecek kalem yok", systemImage: "tablecells",
                                           description: Text("Kalemler sekmesinden kalem ekleyin."))
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        titleColumn(table)
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 0) {
                                    ForEach(months) { month in
                                        monthColumn(month, table: table)
                                            .id(month.key)
                                    }
                                }
                            }
                            .onAppear { proxy.scrollTo(app.month.key, anchor: .center) }
                            .onChange(of: app.month) { _, month in
                                withAnimation { proxy.scrollTo(month.key, anchor: .center) }
                            }
                        }
                    }
                    .background(Color.kart)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text("Hücreye dokunarak tutarı düzenleyin. Üstü çizili: ödendi. Soluk: hariç. İtalik: düzenli ödemeden tahmini.")
                        .font(.footnote)
                        .foregroundStyle(Color.ikincil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.zemin)
        .navigationTitle("Tablo")
        .toolbar { MonthNavigator(month: $app.month) }
        .sheet(item: $route) { EditorSheet(route: $0) }
    }

    // MARK: - Sütunlar

    private func titleColumn(_ table: Table) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerCell(String(localized: "Kalem"), alignment: .leading)
            ForEach(table.rows, id: \.objectID) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.owner?.color ?? .petrol)
                        .frame(width: 6, height: 6)
                    Text(item.fullTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .frame(width: titleWidth, height: rowHeight, alignment: .leading)
                .overlay(alignment: .bottom) { Divider() }
                .contentShape(Rectangle())
                .onTapGesture { route = .item(item) }
            }
            Text("Net \(Money.baseCurrency.symbol)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .frame(width: titleWidth, height: rowHeight, alignment: .leading)
        }
        .background(Color.kart)
        .overlay(alignment: .trailing) { Divider() }
    }

    private func monthColumn(_ month: Month, table: Table) -> some View {
        let isSelected = month == app.month
        let net = table.net[month.key] ?? 0
        return VStack(spacing: 0) {
            headerCell(month.shortTitle, alignment: .trailing, bold: isSelected)
            ForEach(table.rows, id: \.objectID) { item in
                cell(table.lines[item.objectID]?[month.key])
                    .frame(width: columnWidth, height: rowHeight, alignment: .trailing)
                    .overlay(alignment: .bottom) { Divider() }
                    .contentShape(Rectangle())
                    .onTapGesture { route = .entry(item: item, month: month) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(item.fullTitle), \(month.title)"))
                    .accessibilityValue(Text(verbatim: cellDescription(table.lines[item.objectID]?[month.key])))
                    .accessibilityAddTraits(.isButton)
            }
            Text(Money.compact(net))
                .font(.amount(12))
                .foregroundStyle(Color.amount(net))
                .padding(.horizontal, 8)
                .frame(width: columnWidth, height: rowHeight, alignment: .trailing)
        }
        .background(isSelected ? Color.petrolSoft : Color.clear)
    }

    private func headerCell(_ text: String, alignment: Alignment, bold: Bool = false) -> some View {
        Text(text.uppercased(with: Money.locale))
            .font(.caption2.weight(bold ? .heavy : .semibold))
            .foregroundStyle(bold ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(width: alignment == .leading ? titleWidth : columnWidth, height: 32, alignment: alignment)
            .overlay(alignment: .bottom) { Divider() }
    }

    private func cellDescription(_ line: LedgerLine?) -> String {
        guard let line else { return String(localized: "Kayıt yok") }
        let amount = Money.string(line.amount * line.direction.sign, currency: line.currency)
        return line.isProjected ? "\(amount), \(String(localized: "Düzenli · tahmini"))" : "\(amount), \(line.status.title)"
    }

    @ViewBuilder
    private func cell(_ line: LedgerLine?) -> some View {
        if let line {
            let value = line.amount * line.direction.sign
            Text(line.currency == Money.baseCurrency ? Money.compact(value) : Money.string(value, currency: line.currency, fractions: false))
                .font(.system(.caption, design: .rounded, weight: line.status == .pending ? .semibold : .regular))
                .monospacedDigit()
                .italic(line.isProjected)
                .strikethrough(line.status != .pending, pattern: line.status == .excluded ? .dash : .solid)
                .foregroundStyle(line.status == .pending ? Color.amount(value) : Color.odendi)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
        } else {
            Color.clear
        }
    }

    // MARK: - Veri

    private struct Table {
        var rows: [LedgerItem] = []
        var lines: [NSManagedObjectID: [Int32: LedgerLine]] = [:]
        var net: [Int32: Decimal] = [:]
    }

    private func buildTable(months: [Month]) -> Table {
        var table = Table()
        for item in items where filter.includes(item) {
            var row: [Int32: LedgerLine] = [:]
            for month in months {
                if let line = Ledger.line(for: item, month: month, rates: rates.table) {
                    row[month.key] = line
                }
            }
            guard !item.isArchived || !row.isEmpty else { continue }
            table.rows.append(item)
            table.lines[item.objectID] = row
        }
        for month in months {
            let monthLines = table.rows.compactMap { table.lines[$0.objectID]?[month.key] }
            table.net[month.key] = Ledger.summary(of: monthLines).net
        }
        return table
    }
}

#Preview {
    NavigationStack { GridView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(AppState())
        .environment(RateService())
}
