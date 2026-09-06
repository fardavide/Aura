import AVFoundation
import SwiftUI

import CommonDesign
import CommonPlayer
import TimelineDomain

/// One camera tile, kept in sync with the shared scrub clock.
struct PreviewTileView: View {
    let viewModel: PreviewTileViewModel
    let clock: ScrubClock
    let transport: TimelineTransport
    let range: TimeRange
    let style: PreviewTileStyle
    let alertLabel: String?

    var body: some View {
        Group {
            switch style {
            // The hero takes the shared video-frame rim (the Live card and the Cameras hero use
            // the same vocabulary), at the mock's heavier 2pt width and its own glow.
            case .hero:
                tileBase
                    .auroraFrame(cornerRadius: style.cornerRadius, lineWidth: 2)
                    .shadow(color: .auroraGradientViolet.opacity(0.35), radius: 24, y: 10)
            // Every other tile keeps a plain 1pt border.
            case .compactGrid, .regularGrid:
                tileBase
                    .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                            .strokeBorder(.auroraChipBorder, lineWidth: 1)
                    }
            }
        }
        // The first load is keyed off the **fixed span start**, so extending the live edge
        // (which moves only span.end) can't cancel an in-flight first load and strand the tile
        // on its spinner. Following the live edge is a separate trigger keyed off span.end — it
        // refreshes the material in place (newly recorded footage reaches the tile without
        // rebuilding the playing clip) but never tears the first load down.
        .task(id: range.start) {
            await viewModel.prepare(range: range, at: clock.instant)
        }
        .task(id: range.end) {
            await viewModel.followLiveEdge(to: range, at: clock.instant)
        }
        .onChange(of: clock.instant) { _, instant in
            viewModel.scrub(to: instant)
        }
        // Entering playback swaps the low-res scrub material for the camera's own recording;
        // leaving it puts the tile back on the previews at wherever the playhead stopped.
        .task(id: transport.isPlaying) {
            if transport.isPlaying {
                await viewModel.beginPlayback(at: clock.instant, speed: transport.speed)
            } else {
                viewModel.endPlayback(at: clock.instant)
            }
        }
        .onChange(of: transport.speed) { _, speed in
            viewModel.select(speed)
        }
    }

    /// The 16:9 canvas comes from the always-flexible color, not from `content`: a fixed-size
    /// placeholder (spinner, no-footage well) under `aspectRatio` would collapse the whole tile to
    /// its own height, leaving a thin bar where a camera slot belongs. Chrome is composed inside
    /// the same overlay as `content`, before any clip or frame, so the scrim and badge are clipped
    /// to the tile's corners and never paint over the hero's gradient rim.
    private var tileBase: some View {
        Color.black
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { ZStack { content; chrome } }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.display {
        case .loading:
            ProgressView()
        case .clip(let player), .recording(let player):
            ScrubbingPlayerView(player: player, videoGravity: .resizeAspectFill)
        case .frame(let image):
            image
                .resizable()
                .scaledToFill()
        case .unavailable:
            ZStack {
                Color.auroraNoFootage
                Text("No footage").auroraText(.captionEmphasis).foregroundStyle(.auroraTextSecondary)
            }
        case .failed:
            ZStack {
                Color.auroraNoFootage
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Unavailable")
                }
                .auroraText(.captionEmphasis)
                .foregroundStyle(.auroraTextSecondary)
            }
        }
    }

    /// Footage-bearing material gets the full scrim/name/clock/badge headline, forced to the dark
    /// catalog values since it sits on video (decision #11) in both app appearances. The
    /// "No footage"/"Unavailable" well and the loading spinner take the app's own appearance
    /// instead — forcing dark chrome there would paint a dark band and white name across the pale
    /// well in light mode.
    @ViewBuilder private var chrome: some View {
        switch viewModel.display {
        case .clip, .recording, .frame:
            Color.clear
                .overlay {
                    LinearGradient(
                        colors: [.auroraBase.opacity(0.78), .auroraBase.opacity(0)],
                        startPoint: .bottom, endPoint: .center
                    )
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(cameraName)
                        .auroraText(style.nameStyle)
                        .foregroundStyle(.auroraTextPrimary)
                        .padding(style.chromeInset)
                }
                .overlay(alignment: .bottomTrailing) {
                    if style.showsClock {
                        Text(clock.instant, format: .dateTime.hour().minute().second())
                            // `.tileClock` was requested but not added to CommonDesign;
                            // `.rowSummary` (13/bold) is the plan's documented fallback.
                            .auroraNumerals(.rowSummary)
                            .foregroundStyle(.auroraTextPrimary.opacity(0.9))
                            .padding(style.chromeInset)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let alertLabel {
                        // The label is `ReviewMarker.label` — the tracked object ("Car", "Dog", the
                        // fallback word) — so it is text-only in every style: a hardcoded glyph would
                        // assert something false about the footage, and mapping object words to
                        // symbols isn't worth a lookup table that silently defaults.
                        Text(alertLabel)
                            // `.compactWord` was requested but not added to CommonDesign; `.compact`
                            // is the plan's documented fallback (its `.livePill` tracking suits
                            // uppercase words better than this mixed-case one, but ships unblocked).
                            .auroraBadge(.alert, size: .compact)
                            .padding(style.chromeInset)
                    }
                }
                .environment(\.colorScheme, .dark)
        case .loading, .unavailable, .failed:
            if style.showsWellName {
                Color.clear
                    .overlay(alignment: .bottomLeading) {
                        Text(cameraName)
                            .auroraText(style.nameStyle)
                            .foregroundStyle(.auroraTextPrimary)
                            .padding(style.chromeInset)
                    }
            }
        }
    }

    private var cameraName: String {
        viewModel.camera.friendlyName ?? viewModel.camera.name.value
    }
}
