import SwiftUI
import UIKit

extension Color {
    static let petrol = Color(light: 0x0E5F59, dark: 0x43B5A9)
    /// Vurgulu zemin (ör. tabloda seçili ay); üzerindeki gelir/gider yazıları 4,5:1'i geçer.
    static let petrolSoft = Color(light: 0xEAF4F2, dark: 0x152825)
    // Metin olarak kullanılan renkler açık ve koyu zeminde en az 4,5:1 kontrast verir (WCAG AA).
    static let gelir = Color(light: 0x197E4F, dark: 0x4CC48A)
    static let gider = Color(light: 0xC34035, dark: 0xF0736A)
    static let uyari = Color(light: 0x98630B, dark: 0xF0B04A)
    static let odendi = Color(light: 0x69706D, dark: 0x8A9793)
    /// Gelir, gider ve uyarı renginin üzerindeki yazı: açık modda beyaz, koyu modda siyah.
    static let vurguUstu = Color(light: 0xFFFFFF, dark: 0x000000)
    /// İkincil metin: sistem grisinden biraz koyu, kart ve zeminde en az 4,5:1 kontrast.
    static let ikincil = Color(light: 0x5E6A66, dark: 0x9AA7A3)
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
        value < 0 ? .gider : (value > 0 ? .gelir : .ikincil)
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
    /// Tutarlar: SF Pro Rounded, sabit genişlikli rakamlar. Boyut en yakın metin stiline bağlanır,
    /// böylece telefonun yazı boyutu (Dynamic Type) ayarıyla birlikte büyür.
    static func amount(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let style: Font.TextStyle = switch size {
        case 30...: .largeTitle
        case 24..<30: .title
        case 20..<24: .title2
        case 17..<20: .body
        case 16..<17: .callout
        case 15..<16: .subheadline
        case 13..<15: .footnote
        case 12..<13: .caption
        default: .caption2
        }
        return .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}
