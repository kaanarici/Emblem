import SwiftUI
import EmblemCore

private struct ComparisonCard: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let presentation: ComparisonPresentation
    let columns: [Int]
    var isMulti = false
    var showsAll = false
    let expand: () -> Void
    let zoomNamespace: Namespace.ID
    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        Button(action: { blockInteraction.performActivation(expand) }) {
        TwoColumnBody(entities: presentation.entities, groups: presentation.groups,
                      columns: columns, showsLabels: false, showsDivider: !showsAll)
            .padding(.top, 12)
            .padding(.bottom, 48)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalHeight = $0 }
            .frame(minHeight: isMulti ? CompareMetrics.inlineHeight : nil,
                   maxHeight: CompareMetrics.inlineHeight, alignment: .top)
            .contentShape(Rectangle())
            .overlay {
                if showsAll {
                    Rectangle().fill(Theme.ink.opacity(0.07)).frame(width: 1)
                        .padding(.bottom, 53)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                if naturalHeight > CompareMetrics.inlineHeight {
                    LinearGradient(colors: [.clear, Theme.surface], startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CompareMetrics.cardRadius, style: .continuous))
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: CompareMetrics.cardRadius, style: .continuous))
            .modifier(CardZoomSource(id: presentation.sourceID, namespace: zoomNamespace,
                                     elevation: .rounded(CompareMetrics.cardRadius), drawsRestingShadow: false))
        }
            .buttonStyle(PressableStyle(elevation: .rounded(CompareMetrics.cardRadius)))
            .accessibilityElement(children: .contain)
            .overlay(alignment: showsAll ? .bottom : .bottomTrailing) {
                if showsAll {
                    Button(action: { blockInteraction.performActivation(expand) }) {
                        Text("Show all")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 13)
                            .frame(height: 40)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.06), lineWidth: 1))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Capsule())
                    }
                    .blockActivationControl()
                    .buttonStyle(PressableStyle(pressedScale: 0.985))
                    .accessibilityLabel("Show all")
                    .accessibilityIdentifier("comparison-expand-\(presentation.id)")
                    .padding(.bottom, 11)
                } else {
                    Button(action: { blockInteraction.performActivation(expand) }) {
                        ChromeGlyph(symbol: .expand)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.ink.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    .frame(width: 44, height: 44)
                    .blockActivationControl()
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Expand")
                    .accessibilityIdentifier("comparison-expand-\(presentation.id)")
                    .padding(12)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: CompareMetrics.cardRadius))
            .accessibilityAction(named: Text("Expand comparison")) {
                blockInteraction.performActivation(expand)
            }
            .blockActivationControl()
            .padding(.horizontal, Theme.textMargin)
            .task(id: presentation.id) { await warmExpandedArtwork() }
    }

    private func warmExpandedArtwork() async {
        for entity in presentation.entities {
            if let url = entity.photographicArtworkURL.flatMap(URL.init(string:)) {
                _ = await ImageLoader.shared.image(at: url, maxPixelSize: 600, priority: .utility)
            } else if let spec = entity.photographicArtwork {
                _ = await ImageLoader.shared.image(for: spec, maxPixelSize: 600, priority: .utility)
            }
        }
    }
}

struct SideBySideView: View {
    let block: SideBySide
    @Environment(\.presentComparison) private var presentComparison
    @Environment(\.expansionNamespace) private var sharedExpansionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: ComparisonPresentation?
    @Namespace private var transition

    private var presentation: ComparisonPresentation {
        ComparisonPresentation(id: block.id, title: block.sectionTitle,
                               entities: block.entities, groups: block.comparisonSections)
    }

    var body: some View {
        if block.entities.count >= 2 {
            ComparisonCard(presentation: presentation, columns: [0, 1],
                           isMulti: block.entities.count > 2, showsAll: block.entities.count > 2,
                           expand: expand, zoomNamespace: sharedExpansionNamespace ?? transition)
                .fullScreenCover(item: $expanded) { value in
                    if reduceMotion {
                        ExpandedComparison(presentation: value, dismiss: { expanded = nil })
                    } else {
                        ExpandedComparison(presentation: value, dismiss: { expanded = nil })
                            .navigationTransition(.zoom(sourceID: value.sourceID, in: sharedExpansionNamespace ?? transition))
                    }
                }
        }
    }

    private func expand() {
        if let presentComparison { presentComparison(presentation) }
        else { expanded = presentation }
    }
}

struct OneAgainstManyView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: OneAgainstMany
    @Environment(\.presentComparison) private var presentComparison
    @Environment(\.expansionNamespace) private var sharedExpansionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 0
    @State private var expanded: ComparisonPresentation?
    @Namespace private var transition

    private var selectedIndex: Int { block.challengers.indices.contains(selected) ? selected : 0 }
    private var presentation: ComparisonPresentation {
        let entities = ([block.anchor] + block.challengers).map {
            CompareEntity(name: $0.name, price: $0.price, image: $0.image,
                          imageURL: $0.imageURL, icon: $0.icon)
        }
        return ComparisonPresentation(id: block.id, title: block.sectionTitle,
                                      entities: entities, groups: block.comparisonSections,
                                      selectedChallenger: $selected, selectionOwner: transition)
    }

    var body: some View {
        if !block.challengers.isEmpty {
            VStack(spacing: 23) {
                ComparisonCard(presentation: presentation, columns: [0, selectedIndex + 1],
                               isMulti: true, expand: expand,
                               zoomNamespace: sharedExpansionNamespace ?? transition)
                swapChips
            }
            .fullScreenCover(item: $expanded) { value in
                if reduceMotion {
                    ExpandedComparison(presentation: value, dismiss: { expanded = nil })
                } else {
                    ExpandedComparison(presentation: value, dismiss: { expanded = nil })
                        .navigationTransition(.zoom(sourceID: value.sourceID, in: sharedExpansionNamespace ?? transition))
                }
            }
        }
    }

    private var swapChips: some View {
        ComparisonSwapChips(entities: Array(presentation.entities.dropFirst()), selected: $selected)
    }

    private func expand() {
        if let presentComparison { presentComparison(presentation) }
        else { expanded = presentation }
    }
}

