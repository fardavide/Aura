import SwiftUI

import CommonPlayer

/// The Timeline-detail screen's on-screen composition: one camera's footage with the timeline panel
/// against it, in the arrangement the available space calls for.
///
/// - **Phone upright** — the footage sits at the top, in the space the bottom glass panel leaves
///   free, so the controls never cover the resting picture.
/// - **Phone on its side** — the footage takes the space beside a tall rail down the trailing
///   edge; the same rule, sideways.
/// - **iPad and Mac** — a 16:9 hero with the panel spread wide beneath it, the time axis and the
///   controls side by side.
///
/// The video is pinch-zoomable everywhere. On the phones its **slot** is unclipped, so zoomed
/// footage overflows it and slides under the glass instead of stopping at an invisible line; the
/// iPad hero clips to its rounded frame, since nothing overlaps it. The chrome and the panel live
/// outside the zoom and never scale.
///
/// Split out from `RecordingPlayerView` so every arrangement can be screenshot-tested over a
/// placeholder, with literal state and no player — and with `cameraAreaHighlights` on, the
/// baselines outline the surface and the slot so a panel creeping over the picture is caught here.
public struct RecordingDetailLayout<Video: View>: View {
    private let state: RecordingDetailState
    private let actions: RecordingDetailActions
    private let video: Video

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.cameraAreaHighlights) private var cameraAreaHighlights

    private static var railWidth: CGFloat { 168 }
    private static var splitPanelMaxWidth: CGFloat { 1100 }

    public init(
        state: RecordingDetailState,
        actions: RecordingDetailActions,
        @ViewBuilder video: () -> Video
    ) {
        self.state = state
        self.actions = actions
        self.video = video()
    }

    public var body: some View {
        switch arrangement {
        case .stacked: stacked
        case .rail: rail
        case .split: split
        }
    }

    private var stacked: some View {
        VStack(spacing: 12) {
            slot(clipped: false)
            panel(.stacked)
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .overlay { surfaceHighlight }
    }

    private var rail: some View {
        HStack(spacing: 10) {
            slot(clipped: false)
            panel(.rail)
                .frame(width: Self.railWidth)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .overlay { surfaceHighlight }
    }

    private var split: some View {
        VStack(spacing: 16) {
            slot(clipped: true)
                .background(.black)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { surfaceHighlight }
            panel(.split)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: Self.splitPanelMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    /// The zoomable video area. At rest the video letterboxes inside this slot — the one part of
    /// the screen the panel never covers. The chrome overlays the slot *outside* the zoom, so the
    /// badges stay put and legible while the picture scales under them.
    private func slot(clipped: Bool) -> some View {
        ZoomableContainer(onSingleTap: {}, clipsContent: clipped) {
            video
        }
        .overlay { RecordingHeroOverlay(state: state) }
        .overlay { slotHighlight }
    }

    private func panel(_ arrangement: RecordingTimelinePanel.Arrangement) -> some View {
        RecordingTimelinePanel(arrangement: arrangement, state: state, actions: actions)
    }

    /// Diagnostics for the screenshot suite: everything zoomed footage may cover. Drawn above the
    /// panel on purpose — the surface legitimately runs under it.
    @ViewBuilder private var surfaceHighlight: some View {
        if cameraAreaHighlights {
            areaHighlight(.orange, label: "SURFACE", labelAt: .bottomTrailing)
        }
    }

    /// Diagnostics for the screenshot suite: the resting video's space. Any glass over this
    /// outline in a baseline is a layout regression.
    @ViewBuilder private var slotHighlight: some View {
        if cameraAreaHighlights {
            areaHighlight(.green, label: "CAMERA SLOT", labelAt: .bottomLeading)
        }
    }

    private func areaHighlight(_ color: Color, label: String, labelAt alignment: Alignment) -> some View {
        Rectangle()
            .fill(color.opacity(0.08))
            .overlay {
                Rectangle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .overlay(alignment: alignment) {
                Text(label)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.85), in: Capsule())
                    .padding(10)
                    .fixedSize()
            }
            .allowsHitTesting(false)
    }

    /// Wide and short is a phone on its side — iPad reports a regular height in every orientation
    /// and multitasking mode, and macOS has no size class at all, so both take the split.
    private var arrangement: RecordingTimelinePanel.Arrangement {
        #if os(iOS)
        if verticalSizeClass == .compact { return .rail }
        return horizontalSizeClass == .compact ? .stacked : .split
        #else
        return .split
        #endif
    }
}
