import SwiftUI

import CamerasDomain
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

    @State private var image: Image?

    var body: some View {
        ZStack {
            Color.black
            if !isOffline, let image {
                image.resizable().aspectRatio(contentMode: .fill)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay { overlay }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task(id: imageData) {
            image = imageData.flatMap(platformImage(from:))
        }
    }

    @ViewBuilder private var overlay: some View {
        if isOffline {
            OfflineTileOverlay(name: displayName)
        } else {
            LiveTileOverlay(name: displayName, activity: activity)
        }
    }

    private var displayName: String { camera.friendlyName ?? camera.name.value }
}

private struct LiveTileOverlay: View {
    let name: String
    let activity: CameraActivity?

    var body: some View {
        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .center)
            .overlay(alignment: .topLeading) { LiveBadge().padding(10) }
            .overlay(alignment: .bottomLeading) { TileName(name: name).padding(10) }
            .overlay(alignment: .bottomTrailing) {
                if let activity { ActivityBadge(activity: activity).padding(10) }
            }
    }
}

private struct OfflineTileOverlay: View {
    let name: String

    var body: some View {
        Color.white.opacity(0.04)
            .overlay {
                VStack(spacing: 5) {
                    Image(systemName: "video.slash.fill").font(.system(size: 20))
                    Text("Offline").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .overlay(alignment: .bottomLeading) { TileName(name: name).opacity(0.7).padding(10) }
    }
}

private struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("LIVE").font(.system(size: 10, weight: .heavy)).tracking(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TileName: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}

/// The red (alert) / amber (detection) pill that marks what Frigate is tracking on a tile.
private struct ActivityBadge: View {
    let activity: CameraActivity

    var body: some View {
        HStack(spacing: 4) {
            if activity.severity == .alert {
                Image(systemName: "person.fill").font(.system(size: 10, weight: .bold))
            }
            Text(activity.label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var background: Color {
        switch activity.severity {
        case .alert: .red
        case .detection: .orange
        }
    }

    private var foreground: Color {
        switch activity.severity {
        case .alert: .white
        case .detection: .black
        }
    }
}
