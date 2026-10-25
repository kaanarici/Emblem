import SwiftUI
import EmblemCore

struct ReviewSummaryView: View {
    let block: ReviewSummary

    private let margin: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let intro = block.intro {
                Text(intro)
                    .font(Theme.body())
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 18)
            }
            if let sources = block.sources, !sources.isEmpty {
                sourceRow(sources)
                    .padding(.bottom, 24)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(block.themes.enumerated()), id: \.offset) { _, theme in
                        themeCard(theme)
                            .containerRelativeFrame(.horizontal) { length, _ in
                                (length - margin * 2) * 0.75
                            }
                    }
                }
                .padding(.horizontal, margin)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
        }
    }

    private func sourceRow(_ sources: [ReviewSummary.Source]) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                HStack(spacing: 6) {
                    if let symbol = source.icon?.sfSymbol, Hugeicons.isRenderable(symbol) {
                        GlyphImage(symbol: symbol, size: 16)
                    } else if source.icon != nil {
                        IconView(icon: source.icon, size: 16)
                    }
                    Text(source.score)
                        .font(.system(size: 15, weight: .semibold))
                    Text("on \(source.source)")
                        .font(.system(size: 15))
                }
                if index < sources.count - 1 {
                    Text("·").font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, 32)
    }

    private func themeCard(_ theme: ReviewSummary.Theme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if theme.icon != nil {
                IconView(icon: theme.icon, size: 80)
                    .frame(width: 96, height: 96)
                    .padding(.bottom, 9)
            }
            Text(theme.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(theme.summary)
                .font(.system(size: 14))
                .lineSpacing(max(0, 18 - UIFont.systemFont(ofSize: 14).lineHeight))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if let quote = theme.quote {
                quoteDivider
                    .padding(.top, 25)
                VStack(spacing: 12) {
                    Text(quote)
                        .font(.system(size: 19, design: .serif))
                        .lineSpacing(max(0, 26 - UIFont.systemFont(ofSize: 19).lineHeight))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let attribution = theme.attribution {
                        Text(attribution)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 17)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 33)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                .modifier(MediaArtworkShadow())
        }
    }

    private var quoteDivider: some View {
        HStack(spacing: 4) {
            Rectangle().fill(Theme.inkSecondary.opacity(0.18)).frame(width: 48, height: 1)
            HStack(spacing: 4) {
                Image(systemName: "quote.opening")
                Image(systemName: "quote.closing")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.inkSecondary.opacity(0.4))
            Rectangle().fill(Theme.inkSecondary.opacity(0.18)).frame(width: 48, height: 1)
        }
        .frame(maxWidth: .infinity)
    }
}
