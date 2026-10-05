import SwiftUI
import UIKit

/// Uygulamanın görünümü: telefonun ayarını izler ya da her zaman açık / koyu açılır. Cihaza özel saklanır.
nonisolated enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let key = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Sistem")
        case .light: String(localized: "Açık")
        case .dark: String(localized: "Koyu")
        }
    }

    /// SwiftUI için: `nil` telefonun ayarını izler.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    static var current: Appearance {
        UserDefaults.standard.string(forKey: key).flatMap(Appearance.init(rawValue:)) ?? .system
    }
}

extension Appearance {
    /// Sahnedeki tüm pencerelere uygular; açık sayfalar (sheet), kilit ekranı ve iOS'un paylaşım ekranı da dahil.
    func apply() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}
