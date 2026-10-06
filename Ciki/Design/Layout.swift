import SwiftUI

extension EnvironmentValues {
    /// Pencere 600 pt'den genişse iki sütunlu düzen. Boyut sınıfı yerine genişliğe bakılır; iPhone Duo'nun
    /// iç ekranı iPhone olduğu için "dar" sınıfta raporlanabilir ama iPad mini kadar geniştir.
    @Entry var isWideLayout = false
}

extension View {
    /// Pencerenin genişliğini ölçüp `isWideLayout` değerini alt görünümlere iletir.
    func measuresWideLayout() -> some View {
        modifier(WideLayoutReader())
    }

    /// Geniş ekranlarda (iPad, iPhone Duo iç ekranı, Mac) listeyi okunur genişlikte ortalar.
    func readableWidth(_ maxWidth: CGFloat = 860) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

private struct WideLayoutReader: ViewModifier {
    @State private var isWide = false

    func body(content: Content) -> some View {
        content
            .environment(\.isWideLayout, isWide)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 600 } action: { isWide = $0 }
    }
}
