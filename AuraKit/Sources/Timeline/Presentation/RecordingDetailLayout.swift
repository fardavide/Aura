import SwiftUI

/// The Timeline-detail screen's on-screen composition: one camera's footage with the timeline panel
/// against it, in the arrangement the available space calls for.
///
/// - **Phone upright** — the footage fills the screen and the panel floats over the bottom on
///   glass, so the picture keeps the whole display and the footage refracts through the card.
/// - **Phone on its side** — the footage goes full-bleed and the panel becomes a tall rail down the
///   trailing edge, where the height it needs is the one thing that orientation has to spare.
/// - **iPad and Mac** — a 16:9 hero with the panel spread wide beneath it, the time axis and the
///   controls side by side.
///
/// Split out from `RecordingPlayerView` so every arrangement can be screenshot-tested over a
/// placeholder, with literal state and no player.
public struct RecordingDetailLayout<Video: View>: View {
    private let state: RecordingDetailState
    private let actions: RecordingDetailActions
    private let video: Video

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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
        hero(clearingTrailing: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                panel(.stacked)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
    }

    /// The footage runs edge to edge and the rail floats on glass over its trailing side — the
    /// chrome keeps clear of that strip so a badge never ends up behind the panel.
    private var rail: some View {
        hero(clearingTrailing: Self.railWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                panel(.rail)
                    .frame(width: Self.railWidth)
                    .padding(.trailing, 10)
                    .padding(.vertical, 10)
            }
    }

    private var split: some View {
        VStack(spacing: 16) {
            hero(clearingTrailing: 0)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            panel(.split)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: Self.splitPanelMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private func hero(clearingTrailing inset: CGFloat) -> some View {
        video
            .background(.black)
            .overlay {
                RecordingHeroOverlay(state: state)
                    .padding(.trailing, inset)
            }
    }

    private func panel(_ arrangement: RecordingTimelinePanel.Arrangement) -> some View {
        RecordingTimelinePanel(arrangement: arrangement, state: state, actions: actions)
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
