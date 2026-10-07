import AppKit

/// Menü çubuğundaki Çıkı simgesi ve tıklayınca açılan aylık özet.
@objc(CikiMenuBarController)
final class MenuBarController: NSObject, MenuBarControlling {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let model = MenuBarModel()
    private lazy var viewController = MenuBarViewController(model: model)
    private var openApp: (() -> Void)?

    override required init() {
        super.init()
    }

    func start(openApp: @escaping () -> Void) {
        self.openApp = openApp
        model.openApp = { [weak self] in
            self?.popover.performClose(nil)
            NSApplication.shared.activate()
            self?.openApp?()
        }
        model.onChange = { [weak self] in
            self?.viewController.reload()
            self?.updateButton()
        }
        popover.behavior = .transient
        popover.contentViewController = viewController
        setVisible(true)
        #if DEBUG
        // "-openMenuBar": ekran görüntüsü için açılışta menüyü açar.
        if CommandLine.arguments.contains("-openMenuBar") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.toggle() }
        }
        #endif
    }

    func update(snapshot: Data) {
        guard let snapshot = WidgetSnapshot.decode(snapshot) else { return }
        model.snapshot = snapshot
    }

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "bag", accessibilityDescription: "Çıkı")
            item.button?.imagePosition = .imageLeading
            item.button?.target = self
            item.button?.action = #selector(toggle)
            statusItem = item
            updateButton()
        } else if !visible, let item = statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Bugün son ödeme günü olan bekleyen ödeme varsa simgenin yanında sayısı yazar.
    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let dueToday = model.dueTodayCount
        button.title = dueToday > 0 ? " \(dueToday)" : ""
        button.toolTip = dueToday > 0
            ? String(localized: "Bugün \(dueToday) ödeme var", bundle: .menuBar)
            : Bundle.menuBar.localizedString(forKey: "Çıkı: bu ayın özeti", value: nil, table: nil)
    }

    @objc private func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.showCurrentMonth()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

extension Bundle {
    /// Eklentinin kendi paketi; metinler buradaki katalogdan okunur.
    static let menuBar = Bundle(for: MenuBarController.self)
}
