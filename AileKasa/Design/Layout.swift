import SwiftUI

extension View {
    /// Geniş ekranlarda (iPad, iPhone Duo iç ekranı, Mac) listeyi okunur genişlikte ortalar.
    func readableWidth(_ maxWidth: CGFloat = 860) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}
