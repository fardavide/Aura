import AVKit
import Foundation
import SwiftUI

import CommonDesign
import EventsDomain

public struct EventDetailView: View {
    private let viewModel: EventDetailViewModel
    private let cameraName: String

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(viewModel: EventDetailViewModel, cameraName: String) {
        self.viewModel = viewModel
        self.cameraName = cameraName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if verticalSizeClass != .compact {
                header
            }
            content
        }
        .auroraBackground()
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .task { await viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(viewModel.label.capitalized).auroraText(.heroTitle)
                severityBadge
            }
            HStack(spacing: 6) {
                Text(cameraName).auroraText(.caption)
                Text(verbatim: "·")
                Text(viewModel.startTime, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    .auroraNumerals(.rulerLabel)
                if let duration = viewModel.duration {
                    Text(verbatim: "·")
                    Text(durationText(duration)).auroraNumerals(.rulerLabel)
                }
            }
            .foregroundStyle(.auroraTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder private var severityBadge: some View {
        switch viewModel.severity {
        case .alert:
            Text("Alert").textCase(.uppercase).auroraBadge(.alertTag, size: .compact)
        case .detection:
            Text("Detection").textCase(.uppercase).auroraBadge(.detection, size: .compact)
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .unavailable:
            ContentUnavailableView(
                "No clip",
                systemImage: "film.stack",
                description: Text("This event has no recorded clip.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let data):
            ClipPlayer(data: data)
                .aspectRatio(16 / 9, contentMode: .fit)
                .auroraFrame(cornerRadius: 22)
                .padding(.horizontal, 16)
        case .failed:
            ContentUnavailableView(
                "Couldn't load clip",
                systemImage: "exclamationmark.triangle",
                description: Text("The recording couldn't be downloaded from the server.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func durationText(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
    }
}

/// Writes the downloaded clip bytes to a temp file and plays it locally — avoids streaming the
/// MP4 (and its auth/byte-range pitfalls) through AVPlayer.
private struct ClipPlayer: View {
    let data: Data

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Color.auroraNoFootage
            }
        }
        .task {
            guard player == nil else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            guard (try? data.write(to: url)) != nil else { return }
            let created = AVPlayer(url: url)
            player = created
            created.play()
        }
        .onDisappear { player?.pause() }
    }
}
