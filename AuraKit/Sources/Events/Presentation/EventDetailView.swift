import AVKit
import Foundation
import SwiftUI

import CommonDesign
import EventsDomain

public struct EventDetailView: View {
    // Pinned, per the project's view-model rule: the navigation destination builds a fresh view
    // model on every re-evaluation of the list behind it, and a plain `let` would swap the
    // displayed one — throwing away a verdict the user had just given.
    @State private var viewModel: EventDetailViewModel
    private let cameraName: String

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(viewModel: EventDetailViewModel, cameraName: String) {
        _viewModel = State(initialValue: viewModel)
        self.cameraName = cameraName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if verticalSizeClass != .compact {
                header
            }
            content
            feedbackPanel
        }
        .auroraBackground()
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .task { await viewModel.load() }
        // Its own task, so the panel appears while the clip is still downloading.
        .task { await viewModel.loadFeedback() }
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

    /// Frigate+ is a paid add-on, so nothing is drawn unless the server confirmed it takes feedback
    /// and this event is one it can accept — the view model owns that gate, not this switch.
    @ViewBuilder private var feedbackPanel: some View {
        switch viewModel.feedback {
        case .unavailable:
            EmptyView()
        case .ready:
            feedbackCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Is this a \(viewModel.label)?")
                        .auroraText(.bodyEmphasis)
                        .foregroundStyle(.auroraTextPrimary)
                    HStack(spacing: 10) {
                        Button("Yes") { Task { await viewModel.submit(.correct) } }
                            .buttonStyle(.auroraGradient)
                            .accessibilityLabel("Yes, this is a \(viewModel.label)")
                        Button("No") { Task { await viewModel.submit(.incorrect) } }
                            .buttonStyle(.plain)
                            .auroraChip()
                            .accessibilityLabel("No, this is not a \(viewModel.label)")
                    }
                    Text("Either answer sends this snapshot to Frigate+ to train your model.")
                        .auroraText(.caption)
                        .foregroundStyle(.auroraTextSecondary)
                }
            }
        case .sending:
            feedbackCard {
                HStack(spacing: 10) {
                    ProgressView().tint(.auroraGradientPink)
                    Text("Sending to Frigate+…")
                        .auroraText(.body)
                        .foregroundStyle(.auroraTextSecondary)
                }
            }
        case .submitted(let verdict):
            feedbackCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(submittedTitle(verdict))
                        .auroraText(.bodyEmphasis)
                        .foregroundStyle(.auroraTextPrimary)
                    // The API carries a yes/no and nothing else — naming the right object is only
                    // possible in the Frigate+ dataset itself, so the panel says where to go.
                    Text("The snapshot is in your Frigate+ dataset. Give it the right label there to teach your model.")
                        .auroraText(.caption)
                        .foregroundStyle(.auroraTextSecondary)
                    Link("Open Frigate+", destination: frigatePlusDashboard)
                        .buttonStyle(.plain)
                        .auroraChip()
                        .padding(.top, 4)
                }
            }
        case .failed(let verdict, let error):
            feedbackCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(feedbackMessage(for: error))
                        .auroraText(.body)
                        .foregroundStyle(.auroraTextSecondary)
                    // A refusal is the server's final word — repeating the request fails the same
                    // way, so no retry is offered for it.
                    if error != .notAccepted {
                        Button("Try again") { Task { await viewModel.submit(verdict) } }
                            .buttonStyle(.plain)
                            .auroraChip()
                    }
                }
            }
        }
    }

    private func feedbackCard(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .auroraCard(cornerRadius: 18)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
    }

    private func submittedTitle(_ verdict: DetectionVerdict?) -> String {
        switch verdict {
        case .correct: "Confirmed as a \(viewModel.label)."
        case .incorrect: "Reported as not a \(viewModel.label)."
        case nil: "Already sent to Frigate+."
        }
    }

    private func feedbackMessage(for error: EventsError) -> String {
        switch error {
        case .unreachable: "Can't reach the server. Check your connection."
        case .notAuthorized: "Frigate+ refused the sign-in. Submitting needs an admin account."
        case .notAccepted: "Frigate+ wouldn't accept this event. It needs a clean snapshot, which this one doesn't have."
        case .serverUnavailable: "The server returned an error. Try again later."
        case .invalidData: "The server's response couldn't be read."
        case .unknown: "Couldn't send this to Frigate+."
        }
    }

    private func durationText(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
    }
}

/// A compile-time constant, not runtime input — `URL(string:)` cannot fail on it.
private let frigatePlusDashboard = URL(string: "https://plus.frigate.video")!

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
