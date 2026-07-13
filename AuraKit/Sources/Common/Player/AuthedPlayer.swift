import AVKit
import Foundation

/// Builds an `AVPlayerItem` whose media requests carry the given HTTP headers (e.g. auth) via
/// `AVURLAssetHTTPHeaderFieldsKey`. A fresh item for a live source starts at the live edge — the
/// live view rebuilds one to recover a stream that went stale while paused.
public func makeAuthedPlayerItem(url: URL, headers: [String: String]) -> AVPlayerItem {
    let options = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
    let asset = AVURLAsset(url: url, options: options)
    return AVPlayerItem(asset: asset)
}

/// Builds an `AVPlayer` whose media requests carry the given HTTP headers (e.g. auth) —
/// the one path live streams, clips, and previews all rely on.
public func makeAuthedPlayer(url: URL, headers: [String: String]) -> AVPlayer {
    AVPlayer(playerItem: makeAuthedPlayerItem(url: url, headers: headers))
}
