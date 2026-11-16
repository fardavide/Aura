#if os(iOS)
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import CamerasPresentation

@MainActor
struct CameraWallPreviewLayoutTests {
    @Test func `given four by three previews when the wide camera wall loads then its tiles do not overlap`() throws {
        // given
        let scenario = Scenario()
        let host = UIHostingController(rootView: scenario.sut)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            originalWindow?.makeKey()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        // when
        let deadline = Date(timeIntervalSinceNow: 3)
        while !scenario.sidePreviewsHaveLoaded(in: host.view), Date.now < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        try #require(scenario.sidePreviewsHaveLoaded(in: host.view))

        // then
        let upperTile = try #require(scenario.frames[1])
        let lowerTile = try #require(scenario.frames[2])
        #expect(upperTile.maxY < lowerTile.minY)
    }

    @MainActor
    private final class Scenario {
        private let cameras = Array(snapshotCameras().prefix(3))
        private let preview = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).pngData { renderer in
            UIColor.red.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }

        private(set) var frames: [Int: CGRect] = [:]

        var sut: some View {
            CameraWallLayout(style: .heroLeading, spacing: 12) {
                ForEach(cameras.indices, id: \.self) { [self] index in
                    CameraTileView(
                        camera: cameras[index], activity: nil, isOffline: false, imageData: preview,
                        style: index == 0 ? .hero : .tile
                    )
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("camera-wall-host")) } action: {
                        self.frames[index] = $0
                    }
                }
            }
            .frame(width: 340)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(name: "camera-wall-host")
            .ignoresSafeArea()
            .snapshotEnvironment()
        }

        func sidePreviewsHaveLoaded(in view: UIView) -> Bool {
            guard let upperTile = frames[1], let lowerTile = frames[2] else { return false }
            let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
            let image = renderer.image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            return [upperTile, lowerTile].allSatisfy { frame in
                let pixel = CGRect(x: (frame.maxX - 20) * image.scale, y: frame.midY * image.scale, width: 1, height: 1)
                guard let sample = image.cgImage?.cropping(to: pixel.integral),
                      let context = CGContext(
                        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else { return false }
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
                return bytes[0] > 150 && bytes[1] < 30 && bytes[2] < 30
            }
        }
    }
}
#endif
