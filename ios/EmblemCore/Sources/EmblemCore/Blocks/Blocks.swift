import Foundation
import os

public enum Block: Identifiable {
    case pageMeta(PageMeta)
    case runStamp(RunStamp)
    case quiz(Quiz)
    case flashcards(Flashcards)
    case chart(ChartBlock)
    case diagram(DiagramBlock)
    case whatIf(WhatIfBlock)
    case text(TextBlock)
    case writing(WritingBlock)
    case hero(Hero)
    case titleBlock(TitleBlock)
    case sectionHeader(SectionHeader)
    case cardCarousel(CardCarousel)
    case featureList(FeatureList)
    case quote(Quote)
    case ratingRow(RatingRow)
    case mediaRowList(MediaRowList)
    case spotList(SpotList)
    case factList(FactList)
    case chipRow(ChipRow)
    case statRow(StatRow)
    case itemGrid(ItemGrid)
    case stepCarousel(StepCarousel)
    case listBlock(ListBlock)
    case comparisonTable(ComparisonTable)
    case sideBySide(SideBySide)
    case oneAgainstMany(OneAgainstMany)
    case reviewSummary(ReviewSummary)
    case timeline(Timeline)
    case questionList(QuestionList)
    case map(MapBlock)
    case route(RouteBlock)
    case weather(WeatherBlock)
    case photoGrid(PhotoGrid)
    case timeAsk(TimeAsk)
    case eventCard(EventCard)
    case music(MusicBlock)
    case reminders(RemindersBlock)
    case contact(ContactBlock)
    case homeControl(HomeControlBlock)
    case unknown(id: String)

    public var id: String {
        switch self {
        case .pageMeta(let b): b.id
        case .runStamp(let b): b.id
        case .quiz(let b): b.id
        case .flashcards(let b): b.id
        case .chart(let b): b.id
        case .diagram(let b): b.id
        case .whatIf(let b): b.id
        case .text(let b): b.id
        case .writing(let b): b.id
        case .hero(let b): b.id
        case .titleBlock(let b): b.id
        case .sectionHeader(let b): b.id
        case .cardCarousel(let b): b.id
        case .featureList(let b): b.id
        case .quote(let b): b.id
        case .ratingRow(let b): b.id
        case .mediaRowList(let b): b.id
        case .spotList(let b): b.id
        case .factList(let b): b.id
        case .chipRow(let b): b.id
        case .statRow(let b): b.id
        case .itemGrid(let b): b.id
        case .stepCarousel(let b): b.id
        case .listBlock(let b): b.id
        case .comparisonTable(let b): b.id
        case .sideBySide(let b): b.id
        case .oneAgainstMany(let b): b.id
        case .reviewSummary(let b): b.id
        case .timeline(let b): b.id
        case .questionList(let b): b.id
        case .map(let b): b.id
        case .route(let b): b.id
        case .weather(let b): b.id
        case .photoGrid(let b): b.id
        case .timeAsk(let b): b.id
        case .eventCard(let b): b.id
        case .music(let b): b.id
        case .reminders(let b): b.id
        case .contact(let b): b.id
        case .homeControl(let b): b.id
        case .unknown(let id): id
        }
    }
}

extension Block: Decodable {
    private enum CodingKeys: String, CodingKey { case type, id }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            Self.noteDecodeFailure("non_object")
            self = .unknown(id: Self.positionalFallbackID(decoder.codingPath))
            return
        }
        let type = (try? c.decode(String.self, forKey: .type)) ?? ""
        do {
            switch type {
            case "pageMeta": self = .pageMeta(try PageMeta(from: decoder))
            case "runStamp": self = .runStamp(try RunStamp(from: decoder))
            case "quiz": self = .quiz(try Quiz(from: decoder))
            case "flashcards": self = .flashcards(try Flashcards(from: decoder))
            case "chart": self = .chart(try ChartBlock(from: decoder))
            case "diagram": self = .diagram(try DiagramBlock(from: decoder))
            case "whatIf": self = .whatIf(try WhatIfBlock(from: decoder))
            case "text": self = .text(try TextBlock(from: decoder))
            case "writing": self = .writing(try WritingBlock(from: decoder))
            case "hero": self = .hero(try Hero(from: decoder))
            case "titleBlock": self = .titleBlock(try TitleBlock(from: decoder))
            case "sectionHeader": self = .sectionHeader(try SectionHeader(from: decoder))
            case "cardCarousel": self = .cardCarousel(try CardCarousel(from: decoder))
            case "featureList": self = .featureList(try FeatureList(from: decoder))
            case "quote": self = .quote(try Quote(from: decoder))
            case "ratingRow": self = .ratingRow(try RatingRow(from: decoder))
            case "mediaRowList": self = .mediaRowList(try MediaRowList(from: decoder))
            case "spotList": self = .spotList(try SpotList(from: decoder))
            case "factList": self = .factList(try FactList(from: decoder))
            case "chipRow": self = .chipRow(try ChipRow(from: decoder))
            case "statRow": self = .statRow(try StatRow(from: decoder))
            case "itemGrid": self = .itemGrid(try ItemGrid(from: decoder))
            case "stepCarousel": self = .stepCarousel(try StepCarousel(from: decoder))
            case "listBlock": self = .listBlock(try ListBlock(from: decoder))
            case "comparisonTable": self = .comparisonTable(try ComparisonTable(from: decoder))
            case "sideBySide": self = .sideBySide(try SideBySide(from: decoder))
            case "oneAgainstMany": self = .oneAgainstMany(try OneAgainstMany(from: decoder))
            case "reviewSummary": self = .reviewSummary(try ReviewSummary(from: decoder))
            case "timeline": self = .timeline(try Timeline(from: decoder))
            case "questionList": self = .questionList(try QuestionList(from: decoder))
            case "map": self = .map(try MapBlock(from: decoder))
            case "route": self = .route(try RouteBlock(from: decoder))
            case "weather": self = .weather(try WeatherBlock(from: decoder))
            case "photoGrid": self = .photoGrid(try PhotoGrid(from: decoder))
            case "timeAsk": self = .timeAsk(try TimeAsk(from: decoder))
            case "eventCard": self = .eventCard(try EventCard(from: decoder))
            case "music": self = .music(try MusicBlock(from: decoder))
            case "reminders": self = .reminders(try RemindersBlock(from: decoder))
            case "contact": self = .contact(try ContactBlock(from: decoder))
            case "homeControl": self = .homeControl(try HomeControlBlock(from: decoder))
            default:
                Self.noteDecodeFailure("unknown_type")
                self = .unknown(id: Self.fallbackID(c))
            }
        } catch {
            Self.noteDecodeFailure("invalid_payload")
            self = .unknown(id: Self.fallbackID(c))
        }
    }

    private static func fallbackID(_ c: KeyedDecodingContainer<CodingKeys>) -> String {
        (try? c.decode(String.self, forKey: .id)) ?? positionalFallbackID(c.codingPath)
    }

    private static func positionalFallbackID(_ path: [any CodingKey]) -> String {
        let indices = path.compactMap(\.intValue).map(String.init)
        return "unknown@" + (indices.isEmpty ? "root" : indices.joined(separator: "."))
    }

    private static func noteDecodeFailure(_ reason: StaticString) {
        #if DEBUG
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "emblem", category: "decoding")
            .debug("Response block ignored: \(String(describing: reason), privacy: .public)")
        #endif
    }
}
