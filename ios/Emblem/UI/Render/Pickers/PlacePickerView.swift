import SwiftUI
import MapKit

struct PlacePickerView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Binding var value: String
    @Environment(ConversationStore.self) private var store
    @State private var model = PlaceCompleter()
    @State private var query = ""

    private var currentCity: String? {
        store.locationSnapshot?.city
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                TextField("Search cities or airports", text: $query)
                    .blockActivationControl()
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        guard blockInteraction.allowsActivation else { return }
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .blockActivationControl()
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .padding(.horizontal, Theme.pageMargin)

            ScrollView {
                VStack(spacing: 0) {
                    if query.isEmpty {
                        if let city = currentCity {
                            row(
                                title: city,
                                subtitle: "Current location",
                                systemImage: "location.fill"
                            ) { commit(city) }
                        }
                    } else {
                        ForEach(model.results) { result in
                            row(title: result.title, subtitle: result.subtitle) {
                                select(result)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: query) { _, new in model.update(new) }
    }

    @ViewBuilder
    private func row(
        title: String,
        subtitle: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { blockInteraction.performActivation(action) }) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, Theme.pageMargin)
            .contentShape(Rectangle())
        }
        .blockActivationControl()
        .buttonStyle(.pressable)
        Divider().padding(.leading, Theme.pageMargin)
    }

    private func commit(_ name: String) {
        guard blockInteraction.allowsActivation else { return }
        value = name
        query = name
    }

    private func select(_ result: PlaceCompleter.Result) {
        commit(result.title)
        Task {
            if let resolved = await model.resolve(result) {
                commit(resolved)
            }
        }
    }
}

@MainActor @Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    struct Result: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let subtitle: String
    }

    var results: [Result] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.pointOfInterest, .address, .query]
        completer.delegate = self
    }

    func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func resolve(_ result: Result) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [result.title, result.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let search = MKLocalSearch(request: request)
        guard let item = try? await search.start().mapItems.first else { return nil }
        return item.name ?? item.addressRepresentations?.cityName ?? result.title
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.prefix(12).map {
            Result(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in self.results = Array(mapped) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
