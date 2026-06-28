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

    public let title: String
    public private(set) var state: State

    private let event: Event
    private let clipLoader: any EventClipLoading

    public init(event: Event, clipLoader: any EventClipLoading) {
        self.event = event
        self.clipLoader = clipLoader
        title = event.label
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
