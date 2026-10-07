#if targetEnvironment(macCatalyst)
import UIKit

/// Mac'te menü çubuğu eklentisini (CikiMenuBar.bundle) yükler ve özeti ona iletir.
final class MenuBarBridge {
    static let shared = MenuBarBridge()
    /// Ayarlar'daki "Menü çubuğunda göster" seçeneği.
    static let visibleKey = "menuBar.visible"

    private var controller: MenuBarControlling?

    func start() {
        guard controller == nil,
              let url = Bundle.main.builtInPlugInsURL?.appending(path: "CikiMenuBar.bundle"),
              let bundle = Bundle(url: url), bundle.load(),
              let type = bundle.principalClass as? MenuBarControlling.Type else { return }
        let controller = type.init()
        controller.start { Self.openAppWindow() }
        self.controller = controller
        setVisible(UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true)
        if let snapshot = WidgetSnapshot.load() { update(snapshot) }
    }

    func update(_ snapshot: WidgetSnapshot) {
        guard let data = snapshot.encoded() else { return }
        controller?.update(snapshot: data)
    }

    func setVisible(_ visible: Bool) {
        controller?.setVisible(visible)
    }

    /// Açık pencere yoksa yeni bir pencere açar; varsa öne getirir.
    private static func openAppWindow() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first {
            UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil)
        } else {
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil)
        }
    }
}
#endif
