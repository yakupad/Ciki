import SwiftUI
import UIKit

extension Color {
    static let petrol = Color(light: 0x0E5F59, dark: 0x43B5A9)
    static let petrolSoft = Color(light: 0xD6EAE6, dark: 0x16332F)
    static let gelir = Color(light: 0x1C8A57, dark: 0x4CC48A)
    static let gider = Color(light: 0xCF4438, dark: 0xF0736A)
    static let uyari = Color(light: 0xD98E10, dark: 0xF0B04A)
    static let odendi = Color(light: 0x8C9692, dark: 0x6E7C78)
    static let zemin = Color(light: 0xF3F5F2, dark: 0x0D1312)
    static let kart = Color(light: 0xFFFFFF, dark: 0x161E1C)

    nonisolated init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    nonisolated init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// "3D5FD9" biçiminde, kişi renklerini saklamak için.
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", channel(red), channel(green), channel(blue))
    }

    static func amount(_ value: Decimal) -> Color {
        value < 0 ? .gider : (value > 0 ? .gelir : .secondary)
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Person {
    var color: Color { Color(hexString: colorHex ?? "") ?? .petrol }
}

extension Font {
    /// Büyük tutarlar: SF Pro Rounded, sabit genişlikli rakamlar.
    static func amount(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
