import FoundationModels
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@available(iOS 26, macOS 26, *)
enum ApplePageBlocks {
    static func blocks(from page: ApplePage.PartiallyGenerated) -> [Block] {
        var result: [Block] = []
        if let title = clean(page.title) { result.append(.pageMeta(PageMeta(id: "apple-meta", title: title, dockAction: nil))) }
        if let intro = clean(page.intro) { result.append(.text(TextBlock(id: "apple-intro", body: intro, style: .intro))) }
        for (index, section) in (page.sections ?? []).prefix(5).enumerated() {
            let id = "apple-section-\(index)"
            let text = clean(section.text).map { Block.text(TextBlock(id: id + "-text", body: $0, style: .body)) }
            let content = section.content.flatMap { block(id: id, from: $0) }
            guard text != nil || content != nil else { continue }
            if let heading = clean(section.heading) {
                result.append(.sectionHeader(SectionHeader(id: id + "-heading", title: heading, subtitle: nil)))
            }
            result += [text, content].compactMap { $0 }
        }
        let chips = (page.followUps ?? []).prefix(3).compactMap(clean).map { ChipRow.Chip(label: $0) }
        if !chips.isEmpty { result.append(.chipRow(ChipRow(id: "apple-follow-ups", role: .followUp, title: nil, chips: chips))) }
        return result
    }

    private static func block(id: String, from content: AppleSection.Content.PartiallyGenerated) -> Block? {
        switch content {
        case .cards(let values):
            let cards = (values ?? []).prefix(8).compactMap { card -> CardCarousel.Card? in
                guard let title = clean(card.title) else { return nil }
                let image = card.imageKind.flatMap { kind in imageQuery(card.image).map { ImageSpec(query: $0, kind: imageKind(kind)) } }
                return .init(image: image, title: title, caption: clean(card.caption), prompt: "Tell me more about \(title)")
            }
            return cards.isEmpty ? nil : .cardCarousel(CardCarousel(id: id, cards: cards))
        case .bullets(let values):
            let items = (values ?? []).compactMap(clean).prefix(8).map { ListBlock.Item(icon: nil, text: $0) }
            return items.isEmpty ? nil : .listBlock(ListBlock(id: id, style: .bullet, items: items))
        case .facts(let values):
            let facts = (values ?? []).prefix(6).compactMap { value -> FactList.Fact? in
                guard let label = clean(value.label), let text = clean(value.value) else { return nil }
                return .init(icon: symbol(value.sfSymbol), label: label, value: text)
            }
            return facts.isEmpty ? nil : .factList(FactList(id: id, facts: facts))
        case .stats(let values):
            let stats = (values ?? []).prefix(4).compactMap { value -> StatRow.Stat? in
                guard let number = clean(value.value), let label = clean(value.label) else { return nil }
                return .init(value: number, label: label)
            }
            return stats.isEmpty ? nil : .statRow(StatRow(id: id, stats: stats))
        case .steps(let values):
            let steps = (values ?? []).prefix(8).compactMap { value -> StepCarousel.Step? in
                guard let title = clean(value.title), let detail = clean(value.detail) else { return nil }
                return .init(sfSymbol: validSymbol(value.sfSymbol), title: title, body: detail)
            }
            return steps.isEmpty ? nil : .stepCarousel(StepCarousel(id: id, steps: steps))
        case .timeline(let values):
            let items = (values ?? []).prefix(8).compactMap { value -> Timeline.Item? in
                guard let time = clean(value.time), let title = clean(value.title) else { return nil }
                return .init(time: time, title: title, caption: clean(value.caption), icon: nil)
            }
            return items.isEmpty ? nil : .timeline(Timeline(id: id, items: items))
        case .items(let values):
            let items = (values ?? []).prefix(8).compactMap { value -> ItemGrid.Item? in
                guard let title = clean(value.title) else { return nil }
                return .init(icon: symbol(value.sfSymbol), title: title, caption: clean(value.caption))
            }
            return items.isEmpty ? nil : .itemGrid(ItemGrid(id: id, items: items, columns: nil))
        case .quote(let quote):
            return clean(quote?.text).map { .quote(Quote(id: id, text: $0, attribution: clean(quote?.attribution))) }
        case .chart(let chart):
            guard let chart, let kind = chart.kind else { return nil }
            let points = (chart.points ?? []).prefix(12).compactMap { value -> ChartBlock.Point? in
                guard let label = clean(value.label), let number = value.value, number.isFinite else { return nil }
                return .init(label: label, value: number)
            }
            guard points.count >= 2, kind != .pie || points.allSatisfy({ $0.value >= 0 }) else { return nil }
            let nativeKind: ChartBlock.Kind = switch kind { case .bar: .bar; case .line: .line; case .pie: .pie }
            return .chart(ChartBlock(id: id, kind: nativeKind, title: clean(chart.title), unit: clean(chart.unit), colors: nil, series: [.init(name: nil, points: points)]))
        case .comparison(let comparison):
            let columns = (comparison?.columns ?? []).compactMap(clean)
            guard (2...3).contains(columns.count) else { return nil }
            let rows = (comparison?.rows ?? []).prefix(6).compactMap { row -> SideBySide.Row? in
                let values = (row.values ?? []).compactMap(clean)
                guard let label = clean(row.label), values.count == columns.count, values != columns else { return nil }
                return .init(label: label, values: values.map { CompareCell(text: $0) })
            }
            guard !rows.isEmpty else { return nil }
            let entities = columns.map { CompareEntity(name: $0, price: nil, image: nil, imageURL: nil, icon: nil) }
            return .sideBySide(SideBySide(id: id, sectionTitle: nil, sectionIcon: nil, entities: entities, rows: rows))
        case .writing(let draft):
            guard let label = clean(draft?.label), let body = clean(draft?.body), body.utf16.count <= 20_000 else { return nil }
            return .writing(WritingBlock(id: id, title: nil, drafts: [.init(id: id + "-draft", label: label, sym: "square.and.pencil", body: body)]))
        }
    }

