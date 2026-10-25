import SwiftUI
import EmblemCore

struct ChoiceOptionList: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let options: [String]
    var rowHeight: CGFloat = 69
    @Binding var selection: String

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    guard blockInteraction.allowsActivation else { return }
                    selection = option
                } label: {
                    Text(option)
                        .font(.system(size: rowHeight > 70 ? 16 : 15.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: rowHeight)
                        .background(InputOptionBackground(selected: isSelected))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .blockActivationControl()
                .buttonStyle(.pressable)
                .animation(.smooth(duration: 0.2), value: isSelected)
                .accessibilityIdentifier("choice-\(option)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct ChoiceChips: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let options: [String]
    @Binding var selection: String

    var body: some View {
        LeadingFlowLayout(spacing: 7, lineSpacing: 6) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    guard blockInteraction.allowsActivation else { return }
                    selection = option
                } label: {
                    Text(option)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 11.5)
                        .frame(height: 40)
                        .background(InputOptionBackground(selected: isSelected, radius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .blockActivationControl()
                .buttonStyle(.pressable)
                .animation(.smooth(duration: 0.2), value: isSelected)
                .accessibilityIdentifier("choice-\(option)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct ChoiceCardGrid: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let options: [String]
    let icons: [Icon]
    var multiple = false
    @Binding var selection: String

    static let cardHeight: CGFloat = 168
    static let rowSpacing: CGFloat = 12

    var body: some View {
        let picks = multiple ? Self.picks(in: selection, from: options) : [selection]
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: Self.rowSpacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = picks.contains(option)
                Button {
                    guard blockInteraction.allowsActivation else { return }
                    selection = multiple ? Self.toggling(option, in: picks, from: options) : option
                } label: {
                    VStack(spacing: 0) {
                        IconView(icon: Icon(sfSymbol: "sparkles",
                                            image: icons.indices.contains(index) ? icons[index].image : nil),
                                 size: 72, cardGlyph: true)
                            .frame(width: 72, height: 72)
                            .padding(.top, 32)
                        Text(option)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.cardHeight)
                    .background(InputOptionBackground(selected: isSelected, radius: 17, rest: InputPalette.tile))
                    .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .blockActivationControl()
                .buttonStyle(.pressable)
                .sensoryFeedback(.selection, trigger: isSelected)
                .animation(.smooth(duration: 0.2), value: isSelected)
                .accessibilityIdentifier("choice-\(option)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    static func picks(in value: String, from options: [String]) -> Set<String> {
        let parts = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return Set(options.filter { parts.contains($0.lowercased()) })
    }

    static func toggling(_ option: String, in picks: Set<String>, from options: [String]) -> String {
        let next = picks.symmetricDifference([option])
        return options.filter(next.contains).joined(separator: ", ")
    }
}

struct LeadingFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var centered = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX + (centered ? (bounds.width - row.width) / 2 : 0)
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if var last = rows.last, last.width + spacing + size.width <= width {
                last.indices.append(index)
                last.sizes.append(size)
                last.width += spacing + size.width
                last.height = max(last.height, size.height)
                rows[rows.count - 1] = last
            } else {
                rows.append(Row(indices: [index], sizes: [size], width: size.width, height: size.height))
            }
        }
        return rows
    }
}
