import SwiftUI

struct MediaArtworkShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(RestingElevation(elevation: .media(0)))
    }
}
