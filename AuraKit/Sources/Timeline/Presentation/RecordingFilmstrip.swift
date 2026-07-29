import Foundation
import SwiftUI

import TimelineDomain

/// The Hour-zoom filmstrip behind the scrub track: one still per ten-minute slot, sliding under
/// the overlays with the footage. A slot without a loaded thumbnail — nothing fetched yet, or
/// nothing recorded to fetch — renders as a stable placeholder cell, so the strip lays out
/// identically with and without a server; a screenshot captures exactly those cells.
///
/// Cells are separated by the same hairline the motion bars use: without it, neighbouring stills
/// weld into one image and the strip stops reading as sampled instants.
struct RecordingFilmstrip: View {
    let axis: Axis
    let viewport: TimelineViewport
    let span: TimeRange
    let store: RecordingFilmstripStore

    var body: some View {
        let slots = FilmstripSlots.instants(visible: viewport.visible, span: span)
        GeometryReader { proxy in
            let geometry = TrackGeometry(axis: axis, viewport: viewport, size: proxy.size)
            ZStack(alignment: .topLeading) {
                // Claims the full box so the offset cells are placed against its origin.
                Color.clear
                ForEach(slots, id: \.self) { slot in
                    cell(for: slot, in: geometry)
                }
            }
        }
        .task(id: FilmstripRequest(slots: slots, span: span)) {
            await store.update(slots: slots, span: span)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func cell(for slot: Date, in geometry: TrackGeometry) -> some View {
        let rect = geometry.narrowed(
            geometry.rect(
                from: slot,
                to: slot.addingTimeInterval(FilmstripSlots.duration),
                crossFrom: 0,
                crossTo: geometry.crossExtent
            ),
            by: 1
        )
        Group {
            if let image = store.images[slot] {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipped()
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// One update's identity: the strip re-requests only when a slot enters the grid or the live edge
/// extends the span — not on every playhead tick that merely slides the cells.
private struct FilmstripRequest: Equatable {
    let slots: [Date]
    let span: TimeRange
}
