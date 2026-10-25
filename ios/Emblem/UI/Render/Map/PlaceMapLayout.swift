#if canImport(UIKit)
import UIKit
typealias PlaceLabelFont = UIFont
#else
import AppKit
typealias PlaceLabelFont = NSFont
#endif
import EmblemCore

struct PlaceMapLayout: Equatable {
    struct Entry {
        let id: String
        let name: String
        let category: String?
    }

    enum Role: Equatable {
        case marker
        case cluster(Int)
        case hidden
    }

    private(set) var roles: [String: Role] = [:]
    private(set) var members: [String: [String]] = [:]
    private(set) var labeled: Set<String> = []

    static let markerDiameter: CGFloat = 32
    static let balloonDiameter: CGFloat = 66
    static let balloonTail: CGFloat = 11
    static let labelWidth: CGFloat = 124
    static let selectedLabelScale: CGFloat = 12 / 11
    private static let gap: CGFloat = 3

    func role(_ id: String) -> Role { roles[id] ?? .marker }
    func absorbed(_ id: String) -> Int { max((members[id]?.count ?? 1) - 1, 0) }

    init(_ entries: [Entry], at points: [String: CGPoint], selectedID: String?) {
        let ordered = entries.filter { $0.id == selectedID } + entries.filter { $0.id != selectedID }
        var footprints: [(id: String, rect: CGRect)] = []
        for entry in ordered {
            guard let point = points[entry.id] else { continue }
            let circle = Self.circle(at: point)
            if let host = footprints.first(where: { $0.rect.intersects(circle) }) {
                members[host.id, default: []].append(entry.id)
                roles[entry.id] = .hidden
                continue
            }
            members[entry.id] = [entry.id]
            roles[entry.id] = .marker
            let rect = entry.id == selectedID
                ? Self.balloon(at: point).union(Self.labelRect(entry, at: point, selected: true))
                : circle
            footprints.append((entry.id, rect))
        }
        for (id, group) in members where group.count > 1 && id != selectedID {
            roles[id] = .cluster(group.count)
        }

        var labels: [CGRect] = []
        for entry in ordered where roles[entry.id] == .marker {
            guard let point = points[entry.id] else { continue }
            let selected = entry.id == selectedID
            let rect = Self.labelRect(entry, at: point, selected: selected)
            if !selected {
                let blocked = footprints.contains { $0.id != entry.id && $0.rect.intersects(rect) }
                    || labels.contains { $0.intersects(rect) }
                if blocked { continue }
            }
            labels.append(rect)
            labeled.insert(entry.id)
        }
    }

    static func circle(at point: CGPoint) -> CGRect {
        let radius = markerDiameter / 2 + gap / 2
        return CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }

    static func balloon(at point: CGPoint) -> CGRect {
        let radius = balloonDiameter / 2 + gap
        return CGRect(x: point.x - radius, y: point.y - balloonTail - balloonDiameter - gap,
                      width: radius * 2, height: balloonTail + balloonDiameter + gap)
    }

    static func labelRect(_ entry: Entry, at point: CGPoint, selected: Bool) -> CGRect {
        let nameWidth = textWidth(entry.name, font: nameFont)
        let categoryWidth = entry.category.map { textWidth($0, font: categoryFont) } ?? 0
        let nameLines: CGFloat = nameWidth > labelWidth ? 2 : 1
        let scale = selected ? selectedLabelScale : 1
        let width = (min(labelWidth, max(nameWidth, categoryWidth)) + 4) * scale
        let height = (nameLines * lineHeight(nameFont) + (entry.category == nil ? 0 : lineHeight(categoryFont))) * scale
        let top = point.y + (selected ? gap : markerDiameter / 2 + gap)
        return CGRect(x: point.x - width / 2, y: top, width: width, height: height)
    }

    static var nameFont: PlaceLabelFont { .systemFont(ofSize: 10, weight: .semibold) }
    static var categoryFont: PlaceLabelFont { .systemFont(ofSize: 11) }

    private static func textWidth(_ text: String, font: PlaceLabelFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func lineHeight(_ font: PlaceLabelFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }
}

extension MapBlock.Place {
    var displayName: String {
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let city = locality.flatMap { $0.split(separator: ",").first }
            .map { fold(String($0)).trimmingCharacters(in: .whitespaces) }
        for separator in [", ", " - ", " – ", " | "] {
            guard let range = name.range(of: separator) else { continue }
            let head = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let tail = fold(String(name[range.upperBound...]))
            let isSuffix = tail.contains("member of") || tail.hasPrefix("by ")
                || city.map { !$0.isEmpty && tail.hasPrefix($0) } == true
            if isSuffix, head.count >= 3 { return head }
        }
        return name
    }
}
