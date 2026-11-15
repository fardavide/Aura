#if os(iOS)
import AVFoundation
import Foundation
import SwiftUI
import Testing
import UIKit

import CamerasDomain
import CamerasEntities
import CamerasPresentation
import TestDoubles

@MainActor
struct CameraTimelineNavigationTests {
    @Test func `given a live camera when its timeline opens then the camera player releases its item before timeline playback`() throws {
        // given
        let source = CameraStreamSource(
            url: try #require(URL(string: "aura-test://camera/live.m3u8")),
            headers: [:]
        )
        let scenario = Scenario(source: source)
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
        try #require(waitFor { player(in: host.view.layer)?.currentItem != nil })
        let cameraPlayer = try #require(player(in: host.view.layer))
        scenario.cameraPlayer = cameraPlayer
        let navBar = try #require(navigationController(in: host)?.navigationBar)
        // This screen has one trailing toolbar action. Invoke the native control's registered
        // action so the test exercises the same route as a tap.
        let buttons = controls(in: navBar).filter { control in
            control.isEnabled && control.allControlEvents.contains(.primaryActionTriggered)
                && control.convert(control.bounds, to: navBar).midX > navBar.bounds.midX
        }
        try #require(buttons.count == 1)
        let timelineButton = try #require(buttons.first)

        // when
        timelineButton.sendActions(for: .primaryActionTriggered)
        try #require(waitFor { scenario.didReleaseCameraItemBeforeTimelinePlayback != nil })

        // then
        #expect(scenario.didReleaseCameraItemBeforeTimelinePlayback == true)
    }

    private func navigationController(in controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController {
            return navigation
        }
        return controller.children.lazy.compactMap { navigationController(in: $0) }.first
    }

    private func controls(in view: UIView) -> [UIControl] {
        let nested = view.subviews.flatMap { controls(in: $0) }
        guard let control = view as? UIControl else { return nested }
        return [control] + nested
    }

    private func player(in layer: CALayer) -> AVPlayer? {
        if let layer = layer as? AVPlayerLayer {
            return layer.player
        }
        return layer.sublayers?.lazy.compactMap { player(in: $0) }.first
    }

    private func waitFor(_ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 3)
        while !condition(), Date.now < deadline {
            _ = RunLoop.main.run(mode: .default, before: deadline)
        }
        return condition()
    }

    @MainActor
    @Observable
    fileprivate final class Scenario {
        private let camera = Camera(
            name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"]
        )
        private let streamProvider: FakeCameraStreamProvider
        private var path: [Camera]
        var cameraPlayer: AVPlayer?
        private(set) var didReleaseCameraItemBeforeTimelinePlayback: Bool?

        init(source: CameraStreamSource) {
            streamProvider = FakeCameraStreamProvider(source)
            path = [camera]
        }

        var sut: some View {
            @Bindable var scenario = self
            let detail = CameraDetailView(
                camera: camera,
                viewModel: CameraDetailViewModel(camera: camera, streamProvider: streamProvider)
            ) { _ in
                Color.clear.onAppear {
                    self.didReleaseCameraItemBeforeTimelinePlayback = self.cameraPlayer.map { $0.currentItem == nil }
                }
            }
            return NavigationStack(path: $scenario.path) {
                Color.clear
                    .navigationDestination(for: Camera.self) { _ in detail }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}
#endif
