import Foundation
import SwiftUI

import TimelineDomain

/// A single continuous timeline the user scrolls/pans to move through time. The playhead is fixed
/// at center; scrolling sets the scrub time (so panning the bar *is* scrubbing). Activity overlays
/// (markers, motion, gaps) and hour/day gridlines scroll with the content.
struct ScrollableTimelineView: View {
    let span: TimeRange
    let timeline: DayTimeline
    let onScrub: (Date) -> Void

    private let pointsPerHour: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            let viewportWidth = geo.size.width
            let hours = span.end.timeIntervalSince(span.start) / 3600
            let contentWidth = Swift.max(viewportWidth, CGFloat(hours) * pointsPerHour)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: viewportWidth / 2)
                    TimelineTrack(span: span, timeline: timeline, width: contentWidth)
                    Color.clear.frame(width: viewportWidth / 2)
                }
            }
            .defaultScrollAnchor(.trailing)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, offsetX in
                guard contentWidth > 0 else { return }
                let fraction = min(1, Swift.max(0, offsetX / contentWidth))
                onScrub(span.start.addingTimeInterval(span.end.timeIntervalSince(span.start) * Double(fraction)))
            }
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(.red.opacity(0.8))
                    .frame(width: 2)
                    .allowsHitTesting(false)
            }
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(height: 84)
    }
}

private struct TimelineTrack: View {
    let span: TimeRange
    let timeline: DayTimeline
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            let duration = span.end.timeIntervalSince(span.start)
            guard duration > 0 else { return }
            func x(_ time: Date) -> CGFloat {
                CGFloat(time.timeIntervalSince(span.start) / duration) * size.width
            }

            drawGrid(in: context, size: size, x: x)

            for gap in timeline.gaps {
                let start = x(gap.range.start)
                let end = x(gap.range.end)
                context.fill(
                    Path(CGRect(x: start, y: 0, width: Swift.max(1, end - start), height: size.height)),
                    with: .color(.gray.opacity(0.12))
                )
            }
            for bucket in timeline.motion where bucket.intensity > 0 {
                let height = size.height * 0.5 * CGFloat(bucket.intensity) / 100
                context.fill(
                    Path(CGRect(x: x(bucket.time), y: size.height - height, width: 1.5, height: height)),
                    with: .color(.blue.opacity(0.22))
                )
            }
            for marker in timeline.markers {
                context.fill(
                    Path(CGRect(x: x(marker.start), y: 4, width: 2, height: size.height * 0.4)),
                    with: .color(marker.severity == .alert ? .red.opacity(0.55) : .orange.opacity(0.45))
                )
            }
        }
        .frame(width: width)
    }

    private func drawGrid(in context: GraphicsContext, size: CGSize, x: (Date) -> CGFloat) {
        let calendar = Calendar.current
        guard var tick = calendar.nextDate(
            after: span.start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime
        ) else { return }

        while tick < span.end {
            let hour = calendar.component(.hour, from: tick)
            let position = x(tick)
            let isMidnight = hour == 0
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: position, y: 0))
                    path.addLine(to: CGPoint(x: position, y: size.height))
                },
                with: .color(.gray.opacity(isMidnight ? 0.3 : 0.1)),
                lineWidth: 0.5
            )
            if isMidnight {
                context.draw(
                    Text(tick, format: .dateTime.weekday(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary),
                    at: CGPoint(x: position + 4, y: 9), anchor: .leading
                )
            } else if hour.isMultiple(of: 6) {
                context.draw(
                    Text(tick, format: .dateTime.hour()).font(.system(size: 9)).foregroundStyle(.tertiary),
                    at: CGPoint(x: position + 3, y: 9), anchor: .leading
                )
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: tick) else { return }
            tick = next
        }
    }
}
