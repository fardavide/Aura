/// Everything the day timeline overlays on one time axis: activity markers, the motion strip,
/// and the no-footage gaps.
public struct DayTimeline: Equatable, Sendable {
    public let markers: [ReviewMarker]
    public let motion: [MotionBucket]
    public let gaps: [FootageGap]

    public init(markers: [ReviewMarker], motion: [MotionBucket], gaps: [FootageGap]) {
        self.markers = markers
        self.motion = motion
        self.gaps = gaps
    }
}
