import SwiftUI

struct GroupedRowShape: Shape {
    let index: Int
    let count: Int
    var outer: CGFloat = 18
    var inner: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let top = index == 0 ? outer : inner
        let bottom = index == count - 1 ? outer : inner
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top,
            style: .continuous).path(in: rect)
    }
}

extension View {
    func groupedRowShadow() -> some View {
        compositingGroup()
            .shadow(color: .black.opacity(0.05), radius: 0.6, y: 0.8)
    }
}