struct ComparisonSwapChips: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entities: [CompareEntity]
    @Binding var selected: Int
    @State private var shown: Int?
    @State private var laps: [Int: Int] = [:]

    private var current: Int {
        let value = shown ?? selected
        return entities.indices.contains(value) ? value : 0
    }

    var body: some View {
        ZStack {
            ForEach(Array(entities.enumerated()), id: \.offset) { index, entity in
                let slot = slot(of: index, around: current)
                let isSelected = index == current
                Button { select(index) } label: {
                    ComparisonSwapChip(entity: entity, isSelected: isSelected)
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CompareMetrics.chipRadius, style: .continuous))
                .blockActivationControl()
                .buttonStyle(.pressable)
                .scaleEffect(isSelected ? 1.11 : 1)
                .offset(x: offset(of: index, slot: slot))
                .zIndex(isSelected ? 1 : -Double(abs(slot)))
                .accessibilityLabel([entity.name, entity.price].compactMap { $0 }.joined(separator: ", "))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .id("\(index)-\(laps[index, default: 0])")
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.16)),
                    removal: .opacity.animation(.easeIn(duration: 0.14))))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > 40, abs(dx) > abs(value.translation.height) * 1.5 else { return }
            if isPair { select(dx < 0 ? 1 : 0) }
            else { select((current + (dx < 0 ? 1 : -1) + entities.count) % entities.count) }
        })
        .sensoryFeedback(.selection, trigger: current)
        .onChange(of: selected) { _, value in
            if value != current { move(to: value) }
        }
    }

    private var isPair: Bool { entities.count == 2 }

    private func offset(of index: Int, slot: Int) -> CGFloat {
        isPair ? (index == 0 ? -0.5 : 0.5) * CompareMetrics.swapPitch : CGFloat(slot) * CompareMetrics.swapPitch
    }

    private func slot(of index: Int, around center: Int) -> Int {
        let count = entities.count
        var distance = ((index - center) % count + count) % count
        if distance > count / 2 { distance -= count }
        return distance
    }

    private func move(to index: Int) {
        guard entities.indices.contains(index) else { return }
        if isPair {
            shown = index
            return
        }
        let step = slot(of: index, around: current)
        for other in entities.indices
        where slot(of: other, around: index) != slot(of: other, around: current) - step {
            laps[other, default: 0] += 1
        }
        shown = index
    }

    private func select(_ index: Int) {
        guard blockInteraction.allowsActivation, index != current else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.12)) {
            move(to: index)
        }
        selected = index
    }
}

private struct ComparisonSwapChip: View {
    let entity: CompareEntity
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            CompareImage(image: entity.photographicArtwork, imageURL: entity.photographicArtworkURL,
                         icon: entity.icon, maxPixelSize: 180, iconSize: 22)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2.5) {
                Text(entity.name)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let price = entity.price {
                    Text(price)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(isSelected ? 1 : 0.42)
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(width: 122, height: 53)
        .contentShape(RoundedRectangle(cornerRadius: CompareMetrics.chipRadius, style: .continuous))
    }
}

struct ComparisonGroupHeading: View {
    let title: String
    let icon: Icon?
    var centered = false
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 20
    private var iconSize: CGFloat { centered ? 49 : 40 }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 13) {
            if let icon { IconView(icon: icon, size: iconSize, glyphFallback: false).offset(y: centered ? 6 : 0).frame(height: centered ? 158 / 3 : 40, alignment: centered ? .center : .top).accessibilityHidden(true) }
            if !title.isEmpty {
                Text(title).font(.system(size: titleSize, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

struct ComparisonRowsLayout: Layout {
    let hasSecondaryContent: [Bool]

    struct Cache {
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowY: [CGFloat] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func measure(proposal: ProposedViewSize, subviews: Subviews) -> Cache {
        guard !subviews.isEmpty else { return Cache() }
        let rowProposal = ProposedViewSize(width: proposal.width, height: nil)
        let dimensions = subviews.map { $0.dimensions(in: rowProposal) }
        var cursor: CGFloat = 6
        var positions: [CGFloat] = []
        for index in dimensions.indices {
            positions.append(cursor)
            cursor += dimensions[index].height
            if index + 1 < dimensions.count {
                cursor += hasSecondaryContent.indices.contains(index) && hasSecondaryContent[index] ? 14 : 13
            }
        }
        cursor += 8
        return Cache(width: dimensions.map(\.width).max() ?? 0, height: cursor, rowY: positions)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        cache = measure(proposal: proposal, subviews: subviews)
        return CGSize(width: cache.width, height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        if cache.width != bounds.width || cache.rowY.count != subviews.count {
            cache = measure(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        }
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX, y: bounds.minY + cache.rowY[index]),
                                 anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}
