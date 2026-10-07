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
            item.button?.image = Self.pouchImage
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

extension MenuBarController {
    /// Uygulama ikonundaki kese, menü çubuğu için tek renkli şablon simge olarak (18 pt).
    /// Yollar ikonun SVG katmanlarından (1024'lük tuval) alınır; düğüm bandı gövdeden ince bir boşlukla ayrılır.
    static let pouchImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Kesenin kapladığı alan: x 222…802, y 252…836. Yüksekliğe sığdırılıp yatayda ortalanır.
            let scale = rect.height / 640
            context.translateBy(x: rect.midX - 512 * scale, y: (rect.height - 584 * scale) / 2 - 252 * scale)
            context.scaleBy(x: scale, y: scale)

            let body = NSBezierPath()
            body.move(to: NSPoint(x: 436, y: 454))
            body.curve(to: NSPoint(x: 222, y: 672), controlPoint1: NSPoint(x: 320, y: 478), controlPoint2: NSPoint(x: 222, y: 556))
            body.curve(to: NSPoint(x: 512, y: 836), controlPoint1: NSPoint(x: 222, y: 782), controlPoint2: NSPoint(x: 352, y: 836))
            body.curve(to: NSPoint(x: 802, y: 672), controlPoint1: NSPoint(x: 672, y: 836), controlPoint2: NSPoint(x: 802, y: 782))
            body.curve(to: NSPoint(x: 588, y: 454), controlPoint1: NSPoint(x: 802, y: 556), controlPoint2: NSPoint(x: 704, y: 478))
            body.close()

            let crown = NSBezierPath()
            crown.move(to: NSPoint(x: 444, y: 446))
            let curves: [(NSPoint, NSPoint, NSPoint)] = [
                (NSPoint(x: 420, y: 400), NSPoint(x: 380, y: 352), NSPoint(x: 344, y: 312)),
                (NSPoint(x: 330, y: 296), NSPoint(x: 342, y: 274), NSPoint(x: 364, y: 280)),
                (NSPoint(x: 392, y: 288), NSPoint(x: 412, y: 300), NSPoint(x: 430, y: 296)),
                (NSPoint(x: 450, y: 292), NSPoint(x: 462, y: 262), NSPoint(x: 486, y: 256)),
                (NSPoint(x: 500, y: 252), NSPoint(x: 506, y: 262), NSPoint(x: 512, y: 262)),
                (NSPoint(x: 518, y: 262), NSPoint(x: 524, y: 252), NSPoint(x: 538, y: 256)),
                (NSPoint(x: 562, y: 262), NSPoint(x: 574, y: 292), NSPoint(x: 594, y: 296)),
                (NSPoint(x: 612, y: 300), NSPoint(x: 632, y: 288), NSPoint(x: 660, y: 280)),
                (NSPoint(x: 682, y: 274), NSPoint(x: 694, y: 296), NSPoint(x: 680, y: 312)),
                (NSPoint(x: 644, y: 352), NSPoint(x: 604, y: 400), NSPoint(x: 580, y: 446)),
            ]
            for (control1, control2, end) in curves {
                crown.curve(to: end, controlPoint1: control1, controlPoint2: control2)
            }
            crown.close()

            NSColor.black.setFill()
            body.fill()
            crown.fill()
            // Düğüm bandının çevresi boşaltılır, sonra band çizilir: küçük boyutta da üç parça seçilir.
            let gap: CGFloat = 26
            context.setBlendMode(.clear)
            NSBezierPath(roundedRect: NSRect(x: 414 - gap, y: 402 - gap, width: 196 + gap * 2, height: 80 + gap * 2),
                         xRadius: 40 + gap, yRadius: 40 + gap).fill()
            context.setBlendMode(.normal)
            NSBezierPath(roundedRect: NSRect(x: 414, y: 402, width: 196, height: 80), xRadius: 40, yRadius: 40).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Çıkı"
        return image
    }()
}
