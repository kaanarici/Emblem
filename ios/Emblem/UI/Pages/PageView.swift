import SwiftUI
import UIKit
import EmblemCore

struct PageView: View {
    let page: GeneratedPage
    let expansionNamespace: Namespace.ID
    @Environment(ConversationStore.self) private var store
    @Environment(\.openURL) private var inheritedOpenURL
    @State private var topPullDistance: CGFloat = 0
    @State private var homeTopInset: CGFloat = 0
    @State private var homeKeyboardOverlap: CGFloat = 0

    private var surfacePlan: ResponseSurfacePlan {
        ResponseSurfacePlan(
            blocks: page.presentedBlocks, isHome: page.isHome,
            asksQuestions: page.presentationMeta?.ask == true)
    }

    private var pageBackground: Color {
        return page.isHome ? .clear : (surfacePlan.terminalSurface?.color ?? Theme.responsePaper)
    }

    var body: some View {
        Group {
            if let source = page.expansionSource {
                GeometryReader { geometry in
                    expansionPage(
                        source: source,
                        coverHeight: source.contentStyle == .event
                            ? 266 : min(430, max(340, geometry.size.width * 0.84)))
                }
                .accessibilityIdentifier("expansion-page")
            } else {
                standardPage
            }
        }
        .allowsHitTesting(!store.isAwaitingFirstGenerationContent)
        .environment(\.openURL, page.hasProvisionalPresentation
            ? OpenURLAction { _ in .discarded } : inheritedOpenURL)
        .environment(\.renderedPage, page)
        .environment(\.blockInteraction, store.blockInteraction(for: page))
        .environment(\.expansionNamespace, expansionNamespace)
        .background(
            pageBackground,
            ignoresSafeAreaEdges: .all)
    }

    @ViewBuilder
    private var standardPage: some View {
        switch currentConversationLoadState {
        case .loading(_, showingCachedContent: false):
            conversationLoadingPage
        case .failed(_, showingCachedContent: false):
            conversationUnavailablePage
        default:
            if let area = inlineArea {
                AreaPickerPage(item: area)
            } else {
                scrollingPage
            }
        }
    }

    private var inlineArea: QuestionList.Item? {
        guard !page.isHome else { return nil }
        return page.presentedBlocks.lazy.compactMap { block -> QuestionList.Item? in
            if case .questionList(let list) = block { return list.inlineArea }
            return nil
        }.first
    }

