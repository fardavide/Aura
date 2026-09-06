import Foundation

import CommonFrigate
import CommonNetwork
import EventsDomain

/// Reads events from Frigate's `/api/events`, decoding + mapping to the domain, then joins
/// severity from a best-effort `/api/review` read over the loaded window (decision #4): an event
/// is an alert when an alert-severity review item lists its id in `data.detections`.
public struct FrigateEventsRepository: EventsRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient

    /// Frigate orders review items severity asc then start_time desc, so truncation drops the
    /// oldest *detections* first and every alert survives — the same cap the Timeline uses per
    /// window (`/frigate-rest`).
    private let reviewLimit = 1_000

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func events(limit: Int) async throws(EventsError) -> [Event] {
        let data = try await get(.events(limit: limit, after: nil))
        let events: [Event]
        do {
            events = try JSONDecoder().decode([EventDto].self, from: data).toEvents()
        } catch {
            throw EventsError.invalidData
        }
        guard !events.isEmpty else { return events }

        let alertIds = await alertEventIds(for: events)
        guard !alertIds.isEmpty else { return events }
        return events.map { alertIds.contains($0.id.value) ? $0.withSeverity(.alert) : $0 }
    }

    /// Best effort: any failure (transport or decode) yields an empty set, so the events list
    /// still renders with no ALERT tags rather than a review outage blacking out the tab.
    private func alertEventIds(for events: [Event]) async -> Set<String> {
        let after = events.map(\.startTime).min() ?? Date()
        let before = events.map { $0.endTime ?? $0.startTime }.max() ?? Date()
        let url = FrigateReviewUrl.review(
            base: config.baseUrl,
            cameras: [],
            after: after.timeIntervalSince1970,
            before: before.timeIntervalSince1970,
            limit: reviewLimit
        )
        guard let data = try? await api.get(url) else { return [] }
        guard let reviews = try? JSONDecoder().decode([EventReviewDto].self, from: data) else { return [] }
        return reviews.alertEventIds()
    }

    private func get(_ endpoint: FrigateEndpoint) async throws(EventsError) -> Data {
        do {
            return try await api.get(endpoint.url(base: config.baseUrl))
        } catch {
            throw EventsError(error)
        }
    }
}

private extension EventsError {
    /// Translates the shared Frigate transport error into the feature's domain error at the Data
    /// boundary, so the Domain never sees Frigate vocabulary.
    init(_ error: FrigateApiError) {
        switch error {
        case .unreachable: self = .unreachable
        case .notAuthorized: self = .notAuthorized
        case .serverUnavailable: self = .serverUnavailable
        case .unknown: self = .unknown
        }
    }
}
