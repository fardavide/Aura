#if os(iOS)
import Foundation
import SwiftUI
import Testing
import UIKit

import SettingsDomain
import SettingsPresentation
import TestDoubles

@MainActor
@Suite(.serialized)
struct ServerSetupFlowTests {
    @Test(arguments: [
        Hosts(remote: "192.168.1.50", local: "192.168.1.50"),
        Hosts(remote: "frigate.example.net", local: nil),
        Hosts(remote: nil, local: "192.168.1.50")
    ])
    func `given first setup when saving the server then Settings starts connecting`(hosts: Hosts) async throws {
        // given
        try await withServerEditor(hosts: hosts) { window, _, scenario in
            let save = try #require(await waitFor(in: window) {
                allViews(in: window).lazy.compactMap { $0 as? UINavigationBar }.flatMap { allViews(in: $0) }
                    .compactMap { ($0 as? ButtonActionView)?.trigger }
                    .first
            }, "The server editor exposes its SwiftUI toolbar action")

            // when
            save()

            // then
            try #require(scenario.editor.didSave, "The entered addresses were saved. \(scenario.editor.errorMessage ?? "")")
            let connected = try #require(scenario.connectedSettings)
            #expect(connected.remote == hosts.remote.map { ServerAddress(scheme: .http, host: $0, port: 5000) })
            #expect(connected.local == hosts.local.map { ServerAddress(scheme: .http, host: $0, port: 5000) })
        }
    }

    @Test func `given the server editor when scrolling then both live ports and credentials are visible`() async throws {
        // given
        try await withServerEditor(hosts: Hosts(remote: nil, local: nil)) { _, form, _ in
            let rows = (0..<form.numberOfSections).flatMap { section in
                (0..<form.numberOfItems(inSection: section)).map { IndexPath(item: $0, section: section) }
            }
            var placeholders: Set<String> = []
            var livePortCount = 0

            // when
            for row in rows {
                form.scrollToItem(at: row, at: .centeredVertically, animated: false)
                let cell = try #require(await waitFor(in: form) { form.cellForItem(at: row) })
                let fields = allViews(in: cell).compactMap { $0 as? UITextField }
                livePortCount += fields.filter { $0.keyboardType == .numberPad && $0.text == "1984" }.count
                placeholders.formUnion(fields.compactMap(\.placeholder))
            }

            // then
            #expect(livePortCount == 2)
            #expect(placeholders.isSuperset(of: ["Username", "Password"]))
        }
    }

    private func withServerEditor(
        hosts: Hosts,
        perform: @MainActor (UIWindow, UICollectionView, Scenario) async throws -> Void
    ) async throws {
        let scenario = Scenario(hosts: hosts)
        let host = UIHostingController(rootView: scenario.sut
            .buttonStyle(ActionCaptureStyle())
            .snapshotEnvironment()
            .environment(\.layoutDirection, .leftToRight))
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
        let settingsList = try #require(await waitFor(in: host.view) {
            allViews(in: host.view).lazy.compactMap { $0 as? UICollectionView }.first
        })
        let firstRow = IndexPath(item: 0, section: 0)
        // The Server section is first and its only row opens the connection editor.
        settingsList.delegate?.collectionView?(settingsList, didSelectItemAt: firstRow)
        let form = try #require(await waitFor(in: host.view) {
            allViews(in: host.view).lazy.compactMap { $0 as? UICollectionView }.first { collection in
                let placeholders = allViews(in: collection).compactMap { ($0 as? UITextField)?.placeholder }
                return placeholders.contains("http://192.168.1.50:5000")
                    && placeholders.contains("https://frigate.example.net")
            }
        }, "The Server row opens the editor with both address fields")
        try await perform(window, form, scenario)
    }

    private func waitFor<T>(in view: UIView, matching match: () -> T?) async -> T? {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        repeat {
            view.layoutIfNeeded()
            if let match = match() { return match }
            await Task.yield()
        } while clock.now < deadline
        return nil
    }

    private func allViews(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { allViews(in: $0) }
    }

    struct Hosts: Sendable {
        let remote: String?
        let local: String?
    }

    @MainActor
    private final class Scenario {
        let editor: ServerSettingsViewModel
        private let loadConnection: LoadConnection
        private let settings: SettingsViewModel
        private(set) var connectedSettings: ConnectionSettings?

        init(hosts: Hosts) {
            let repository = FakeSettingsRepository()
            loadConnection = LoadConnection(repository: repository)
            editor = ServerSettingsViewModel(
                loadConnection: loadConnection,
                saveConnection: SaveConnection(repository: repository)
            )
            editor.remoteAddress = hosts.remote ?? ""
            editor.localAddress = hosts.local ?? ""
            settings = SettingsViewModel(
                loadTheme: LoadTheme(repository: repository),
                saveTheme: SaveTheme(repository: repository),
                loadConnection: loadConnection,
                activeServer: nil,
                loadDynamicCameraOrder: LoadDynamicCameraOrder(repository: repository),
                saveDynamicCameraOrder: SaveDynamicCameraOrder(repository: repository),
                getCameras: nil
            )
        }

        var sut: SettingsView {
            SettingsView(
                viewModel: settings,
                makeServerSettingsViewModel: { self.editor },
                makeCameraOrderViewModel: nil,
                appIconViewModel: nil,
                isFirstSetup: true,
                onDone: { self.connectedSettings = self.loadConnection.execute() }
            )
        }
    }
}

// SwiftUI toolbar buttons have no UIKit target/action entry point in the app-hosted test.
private struct ActionCaptureStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .background(ButtonActionCapture(trigger: configuration.trigger))
    }
}

private struct ButtonActionCapture: UIViewRepresentable {
    let trigger: () -> Void

    func makeUIView(context: Context) -> ButtonActionView { ButtonActionView() }

    func updateUIView(_ view: ButtonActionView, context: Context) { view.trigger = trigger }
}

private final class ButtonActionView: UIView {
    var trigger: (() -> Void)?
}
#endif
