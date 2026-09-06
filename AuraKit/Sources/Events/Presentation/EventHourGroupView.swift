import SwiftUI

import CamerasEntities
import CommonDesign
import EventsDomain

/// One hour band's header + glass card of rows, newest event first.
struct EventHourGroupView: View {
    let group: EventHourGroup
    let countText: String
    let dayContext: (Date) -> EventsListViewModel.EventDayContext
    let displayName: (CameraName) -> String
    let duration: (Event) -> String?
    let loadThumbnail: (Event) async -> Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            card
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            hourLabel
            Rectangle()
                .fill(LinearGradient(colors: [.auroraChipBorder, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            Text(countText).auroraText(.caption).foregroundStyle(.auroraTextSecondary)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var hourLabel: some View {
        switch dayContext(group.hourStart) {
        case .today:
            Text(group.hourStart, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                .auroraNumerals(.rowSummary)
        case .otherDay:
            // "Sat 12 · 20:00" — two different days both rendering "20:00" would be ambiguous.
            Text(
                "\(group.hourStart, format: .dateTime.weekday(.abbreviated).day()) · \(group.hourStart, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())"
            )
            .auroraNumerals(.rowSummary)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                NavigationLink(value: event) {
                    EventRowView(
                        event: event,
                        cameraName: displayName(event.camera),
                        duration: duration(event),
                        loadThumbnail: loadThumbnail
                    )
                }
                .buttonStyle(.plain)
                if index < group.events.count - 1 {
                    Divider().overlay(.auroraChipBorder)
                }
            }
        }
        .auroraCard(cornerRadius: 20)
    }
}
