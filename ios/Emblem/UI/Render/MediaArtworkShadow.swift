import SwiftUI

struct MediaArtworkShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.13), radius: 12, y: 5)
            .shadow(color: .black.opacity(0.05), radius: 1.3, y: 1)
    }
}
