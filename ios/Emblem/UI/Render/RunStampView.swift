import SwiftUI
import EmblemCore

struct RunStampView: View {
    let block: RunStamp

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                hairline
                Text("Automation ran")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize()
                hairline
            }
            VStack(spacing: 3) {
                Text(dateLine)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(timeLine)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.textMargin)
        .padding(.vertical, 6)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.inkSecondary.opacity(0.25))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private var runDate: Date? {
        ISO8601DateFormatter().date(from: block.iso)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: block.iso) }()
    }

    private var dateLine: String {
        guard let date = runDate else { return "" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "EEEE, MMMM d"
        } else {
            formatter.dateFormat = "MMMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    private var timeLine: String {
        guard let date = runDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
