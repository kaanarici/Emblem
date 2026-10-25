import CoreLocation
import Foundation
import MapKit
import Observation

public struct LocationSnapshot: Sendable, Equatable {
    public var city: String?
    var region: String?
    var country: String?
    public var latitude: Double
    public var longitude: Double
}

@Observable @MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var snapshot: LocationSnapshot?

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }

    private let manager = CLLocationManager()
    private struct PendingRequest {
        let id: UUID
        let continuation: CheckedContinuation<LocationSnapshot?, Never>
    }

    private var pending: [PendingRequest] = []
    private var isResolving = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOnce() async -> LocationSnapshot? {
        if let snapshot { return snapshot }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        let requestID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                pending.append(PendingRequest(id: requestID, continuation: continuation))
                startFixIfNeeded()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingRequest(requestID)
            }
        }
    }

    private func cancelPendingRequest(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).continuation.resume(returning: nil)
    }

    private func startFixIfNeeded() {
        guard !pending.isEmpty, !isResolving else { return }
        guard isAuthorized else { return }
        isResolving = true
        manager.requestLocation()
    }

    private func finish(_ result: LocationSnapshot?) {
        snapshot = result
        isResolving = false
        let waiters = pending
        pending = []
        for request in waiters { request.continuation.resume(returning: result) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                startFixIfNeeded()
            case .denied, .restricted:
                finish(nil)
            case .notDetermined:
                break
            @unknown default:
                finish(nil)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            Task { @MainActor in self.finish(nil) }
            return
        }
        Task { @MainActor in await self.reverseGeocode(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        let coordinate = location.coordinate
        let item = try? await MKReverseGeocodingRequest(location: location)?.mapItems.first
        let address = item?.addressRepresentations
        let fullAddress = item?.address?.fullAddress ?? ""
        let components = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
            .firstMatch(in: fullAddress, range: NSRange(fullAddress.startIndex..., in: fullAddress))?
            .addressComponents
        finish(LocationSnapshot(
            city: address?.cityName ?? components?[.city],
            region: components?[.state],
            country: address?.regionName ?? components?[.country],
            latitude: coordinate.latitude,
            longitude: coordinate.longitude))
    }
}
