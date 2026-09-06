import SwiftUI

import CommonDesign
import CommonPlayer
import EventsDomain

/// The "LATEST ALERT" (or "LATEST EVENT", when no alert is loaded — decision #4) hero card: the
/// newest significant event's full-frame still, pushed like any other row.
struct EventHeroCard: View {
    let event: Event
    let cameraName: String
    let duration: String?
    let loadImage: (Event) async -> Data?

    @State private var image: Image?

    var body: some View {
        NavigationLink(value: event) {
            card
        }
        .buttonStyle(.plain)
        .auroraFrame(cornerRadius: 24)
        .task(id: event.id) {
            image = await loadImage(event).flatMap(platformImage(from:))
        }
    }

    private var card: some View {
        ZStack(alignment: .topLeading) {
            Color.auroraNoFootage
            if let image {
                image.resizable().aspectRatio(contentMode: .fill)
            }
            LinearGradient(colors: [.clear, .auroraBase], startPoint: .center, endPoint: .bottom)
            chrome
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .environment(\.colorScheme, .dark)
    }

    private var chrome: some View {
        VStack {
            HStack(alignment: .top) {
                Label(pillText, systemImage: "person.fill")
                    .textCase(.uppercase)
                    .auroraBadge(.alert, size: .compact)
                Spacer()
                Text(timeAndDuration).auroraNumerals(.rulerLabel)
                    .foregroundStyle(.white)
                    .auroraChip(over: .video)
            }
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.label.capitalized).auroraText(.heroTitle)
                    Text(cameraName).auroraText(.caption).foregroundStyle(.auroraTextSecondary)
                }
                Spacer()
                if event.hasClip {
                    Image(systemName: "play.fill").auroraChip(over: .video)
                }
            }
        }
        .padding(14)
    }

    private var pillText: String {
        event.severity == .alert ? "Latest alert" : "Latest event"
    }

    private var timeAndDuration: String {
        let time = event.startTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
        guard let duration else { return time }
        return "\(time) · \(duration)"
    }
}
