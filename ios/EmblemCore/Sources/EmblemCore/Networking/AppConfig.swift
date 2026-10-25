import Foundation

public enum AppConfig {
    #if DEBUG
    private static let overrideURL = ProcessInfo.processInfo.environment["EMBLEM_SERVER_URL"]
        .flatMap(URL.init(string:))
    #endif

    private static let configuredURL = (Bundle.main.object(forInfoDictionaryKey: "EmblemServerURL") as? String)
        .flatMap(URL.init(string:))
        .flatMap { ["http", "https"].contains($0.scheme) && $0.host != nil ? $0 : nil }

    public static let baseURL: URL = {
        #if DEBUG
        if let overrideURL { return overrideURL }
        return configuredURL ?? URL(string: "http://127.0.0.1:3000")!
        #else
        guard let configuredURL, configuredURL.scheme == "https",
              let host = configuredURL.host?.lowercased(),
              host != "localhost", host != "::1", !host.hasPrefix("127.") else {
            preconditionFailure("EmblemServerURL must be an HTTPS service URL in Release.")
        }
        return configuredURL
        #endif
    }()
}
