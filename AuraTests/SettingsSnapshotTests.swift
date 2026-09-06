import SwiftUI
import Testing

import CamerasDomain
import SettingsDomain
import SettingsPresentation
import TestDoubles

/// Screenshot tests for the Settings menu and its Server sub-screen, captured on every device +
/// orientation (iOS). The screens are fully synchronous (no network, no dates): the fake
/// repository's values drive the fields, and view models are pre-driven so the views' own
/// `onAppear` re-load settles on the same pixels.
@MainActor
struct SettingsSnapshotTests {

    @Test func `given no connection when the menu is shown then it matches the reference`() async {
        // given — first run: no camera-order row yet
        let view = await settingsMenu(repository: FakeSettingsRepository(), cameras: nil, appIcon: FakeAppIconSwitcher())

        // then
        assertScreenSnapshot(view, named: "menu-first-run")
    }

    @Test func `given a configured server when the menu is shown then it matches the reference`() async {
        // given
        let repository = FakeSettingsRepository(
            connection: ConnectionSettings(
                scheme: .https, host: "frigate.local", port: 8_971,
                username: "admin", password: "hunter2"
            ),
            theme: .dark
        )
        let view = await settingsMenu(
            repository: repository, cameras: .success(snapshotCameras()), appIcon: FakeAppIconSwitcher()
        )

        // then
        assertScreenSnapshot(view, named: "menu")
    }

    @Test func `given the cameras read fails when the menu is shown then the count is omitted`() async {
        // given
        let repository = FakeSettingsRepository(
            connection: ConnectionSettings(
                scheme: .https, host: "frigate.local", port: 8_971,
                username: "admin", password: "hunter2"
            ),
            theme: .dark
        )
        let view = await settingsMenu(
            repository: repository, cameras: .failure(.unreachable), appIcon: FakeAppIconSwitcher()
        )

        // then
        assertScreenSnapshot(view, named: "menu-count-unknown")
    }

    @Test func `given a chosen alternate when the icon picker is shown then it matches the reference`() {
        // given — the preview artwork comes from the app bundle, so this also proves the
        // asset names in the picker match the catalog
        let viewModel = appIconViewModel(FakeAppIconSwitcher(current: .signal))
        viewModel.onAppear()

        // then
        assertScreenSnapshot(NavigationStack { AppIconView(viewModel: viewModel) }, named: "app-icon")
    }

    @Test func `given no saved connection when the server form is shown then it matches the reference`() {
        // given
        let viewModel = serverSettingsViewModel(FakeSettingsRepository())
        viewModel.onAppear()

        // then
        assertScreenSnapshot(NavigationStack { ServerSettingsView(viewModel: viewModel) }, named: "server-first-run")
    }

    // The password SecureField renders BLANK in the reference on purpose: iOS excludes
    // isSecureTextEntry content from window-hierarchy captures (the drawHierarchyInKeyWindow
    // path this suite needs for Liquid Glass). Verified against a plain layer-rendering probe,
    // which shows the seven bullets.
    @Test func `given a saved connection when the server form is shown then it matches the reference`() {
        // given
        let viewModel = serverSettingsViewModel(FakeSettingsRepository(
            connection: ConnectionSettings(
                scheme: .https, host: "frigate.local", port: 8_971,
                username: "admin", password: "hunter2"
            )
        ))
        viewModel.onAppear()

        // then
        assertScreenSnapshot(NavigationStack { ServerSettingsView(viewModel: viewModel) }, named: "server-saved")
    }

    @Test func `given an empty host when saving the server form then the error is shown`() {
        // given
        let viewModel = serverSettingsViewModel(FakeSettingsRepository())
        viewModel.onAppear()

        // when
        viewModel.save()

        // then
        assertScreenSnapshot(NavigationStack { ServerSettingsView(viewModel: viewModel) }, named: "server-invalid-host")
    }

    @Test func `given four cameras when the order screen is shown then it matches the reference`() async {
        // given
        let view = await cameraOrder(snapshotCameras())

        // then
        assertScreenSnapshot(view, named: "camera-order")
    }

    @Test func `given a server with no cameras when the order screen is shown then it explains`() async {
        // given
        let view = await cameraOrder([])

        // then
        assertScreenSnapshot(view, named: "camera-order-empty")
    }
}

// MARK: - View builders

@MainActor
private func settingsMenu(
    repository: FakeSettingsRepository,
    cameras: Result<[Camera], CamerasError>?,
    appIcon: FakeAppIconSwitcher
) async -> some View {
    let viewModel = SettingsViewModel(
        loadTheme: LoadTheme(repository: repository),
        saveTheme: SaveTheme(repository: repository),
        loadConnection: LoadConnection(repository: repository),
        getCameras: cameras.map { GetCameras(repository: FakeCamerasRepository($0)) },
        loadAppIcon: LoadAppIcon(switcher: appIcon)
    )
    viewModel.onAppear()
    await viewModel.load()
    return SettingsView(
        viewModel: viewModel,
        makeServerSettingsViewModel: { serverSettingsViewModel(repository) },
        // Derived from the same `cameras` as the view model's count, so the row and the count
        // always agree (nil → nil, a result → the same fixture).
        makeCameraOrderViewModel: cameras.map { cameras in
            {
                CameraOrderViewModel(
                    getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
                    loadCameraOrder: LoadCameraOrder(repository: repository),
                    saveCameraOrder: SaveCameraOrder(repository: repository)
                )
            }
        },
        makeAppIconViewModel: { appIconViewModel(appIcon) },
        onDone: {}
    )
}

@MainActor
private func cameraOrder(_ cameras: [Camera]) async -> some View {
    let settings = FakeSettingsRepository()
    let viewModel = CameraOrderViewModel(
        getCameras: GetCameras(repository: FakeCamerasRepository(.success(cameras))),
        loadCameraOrder: LoadCameraOrder(repository: settings),
        saveCameraOrder: SaveCameraOrder(repository: settings)
    )
    await viewModel.load()
    return NavigationStack { CameraOrderView(viewModel: viewModel) }
}

@MainActor
private func appIconViewModel(_ switcher: FakeAppIconSwitcher) -> AppIconViewModel {
    AppIconViewModel(
        loadAppIcon: LoadAppIcon(switcher: switcher),
        changeAppIcon: ChangeAppIcon(switcher: switcher)
    )
}

@MainActor
private func serverSettingsViewModel(_ repository: FakeSettingsRepository) -> ServerSettingsViewModel {
    ServerSettingsViewModel(
        loadConnection: LoadConnection(repository: repository),
        saveConnection: SaveConnection(repository: repository)
    )
}
