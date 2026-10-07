import AppKit

/// Menüde gösterilen veri: uygulamanın hazırladığı özet ve seçili ay.
/// Eklenti Mac Catalyst sürecinde yüklendiği için AppKit'in SwiftUI'ı kullanılamaz; görünüm AppKit ile kurulur.
final class MenuBarModel {
    var snapshot: WidgetSnapshot? { didSet { onChange() } }
    /// Gösterilen ayın anahtarı; boşsa bu ay.
    var selectedKey: Int32? { didSet { onChange() } }
    var openApp: () -> Void = {}
    var onChange: () -> Void = {}

    var months: [WidgetSnapshot.MonthSummary] { snapshot?.monthList ?? [] }

    var selectedIndex: Int? {
        guard !months.isEmpty else { return nil }
        if let selectedKey, let index = months.firstIndex(where: { $0.key == selectedKey }) { return index }
        return months.firstIndex(where: \.isCurrent) ?? 0
    }

    var dueTodayCount: Int {
        months.first(where: \.isCurrent)?.payments.filter { Calendar.current.isDateInToday($0.dueDate) }.count ?? 0
    }

    func showCurrentMonth() { selectedKey = nil }

    func move(by offset: Int) {
        guard let index = selectedIndex, months.indices.contains(index + offset) else { return }
        selectedKey = months[index + offset].key
    }
}

/// Açılan pencere: ay başlığı ve okları, özet rakamlar, bekleyen ödemeler, uygulamayı açma düğmesi.
final class MenuBarViewController: NSViewController {
    private let model: MenuBarModel
    private let stack = NSStackView()
    /// Pencerede en fazla bu kadar ödeme satırı gösterilir; fazlası "+N ödeme daha" olarak yazılır.
    private let maxRows = 10

