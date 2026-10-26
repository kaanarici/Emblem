import MapKit
import Observation

@Observable @MainActor
final class CalendarTravel {
    static let shared = CalendarTravel()
    private var minutes: [String: Int] = [:]
    @ObservationIgnored private var asked: [String: Date] = [:]

    func minutes(to event: CalendarAgendaEvent, now: Date) -> Int? {
        guard let place = event.place, DeviceAccess.shared.canUse(.location) else { return nil }
        let key = event.id + "|" + place
        if asked[key].map({ now.timeIntervalSince($0) < 600 }) != true {
            asked[key] = now
            Task { await estimate(place, key: key) }
        }
        return minutes[key]
    }

    private func estimate(_ place: String, key: String) async {
        let search = MKLocalSearch.Request()
        search.naturalLanguageQuery = place
        guard let destination = try? await MKLocalSearch(request: search).start().mapItems.first else { return }
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = destination
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return }
        let travel = Int((eta.expectedTravelTime / 60).rounded(.up))
        if (2...120).contains(travel) { minutes[key] = travel }
    }
}