    static func isValid(_ page: ApplePage) -> Bool {
        clean(page.title) != nil && clean(page.intro) != nil && (1...5).contains(page.sections.count)
    }

    private static func imageKind(_ kind: AppleCard.Kind) -> ImageSpec.Kind {
        switch kind {
        case .photo: .photo
        case .poster: .poster
        case .logo: .logo
        }
    }

    private static func imageQuery(_ text: String?) -> String? {
        var words = (clean(text) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "'\"")).split(separator: " ")
        while let last = words.last, ["photo", "image", "picture"].contains(last.lowercased()) { words.removeLast() }
        let query = words.joined(separator: " ")
        return query.isEmpty || query.count > 80 || query.contains("://") ? nil : query
    }

    private static func symbol(_ name: String?) -> Icon? {
        validSymbol(name).map { Icon(sfSymbol: $0) }
    }

    private static func validSymbol(_ name: String?) -> String? {
        guard let name = clean(name) else { return nil }
        #if canImport(UIKit)
        return UIImage(systemName: name) == nil ? nil : name
        #else
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? nil : name
        #endif
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

private extension ListBlock {
    init(id: String, style: Style, items: [Item]) { self.id = id; self.style = style; self.items = items }
}
private extension ChartBlock {
    init(id: String, kind: Kind, title: String?, unit: String?, colors: [String]?, series: [Series]) {
        self.id = id; self.kind = kind; self.title = title; self.unit = unit; self.colors = colors; self.series = series
    }
}
private extension WritingBlock {
    init(id: String, title: String?, drafts: [Draft]) { self.id = id; self.title = title; self.drafts = drafts }
}
private extension StatRow.Stat {
    init(value: String, label: String) { self.value = value; self.label = label }
}
private extension ChipRow.Chip {
    init(label: String) { self.label = label }
}
