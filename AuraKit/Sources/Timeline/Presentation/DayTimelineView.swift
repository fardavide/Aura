import SwiftUI

import TimelineDomain

/// The draggable day ruler: motion-intensity strip, alert/detection markers, no-footage gaps,
/// and the playhead. Dragging writes the shared scrub clock.
struct DayTimelineView: View {
    let day: TimeRange
    let timeline: DayTimeline
    let clock: ScrubClock
    let onScrub: (Date) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Canvas { context, size in draw(in: context, size: size) }
                Rectangle()
                    .fill(.red)
                    .frame(width: 2)
                    .offset(x: x(for: clock.instant, width: width) - 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        clock.beginScrub()
                        onScrub(time(forX: value.location.x, width: width))
                    }
                    .onEnded { _ in clock.endScrub() }
            )
        }
        .frame(height: 64)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        for gap in timeline.gaps {
            let start = x(for: gap.range.start, width: size.width)
            let end = x(for: gap.range.end, width: size.width)
            context.fill(
                Path(CGRect(x: start, y: 0, width: Swift.max(1, end - start), height: size.height)),
                with: .color(.black.opacity(0.25))
            )
        }
        for bucket in timeline.motion where bucket.intensity > 0 {
            let height = size.height * CGFloat(bucket.intensity) / 100
            context.fill(
                Path(CGRect(x: x(for: bucket.time, width: size.width), y: size.height - height, width: 2, height: height)),
                with: .color(.green.opacity(0.6))
            )
        }
        for marker in timeline.markers {
            context.fill(
                Path(CGRect(x: x(for: marker.start, width: size.width), y: 0, width: 3, height: size.height * 0.4)),
                with: .color(marker.severity == .alert ? .red : .yellow)
            )
        }
    }

    private func x(for time: Date, width: CGFloat) -> CGFloat {
        let total = day.end.timeIntervalSince(day.start)
        guard total > 0 else { return 0 }
        let fraction = time.timeIntervalSince(day.start) / total
        return CGFloat(min(1, Swift.max(0, fraction))) * width
    }

    private func time(forX x: CGFloat, width: CGFloat) -> Date {
        guard width > 0 else { return day.start }
        let fraction = min(1, Swift.max(0, x / width))
        return day.start.addingTimeInterval(day.end.timeIntervalSince(day.start) * Double(fraction))
    }
}
