import Foundation

import CamerasDomain
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
