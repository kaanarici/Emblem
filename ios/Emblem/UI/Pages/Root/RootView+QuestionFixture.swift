#if DEBUG
import Foundation
import EmblemCore

extension RootView {
    func showQuestionFixture() {
        let env = ProcessInfo.processInfo.environment
        guard env["EMBLEM_FIXTURE_QUESTIONS"] != nil else { return }
        let page = GeneratedPage(prompt: "Help me plan a road trip in California, Nevada.")
        page.blocks = Self.questionFixtureLines.compactMap {
            try? JSONDecoder().decode(Block.self, from: Data($0.utf8))
        }
        page.isStreaming = false
        store.pages = [Self.quietHome(), page]
        guard let row = env["EMBLEM_OPEN_QUESTION"].flatMap(Int.init) else { return }
        for case .questionList(let list) in page.blocks where list.items.indices.contains(row) {
            store.openQuestion(list.items[row])
        }
    }

    private static let questionFixtureLines = [
        #"{"type":"text","id":"intro","style":"intro","body":"A California and Nevada road trip can be amazing. Let’s shape it around your pace and priorities."}"#,
        #"{"type":"questionList","id":"trip","items":["#
            + #"{"icon":{"image":{"query":"map","kind":"object"}},"question":"Where do you want to start?","answer":"United States","input":{"kind":"place"}},"#
            + #"{"icon":{"image":{"query":"calendar","kind":"object"}},"question":"How long?","answer":"5 to 7 days","input":{"kind":"count","ask":"How many days?","unit":"day","min":1,"max":30,"value":6,"options":["4","6","7","10"]}},"#
            + #"{"icon":{"image":{"query":"highway","kind":"object"}},"question":"What kind of route?","answer":"Coast, parks, cities, or mixed","input":{"kind":"choice","ask":"What kind of route sounds best?","options":["Coast","National parks","Cities","Desert","Mixed"],"icons":["cliff","mesa","city","highway","map"]}},"#
            + #"{"icon":{"image":{"query":"beach","kind":"object"}},"question":"Who’s coming?","answer":"Just you","input":{"kind":"count","ask":"How many people are coming?","unit":"person","min":1,"max":12,"value":1,"options":["1","2","4"]}},"#
            + #"{"icon":{"image":{"query":"mountain peak","kind":"object"}},"question":"What vibe?","answer":"Scenic and memorable","input":{"kind":"choice","ask":"What vibe are you after?","options":["Scenic","Memorable","Adventurous","Relaxed"],"icons":["mountain peak","camera","compass","hammock"]}}"#
            + #"]}"#,
    ]
}
#endif
