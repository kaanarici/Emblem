import SwiftUI
import EmblemCore

extension RootView {
    func prepareLaunch() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["EMBLEM_FAKE_HOME"] != nil {
            Task { await ConversationHistory.shared.load() }
            store.pages = [Self.quietHome()]
        }
        showQuestionFixture()
        if let variant = ProcessInfo.processInfo.environment["EMBLEM_AREA_FIXTURE"] {
            Task { await ConversationHistory.shared.load() }
            store.pages = [Self.quietHome(), Self.areaFixture(sheet: variant == "sheet")]
            if variant == "sheet", case .questionList(let list)? = store.currentPage?.blocks.last,
               let row = list.items.first {
                try? await Task.sleep(for: .seconds(1))
                store.openQuestion(row)
            }
        }
        #endif
        store.greetingName = auth.greetingName
        if store.pages.isEmpty { store.loadHome() }
        await speech.prepare()
        if store.dockState != .listening {
            speech.captureListeningBackdrop()
        }
    }

    #if DEBUG
    private static func areaFixture(sheet: Bool) -> GeneratedPage {
        let areas = """
        [{"label":"Manhattan","sym":"building.2","icon":"skyscraper","lat":40.758,"lng":-73.9855,"km":6},
         {"label":"Brooklyn","sym":"bridge","icon":"brooklyn bridge","lat":40.6782,"lng":-73.9442,"km":8},
         {"label":"Downtown","sym":"building.columns","icon":"skyscraper","lat":40.7225,"lng":-73.9985,"km":4},
         {"label":"Queens","sym":"mappin","icon":"subway train","lat":40.7282,"lng":-73.7949,"km":10},
         {"label":"Jersey City","sym":"ferry","icon":"ferry","lat":40.7178,"lng":-74.0431,"km":5}]
        """
        let list = sheet ? """
        {"type":"questionList","id":"q","items":[
         {"question":"Where from?","answer":"","icon":{"image":{"query":"map pin","kind":"object"}},
          "input":{"kind":"area","ask":"Where are you starting from?","areas":\(areas)}},
         {"question":"When?","answer":"","icon":{"image":{"query":"calendar","kind":"object"}},"input":{"kind":"date"}},
         {"question":"Budget?","answer":"","icon":{"image":{"query":"wallet","kind":"object"}},
          "input":{"kind":"choice","options":["Under $50","$50-100","Splurge"]}}]}
        """ : """
        {"type":"questionList","id":"q","items":[{"question":"Let's narrow it down by area first.","answer":"",
         "input":{"kind":"area","areas":\(areas)}}]}
        """
        let intro = #"{"type":"text","id":"intro","style":"intro","body":"Let's narrow it down a bit so I can suggest places you'd actually want to go."}"#
        let json = "[\(sheet ? intro + "," : "")\(list)]"
        let page = GeneratedPage(prompt: "Find me something fun to do in New York")
        page.meta = PageMeta(id: "meta", title: "Area")
        page.blocks = (try? JSONDecoder().decode([Block].self, from: Data(json.utf8))) ?? []
        page.isStreaming = false
        return page
    }

    static func quietHome() -> GeneratedPage {
        let home = GeneratedPage(prompt: "home", isHome: true)
        home.meta = PageMeta(id: "meta", title: "Home")
        home.blocks = [
            .text(TextBlock(
                id: "greeting",
                body: "Good afternoon, **Alex**.\nYour 📅 **meeting with Sam** is today at **3:00 PM**.",
                style: .intro)),
            .mediaRowList(MediaRowList(
                id: "next-event-actions", title: nil,
                rows: [
                    .init(
                        icon: nil, title: "Product review", subtitle: nil,
                        action: Action(
                            label: "Join meeting", sfSymbol: "video.fill",
                            url: "https://meet.google.com/lookup/emblem-preview")),
                    .init(
                        icon: nil, title: "Product review", subtitle: nil,
                        action: Action(
                            label: "Prep agenda", sfSymbol: "sparkles",
                            prompt: "Prepare me for Product review at 3:00 PM.")),
                ])),
            .sectionHeader(SectionHeader(
                id: "daily-update-h", title: "Today", subtitle: nil)),
            .mediaRowList(MediaRowList(
                id: "daily-update", title: nil,
                rows: [.init(
                    icon: Icon(sfSymbol: "sun.max.fill"),
                    title: "Maya needs your reply",
                    subtitle: "Launch date · Before 3:00 PM",
                    action: Action(
                        label: "Open", sfSymbol: nil, url: nil,
                        prompt: nil,
                        conversation: nil, native: nil, destination: nil,
                        openAutomation: "qa-update", automation: nil))])),
        ]
        home.isStreaming = false
        return home
    }
    #endif
}
