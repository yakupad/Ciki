import Foundation

/// IBAN biçimlendirme ve ISO 13616 (mod 97) doğrulaması.
nonisolated enum IBAN {
    /// Boşluksuz, büyük harf: "TR330006100519786457841326"
    static func normalized(_ raw: String) -> String {
        raw.uppercased(with: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Dörder gruplanmış: "TR33 0006 1005 1978 6457 8413 26"
    static func formatted(_ raw: String) -> String {
        let compact = normalized(raw)
        return stride(from: 0, to: compact.count, by: 4).map { offset in
            let start = compact.index(compact.startIndex, offsetBy: offset)
            let end = compact.index(start, offsetBy: 4, limitedBy: compact.endIndex) ?? compact.endIndex
            return String(compact[start..<end])
        }.joined(separator: " ")
    }

    enum Validity: Equatable {
        case empty
        case incomplete(expected: Int)
        case valid
        case invalid
    }

    static func validate(_ raw: String) -> Validity {
        let compact = normalized(raw)
        guard !compact.isEmpty else { return .empty }
        if compact.hasPrefix("TR"), compact.count < 26 { return .incomplete(expected: 26) }
        guard compact.count >= 15, compact.count <= 34,
              compact.prefix(2).allSatisfy(\.isLetter),
              compact.dropFirst(2).prefix(2).allSatisfy(\.isNumber) else {
            return compact.count < 15 ? .incomplete(expected: 15) : .invalid
        }
        if compact.hasPrefix("TR"), compact.count != 26 { return .invalid }
        return checksum(compact) == 1 ? .valid : .invalid
    }

    /// İlk dört karakter sona alınır, harfler sayıya çevrilir (A=10…Z=35) ve 97'ye bölümden kalan hesaplanır.
    private static func checksum(_ compact: String) -> Int {
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            let digits: String
            if let number = character.wholeNumberValue {
                digits = String(number)
            } else if let ascii = character.asciiValue, character.isLetter {
                digits = String(Int(ascii) - 55)
            } else {
                return -1
            }
            for digit in digits {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder
    }
}
