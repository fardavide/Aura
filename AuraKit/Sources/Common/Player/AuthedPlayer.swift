import AVKit
import Foundation

/// Builds an `AVURLAsset` whose media requests carry the given HTTP headers (e.g. auth) via
/// `AVURLAssetHTTPHeaderFieldsKey` — shared by playback and by thumbnail generation.
public func makeAuthedAsset(url: URL, headers: [String: String]) -> AVURLAsset {
    let options = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
    return AVURLAsset(url: url, options: options)
}

/// Builds an `AVPlayerItem` whose media requests carry the given HTTP headers (e.g. auth). A fresh
/// item for a live source starts at the live edge — the live view rebuilds one to recover a stream
/// that went stale while paused.
public func makeAuthedPlayerItem(url: URL, headers: [String: String]) -> AVPlayerItem {
    AVPlayerItem(asset: makeAuthedAsset(url: url, headers: headers))
}

/// Builds an `AVPlayer` whose media requests carry the given HTTP headers (e.g. auth) —
/// the one path live streams, clips, and previews all rely on.
public func makeAuthedPlayer(url: URL, headers: [String: String]) -> AVPlayer {
    AVPlayer(playerItem: makeAuthedPlayerItem(url: url, headers: headers))
}
