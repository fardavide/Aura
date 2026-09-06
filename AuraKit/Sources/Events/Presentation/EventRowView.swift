import SwiftUI

import CommonDesign
import CommonPlayer
import EventsDomain

struct EventRowView: View {
    let event: Event
    let cameraName: String
    let duration: String?
    let loadThumbnail: (Event) async -> Data?

    @State private var image: Image?

    var body: some View {
        HStack(spacing: 12) {
            timeColumn
            thumbnail
            details
            Spacer(minLength: 0)
            chevron
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .task(id: event.id) {
            image = await loadThumbnail(event).flatMap(platformImage(from:))
        }
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.startTime, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                .auroraNumerals(.rowSummary)
            if let duration {
                Text(duration).auroraNumerals(.rulerLabel).foregroundStyle(.auroraTextTertiary)
            } else {
                HStack(spacing: 4) {
                    Circle().fill(.auroraLive).frame(width: 5, height: 5)
                    Text("Live").auroraText(.overline).textCase(.uppercase)
                        .foregroundStyle(.auroraAlertTagText)
                }
            }
        }
        .frame(minWidth: 46, alignment: .leading)
    }

    private var thumbnail: some View {
        Group {
            if let image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.auroraNoFootage)
                    .overlay { Image(systemName: "photo").foregroundStyle(.auroraTextMuted) }
            }
        }
        .frame(width: 88, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if event.severity == .alert {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .inset(by: -2)
                    .strokeBorder(AuroraGradient.diagonal, lineWidth: 2)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(event.label.capitalized).auroraText(.headline)
                if event.severity == .alert {
                    Text("Alert").textCase(.uppercase).auroraBadge(.alertTag, size: .compact)
                }
            }
            Text(cameraName).auroraText(.caption).foregroundStyle(.auroraTextSecondary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").auroraText(.captionEmphasis)
            .foregroundStyle(.auroraTextQuaternary)
    }
}
