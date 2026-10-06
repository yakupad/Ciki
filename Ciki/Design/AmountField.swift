import SwiftUI
import UIKit

/// Tutar yazarken metni anında biçimler: "125000" → "125.000", "1234,5" → "1.234,5".
/// Binlik ayırıcıyı kullanıcı yazmaz; ondalık ayırıcı ("," ya da ".") bir kez ve en fazla iki hane kabul edilir.
nonisolated enum AmountInput {
    static func format(_ raw: String, locale: Locale = Money.locale) -> (text: String, value: Decimal?) {
        let decimalSeparator = locale.decimalSeparator ?? ","
        let groupingSeparator = locale.groupingSeparator ?? "."

        var integer = ""
        var fraction: String?
        for character in raw {
            if character.isASCII, character.isNumber {
                if fraction != nil {
                    if fraction!.count < 2 { fraction!.append(character) }
                } else {
                    integer.append(character)
                }
            } else if fraction == nil, String(character) == decimalSeparator
                        || (character == "," || character == ".") && String(character) != groupingSeparator {
                // Ondalık ayırıcı; yerel ayarın binlik ayırıcısı (ör. Türkçede ".") yok sayılır.
                fraction = ""
            }
        }
        // Baştaki sıfırlar atılır ama "0,5" gibi yazımlarda bir sıfır kalır.
        while integer.count > 1, integer.hasPrefix("0") { integer.removeFirst() }
        if integer.isEmpty, fraction != nil { integer = "0" }
        guard !integer.isEmpty else { return ("", nil) }

        var grouped = ""
        for (index, digit) in integer.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.insert(contentsOf: groupingSeparator, at: grouped.startIndex) }
            grouped.insert(digit, at: grouped.startIndex)
        }
        let text = fraction.map { grouped + decimalSeparator + $0 } ?? grouped
        let value = Decimal(string: integer + (fraction.map { $0.isEmpty ? "" : "." + $0 } ?? ""),
                            locale: Locale(identifier: "en_US_POSIX"))
        return (text, value)
    }

    /// Kayıtlı bir tutarın alanda görünen hali: "125000" → "125.000", "1234.5" → "1.234,50".
    static func text(for value: Decimal?, locale: Locale = Money.locale) -> String {
        guard let value else { return "" }
        let hasFraction = value != value.rounded(scale: 0)
        return value.formatted(.number.locale(locale).precision(.fractionLength(hasFraction ? 2 : 0)))
    }
}

/// Yazarken binlik ayırıcı ekleyen tutar alanı. UIKit metin alanı kullanılır; böylece biçimleme
/// sonrası imleç aynı rakamın yanında kalır ve binlik noktası üzerinde geri silme bir rakam siler.
struct AmountField: UIViewRepresentable {
    @Binding var value: Decimal?
    /// Yazı boyutu (Dynamic Type ile büyür) ve kalınlığı; tutarlar SF Pro Rounded'dır.
    var size: CGFloat = 17
    var weight: UIFont.Weight = .semibold
    var alignment: NSTextAlignment = .right
    var color: UIColor = .label
    /// Ekran açılınca klavye hemen gelsin mi (yeni kayıt girerken).
    var autofocus = false

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.placeholder = "0"
        field.text = AmountInput.text(for: value)
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.value = $value
        field.font = Self.font(size: size, weight: weight)
        field.textAlignment = alignment
        field.textColor = color
        // Dışarıdan değişti (ör. öneri çipi): alan yeniden yazılır.
        if AmountInput.format(field.text ?? "").value != value {
            field.text = AmountInput.text(for: value)
        }
        if autofocus, !context.coordinator.didAutofocus {
            context.coordinator.didAutofocus = true
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        let height = uiView.intrinsicContentSize.height
        return CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: height)
    }

    /// `Font.amount` ile aynı eşleme: boyut en yakın metin stiline bağlanır.
    static func font(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let style: UIFont.TextStyle = switch size {
        case 30...: .largeTitle
        case 24..<30: .title1
        case 20..<24: .title2
        case 17..<20: .body
        default: .subheadline
        }
        var font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        if let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: rounded, size: size)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Decimal?>
        var didAutofocus = false

        init(value: Binding<Decimal?>) { self.value = value }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard var editRange = Range(range, in: current) else { return false }
            let grouping = Money.locale.groupingSeparator ?? "."
            // Binlik noktası üzerinde geri silme: noktadan önceki rakam silinir.
            if string.isEmpty, current[editRange] == grouping, editRange.lowerBound > current.startIndex {
                editRange = current.index(before: editRange.lowerBound)..<editRange.upperBound
            }
            // İmleçten sonra kaç anlamlı karakter (rakam ya da ondalık ayırıcı) kaldığı korunur.
            let trailing = Self.significantCount(current[editRange.upperBound...], grouping: grouping)
            let proposed = current.replacingCharacters(in: editRange, with: string)
            let formatted = AmountInput.format(proposed)
            textField.text = formatted.text
            Self.placeCaret(in: textField, trailingSignificant: trailing, grouping: grouping)
            if formatted.value != value.wrappedValue { value.wrappedValue = formatted.value }
            return false
        }

        private static func significantCount(_ text: Substring, grouping: String) -> Int {
            text.filter { String($0) != grouping }.count
        }

        private static func placeCaret(in field: UITextField, trailingSignificant: Int, grouping: String) {
            let text = field.text ?? ""
            var index = text.endIndex
            var remaining = trailingSignificant
            while remaining > 0, index > text.startIndex {
                index = text.index(before: index)
                if String(text[index]) != grouping { remaining -= 1 }
            }
            let offset = text.distance(from: text.startIndex, to: index)
            if let position = field.position(from: field.beginningOfDocument, offset: offset) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
        }
    }
}

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
/// Pencerede metin alanı dışında bir yere dokununca klavyeyi kapatır.
/// Dokunuşu iptal etmez; düğmeler ve satırlar çalışmaya devam eder.
struct KeyboardDismissOnTap: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, window !== installedWindow else { return }
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            // Dokunuş SwiftUI düğmelerine gecikmeden ve iptal edilmeden ulaşır.
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            installedWindow = window
            isUserInteractionEnabled = false
        }

        @objc private func dismissKeyboard() {
            installedWindow?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Metin alanına dokunmak klavyeyi kapatmaz.
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
#endif

extension View {
    /// Boş bir yere dokununca klavyeyi kapatır (iPhone ve iPad). Uygulamanın kök görünümüne bir kez eklenir.
    func dismissesKeyboardOnTap() -> some View {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        background(KeyboardDismissOnTap().frame(width: 0, height: 0))
        #else
        self
        #endif
    }
}
