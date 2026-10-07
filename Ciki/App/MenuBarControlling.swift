import Foundation

/// Mac menü çubuğu eklentisiyle (CikiMenuBar.bundle) uygulama arasındaki sözleşme.
/// Eklenti AppKit ile çalışır; Mac Catalyst uygulaması onu çalışma anında yükler.
/// Bu dosya hem uygulamada hem eklentide derlenir.
@objc(CikiMenuBarControlling)
protocol MenuBarControlling: NSObjectProtocol {
    init()
    /// Menü çubuğu simgesini kurar. `openApp`, "Çıkı'yı aç" seçilince uygulama penceresini öne getirir.
    func start(openApp: @escaping () -> Void)
    /// Uygulamanın hazırladığı özet (`WidgetSnapshot`, JSON).
    func update(snapshot: Data)
    func setVisible(_ visible: Bool)
}
