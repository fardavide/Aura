import SwiftUI

import CommonDesign
import TimelineDomain

/// The chrome floated over the footage: which camera and exactly when, on the leading side; what
/// the server flagged at that instant, on the trailing side. Over a stretch with nothing recorded
/// it replaces the picture with a plain statement rather than leaving the last frame up, which
/// would read as the wrong moment.
struct RecordingHeroOverlay: View {
    let state: RecordingDetailState

    var body: some View {
        ZStack {
            if !state.hasFootage {
                noFootage
            }
            VStack {
                HStack(alignment: .top) {
                    identity
                    Spacer(minLength: 12)
                    badge
                }
                Spacer()
            }
            .padding(12)
        }
        // The hero is a dark surface whatever the app's appearance — the footage behind it is, and
        // so is the fallback it shows over a gap. Forcing dark here is what keeps this chrome
        // legible in a light-mode app (decision #11).
        .environment(\.colorScheme, .dark)
    }

    private var noFootage: some View {
        ZStack {
            Color.auroraNoFootage
            VStack(spacing: 8) {
                Image(systemName: "clock.badge.questionmark").imageScale(.large)
                Text("No footage at this time").auroraText(.captionEmphasis)
            }
            .foregroundStyle(.auroraTextMuted)
        }
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
