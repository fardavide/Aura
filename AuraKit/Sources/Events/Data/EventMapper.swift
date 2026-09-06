import Foundation

import CamerasEntities
import EventsDomain

extension [EventDto] {
    func toEvents() -> [Event] {
        map { $0.toEvent() }
    }
}

extension EventDto {
    func toEvent() -> Event {
        Event(
            id: EventId(id),
            camera: CameraName(camera),
            label: label,
            severity: .detection,
            subLabel: subLabel,
            startTime: Date(timeIntervalSince1970: startTime),
            endTime: endTime.map { Date(timeIntervalSince1970: $0) },
            hasClip: hasClip ?? false,
            hasSnapshot: hasSnapshot ?? false,
            score: data?.score ?? data?.topScore,
            zones: zones ?? []
        )
    }
}

extension Event {
    /// A full re-init with a different severity — `Event` is immutable, so the alert join has one
    /// place to change rather than every field being repeated at each call site.
    func withSeverity(_ severity: EventSeverity) -> Event {
        Event(
            id: id,
            camera: camera,
            label: label,
            severity: severity,
            subLabel: subLabel,
            startTime: startTime,
            endTime: endTime,
            hasClip: hasClip,
            hasSnapshot: hasSnapshot,
            score: score,
            zones: zones
        )
    }
}
