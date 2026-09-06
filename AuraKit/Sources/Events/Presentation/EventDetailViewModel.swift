import Foundation
import Observation

import EventsDomain

@Observable
@MainActor
public final class EventDetailViewModel {
    public enum State: Equatable {
        case unavailable
        case loading
        case ready(Data)
        case failed
    }

    public let label: String
    public let severity: EventSeverity
    public let startTime: Date
    public let duration: Duration?
    public private(set) var state: State

    private let event: Event
    private let clipLoader: any EventClipLoading

    public init(event: Event, clipLoader: any EventClipLoading) {
        self.event = event
        self.clipLoader = clipLoader
        label = event.label
        severity = event.severity
        startTime = event.startTime
        duration = event.endTime.map { Duration.seconds($0.timeIntervalSince(event.startTime)) }
        state = event.hasClip ? .loading : .unavailable
    }

    public func load() async {
        guard event.hasClip else { return }
        state = .loading
        if let data = await clipLoader.downloadClip(for: event) {
            state = .ready(data)
        } else {
            state = .failed
        }
    }
}
