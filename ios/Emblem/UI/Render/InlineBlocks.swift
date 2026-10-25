import SwiftUI
import EmblemCore

struct SectionHeaderView: View {
    let block: SectionHeader
    @Environment(\.renderedPage) private var renderedPage

    private var hiddenOnHome: Bool {
        block.id == "daily-update-h"
    }

    var body: some View {
        if !hiddenOnHome {
            VStack(alignment: .leading, spacing: renderedPage?.isHome == true ? 8 : 6) {
                Text(block.title)
                    .font(renderedPage?.isHome == true
                        ? .system(size: 16, weight: .semibold)
                        : .system(size: 20, weight: .bold))
                    .tracking(renderedPage?.isHome == true ? -0.3 : -0.5)
                    .foregroundStyle(Theme.ink)
                if let subtitle = block.subtitle {
                    Text(subtitle)
                        .font(.system(size: 16))
                        .lineSpacing(renderedPage?.isHome == true ? 0 : 3)
                        .foregroundStyle(renderedPage?.isHome == true ? Theme.inkSecondary : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, renderedPage?.isHome == true ? Theme.homeMargin : 32)
        }
    }
}

struct QuoteView: View {
    let block: Quote

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\u{201C}\(block.text)\u{201D}")
                .font(Theme.quote())
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let attribution = block.attribution {
                Text("–\(attribution)")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .cardBackground()
        .padding(.horizontal, Theme.contentMargin)
    }
}

struct RatingRowView: View {
    let block: RatingRow

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: block.icon ?? Icon(sfSymbol: "star.fill"), size: 17)
            Text(block.text)
                .font(Theme.bodySecondary())
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, Theme.textMargin)
    }
}

struct FactListView: View {
    let block: FactList

    private var showsIcons: Bool {
        ListIconPolicy.showsIcons(block.facts.map(\.icon))
    }

    var body: some View {
        if let contacts = ContactAction.actions(for: block.facts) {
            ContactActionList(actions: contacts)
        } else {
            VStack(alignment: .leading, spacing: 11.5) {
                ForEach(Array(block.facts.enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .top, spacing: 16) {
                        if showsIcons {
                            IconView(icon: fact.icon, size: 18, loadingSkeleton: true)
                                .padding(.top, 2)
                        }
                        ListRowText(title: fact.value, caption: fact.label)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
        }
    }
}