    private var scrollingPage: some View {
            ScrollView {
                Group {
                    if page.isHome {
                        homeContent(blocks: page.visibleBlocks)
                    } else {
                        pageContent(blocks: page.presentedBlocks)
                    }
                }
                    .padding(.top, 18)
                    .background(alignment: .top) {
                        if surfacePlan.isEnabled {
                            surfacePlan.initialColor.frame(height: 18)
                        }
                    }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, distance in
                topPullDistance = distance
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, inset in
                homeTopInset = inset
            }
            .safeAreaPadding(.bottom, page.isHome ? 0 : 80)
            .background(alignment: .top) {
                if surfacePlan.isEnabled {
                    surfacePlan.initialColor
                        .frame(height: 160 + topPullDistance)
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
    }

    private var conversationLoadingPage: some View {
        Color.clear
            .accessibilityLabel("Opening conversation")
            .accessibilityIdentifier("conversation-loading")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.responsePaper)
    }

    private var conversationUnavailablePage: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.inkSecondary)
            Text("This chat didn't load")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("conversation-error")
            Text("Check your connection and try again.")
                .font(Theme.bodySecondary())
                .foregroundStyle(Theme.inkSecondary)
            Button("Try again") {
                if let key = page.conversationKey {
                    store.restoreConversation(key: key)
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("conversation-retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 100)
        .background(Theme.responsePaper)
    }

    private func expansionPage(
        source: PageExpansionSource,
        coverHeight: CGFloat
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if source.contentStyle == .event {
                        if let icon = streamedLead?.icon ?? source.card.icon, icon.image?.kind == .object {
                            IconView(icon: Icon(image: icon.image), size: 100)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .opacity(articleBlocks.isEmpty && page.isStreaming ? 0 : 1)
                                .animation(.easeOut(duration: 0.3), value: articleBlocks.isEmpty && page.isStreaming)
                                .accessibilityHidden(true)
                        } else {
                            Color.clear
                        }
                    } else {
                        ExpansionPageCover(
                            card: coverCard(for: source), refreshedURL: refreshedCoverURL(for: source),
                            namespace: expansionNamespace)
                    }
                }
                .frame(height: coverHeight)
                .background(eventLeadSurface(source))
                ZStack(alignment: .top) {
                    TitleBlockView(block: streamedLead ?? TitleBlock(
                        id: "expansion-source-lead",
                        title: source.card.title,
                        metaLine: source.contentStyle == .event ? " " : nil,
                        summary: source.card.caption,
                        tags: nil,
                        actions: nil),
                        sweepsIn: streamedLead != nil,
                        metaGlyphs: source.contentStyle == .event)
                        .id(streamedLead != nil)
                        .transition(.identity)
                }
                .padding(.top, source.contentStyle == .event ? 20 : 28)
                .padding(.bottom, source.contentStyle == .event ? 44 : 64)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(source.contentStyle == .event ? eventLeadSurface(source) : Theme.responsePaper)
                .accessibilityIdentifier("expansion-source-lead")
                if source.contentStyle != .event || !articleBlocks.isEmpty {
                    pageContent(blocks: articleBlocks)
                }
            }
            .animation(.smooth(duration: 0.32), value: page.visibleBlocks.count)
            .animation(.smooth(duration: 0.32), value: streamedLead != nil)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > coverHeight - 140
        } action: { _, underlap in
            page.chromeUnderlap = underlap
        }
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaPadding(.bottom, 80)
        .scrollEdgeEffectHidden(source.contentStyle != .event, for: .top)
        .background(pageBackground.ignoresSafeArea())
    }

    private func eventLeadSurface(_ source: PageExpansionSource) -> Color {
        source.contentStyle == .event ? Theme.responsePaper : .clear
    }

    private func coverCard(for source: PageExpansionSource) -> CardCarousel.Card {
        var card = source.card
        guard card.image == nil, card.imageURL == nil, let hero = pageHero else { return card }
        card.image = hero.image
        card.imageURL = hero.imageURL
        return card
    }

    private func refreshedCoverURL(for source: PageExpansionSource) -> URL? {
        guard source.card.image != nil || source.card.imageURL != nil,
              let url = pageHero?.imageURL, url != source.card.imageURL else { return nil }
        return URL(string: url)
    }

    private var pageHero: Hero? {
        page.visibleBlocks.lazy.compactMap { block -> Hero? in
            if case .hero(let hero) = block { return hero }
            return nil
        }.first
    }

    private var streamedLead: TitleBlock? {
        for block in page.visibleBlocks {
            if case .titleBlock(let lead) = block { return lead }
        }
        return nil
    }

    private var articleBlocks: [Block] {
        page.visibleBlocks.filter { block in
            switch block {
            case .hero, .titleBlock:
                return false
            default:
                return true
            }
        }
    }

    @ViewBuilder
    private func homeContent(blocks: [Block]) -> some View {
        if let greeting = blocks.first, greeting.id == "greeting" {
            let rest = Self.inserting(recentHomeBlocks, into: Array(blocks.dropFirst()), before: "ideas-h")
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                PageBlockList(blocks: [greeting], pageID: page.id.uuidString)
                Spacer(minLength: 0)
                if !rest.isEmpty {
                    Color.clear.frame(height: 38)
                    PageBlockList(blocks: rest, pageID: page.id.uuidString)
                }
                Color.clear.frame(height: rest.isEmpty && store.dockState == .keyboard && homeKeyboardOverlap > 0
                    ? homeKeyboardOverlap + Self.homeComposerReserve
                    : Self.homeBottomReserve)
            }
            .frame(minHeight: max(0, homeScreenHeight - homeTopInset - 18), alignment: .top)
            .containerRelativeFrame(.horizontal)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                withAnimation(DockView.keyboardCurve) {
                    homeKeyboardOverlap = max(0, homeScreenHeight - frame.minY)
                }
            }
        } else {
            pageContent(blocks: blocks)
        }
    }

    private var recentHomeBlocks: [Block] {
        let recent = ConversationHistory.shared.items.prefix(Self.recentRailLimit)
        guard !recent.isEmpty else { return [] }
        return [
            .sectionHeader(SectionHeader(id: "recent-h", title: "Recent chats", subtitle: nil)),
            .cardCarousel(CardCarousel(id: "recent", cards: recent.map { item in
                CardCarousel.Card(
                    image: item.artwork?.image, imageURL: item.artwork?.imageURL ?? item.legacyArtworkURL,
                    icon: nil, title: item.title,
                    caption: item.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)),
                    preview: Self.distinctPreview(item.preview, title: item.title),
                    prompt: nil, conversation: item.key, automation: nil)
            })),
        ]
    }

    private static let recentRailLimit = 8

    private static func distinctPreview(_ preview: String?, title: String) -> String? {
        let words = { (text: String) in text.lowercased().split(whereSeparator: \.isWhitespace) }
        guard let preview, words(preview) != words(title) else { return nil }
        return preview
    }

    private static func inserting(_ rail: [Block], into blocks: [Block], before id: String) -> [Block] {
        var blocks = blocks
        blocks.insert(contentsOf: rail, at: blocks.firstIndex { $0.id == id } ?? blocks.endIndex)
        return blocks
    }

    private static let homeBottomReserve: CGFloat = 130
    private static let homeComposerReserve: CGFloat = 132

    private var homeScreenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }.first ?? 0
    }

    private func pageContent(blocks: [Block]) -> some View {
        let plan = ResponseSurfacePlan(
            blocks: blocks, isHome: page.isHome, asksQuestions: page.presentationMeta?.ask == true)
        return VStack(alignment: .leading, spacing: plan.isEnabled ? 0 : 28) {
            if case .loading(_, showingCachedContent: true) = currentConversationLoadState {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating this chat…")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, Theme.pageMargin)
                .accessibilityIdentifier("conversation-cache-refresh")
            } else if case .failed(_, showingCachedContent: true) = currentConversationLoadState {
                Button {
                    if let key = page.conversationKey {
                        store.restoreConversation(key: key)
                    }
                } label: {
                    Label(
                        "Couldn't refresh this conversation. Retry",
                        systemImage: "wifi.exclamationmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Theme.cardSoft, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.pageMargin)
                .accessibilityIdentifier("conversation-stale-error")
            }

            PageBlockList(blocks: blocks, pageID: page.id.uuidString)
                .padding(.bottom, plan.isEnabled && plan.endsOnPaper ? 28 : 0)
                .background {
                    if plan.isEnabled { plan.initialColor }
                }
                .zIndex(1)

            VStack(spacing: plan.isEnabled ? 0 : 28) {
                if showsSources {
                    SourceDisclosure(sources: page.sources, activities: page.activities)
                        .padding(.top, followsFollowUp(blocks) ? 0 : 32)
                        .padding(.bottom, plan.terminalSurface == .followUpCanvas ? 20 : 0)
                }
                Color.clear.frame(height: plan.terminalSurface == .followUpCanvas ? 0 : 140)
            }
            .background {
                if let surface = plan.terminalSurface {
                    surface.color
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }

    private var showsSources: Bool {
        !page.isStreaming && (
            !page.sources.isEmpty || page.activities.contains {
                $0.status != "started" && $0.source != "web"
            }
        )
    }

    private func followsFollowUp(_ blocks: [Block]) -> Bool {
        guard let last = blocks.last(where: {
            switch $0 { case .pageMeta, .unknown: false; default: true }
        }), case .chipRow(let row) = last else { return false }
        return row.role == .followUp
    }

    private var currentConversationLoadState: ConversationStore.ConversationLoadState {
        guard page === store.currentPage,
              let key = page.conversationKey else {
            return .idle
        }
        switch store.conversationLoadState {
        case .loading(let loadKey, let showingCachedContent) where loadKey == key:
            return .loading(key: key, showingCachedContent: showingCachedContent)
        case .failed(let loadKey, let showingCachedContent) where loadKey == key:
            return .failed(key: key, showingCachedContent: showingCachedContent)
        case .idle, .loading, .failed:
            return .idle
        }
    }
}

private struct ExpansionPageCover: View {
    let card: CardCarousel.Card
    let refreshedURL: URL?
    let namespace: Namespace.ID
    @State private var refreshed: UIImage?

    var body: some View {
        CardArtworkView(
            card: card,
            maxPixelSize: 800)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let refreshed {
                    Image(uiImage: refreshed)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: refreshedURL) {
                guard let refreshedURL else {
                    refreshed = nil
                    return
                }
                async let loaded = ImageLoader.shared.image(at: refreshedURL, maxPixelSize: 800)
                try? await Task.sleep(for: .milliseconds(600))
                guard let image = await loaded, !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.7)) { refreshed = image }
            }
    }
}
