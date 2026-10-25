import Foundation

@MainActor
public enum AgentsClient {
    private struct Schedule: Encodable {
        let hour: Int
        let minute: Int
        let weekdays: [Int]?
        let timezone: String
    }

    private struct CreateBody: Encodable {
        let action = "create"
        let title: String
        let prompt: String
        let schedule: Schedule
        let requestId: String
    }

    private struct RunsPayload: Decodable {
        public struct Run: Decodable {
            let title: String?
            let summary: String?
            let blocks: String
        }

        let runs: [Run]
    }

    public static func createScheduled(
        title: String,
        prompt: String,
        hour: Int,
        minute: Int,
        weekdays: [Int]?,
        timezone: String,
        requestId: String
    ) async throws {
        _ = try await GenerateClient.postJSON(
            path: "api/agents",
            body: CreateBody(
                title: title,
                prompt: prompt,
                schedule: Schedule(
                    hour: hour,
                    minute: minute,
                    weekdays: weekdays,
                    timezone: timezone),
                requestId: requestId))
    }

    public static func runPages(id: String) async throws -> [GeneratedPage] {
        try await runPages(
            path: "api/agents",
            query: [.init(name: "runsFor", value: id)])
    }

    private static func runPages(
        path: String,
        query: [URLQueryItem]
    ) async throws -> [GeneratedPage] {
        let data = try await GenerateClient.fetchJSON(
            path: path,
            query: query)
        let payload = try JSONDecoder().decode(RunsPayload.self, from: data)
        let decoder = JSONDecoder()
        var pages: [GeneratedPage] = []
        for run in payload.runs.reversed() {
            let page = GeneratedPage(prompt: run.title ?? "Agent run")
            if let blocksData = run.blocks.data(using: .utf8),
               let blocks = try? decoder.decode([Block].self, from: blocksData) {
                for block in blocks {
                    if case .pageMeta(let meta) = block {
                        page.meta = meta
                    } else if case .unknown = block {
                        continue
                    } else {
                        page.blocks.append(block)
                    }
                }
            }
            if page.blocks.isEmpty,
               let summary = run.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                page.blocks = [.text(TextBlock(
                    id: "automation-summary",
                    body: summary,
                    style: .body))]
            }
            page.isStreaming = false
            if !page.blocks.isEmpty { pages.append(page) }
        }
        return pages
    }
}

@Observable @MainActor
public final class AgentsStore {
    public init() {}

    private let identityEpoch = ConversationHistory.shared.epoch
    public struct Agent: Decodable, Identifiable {
        public struct Schedule: Codable {
            public var hour: Int
            public var minute: Int
            public var weekdays: [Int]?
            var timezone: String
        }

        public struct BriefingTime: Codable, Equatable {
            public var hour: Int
            public var minute: Int

            public init(hour: Int, minute: Int) {
                self.hour = hour
                self.minute = minute
            }
        }

        struct BriefingTimes: Codable, Equatable {
            var morning: BriefingTime?
            var afternoon: BriefingTime?
            var evening: BriefingTime?
        }

        public struct Run: Decodable {
            public var runId: String
            public var status: String
            var title: String?
            var error: String?
            var startedAt: Double
            var finishedAt: Double?
        }

        public var id: String
        public var title: String
        public var prompt: String
        var preset: String?
        public var schedule: Schedule?
        var briefingTimes: BriefingTimes?
        var updateTimes: [BriefingTime]?
        public var enabled: Bool
        var nextRunAt: Double?
        var lastRunAt: Double?
        public var latestRun: Run?
        var sources: [String]

        public var scheduledTimes: [BriefingTime] {
            if let updateTimes { return updateTimes }
            if let briefingTimes {
                return [briefingTimes.morning, briefingTimes.afternoon, briefingTimes.evening]
                    .compactMap { $0 }
            }
            if let schedule {
                return [.init(hour: schedule.hour, minute: schedule.minute)]
            }
            return []
        }
    }

