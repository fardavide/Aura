import SwiftUI

import CamerasDomain
import CommonDesign
import CommonPlayer

/// A live camera tile: the preview still under a calm set of overlays — a LIVE marker, the camera
/// name over a bottom scrim, and (when Frigate is tracking something) an activity badge. A camera
/// the grid has seen go offline shows an offline treatment instead. It never animates, so the grid
/// stays still and the snapshot tests are deterministic; the offline decision is the grid's (it
/// tracks which stills fail), not this view's, so it doesn't hinge on an async load settling.
struct CameraTileView: View {
    let camera: Camera
    let activity: CameraActivity?
    let isOffline: Bool
    let imageData: Data?
    let style: Style

    @State private var image: Image?

    var body: some View {
        ZStack {
            Color.auroraNoFootage
            if !isOffline, let image {
                image.resizable().scaledToFill()
            }
        }
        .clipped()
        .overlay { overlay }
        .modifier(TileFrame(style: style))
        .task(id: imageData) {
            image = imageData.flatMap(platformImage(from:))
        }
    }

    @ViewBuilder private var overlay: some View {
        if isOffline {
            OfflineTileOverlay(name: displayName, style: style)
        } else {
            LiveTileOverlay(name: displayName, activity: activity, style: style)
        }
    }

    private var displayName: String { camera.friendlyName ?? camera.name.value }

    /// Whether the wall lays this tile out as the hero (full-bleed, gradient rim, larger type) or a
    /// regular tile (1pt glass frame, compact type). Set by `CameraWallLayout.Style.hasHero` and
    /// which camera, if any, is `CameraGridViewModel.heroCamera` — not a property of the tile itself.
    enum Style: Equatable {
        case hero
        case tile
    }
}

/// The hero gets the gradient video-frame rim at r24; a regular tile gets a 1pt glass stroke at r18
/// (mock: 1px `rgba(255,255,255,0.14)` frame r19 outer / r18 inner). No `AuroraGlow` on the hero
/// here — `.auroraFrame` clips its content and the tile root is opaque, so a glow confined to the
/// hero's own bounds would paint zero visible pixels; the screen's one glow sits behind the whole
/// wall instead (`CameraGridView`).
private struct TileFrame: ViewModifier {
    let style: CameraTileView.Style

    func body(content: Content) -> some View {
        switch style {
        case .hero:
            content.auroraFrame(cornerRadius: 24)
        case .tile:
            content
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.auroraChipBorder, lineWidth: 1)
                }
        }
    }
}

private struct LiveTileOverlay: View {
    let name: String
    let activity: CameraActivity?
    let style: CameraTileView.Style

    var body: some View {
        LinearGradient(colors: [.black.opacity(0.78), .clear], startPoint: .bottom, endPoint: .center)
            .overlay(alignment: .topLeading) { AuroraLivePill(style: .glass).padding(padding) }
            .overlay(alignment: .bottomLeading) {
                TileName(name: name, style: style).foregroundStyle(.white).padding(padding)
            }
            .overlay(alignment: .bottomTrailing) {
                if let activity { ActivityBadge(activity: activity, style: style).padding(padding) }
            }
    }

    private var padding: CGFloat {
        switch style {
        case .hero: 12
        case .tile: 10
        }
    }
}

private struct OfflineTileOverlay: View {
    let name: String
    let style: CameraTileView.Style

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "video.slash.fill").font(.aurora(.headline))
            Text("Offline").auroraText(.caption)
        }
        .foregroundStyle(.auroraTextTertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            TileName(name: name, style: style)
                .foregroundStyle(.auroraTextSecondary)
                .opacity(0.7)
                .padding(padding)
        }
    }

    private var padding: CGFloat {
        switch style {
        case .hero: 12
        case .tile: 10
        }
    }
}

/// No foreground colour of its own — over the live scrim the caller inks it `.white`; over the
/// offline (no-scrim, near-white-in-light) backing the caller inks it `.auroraTextSecondary`
/// instead, so it never renders white-on-white.
private struct TileName: View {
    let name: String
    let style: CameraTileView.Style

    var body: some View {
        Text(name)
            .auroraText(style == .hero ? .heroTitle : .tileTitle)
            .lineLimit(1)
    }
}

/// The gradient (alert) / amber (detection) pill that marks what Frigate is tracking on a tile.
private struct ActivityBadge: View {
    let activity: CameraActivity
    let style: CameraTileView.Style

    var body: some View {
        HStack(spacing: 4) {
            if activity.severity == .alert {
                Image(systemName: "person.fill")
            }
            Text(activity.label)
        }
        .auroraBadge(tone, size: style == .hero ? .regular : .compact)
    }

    private var tone: AuroraBadgeTone {
        switch activity.severity {
        case .alert: .alert
        case .detection: .detection
        }
    }
}
