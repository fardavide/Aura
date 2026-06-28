import Foundation

import CamerasDomain
import TimelineDomain

extension [ReviewMarkerDto] {
    /// Maps review segments to markers, dropping severities the timeline doesn't render.
    func toMarkers() -> [ReviewMarker] {
        compactMap { dto in
            guard let severity = dto.severity.reviewSeverity else { return nil }
            return ReviewMarker(
                start: Date(timeIntervalSince1970: dto.startTime),
                end: dto.endTime.map { Date(timeIntervalSince1970: $0) },
                severity: severity
            )
        }
    }
}

extension [MotionActivityDto] {
    func toBuckets() -> [MotionBucket] {
        map { dto in
            MotionBucket(
                time: Date(timeIntervalSince1970: dto.startTime),
                intensity: Swift.min(100, Swift.max(0, Int(dto.motion.rounded())))
            )
        }
    }
}

extension [RecordingGapDto] {
    func toGaps() -> [FootageGap] {
        map { dto in
            FootageGap(
                range: TimeRange(
                    start: Date(timeIntervalSince1970: dto.startTime),
                    end: Date(timeIntervalSince1970: dto.endTime)
                )
            )
        }
    }
}

extension [PreviewClipDto] {
    func toClips() -> [PreviewClip] {
        map { dto in
            PreviewClip(
                camera: CameraName(dto.camera),
                range: TimeRange(
                    start: Date(timeIntervalSince1970: dto.start),
                    end: Date(timeIntervalSince1970: dto.end)
                ),
                path: dto.src
            )
        }
    }
}

extension [String] {
    /// Maps preview-frame filenames (`preview_<camera>-<unixSeconds>.webp`) to domain frames.
    func toFrames(camera: CameraName) -> [PreviewFrame] {
        compactMap { fileName in
            guard let time = fileName.previewFrameTime else { return nil }
            return PreviewFrame(camera: camera, time: time, fileName: fileName)
        }
    }
}

private extension String {
    var reviewSeverity: ReviewSeverity? {
        switch self {
        case "alert": .alert
        case "detection": .detection
        default: nil
        }
    }

    /// Parses the trailing `-<unixSeconds>.webp` of a preview-frame filename into a Date.
    var previewFrameTime: Date? {
        guard hasSuffix(".webp"), let dash = lastIndex(of: "-") else { return nil }
        let timestamp = self[index(after: dash)...].dropLast(".webp".count)
        return Double(timestamp).map(Date.init(timeIntervalSince1970:))
    }
}