    private struct ListResponse: Decodable { var agents: [Agent] }
    private struct ActionBody: Encodable {
        var action: String
        var id: String?
        var runId: String?
        var requestId: String?
    }
    private struct DailyUpdateBody: Encodable {
        var action = "syncDailyBrief"
        var updates: UpdateConfiguration
    }
    private struct UpdateConfiguration: Encodable {
        var timezone: String
        var times: [Agent.BriefingTime]
        var memory: Bool
    }
    private struct CreateBody: Encodable {
        var action = "create"
        var prompt: String
        var schedule: Agent.Schedule
        var requestId: String
    }

    public private(set) var agents: [Agent] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var busyAction: String?
    public private(set) var errorMessage: String?

    public var dailyBrief: Agent? {
        agents.first {
            $0.preset == "daily_brief" || $0.title == "Daily brief" || $0.title == "Morning Page"
        }
    }

    public var automations: [Agent] {
        agents.filter { agent in
            agent.id != dailyBrief?.id && agent.schedule != nil
        }
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await loadAgents()
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = "Agents couldn't be checked. Try again."
        }
    }

    public func configureDailyBrief(
        times: [Agent.BriefingTime],
        memory: Bool
    ) async {
        await perform("configure") {
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/agents",
                body: DailyUpdateBody(updates: .init(
                    timezone: TimeZone.current.identifier,
                    times: times,
                    memory: memory)))
        }
    }

    public func create(prompt: String, hour: Int, minute: Int, weekdays: [Int]?) async {
        let schedule = Agent.Schedule(hour: hour, minute: minute, weekdays: weekdays,
                                      timezone: TimeZone.current.identifier)
        await perform("create") {
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/agents",
                body: CreateBody(prompt: prompt, schedule: schedule, requestId: UUID().uuidString))
        }
    }

    public func replace(_ agent: Agent, prompt: String, hour: Int, minute: Int, weekdays: [Int]?) async {
        await create(prompt: prompt, hour: hour, minute: minute, weekdays: weekdays)
        guard errorMessage == nil else { return }
        await delete(agent)
    }

    public func reconcileDailyBrief(memory: Bool) async {
        guard let agent = dailyBrief, agent.enabled else { return }
        let timezone = TimeZone.current.identifier
        let memoryMatches = agent.sources.contains("memory") == memory
        let timezoneMatches = agent.schedule?.timezone == timezone
        guard !memoryMatches || !timezoneMatches else { return }
        await configureDailyBrief(times: agent.scheduledTimes, memory: memory)
    }

    public func dispatch(_ agent: Agent, retry: Bool = false) async {
        await perform(retry ? "retry" : "dispatch") {
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/agents",
                body: ActionBody(
                    action: retry ? "retry" : "dispatch",
                    id: agent.id,
                    requestId: UUID().uuidString))
        }
    }

    public func cancel(_ run: Agent.Run) async {
        await perform("cancel") {
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/agents",
                body: ActionBody(action: "cancel", runId: run.runId))
        }
    }

    public func setEnabled(_ agent: Agent, enabled: Bool) async {
        await perform(enabled ? "resume" : "pause") {
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/agents",
                body: ActionBody(action: enabled ? "resume" : "pause", id: agent.id))
        }
    }

    public func delete(_ agent: Agent) async {
        await perform("delete") {
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/agents",
                body: ActionBody(action: "delete", id: agent.id))
        }
    }

    private func loadAgents() async throws {
        let data = try await GenerateClient.fetchJSON(identityEpoch: identityEpoch, path: "api/agents", query: [])
        agents = try JSONDecoder().decode(ListResponse.self, from: data).agents
    }

    private func perform(
        _ action: String,
        operation: () async throws -> Void
    ) async {
        busyAction = action
        defer { busyAction = nil }
        do {
            try await operation()
            await refresh()
        } catch {
            errorMessage = "That agent action didn't finish. Try again."
        }
    }
}
