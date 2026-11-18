import Foundation
import SwiftUI
import UserNotifications

// MARK: - Configuration

struct Service: Codable, Identifiable, Hashable {
    /// Host of the status page, e.g. "status.kinsta.com". Stable identifier.
    var id: String
    var name: String
    var baseURL: String
    var symbol: String
    var enabled: Bool
    var isPreset: Bool = false
    /// Set for pages hosted on status.io instead of Atlassian Statuspage.
    var statusioID: String? = nil
}

enum Presets {
    static let all: [Service] = [
        preset("Claude", "https://status.claude.com", "sparkles", enabled: true),
        preset("Kinsta", "https://status.kinsta.com", "server.rack"),
        preset("GitHub", "https://www.githubstatus.com", "chevron.left.forwardslash.chevron.right"),
        preset("OpenAI", "https://status.openai.com", "circle.hexagongrid"),
        preset("Cloudflare", "https://www.cloudflarestatus.com", "cloud"),
        preset("Vercel", "https://www.vercel-status.com", "triangle"),
        preset("DigitalOcean", "https://status.digitalocean.com", "drop"),
        preset("GitLab", "https://status.gitlab.com", "arrow.triangle.branch", statusioID: "5b36dc6502d06804c08349f7"),
    ]

    private static func preset(_ name: String, _ url: String, _ symbol: String, enabled: Bool = false, statusioID: String? = nil) -> Service {
        Service(id: URL(string: url)!.host!, name: name, baseURL: url, symbol: symbol, enabled: enabled, isPreset: true, statusioID: statusioID)
    }
}

// MARK: - Statuspage v2 API

struct SummaryResponse: Decodable {
    struct Page: Decodable { let name: String }
    struct Status: Decodable { let indicator: String; let description: String }
    struct Component: Decodable, Identifiable {
        let id: String
        let name: String
        let status: String
        let position: Int?
        let group_id: String?
        let only_show_if_degraded: Bool?
    }
    struct Incident: Decodable, Identifiable {
        let id: String
        let name: String
        let status: String
        let impact: String?
        let shortlink: String?
    }
    let page: Page
    let status: Status
    let components: [Component]
    let incidents: [Incident]?
}

// MARK: - status.io API (e.g. GitLab)

struct StatusIOResponse: Decodable {
    struct Result: Decodable {
        struct Overall: Decodable { let status: String; let status_code: Int }
        struct Item: Decodable { let id: String; let name: String; let status: String; let status_code: Int }
        struct Incident: Decodable { let _id: String?; let name: String? }
        let status_overall: Overall
        let status: [Item]
        let incidents: [Incident]?
    }
    let result: Result

    /// Maps status.io codes onto the Statuspage v2 vocabulary the rest of the app uses.
    func asSummary(name: String, baseURL: String) -> SummaryResponse {
        func indicator(_ code: Int) -> String {
            switch code {
            case 100: return "none"
            case 200: return "maintenance"
            case 300: return "minor"
            case 400: return "major"
            default: return "critical"
            }
        }
        func componentStatus(_ code: Int) -> String {
            switch code {
            case 100: return "operational"
            case 200: return "under_maintenance"
            case 300: return "degraded_performance"
            case 400: return "partial_outage"
            default: return "major_outage"
            }
        }
        return SummaryResponse(
            page: .init(name: name),
            status: .init(indicator: indicator(result.status_overall.status_code), description: result.status_overall.status),
            components: result.status.enumerated().map { index, item in
                .init(id: item.id, name: item.name, status: componentStatus(item.status_code),
                      position: index, group_id: nil, only_show_if_degraded: nil)
            },
            incidents: (result.incidents ?? []).enumerated().map { index, incident in
                .init(id: incident._id ?? "\(index)", name: incident.name ?? "Incident",
                      status: "investigating", impact: nil, shortlink: baseURL)
            }
        )
    }
}

struct ServiceState {
    var indicator: String = "loading"
    var description: String = "Loading…"
    var components: [SummaryResponse.Component] = []
    var incidents: [SummaryResponse.Incident] = []
    var lastUpdated: Date?
    var error: String?
}

enum StatusPageError: LocalizedError {
    case invalidURL
    case duplicate

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Not a valid URL"
        case .duplicate: return "Already added"
        }
    }
}

// MARK: - Model

@MainActor
final class StatusModel: ObservableObject {
    @Published var services: [Service] {
        didSet {
            saveServices()
            states = states.filter { id, _ in enabledServices.contains { $0.id == id } }
            Task { await poll() }
        }
    }
    @Published var states: [String: ServiceState] = [:]
    @Published var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    private var timer: Timer?
    private let pollInterval: TimeInterval = 10
    private var previousIndicators: [String: String] = [:]

    init() {
        services = Self.loadServices()
        Task { await poll() }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    var enabledServices: [Service] { services.filter(\.enabled) }

    // MARK: Persistence

    private static func loadServices() -> [Service] {
        guard let data = UserDefaults.standard.data(forKey: "services"),
              var stored = try? JSONDecoder().decode([Service].self, from: data) else {
            return Presets.all
        }
        // Presets added in later versions show up disabled.
        for preset in Presets.all where !stored.contains(where: { $0.id == preset.id }) {
            var added = preset
            added.enabled = false
            stored.append(added)
        }
        return stored
    }

    private func saveServices() {
        if let data = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(data, forKey: "services")
        }
    }

