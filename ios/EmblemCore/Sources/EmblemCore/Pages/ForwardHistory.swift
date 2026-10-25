import Foundation

public enum ForwardHistory {
    public static func afterPopping<Page>(
        _ leaving: [Page], forward: [Page], isSubpage: (Page) -> Bool
    ) -> [Page] {
        let kept = leaving.prefix { !isSubpage($0) }
        guard kept.count == leaving.count else { return kept.reversed() }
        return forward + leaving.reversed()
    }
}
