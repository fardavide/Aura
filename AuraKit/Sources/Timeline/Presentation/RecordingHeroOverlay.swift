import SwiftUI

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
                ContentUnavailableView("No footage at this time", systemImage: "clock.badge.questionmark")
            }
            VStack {
                HStack(alignment: .top) {
                    identity
                    Spacer(minLength: 12)
                    badge
                }
                Spacer()
            }
            .padding(16)
        }
        // The hero is a dark surface whatever the app's appearance — the footage behind it is, and
        // so is the black it falls back to. Resolving `primary`/`secondary`/`thinMaterial` against
        // dark is what keeps this chrome legible in a light-mode app.
        .environment(\.colorScheme, .dark)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(state.cameraName)
                .font(.headline)
            Text(state.instant, format: .dateTime.hour().minute().second())
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var badge: some View {
        if state.isLive {
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.red, in: Capsule())
        } else if let marker = state.activeMarker {
            Label(marker.title, systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(marker.severity == .alert ? .red : .orange, in: Capsule())
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
