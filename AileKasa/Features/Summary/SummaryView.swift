import SwiftUI
import Charts
import CoreData

struct SummaryView: View {
    @Environment(AppState.self) private var app
    @Environment(RateService.self) private var rates
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder)])
    private var items: FetchedResults<LedgerItem>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    /// Kayıt değişikliklerinde ekranın yenilenmesi için.
    @FetchRequest(sortDescriptors: [])
    private var entries: FetchedResults<LedgerEntry>

    @State private var route: EditorRoute?
    @Environment(\.isWideLayout) private var isWide
    @State private var showReport = false

    var body: some View {
        @Bindable var app = app
        let _ = entries.count
        let lines = Ledger.lines(for: app.month, items: items, rates: rates.table)
        let summary = Ledger.summary(of: lines)

        ScrollView {
            Group {
                if items.isEmpty {
                    emptyState
                } else if isWide {
                    // iPad, iPhone Duo iç ekranı ve Mac: solda özet, sağda ödenecekler.
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            NetCard(summary: summary)
                            peopleRow(summary)
                            NetChart(points: chartPoints, selected: app.month)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            upcoming
                        }
                    }
                    .readableWidth(1100)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        NetCard(summary: summary)
                        peopleRow(summary)
                        NetChart(points: chartPoints, selected: app.month)
                        upcoming
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.zemin)
        .navigationTitle(app.month.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Ayarlar", systemImage: "gearshape") { route = .settings }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Rapor", systemImage: "chart.line.uptrend.xyaxis") { showReport = true }
            }
            MonthNavigator(month: $app.month)
        }
        .sheet(item: $route) { EditorSheet(route: $0) }
        .navigationDestination(isPresented: $showReport) { ReportView() }
        #if DEBUG
        .onAppear {
            if CommandLine.arguments.contains("-openReport") { showReport = true }
            if CommandLine.arguments.contains("-openSettings") { route = .settings }
        }
        #endif
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Henüz kalem yok", systemImage: "tray")
        } description: {
            Text("Kartlarınızı, kredilerinizi, maaşları ve düzenli ödemeleri kalem olarak ekleyin. Sonra her ay tutarları girersiniz.")
        } actions: {
            Button("İlk kalemi ekle") { route = .newItem }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 60)
    }

    private func peopleRow(_ summary: MonthSummary) -> some View {
        let shared = summary.net(for: nil)
        // Üçlü ızgara: kişi sayısı arttıkça alt satıra geçer.
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(people, id: \.objectID) { person in
                PersonTile(name: person.displayName, color: person.color, value: summary.net(for: person))
            }
            PersonTile(name: String(localized: "Ortak"), color: .petrol, value: shared)
        }
    }

    private var chartPoints: [NetChart.Point] {
        (-6...6).map { offset in
            let month = app.month.adding(offset)
            let summary = Ledger.summary(of: Ledger.lines(for: month, items: items, rates: rates.table))
            return NetChart.Point(month: month, net: summary.net)
        }
    }

    @ViewBuilder
    private var upcoming: some View {
        let month = Month.current
        let pending = Ledger.lines(for: month, items: items, rates: rates.table)
            .filter { $0.direction == .expense && $0.status == .pending && $0.amount > 0 }
            .sorted { lhs, rhs in
                let left = lhs.item.dueDay == 0 ? 99 : lhs.item.dueDay
                let right = rhs.item.dueDay == 0 ? 99 : rhs.item.dueDay
                return left < right
            }

        HStack {
            Text("Bu ay ödenecekler")
            Spacer()
            Text("\(pending.count) ödeme")
        }
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .padding(.top, 6)

        if pending.isEmpty {
            Text("\(month.title) için bekleyen ödeme yok.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.kart, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            VStack(spacing: 0) {
                ForEach(pending) { line in
                    UpcomingRow(line: line) {
                        context.setStatus(.paid, for: line, rates: rates.table)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { route = .entry(item: line.item, month: line.month) }
                    if line.id != pending.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.kart, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct NetCard: View {
    let summary: MonthSummary

    var body: some View {
        let incoming = summary.income + summary.receivable
        let total = incoming + summary.expense
        let ratio = total > 0 ? (incoming / total).doubleValue : 0.5

        VStack(alignment: .leading, spacing: 10) {
            Text("Ay sonu net")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(Money.string(summary.net, sign: .always, fractions: false))
                .font(.amount(34))
                .foregroundStyle(Color.amount(summary.net))
                .contentTransition(.numericText())

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule().fill(Color.gelir).frame(width: max(0, proxy.size.width * ratio - 1))
                    Capsule().fill(Color.gider)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gelir + alacak").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Money.string(incoming, fractions: false)).font(.amount(15, weight: .semibold)).foregroundStyle(Color.gelir)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Gider").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Money.string(summary.expense, fractions: false)).font(.amount(15, weight: .semibold)).foregroundStyle(Color.gider)
                }
            }

            if summary.unpaidExpense > 0 {
                Text("Ödenmemiş: \(Money.string(summary.unpaidExpense, fractions: false))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if summary.missingRateCount > 0 {
                Label("\(summary.missingRateCount) döviz kalemi kur olmadığı için toplama girmedi.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.uyari)
            }
        }
        .padding(16)
        .background(Color.kart, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PersonTile: View {
    let name: String
    let color: Color
    let value: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(Money.string(value, sign: .always, fractions: false))
                .font(.amount(14))
                .foregroundStyle(Color.amount(value))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.kart, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct UpcomingRow: View {
    let line: LedgerLine
    let markPaid: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ItemBadge(item: line.item)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.item.fullTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    if line.item.dueDay > 0 {
                        DueChip(day: Int(line.item.dueDay), month: line.month)
                    }
                    Text(line.item.ownerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Money.string(-line.amount, currency: line.currency))
                .font(.amount(14, weight: .semibold))
                .foregroundStyle(Color.gider)
            Button("Ödendi olarak işaretle", systemImage: "checkmark.circle", action: markPaid)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(Color.gelir)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct NetChart: View {
    struct Point: Identifiable {
        let month: Month
        let net: Decimal
        var id: Int32 { month.key }
    }

    let points: [Point]
    let selected: Month

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aylık net")
                Spacer()
                Text("Gelecek aylar tahmini")
            }
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

            Chart(points) { point in
                BarMark(
                    x: .value("Ay", "\(point.month.key)"),
                    y: .value("Net", point.net.doubleValue)
                )
                .foregroundStyle(point.net < 0 ? Color.gider : Color.gelir)
                .opacity(opacity(for: point.month))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let raw = value.as(String.self), let key = Int32(raw) {
                            let month = Month(key: key)
                            Text(month.shortName)
                                .fontWeight(month == selected ? .bold : .regular)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number / 1000))B", comment: "Grafik ekseni: bin TL kısaltması")
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .padding(14)
        .background(Color.kart, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("Seçili ayın altı ay öncesinden altı ay sonrasına aylık net bakiye")
    }

    private func opacity(for month: Month) -> Double {
        if month == selected { return 1 }
        return month > .current ? 0.3 : 0.55
    }
}

#Preview {
    NavigationStack { SummaryView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(AppState())
        .environment(RateService())
}
