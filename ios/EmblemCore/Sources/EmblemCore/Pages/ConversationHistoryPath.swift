import Foundation

public enum ConversationHistoryPath {
    public struct Entry {
        let key: String
        let previousKey: String?
        var isExpansion = false

        public init(key: String, previousKey: String?, isExpansion: Bool = false) {
            self.key = key
            self.previousKey = previousKey
            self.isExpansion = isExpansion
        }
    }

    public static func indices(in entries: [Entry], preferredLeafKey: String? = nil) -> [Int] {
        let ordinary = entries.indices.filter { !entries[$0].isExpansion }
        guard !ordinary.isEmpty else { return [] }
        guard entries.contains(where: { $0.previousKey != nil }) else { return ordinary }
        let byKey = entries.indices.reduce(into: [String: Int]()) { $0[entries[$1].key] = $1 }
        func predecessor(at index: Int) -> String? {
            guard let key = entries[index].previousKey, key != entries[index].key else { return nil }
            return key
        }
        var ancestors = Set<String>()
        for child in ordinary {
            var next = predecessor(at: child)
            var seen = Set<String>()
            while let key = next, seen.insert(key).inserted, let parent = byKey[key] {
                ancestors.insert(key)
                next = predecessor(at: parent)
            }
        }
        let leaves = ordinary.filter { !ancestors.contains(entries[$0].key) }
        guard var index = preferredLeafKey.flatMap({ key in leaves.last { entries[$0].key == key } })
                ?? leaves.last else { return [] }
        var path: [Int] = []
        var visited = Set<Int>()
        while visited.insert(index).inserted {
            path.append(index)
            guard let previousKey = predecessor(at: index) else {
                path.append(contentsOf: ordinary.filter {
                    $0 < index && entries[$0].previousKey == nil && !visited.contains($0)
                }.reversed())
                return path.reversed()
            }
            guard let previous = byKey[previousKey] else { return path.reversed() }
            index = previous
        }
        return []
    }
}
