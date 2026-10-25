import Foundation
import UIKit
import EmblemCore

@Observable @MainActor
final class ConnectedAppsStore {
    private let identityEpoch = ConversationHistory.shared.epoch
    struct App: Decodable, Identifiable {
        var slug: String
        var title: String
        var status: String
        var detail: String?
        var diagnosticCode: String?
        var lastCheckedAt: Double?
        var canReconnect: Bool?
        var logo: String?
        var accounts: [Account]?
        var id: String { slug }
        var isConnected: Bool { status == "connected" }
        var visibleAccounts: [Account] { (accounts ?? []).filter { $0.status != "authorizing" } }

        static let known: [App] = [("gmail", "Gmail"), ("googlecalendar", "Google Calendar")].map {
            App(slug: $0.0, title: $0.1, status: "unavailable", detail: nil, diagnosticCode: nil,
                lastCheckedAt: nil, canReconnect: false, logo: nil, accounts: [])
        }
    }

    struct Account: Decodable, Identifiable, Hashable {
        var id: String
        var label: String
        var status: String
        var addedAt: String?
        var isConnected: Bool { status == "connected" }
    }

    private struct Mutation: Encodable {
        var action: String
        var toolkit: String
        var account: String?
        var another: Bool?
    }

    private struct ListResponse: Decodable {
        var enabled: Bool
        var toolkits: [App]
    }

    private struct ConnectResponse: Decodable {
        var redirectUrl: String?
        var status: String?
    }

    private(set) var enabled = false
    private(set) var apps: [App] = []
    private(set) var busySlug: String?
    private(set) var errorMessage: String?
    private(set) var loadFailed = false
    private(set) var isRefreshing = false

    func refresh(force: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let query = force ? [URLQueryItem(name: "refresh", value: "1")] : []
            let data = try await GenerateClient.fetchJSON(identityEpoch: identityEpoch, path: "api/connectors", query: query)
            let response = try JSONDecoder().decode(ListResponse.self, from: data)
            enabled = response.enabled
            apps = response.toolkits
            loadFailed = false
            errorMessage = nil
        } catch {
            loadFailed = true
        }
    }

    func connect(_ slug: String, another: Bool = false) async {
        busySlug = slug
        defer { busySlug = nil }
        do {
            let data = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/connectors",
                body: Mutation(action: "connect", toolkit: slug, another: another ? true : nil))
            let response = try JSONDecoder().decode(ConnectResponse.self, from: data)
            if let urlString = response.redirectUrl, let url = URL(string: urlString) {
                await UIApplication.shared.open(url)
            } else {
                await refresh(force: true)
            }
        } catch {
            errorMessage = "Couldn't start connecting. Try again."
        }
    }

    func disconnect(_ slug: String, account: String? = nil) async {
        busySlug = slug
        defer { busySlug = nil }
        do {
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/connectors",
                body: Mutation(action: "disconnect", toolkit: slug, account: account))
            await refresh(force: true)
        } catch {
            errorMessage = "Couldn't disconnect. Try again."
        }
    }
}
