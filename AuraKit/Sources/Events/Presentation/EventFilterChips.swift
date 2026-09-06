import SwiftUI

import CommonDesign
import EventsDomain

/// The label filter row above the events list: "All" plus one chip per distinct label present in
/// the loaded window, ordered by descending count. Renders nothing when there are no filters (no
/// events loaded yet). `filter` writes only through `select(_:)` — the view model's own `filter`
/// stays `private(set)`.
struct EventFilterChips: View {
    let filters: [EventFilter]
    let selection: EventFilter
    let onSelect: (EventFilter) -> Void

    @Environment(\.designMotion) private var designMotion

    var body: some View {
        if !filters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters) { filter in
                        chip(filter)
                    }
                }
            }
            .contentMargins(.horizontal, 16)
            .animation(designMotion == .animated ? .snappy : nil, value: selection)
        }
    }

    private func chip(_ filter: EventFilter) -> some View {
        Button(action: { onSelect(filter) }) {
            if filter == selection {
                Text(filter.title)
                    .auroraText(.chip)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(AuroraGradient.diagonal, in: Capsule())
                    .overlay { Capsule().strokeBorder(.auroraChipBorder, lineWidth: 1) }
            } else {
                Text(filter.title)
                    .auroraText(.chip)
                    .foregroundStyle(.auroraTextSecondary)
                    .auroraChip()
            }
        }
        .buttonStyle(.plain)
    }
}
