import SwiftUI
import Charts
import CoreData

/// Ay ay gelir, gider, net ve kart/kredi borcunun seyri.
struct ReportView: View {
    @Environment(RateService.self) private var rates

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder)])
    private var items: FetchedResults<LedgerItem>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>
    @FetchRequest(sortDescriptors: [])
    private var entries: FetchedResults<LedgerEntry>

    @State private var filter: OwnerFilter = .all
    @State private var range: ReportRange = .year
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum ReportRange: String, CaseIterable, Identifiable {
        case half, year, plan
        var id: String { rawValue }
        var title: String {
            switch self {
            case .half: String(localized: "6 ay")
            case .year: String(localized: "12 ay")
            case .plan: String(localized: "12 ay + 6 ay")
            }
        }
        /// Bugüne göre ay aralığı.
        var offsets: ClosedRange<Int> {
            switch self {
            case .half: -5...0
            case .year: -11...0
            case .plan: -11...6
            }
        }
    }

    var body: some View {
        let _ = entries.count
        let now = Month.current
        let months = range.offsets.map { now.adding($0) }
        let totals = Ledger.totals(for: months, items: items.filter(filter.includes), rates: rates.table)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OwnerFilterPicker(selection: $filter, people: Array(people))
                Picker("Aralık", selection: $range) {
                    ForEach(ReportRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                StatsRow(totals: totals, now: now)
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 14) {
                        NetTrendChart(totals: totals, now: now)
                        DebtChart(totals: totals, now: now)
                    }
                } else {
                    NetTrendChart(totals: totals, now: now)
                    DebtChart(totals: totals, now: now)
                }
                MonthTable(totals: totals, now: now)
            }
            .readableWidth(1100)
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.zemin)
        .navigationTitle("Rapor")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Özet kutuları

private struct StatsRow: View {
    let totals: [MonthTotals]
    let now: Month

    var body: some View {
        let past = totals.filter { $0.month <= now }
        let lastSix = past.suffix(6)
        let average = lastSix.isEmpty ? 0 : lastSix.reduce(Decimal(0)) { $0 + $1.net } / Decimal(lastSix.count)
        let remaining = totals.filter { $0.month >= now }.reduce(Decimal(0)) { $0 + $1.pendingExpense }
        let peak = past.max { $0.expense < $1.expense }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
            StatTile(title: "Son 6 ay ort. net", value: Money.string(average, sign: .always, fractions: false),
                     color: Color.amount(average))
            StatTile(title: "Ödenmemiş gider", value: Money.string(remaining, fractions: false),
                     color: remaining > 0 ? .gider : .secondary,
                     caption: totals.contains { $0.month > now } ? String(localized: "Bu ay ve sonrası") : String(localized: "Bu ay"))
            if let peak {
                StatTile(title: "En yüksek gider", value: Money.string(peak.expense, fractions: false),
                         color: .gider, caption: peak.month.title)
            }
            if let current = totals.first(where: { $0.month == now }) {
                StatTile(title: "Kart ve kredi · bu ay", value: Money.string(current.debt, fractions: false),
                         color: current.debt > 0 ? .gider : .secondary)
            }
        }
    }
}

private struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.amount(17))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.kart, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Grafikler

private struct NetTrendChart: View {
    let totals: [MonthTotals]
    let now: Month

    private struct Point: Identifiable {
        let month: Month
        let net: Double
        let cumulative: Double
        var id: Int32 { month.key }
    }

    private var points: [Point] {
        var running: Decimal = 0
        return totals.map { total in
            running += total.net
            return Point(month: total.month, net: total.net.doubleValue, cumulative: running.doubleValue)
        }
    }

    var body: some View {
        ChartCard(title: "Net ve birikimli bakiye",
                  caption: "Çubuk: o ayın neti. Çizgi: dönem başından bu yana toplam. Çizgi aşağı iniyorsa borç birikiyor.") {
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Ay", "\(point.month.key)"), y: .value("Net", point.net))
                        .foregroundStyle(point.net < 0 ? Color.gider : Color.gelir)
                        .opacity(point.month > now ? 0.3 : 0.6)
                        .cornerRadius(3)
                }
                ForEach(points) { point in
                    LineMark(x: .value("Ay", "\(point.month.key)"), y: .value("Birikimli", point.cumulative))
                        .foregroundStyle(Color.petrol)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Sıfır", 0))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            .monthAxis(totals.map(\.month), now: now)
            .thousandsAxis()
            .frame(height: 200)
        }
    }
}

