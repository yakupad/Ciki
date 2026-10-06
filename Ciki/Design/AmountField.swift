import SwiftUI

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

/// Yazarken binlik ayırıcı ekleyen tutar alanı. Klavyenin üstünde "000" ve "Bitti" düğmeleri olur.
struct AmountField: View {
    @Binding var value: Decimal?
    let prompt: String
    /// Ekran açılınca klavye hemen gelsin mi (yeni kayıt girerken).
    let autofocus: Bool

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(value: Binding<Decimal?>, prompt: String = "0", autofocus: Bool = false) {
        _value = value
        self.prompt = prompt
        self.autofocus = autofocus
        self.text = AmountInput.text(for: value.wrappedValue)
    }

    var body: some View {
        TextField(prompt, text: $text)
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .monospacedDigit()
            .onAppear { if autofocus { isFocused = true } }
            .onChange(of: text) { _, newText in
                let formatted = AmountInput.format(newText)
                if formatted.text != newText { text = formatted.text }
                if formatted.value != value { value = formatted.value }
            }
            .onChange(of: value) { _, newValue in
                // Dışarıdan değişti (ör. öneri çipi): alan yeniden yazılır.
                if AmountInput.format(text).value != newValue { text = AmountInput.text(for: newValue) }
            }
            .toolbar {
                if isFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button("Temizle") { text = "" }
                        Button {
                            text = AmountInput.format(text + "000").text
                        } label: {
                            Text(verbatim: "000").monospacedDigit()
                        }
                        .accessibilityLabel(Text("Üç sıfır ekle"))
                        Spacer()
                        Button("Bitti") { isFocused = false }
                            .fontWeight(.semibold)
                    }
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
