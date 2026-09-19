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
            // An absent type predates the field, which only ever tagged object events until audio
            // and manual events were added — so the missing value is `object`, not "unknown".
            isObjectDetection: (data?.type ?? "object") == "object",
            // `false_positive` wins: the endpoint that sets it also fills `plus_id` on the way
            // through, so the two are true together and only the former says which verdict it was.
            verdict: falsePositive == true ? .incorrect : (plusId != nil ? .correct : nil),
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
            isObjectDetection: isObjectDetection,
            verdict: verdict,
            score: score,
            zones: zones
        )
    }
}
