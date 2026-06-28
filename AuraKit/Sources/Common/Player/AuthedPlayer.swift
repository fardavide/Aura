import AVKit
import Foundation

/// Builds an `AVPlayer` whose media requests carry the given HTTP headers (e.g. auth) via
/// `AVURLAssetHTTPHeaderFieldsKey` — the one path live streams, clips, and previews all rely on.
public func makeAuthedPlayer(url: URL, headers: [String: String]) -> AVPlayer {
    let options = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
    let asset = AVURLAsset(url: url, options: options)
    return AVPlayer(playerItem: AVPlayerItem(asset: asset))
}
