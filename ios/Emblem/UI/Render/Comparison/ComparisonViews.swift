import SwiftUI
import EmblemCore

enum CompareMetrics {
    static let cardRadius: CGFloat = 28
    static let imageRadius: CGFloat = 16
    static let rowSpacing: CGFloat = 14
    static let inlineRowSpacing: CGFloat = 46 / 3
    static let columnWidth: CGFloat = 180
    static let columnGap: CGFloat = 16
    static let expandedInset: CGFloat = 32
    static let inlineHeight: CGFloat = 468
    static let peerColumnFraction: CGFloat = 196 / 440
    static let swapPitch: CGFloat = 143
    static let chipRadius: CGFloat = 15
    static let swapDuration: TimeInterval = 0.25
    static let swapBlur: CGFloat = 6
    static let inlineSwapDelay: TimeInterval = 0
    static let expandedSwapDelay: TimeInterval = 0
}

struct ComparisonPresentation: Hashable, Identifiable {
    let id: String
    let title: String?
    let entities: [CompareEntity]
    let groups: [CompareSection]
    var selectedChallenger: Binding<Int>? = nil
    var selectionOwner: Namespace.ID? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.entities == rhs.entities
            && lhs.groups == rhs.groups
            && lhs.selectionOwner == rhs.selectionOwner
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(entities)
        hasher.combine(groups)
        hasher.combine(selectionOwner)
    }

    var sourceID: String { "comparison-\(id)" }

    var shareText: String {
        let heading = entities.map(\.name).joined(separator: "\t")
        let sections = groups.map { group in
            ([group.title] + group.rows.map { row in
                ([row.label ?? ""] + row.values.map(\.text)).joined(separator: "\t")
            }).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return ([title ?? "", heading] + sections).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

private struct PresentComparisonKey: EnvironmentKey {
    static let defaultValue: (@MainActor (ComparisonPresentation) -> Void)? = nil
}

extension EnvironmentValues {
    var presentComparison: (@MainActor (ComparisonPresentation) -> Void)? {
        get { self[PresentComparisonKey.self] }
        set { self[PresentComparisonKey.self] = newValue }
    }
}

private func verdictColor(_ verdict: CompareVerdict?) -> Color {
    switch verdict {
    case .good: Theme.comparisonPositive
    case .bad: Theme.comparisonNegative
    case nil: Theme.inkSecondary
    }
}

private func verdictFill(_ verdict: CompareVerdict?) -> Color {
    switch verdict {
    case .good: Theme.comparisonPositiveFill
    case .bad: Theme.comparisonNegativeFill
    case nil: Theme.chip
    }
}

private func verdictLabel(_ text: String, _ verdict: CompareVerdict) -> String {
    verdict == .good ? "Positive: \(text)" : "Negative: \(text)"
}

func compareCellAccessibility(entity: String, axis: String, cell: CompareCell?) -> String {
    guard let cell else { return "\(axis), \(entity), no value" }
    let verdict: String? = switch cell.verdict {
    case .good: "positive"
    case .bad: "negative"
    case nil: nil
    }
    return [axis, entity, cell.text, verdict, cell.chipLabel].compactMap { $0 }.joined(separator: ", ")
}

private enum ComparePrimaryCenter: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
}

extension VerticalAlignment {
    static let comparePrimaryCenter = VerticalAlignment(ComparePrimaryCenter.self)
}

struct CompareValueView: View {
    let cell: CompareCell?
    var centered = true
    var expanded = false
    var usesPrimaryEnvelope = false
    var hasAnnotationRow = false
    @ScaledMetric(relativeTo: .subheadline) private var valueSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var chipSize: CGFloat = 12

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: usesPrimaryEnvelope || (cell?.verdict == nil && cell?.chipLabel != nil) ? 6 : 10 / 3) {
            VStack(alignment: centered ? .center : .leading, spacing: expanded ? 13 : 16) {
                ForEach(Array((cell?.text ?? "–").components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: expanded ? valueSize * 14 / 12 : valueSize))
                        .lineSpacing(expanded ? 1 : 0)
                        .foregroundStyle(cell == nil ? Theme.inkSecondary : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .alignmentGuide(.comparePrimaryCenter) { $0[VerticalAlignment.center] }
            if let cell, let chip = cell.chipLabel {
                if let verdict = cell.verdict {
                    if usesPrimaryEnvelope {
                        Text(chip)
                            .font(.system(size: chipSize))
                            .foregroundStyle(verdictColor(verdict))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(verdictFill(verdict))
                                    .padding(.vertical, -2)
                            }
                            .accessibilityLabel(verdictLabel(chip, verdict))
                    } else {
                        Text(chip)
                            .font(.system(size: chipSize))
                            .foregroundStyle(verdictColor(verdict))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(verdictFill(verdict), in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel(verdictLabel(chip, verdict))
                    }
                } else {
                    Text(chip)
                        .font(.system(size: expanded ? valueSize * 14 / 12 : valueSize))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if hasAnnotationRow {
                Text("–")
                    .font(.system(size: chipSize))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.vertical, usesPrimaryEnvelope ? 0 : 2)
            }
        }
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

struct EntityHeader: View {
    let entity: CompareEntity
    var expanded = false
    var showsImage = true
    var showsIcon = true
    var leading = false
    @ScaledMetric(relativeTo: .caption) private var nameSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var priceSize: CGFloat = 14

    var body: some View {
        VStack(alignment: leading ? .leading : .center, spacing: 6) {
            if showsImage {
                CompareImage(image: entity.photographicArtwork, imageURL: entity.photographicArtworkURL, icon: entity.icon,
                             maxPixelSize: expanded ? 600 : 180, iconSize: 40,
                             showsSkeleton: true)
                    .frame(height: 128)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: CompareMetrics.imageRadius))
                    .padding(.horizontal, expanded ? 12 : 0)
                    .padding(.bottom, 7 / 3)
            } else if showsIcon && entity.icon != nil {
                IconView(icon: entity.icon, size: 40)
                    .frame(height: 48)
            }
            Text(entity.name)
                .font(.system(size: nameSize, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let price = entity.price {
                Text(price)
                    .font(.system(size: priceSize))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(leading ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }
}

struct CompareImage: View {
    let image: ImageSpec?
    var imageURL: String? = nil
    let icon: Icon?
    let maxPixelSize: CGFloat
    let iconSize: CGFloat
    var showsSkeleton = false

    var body: some View {
        if image != nil || imageURL != nil {
            RemoteImage(spec: image, url: imageURL.flatMap(URL.init(string:)),
                        maxPixelSize: maxPixelSize,
                        contentMode: image?.kind == .object ? .fit : .fill,
                        showsSkeleton: showsSkeleton)
                .padding(image?.kind == .object ? 14 : 0)
                .background(Theme.surface)
        } else if icon != nil {
            ZStack {
                Rectangle().fill(Theme.cardSoft)
                IconView(icon: icon, size: iconSize)
            }
        } else {
            Rectangle().fill(Theme.cardSoft)
        }
    }
}

struct TwoColumnBody: View {
    let entities: [CompareEntity]
    let groups: [CompareSection]
    let columns: [Int]
    var showsLabels = true
    var showsDivider = true

    private var pair: [CompareEntity] { columns.map { entities[$0] } }
    private var rows: [(axis: String, row: CompareSection.Row)] {
        groups.flatMap { group in group.rows.map { (group.title, $0) } }
    }
    private var showsImages: Bool {
        pair.contains { $0.photographicArtwork != nil || $0.photographicArtworkURL != nil }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(pair.enumerated()), id: \.offset) { slot, entity in
                    EntityHeader(entity: entity, showsImage: showsImages)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .id(columns[slot])
                        .transition(.comparisonSwap)
                }
            }
            VStack(spacing: CompareMetrics.inlineRowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, entry in
                    let row = entry.row
                    VStack(spacing: 6) {
                        if showsLabels, let label = row.label, !label.isEmpty {
                            Text(label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        HStack(alignment: .comparePrimaryCenter, spacing: 0) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                                let cell = row.values.indices.contains(column) ? row.values[column] : nil
                                CompareValueView(cell: cell, hasAnnotationRow: columns.contains { index in
                                    row.values.indices.contains(index) && row.values[index].chipLabel != nil
                                })
                                    .padding(.horizontal, 12)
                                    .id(column)
                                    .transition(.comparisonSwap)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(compareCellAccessibility(
                                        entity: entities[column].name,
                                        axis: row.label ?? entry.axis, cell: cell))
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            Rectangle().fill(Theme.ink.opacity(0.07)).frame(width: 1)
                .padding(.top, -12)
                .padding(.bottom, -8)
                .opacity(showsDivider ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}
