import Foundation

import CamerasEntities
import TimelineDomain

struct RecordingMappingDto: Decodable {
    let durations: [Int]
    let sequences: [Sequence]

    struct Sequence: Decodable {
        let clips: [Clip]
    }

    struct Clip: Decodable {
        let type: String
        let path: String
        let clipFrom: Int?
    }

    func clips(base: URL, camera: CameraName, headers: [String: String], segments: [RecordingSegment], window: TimeRange) throws(TimelineError) -> [RecordingClip] {
        guard sequences.count == 1, let sequence = sequences.first,
              sequence.clips.count == durations.count else { throw .invalidData }
        var remaining = segments
        var result: [RecordingClip] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd/HH/mm.ss'.mp4'"
        for (clip, milliseconds) in zip(sequence.clips, durations) {
            let prefix = "/media/frigate/recordings/"
            guard clip.type == "source", clip.path.hasPrefix(prefix),
                  milliseconds >= 100, milliseconds < 600_000,
                  (clip.clipFrom ?? 0) >= 0 else { throw .invalidData }
            let components = String(clip.path.dropFirst(prefix.count)).split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 4, components[2] == camera.value,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  clip.path.hasSuffix(".mp4"),
                  !clip.path.contains("%"), !clip.path.contains("\\") else { throw .invalidData }
            let timestamp = components[0] + "/" + components[1] + "/" + components[3]
            guard let index = remaining.firstIndex(where: { formatter.string(from: $0.range.start) == timestamp }) else {
                throw .invalidData
            }
            let segment = remaining.remove(at: index)
            let offset = Double(clip.clipFrom ?? 0) / 1000
            // Frigate snaps the mapped start back to a keyframe. Remove that preroll so the
            // composition and its wall-clock mapping begin at the requested instant together.
            let preroll = max(0, window.start.timeIntervalSince(segment.range.start) - offset)
            let duration = Double(milliseconds) / 1000 - preroll
            guard duration.isFinite else { throw .invalidData }
            // Frigate applies its duration filter after adding keyframe preroll. Discard a
            // tiny logical overlap only after correlating the mapped file with its segment.
            guard duration >= 0.1, duration < 600,
                  max(segment.range.start, window.start) < min(segment.range.end, window.end) else { continue }
            result.append(RecordingClip(
                source: CameraStreamSource(
                    url: base.appending(path: "recordings/" + components.joined(separator: "/")), headers: headers
                ),
                range: TimeRange(start: max(segment.range.start, window.start), end: min(segment.range.end, window.end)),
                sourceOffset: offset + preroll,
                duration: duration
            ))
        }
        return result
    }
}
