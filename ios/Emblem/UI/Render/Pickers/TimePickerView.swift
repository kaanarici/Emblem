import SwiftUI

struct TimePickerView: View {
    @Binding var value: String
    @State private var time = Date()

    var body: some View {
        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            .blockActivationControl()
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 190)
            .padding(.top, 26)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
            .onAppear { write() }
            .onChange(of: time) { write() }
    }

    private func write() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        value = formatter.string(from: time)
    }
}