private struct DebtChart: View {
    let totals: [MonthTotals]
    let now: Month

    private struct Slice: Identifiable {
        let month: Month
        let bank: String
        let value: Double
        var id: String { "\(month.key)-\(bank)" }
    }

    var body: some View {
        let slices = totals.flatMap { total in
            total.debtByBank.sorted { $0.key < $1.key }.map {
                Slice(month: total.month, bank: $0.key, value: $0.value.doubleValue)
            }
        }
        let banks = Array(Set(slices.map(\.bank))).sorted()

        ChartCard(title: "Kart ve kredi ödemeleri",
                  caption: "Kart ekstresi, nakit avans ve kredi taksitlerinin bankaya göre aylık toplamı.") {
            if slices.isEmpty {
                Text("Bu aralıkta kart veya kredi kaydı yok.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(slices) { slice in
                    BarMark(x: .value("Ay", "\(slice.month.key)"), y: .value("Tutar", slice.value))
                        .foregroundStyle(by: .value("Banka", slice.bank))
                        .opacity(slice.month > now ? 0.45 : 1)
                }
                .chartForegroundStyleScale(domain: banks, range: banks.map { Color(light: Banks.colorHex(for: $0), dark: Banks.darkColorHex(for: $0)) })
                .chartLegend(position: .bottom, alignment: .leading)
                .monthAxis(totals.map(\.month), now: now)
                .thousandsAxis()
                .frame(height: 220)
            }
        }
    }
}

private struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.kart, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private extension View {
    /// X ekseni tüm aylar için sabit; 8 aydan uzun aralıklarda etiketler ikişer ay atlar.
    func monthAxis(_ months: [Month], now: Month) -> some View {
        let keys = months.map { "\($0.key)" }
        let step = months.count > 8 ? 2 : 1
        let labeled = months.enumerated()
            .filter { ($0.offset - (months.firstIndex(of: now) ?? 0)) % step == 0 }
            .map { "\($0.element.key)" }
        return self
            .chartXScale(domain: keys)
            .chartXAxis {
                AxisMarks(values: labeled) { value in
                    AxisValueLabel {
                        if let raw = value.as(String.self), let key = Int32(raw) {
                            let month = Month(key: key)
                            Text(month.shortName)
                                .fontWeight(month == now ? .bold : .regular)
                        }
                    }
                }
            }
    }

    func thousandsAxis() -> some View {
        chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number / 1000))B", comment: "Grafik ekseni: bin TL kısaltması")
                    }
                }
            }
        }
    }
}

// MARK: - Tablo

private struct MonthTable: View {
    let totals: [MonthTotals]
    let now: Month

    var body: some View {
        let rows = cumulativeRows

        VStack(spacing: 0) {
            row(month: String(localized: "Ay") + " · " + Money.baseCurrency.symbol, incoming: String(localized: "Gelir"), expense: String(localized: "Gider"),
                net: String(localized: "Net"), cumulative: String(localized: "Birikimli"), header: true)
            ForEach(rows.reversed(), id: \.0.id) { total, cumulative in
                Divider()
                row(month: total.month.shortTitle,
                    incoming: Money.compact(total.incoming),
                    expense: Money.compact(-total.expense),
                    net: Money.compact(total.net),
                    cumulative: Money.compact(cumulative),
                    netColor: Color.amount(total.net),
                    cumulativeColor: Color.amount(cumulative))
                    .background(total.month == now ? Color.petrolSoft : .clear)
                    .opacity(total.month > now ? 0.6 : 1)
            }
        }
        .background(Color.kart, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cumulativeRows: [(MonthTotals, Decimal)] {
        var running: Decimal = 0
        return totals.map { total in
            running += total.net
            return (total, running)
        }
    }

    private func row(month: String, incoming: String, expense: String, net: String, cumulative: String,
                     header: Bool = false, netColor: Color = .primary, cumulativeColor: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(month).frame(width: 52, alignment: .leading)
            Text(incoming).frame(maxWidth: .infinity, alignment: .trailing)
            Text(expense).frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(header ? Color.secondary : Color.gider)
            Text(net).frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(header ? Color.secondary : netColor)
            Text(cumulative).frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(header ? Color.secondary : cumulativeColor)
        }
        .font(header ? .caption2.weight(.semibold) : .system(size: 12, weight: .medium, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(header ? .secondary : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, header ? 8 : 9)
    }
}

#Preview {
    NavigationStack { ReportView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(RateService())
}
