import SwiftUI

import EventsDomain
import CommonPlayer

struct EventRowView: View {
    let event: Event
    let loadThumbnail: (Event) async -> Data?

    @State private var image: Image?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(event.label.capitalized).font(.headline)
                Text(event.camera.value).font(.subheadline).foregroundStyle(.secondary)
                Text(event.startTime, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .task(id: event.id) {
            image = await loadThumbnail(event).flatMap(platformImage(from:))
        }
    }

    @ViewBuilder private var thumbnail: some View {
        Group {
            if let image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
