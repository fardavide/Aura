import AVKit
import SwiftUI

import CommonDesign
import CommonPlayer
import ExportsDomain

/// A finished export, playing. Reads as a sibling of the app's other player screens: the picture in
/// the same 22pt gradient-rimmed card, a floating glass transport, and the one action that belongs
/// here — saving a copy.
public struct ExportPlayerView: View {
    @State private var viewModel: ExportPlayerViewModel
    private let cameraName: String
    private let downloadState: ExportDownloadState?
    private let onDownload: () -> Void
    private let onCancelDownload: () -> Void

    public init(
        viewModel: ExportPlayerViewModel,
        cameraName: String,
        downloadState: ExportDownloadState?,
        onDownload: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.cameraName = cameraName
        self.downloadState = downloadState
        self.onDownload = onDownload
        self.onCancelDownload = onCancelDownload
    }

    public var body: some View {
        VStack(spacing: 20) {
            video
            transport
            Spacer(minLength: 0)
            downloadSection
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .auroraBackground()
        .navigationTitle(cameraName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await viewModel.start()
        }
        .onDisappear { viewModel.stop() }
    }

    private var video: some View {
        ScrubbingPlayerView(player: viewModel.player, videoGravity: .resizeAspect)
            .background(Color.auroraBase)
            .aspectRatio(16 / 9, contentMode: .fit)
            .auroraFrame(cornerRadius: 22)
            .auroraCardGlow()
            .accessibilityLabel("\(cameraName) clip")
    }

    private var transport: some View {
        VStack(spacing: 14) {
            scrubTrack
            HStack(spacing: 22) {
                circle(systemImage: "gobackward.10", diameter: 48, label: "Back 10 seconds") {
                    viewModel.skip(-10)
                }
                playButton
                circle(systemImage: "goforward.10", diameter: 48, label: "Forward 10 seconds") {
                    viewModel.skip(10)
                }
            }
        }
    }

    private var playButton: some View {
        Button { viewModel.togglePlayback() } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                // The play triangle reads off-centre in a circle; pause's two bars are symmetric.
                .offset(x: viewModel.isPlaying ? 0 : 2)
                .frame(width: 62, height: 62)
                .background(Circle().fill(AuroraGradient.diagonal))
                .shadow(color: .auroraGradientPink.opacity(0.5), radius: 13, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
    }

    private func circle(
        systemImage: String,
        diameter: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.auroraTextPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.auroraChipFill))
                .overlay { Circle().strokeBorder(.auroraChipBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var scrubTrack: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let fraction = viewModel.duration > 0 ? viewModel.currentTime / viewModel.duration : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.auroraGradientBlue, .auroraGradientPink],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: proxy.size.width * fraction)
                    Circle()
                        .fill(AuroraGradient.playheadDotStops.stops.first?.color ?? .auroraGradientViolet)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                        .frame(width: 15, height: 15)
                        .offset(x: proxy.size.width * fraction - 7.5)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let ratio = min(max(0, value.location.x / proxy.size.width), 1)
                        viewModel.seek(to: ratio * viewModel.duration)
                    }
                )
            }
            .frame(height: 15)
            HStack {
                Text(timecode(viewModel.currentTime))
                Spacer()
                Text(timecode(viewModel.duration))
            }
            .auroraNumerals(.rulerLabel)
            .foregroundStyle(.auroraTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(timecode(viewModel.currentTime)) of \(timecode(viewModel.duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: viewModel.skip(10)
            case .decrement: viewModel.skip(-10)
            @unknown default: break
            }
        }
    }

    @ViewBuilder private var downloadSection: some View {
        switch downloadState {
        case .transferring(let transfer):
            VStack(spacing: 10) {
                ExportTransferBar(transfer: transfer)
                Button(ExportCopy.cancelDownload, action: onCancelDownload)
                    .buttonStyle(ExportChipButtonStyle())
            }
        case .failed(let error):
            ExportErrorStrip(message: ExportCopy.downloadFailure(error), retry: onDownload)
        case .cancelled:
            Text(ExportCopy.cancelledNotice)
                .auroraText(.caption)
                .foregroundStyle(.auroraTextSecondary)
        case .readyToSave, .none:
            VStack(spacing: 8) {
                Button(ExportCopy.download, action: onDownload)
                    .buttonStyle(.auroraGradient(glow: true))
                    .frame(maxWidth: .infinity, minHeight: 50)
                // The hand-off is promised before it happens, so the system sheet that appears
                // afterwards is expected rather than a surprise.
                Text(Self.downloadPromise)
                    .auroraText(.caption)
                    .foregroundStyle(.auroraTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    #if os(macOS)
    private static let downloadPromise = "Saves a copy through the macOS save panel. The clip stays on the server."
    #else
    private static let downloadPromise = "Saves a copy through the iOS share sheet. The clip stays on the server."
    #endif
}