    // MARK: Polling

    func poll() async {
        let targets = enabledServices
        await withTaskGroup(of: (Service, Result<SummaryResponse, Error>).self) { group in
            for service in targets {
                group.addTask {
                    do {
                        return (service, .success(try await Self.fetchSummary(for: service)))
                    } catch {
                        return (service, .failure(error))
                    }
                }
            }
            for await (service, result) in group {
                apply(result, to: service)
            }
        }
    }

    private func apply(_ result: Result<SummaryResponse, Error>, to service: Service) {
        // Service may have been disabled while the request was in flight.
        guard enabledServices.contains(where: { $0.id == service.id }) else { return }
        var state = states[service.id] ?? ServiceState()

        switch result {
        case .success(let summary):
            let newIndicator = summary.status.indicator
            if let prev = previousIndicators[service.id], prev != newIndicator, notificationsEnabled {
                notifyTransition(service: service, to: newIndicator, description: summary.status.description)
            }
            previousIndicators[service.id] = newIndicator

            state.indicator = newIndicator
            state.description = summary.status.description
            state.components = summary.components
                .filter { $0.group_id == nil }
                .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            state.incidents = summary.incidents ?? []
            state.lastUpdated = Date()
            state.error = nil
        case .failure(let error):
            state.error = error.localizedDescription
        }
        states[service.id] = state
    }

    nonisolated private static func fetchSummary(for service: Service) async throws -> SummaryResponse {
        guard let statusioID = service.statusioID else { return try await fetchSummary(service.baseURL) }
        let response: StatusIOResponse = try await fetchJSON("https://api.status.io/1.0/status/\(statusioID)")
        return response.asSummary(name: service.name, baseURL: service.baseURL)
    }

    nonisolated private static func fetchSummary(_ baseURL: String) async throws -> SummaryResponse {
        guard let url = URL(string: baseURL)?.appendingPathComponent("api/v2/summary.json") else {
            throw StatusPageError.invalidURL
        }
        return try await fetchJSON(url.absoluteString)
    }

    nonisolated private static func fetchJSON<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw StatusPageError.invalidURL }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Custom services

    /// Validates that `input` is a Statuspage v2 page and adds it, enabled.
    func addCustomService(_ input: String) async throws {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.contains("://") { raw = "https://" + raw }
        guard let parsed = URL(string: raw), let host = parsed.host, let scheme = parsed.scheme else {
            throw StatusPageError.invalidURL
        }
        guard !services.contains(where: { $0.id == host }) else { throw StatusPageError.duplicate }

        let baseURL = "\(scheme)://\(host)"
        let summary: SummaryResponse
        do {
            summary = try await Self.fetchSummary(baseURL)
        } catch is DecodingError {
            throw NSError(domain: "StatusPage", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "No Statuspage API found at \(host)/api/v2/summary.json",
            ])
        }
        services.append(Service(id: host, name: summary.page.name, baseURL: baseURL, symbol: "globe", enabled: true))
    }

    func remove(_ service: Service) {
        services.removeAll { $0.id == service.id }
    }

    // MARK: Aggregate state

    /// Enabled service with the worst status, nil while nothing is enabled.
    var worstService: Service? {
        enabledServices.max { rank(states[$0.id]?.indicator) < rank(states[$1.id]?.indicator) }
    }

    var indicator: String {
        guard let worst = worstService else { return "none" }
        let worstIndicator = states[worst.id]?.indicator ?? "loading"
        if rank(worstIndicator) == 0, enabledServices.contains(where: { states[$0.id] == nil || states[$0.id]?.indicator == "loading" }) {
            return "loading"
        }
        return worstIndicator
    }

    /// Symbol of the affected service, or of the first enabled service when all is well.
    var iconName: String {
        if rank(indicator) > 0, let worst = worstService { return worst.symbol }
        return enabledServices.first?.symbol ?? "checkmark.circle"
    }

    var iconColor: Color { color(for: indicator) }

    var iconOpacity: Double { indicator == "none" ? 1.0 : 0.5 }

    private func rank(_ indicator: String?) -> Int {
        switch indicator {
        case "maintenance": return 1
        case "minor": return 2
        case "major": return 3
        case "critical": return 4
        default: return 0
        }
    }

    private func notifyTransition(service: Service, to: String, description: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(service.name): \(label(for: to))"
        content.body = description
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func color(for indicator: String) -> Color {
        switch indicator {
        case "none": return .green
        case "maintenance": return .blue
        case "minor": return .yellow
        case "major": return .orange
        case "critical": return .red
        default: return .gray
        }
    }

    func label(for indicator: String) -> String {
        switch indicator {
        case "none": return "All systems operational"
        case "maintenance": return "Under maintenance"
        case "minor": return "Minor issue"
        case "major": return "Major outage"
        case "critical": return "Critical outage"
        case "loading": return "Loading…"
        default: return "Unknown"
        }
    }

    func colorForComponentStatus(_ status: String) -> Color {
        switch status {
        case "operational": return .green
        case "degraded_performance": return .yellow
        case "partial_outage": return .orange
        case "major_outage": return .red
        case "under_maintenance": return .blue
        default: return .gray
        }
    }
}
