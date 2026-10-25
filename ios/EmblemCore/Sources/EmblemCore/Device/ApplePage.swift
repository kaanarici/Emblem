import FoundationModels

@available(iOS 26, macOS 26, *)
@Generable
struct AppleFact { var label: String; var value: String; var sfSymbol: String? }
@available(iOS 26, macOS 26, *)
@Generable
struct AppleStep { var title: String; var detail: String; var sfSymbol: String? }
@available(iOS 26, macOS 26, *)
@Generable
struct AppleItem { var title: String; var caption: String?; var sfSymbol: String? }
@available(iOS 26, macOS 26, *)
@Generable
struct AppleStat { var value: String; var label: String }
@available(iOS 26, macOS 26, *)
@Generable
struct AppleMoment { var time: String; var title: String; var caption: String? }
@available(iOS 26, macOS 26, *)
@Generable
struct AppleQuote { var text: String; var attribution: String? }
@available(iOS 26, macOS 26, *)
@Generable
struct AppleCard {
    var title: String
    var caption: String
    @Guide(description: "The exact subject to show, named precisely with its place or maker.") var image: String
    var imageKind: Kind
    @Generable enum Kind { case photo, poster, logo }
}
@available(iOS 26, macOS 26, *)
@Generable
struct ApplePoint { var label: String; var value: Double }
@available(iOS 26, macOS 26, *)
@Generable
struct AppleChart {
    @Generable enum Kind { case bar, line, pie }
    var kind: Kind
    var title: String
    var unit: String?
    @Guide(.count(2...12)) var points: [ApplePoint]
}
@available(iOS 26, macOS 26, *)
@Generable
struct AppleComparison {
    @Guide(.count(2...3)) var columns: [String]
    @Generable struct Row {
        var label: String
        @Guide(description: "Exactly one value for each column, in column order.") var values: [String]
    }
    @Guide(.count(1...6)) var rows: [Row]
}
@available(iOS 26, macOS 26, *)
@Generable
struct AppleDraft { var label: String; var body: String }

@available(iOS 26, macOS 26, *)
@Generable
struct AppleSection {
    @Guide(description: "A short topical heading about this subject, never the name of a content type.") var heading: String?
    @Guide(description: "One to three sentences explaining this part, when the content alone would not.") var text: String?
    @Generable enum Content {
        case comparison(AppleComparison)
        case cards([AppleCard])
        case bullets([String])
        case facts([AppleFact])
        case stats([AppleStat])
        case steps([AppleStep])
        case timeline([AppleMoment])
        case items([AppleItem])
        case quote(AppleQuote)
        case chart(AppleChart)
        case writing(AppleDraft)
    }
    var content: Content?
}

@available(iOS 26, macOS 26, *)
@Generable
struct ApplePage {
    var title: String
    var intro: String
    @Guide(.count(1...5)) var sections: [AppleSection]
    @Guide(description: "Short requests the user is likely to make next about this subject, phrased as their own commands, never as questions to them.", .count(3)) var followUps: [String]
}
