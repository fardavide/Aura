import SwiftUI

import CommonDesign
import TimelineDomain

/// What sits in the video slot besides the picture. Over footage: the chrome — which camera and
/// exactly when, on the leading side; what the server flagged at that instant, on the trailing
/// side. With no picture the card is gone (`RecordingDetailLayout` hides the rim, glow and
/// letterbox with it) and this draws the reason in its place, on the aurora, in the app's own
/// appearance: a gap, a load in progress, or a server that can't be reached. The chip and the LIVE
/// pill go with the picture too — the nav title, the panel clock and the panel's Live pill already
/// carry the camera, the instant and the live state, so nothing is duplicated up here.
struct RecordingHeroOverlay: View {
    let state: RecordingDetailState

    var body: some View {
        switch state.slot {
        case .footage: chrome
        case .loading: loading
        case .noFootage: noFootage
        case .failed: failed
        }
    }

    private var chrome: some View {
        VStack {
            HStack(alignment: .top) {
                identity
                Spacer(minLength: 12)
                badge
            }
            Spacer()
        }
        .padding(12)
        // Footage is a dark surface whatever the app's appearance, so the chrome over it resolves
        // against dark to stay legible in a light-mode app (decision #11). Only over footage: the
        // messages below sit on the aurora and follow the app.
        .environment(\.colorScheme, .dark)
    }

    private var loading: some View {
        ProgressView()
            .tint(.auroraGradientViolet)
    }

    private var noFootage: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 26))
                .foregroundStyle(.auroraTextTertiary)
            Text("No footage at this time")
                .auroraText(.bodyEmphasis)
                .foregroundStyle(.auroraTextSecondary)
        }
    }

    /// The stack the live camera screen draws for "No live stream", so both player screens fail
    /// the same way.
    private var failed: some View {
        VStack(spacing: 5) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 44))
                .foregroundStyle(.auroraTextTertiary)
                .padding(.bottom, 6)
            Text("Can't reach the server")
                .auroraText(.headline)
                .foregroundStyle(.auroraTextPrimary)
            Text("Check your connection settings.")
                .auroraText(.body)
                .foregroundStyle(.auroraTextTertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(state.cameraName)
                .auroraText(.tileTitle)
                .foregroundStyle(.white)
            Text(state.instant, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .auroraNumerals(.rulerLabel)
                .foregroundStyle(.auroraTextSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Flat, never `glassEffect`/`thinMaterial` over a player — that would sample moving
        // pixels and break snapshot determinism (tokens §4 / §6.4).
        .background(Color.auroraVideoChipFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.auroraVideoChipBorder, lineWidth: 1)
        }
    }

    @ViewBuilder private var badge: some View {
        if state.isLive {
            AuroraLivePill(style: .solid)
        } else if let marker = state.activeMarker {
            // `.compactWord` (an untracked 11/ExtraBold type) was requested but not added to
            // CommonDesign; `.compact` is the plan's documented fallback — its `.livePill`
            // tracking suits an uppercase word better than this mixed-case one, but ships
            // unblocked (Risks R13).
            Text(marker.title).auroraBadge(tone(for: marker.severity), size: .compact)
        }
    }
}

private extension ReviewMarker {
    /// The review vocabulary Frigate itself uses. The objects behind a marker aren't decoded here —
    /// naming them is the activity list's job.
    var title: String {
        switch severity {
        case .alert: "Alert"
        case .detection: "Detection"
        }
    }
}

private func tone(for severity: ReviewSeverity) -> AuroraBadgeTone {
    switch severity {
    case .alert: .alert
    case .detection: .detection
    }
}
