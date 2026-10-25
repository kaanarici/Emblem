import SwiftUI

struct TextPickerView: View {
    let question: String
    @Binding var value: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack {
            TextField(question, text: $value, axis: .vertical)
                .blockActivationControl()
                .font(.system(size: 18))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                .padding(.horizontal, Theme.pageMargin)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .task { focused = true }
    }
}