    init(model: MenuBarModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    override func loadView() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 330),
        ])
        view = container
        reload()
    }

    /// Model değişince içerik baştan kurulur (birkaç satır olduğu için ucuzdur).
    func reload() {
        guard isViewLoaded else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let index = model.selectedIndex {
            let month = model.months[index]
            add(header(month, index: index))
            add(summary(month))
            add(separator())
            payments(month)
        } else {
            add(label(localized("Özet, Çıkı açılınca hazırlanır."), style: .callout, color: .secondaryLabelColor))
        }
        add(separator())
        add(footer())
        preferredContentSize = view.fittingSize
    }

    // MARK: - Bölümler

    private func header(_ month: WidgetSnapshot.MonthSummary, index: Int) -> NSView {
        let previous = iconButton("chevron.left", localized("Önceki ay"), #selector(previousMonth))
        previous.isEnabled = index > 0
        let next = iconButton("chevron.right", localized("Sonraki ay"), #selector(nextMonth))
        next.isEnabled = index < model.months.count - 1

        let title = label(month.title, style: .headline, color: .labelColor)
        let center = NSStackView(views: [title])
        center.orientation = .vertical
        center.spacing = 1
        if !month.isCurrent {
            let back = NSButton(title: localized("Bu aya dön"), target: self, action: #selector(currentMonth))
            back.bezelStyle = .inline
            back.controlSize = .small
            center.addArrangedSubview(back)
        }
        // Başlık okların arasında tam ortada durur.
        let row = NSView()
        for view in [previous, center, next] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            previous.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            previous.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            next.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            next.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            center.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            center.topAnchor.constraint(equalTo: row.topAnchor),
            center.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return fullWidth(row)
    }

    private func summary(_ month: WidgetSnapshot.MonthSummary) -> NSView {
        let caption = label(month.isCurrent ? localized("Ay sonu net") : localized("Net"), style: .caption1, color: .secondaryLabelColor)
        let net = label(month.net, style: .title2, color: month.netIsNegative ? MenuBarColors.gider : MenuBarColors.gelir,
                        weight: .bold, rounded: true)
        let netStack = NSStackView(views: [caption, net])
        netStack.orientation = .vertical
        netStack.alignment = .leading
        netStack.spacing = 1

        let figures = NSStackView(views: [
            figure(localized("Gelir + alacak"), month.incoming, MenuBarColors.gelir), spacer(),
            figure(localized("Gider"), month.expense, MenuBarColors.gider), spacer(),
            figure(localized("Ödenmemiş"), month.unpaid, .labelColor),
        ])
        figures.orientation = .horizontal
        figures.alignment = .top

        let column = NSStackView(views: [netStack, fullWidth(figures)])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        return fullWidth(column)
    }

    private func payments(_ month: WidgetSnapshot.MonthSummary) {
        guard !month.payments.isEmpty else {
            add(label(localized("Bekleyen ödeme yok"), style: .callout, color: .secondaryLabelColor))
            return
        }
        let today = month.payments.filter { Calendar.current.isDateInToday($0.dueDate) }
        let others = month.payments.filter { !Calendar.current.isDateInToday($0.dueDate) }
        var shown = 0
        if !today.isEmpty {
            add(sectionTitle(localized("Bugün")))
            for payment in today.prefix(maxRows) { add(paymentRow(payment, highlighted: true)); shown += 1 }
        }
        if !others.isEmpty, shown < maxRows {
            add(sectionTitle(month.isCurrent ? localized("Bu ay bekleyenler") : localized("Bekleyen ödemeler")))
            for payment in others.prefix(maxRows - shown) { add(paymentRow(payment, highlighted: false)); shown += 1 }
        }
        let remaining = month.payments.count - shown
        if remaining > 0 {
            add(label(String(localized: "+\(remaining) ödeme daha", bundle: .menuBar), style: .caption1, color: .secondaryLabelColor))
        }
    }

    private func footer() -> NSView {
        let open = NSButton(title: localized("Çıkı'yı aç"), target: self, action: #selector(openApp))
        open.bezelStyle = .push
        open.keyEquivalent = "\r"
        var views: [NSView] = [open, spacer()]
        if let updated = model.snapshot?.updatedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            views.append(label(formatter.localizedString(for: updated, relativeTo: .now), style: .caption2,
                               color: .secondaryLabelColor))
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        return fullWidth(row)
    }

    private func paymentRow(_ payment: WidgetSnapshot.Payment, highlighted: Bool) -> NSView {
        let isLate = payment.dueDate < Calendar.current.startOfDay(for: .now)
        let title = label(payment.title, style: .callout, color: .labelColor, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = label("\(dueText(payment.dueDate, isLate: isLate)) · \(payment.owner)", style: .caption1,
                           color: highlighted || isLate ? MenuBarColors.uyari : .secondaryLabelColor)
        let texts = NSStackView(views: [title, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        let amount = label(payment.amount, style: .callout, color: MenuBarColors.gider, weight: .semibold, rounded: true)
        amount.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [texts, spacer(), amount])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        row.setAccessibilityLabel("\(payment.title), \(payment.amount), \(detail.stringValue)")
        return fullWidth(row)
    }

    private func dueText(_ date: Date, isLate: Bool) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return localized("Bugün") }
        if calendar.isDateInTomorrow(date) { return localized("Yarın") }
        if isLate { return localized("Gecikti") }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: - Eylemler

    @objc private func previousMonth() { model.move(by: -1) }
    @objc private func nextMonth() { model.move(by: 1) }
    @objc private func currentMonth() { model.showCurrentMonth() }
    @objc private func openApp() { model.openApp() }

    // MARK: - Yardımcılar

    private func add(_ view: NSView) { stack.addArrangedSubview(view) }

    private func fullWidth(_ view: NSView) -> NSView {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 302).isActive = true
        return view
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        return view
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return fullWidth(box)
    }

    private func sectionTitle(_ text: String) -> NSView {
        label(text.uppercased(with: .current), style: .caption1, color: .secondaryLabelColor, weight: .semibold)
    }

    private func figure(_ title: String, _ value: String, _ color: NSColor) -> NSView {
        let stack = NSStackView(views: [
            label(title, style: .caption2, color: .secondaryLabelColor),
            label(value, style: .callout, color: color, weight: .semibold, rounded: true),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        return stack
    }

    private func iconButton(_ symbol: String, _ description: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: description)!,
                              target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.toolTip = description
        return button
    }

    private func label(_ text: String, style: NSFont.TextStyle, color: NSColor,
                       weight: NSFont.Weight = .regular, rounded: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        var font = NSFont.preferredFont(forTextStyle: style)
        font = NSFont.systemFont(ofSize: font.pointSize, weight: weight)
        if rounded {
            font = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: weight)
            if let descriptor = font.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
            }
        }
        field.font = font
        field.textColor = color
        return field
    }

    private func localized(_ key: String) -> String {
        Bundle.menuBar.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Uygulamanın gelir, gider ve uyarı renkleri; açık ve koyu menü çubuğuna uyar.
enum MenuBarColors {
    static let gelir = dynamic(light: 0x197E4F, dark: 0x4CC48A)
    static let gider = dynamic(light: 0xC34035, dark: 0xF0736A)
    static let uyari = dynamic(light: 0x98630B, dark: 0xF0B04A)

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}
