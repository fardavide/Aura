import Testing

import CamerasDomain
import CamerasEntities
import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct SettingsViewModelTests {

    @Test func `given a saved theme when appearing then it is prefilled`() {
        // given
        let scenario = Scenario(theme: .light)

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.theme == .light)
    }

    @Test func `when the theme changes then it is saved immediately`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.theme = .dark

        // then
        #expect(scenario.settings.savedTheme == .dark)
    }

    @Test func `given no saved connection when appearing then the server summary is not configured`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.serverSummary == .notConfigured)
    }

    @Test func `given one address when appearing then the server summary reports no route`() {
        // given — nothing was chosen, so naming a route would read as a setting rather than a fact
        let scenario = Scenario(connection: connection(local: nil))

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.serverSummary == .configured(hostPort: "frigate.ts.net:8971", route: nil))
    }

    @Test func `given two addresses when appearing then the server summary is the active one`() {
        // given
        let scenario = Scenario(
            connection: connection(local: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000)),
            activeRoute: .local
        )

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.serverSummary == .configured(hostPort: "192.168.1.50:5000", route: .local))
    }

    @Test func `given no server when loading then the camera count stays unknown`() async {
        // given
        let scenario = Scenario()

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.cameraCount == .unknown)
    }

    @Test func `given three cameras when loading then the camera count is known`() async {
        // given
        let scenario = Scenario(cameras: .success([camera("attic"), camera("driveway"), camera("garage")]))

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.cameraCount == .known(3))
    }

    @Test func `given the cameras read fails when loading then the camera count stays unknown`() async {
        // given
        let scenario = Scenario(cameras: .failure(.unreachable))

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.cameraCount == .unknown)
    }

    @Test func `given a known count when a reload fails then the last count is kept`() async {
        // given
        let scenario = Scenario(cameras: .success([camera("attic")]))
        await scenario.sut.load()

        // when
        scenario.cameras?.result = .failure(.serverUnavailable)
        await scenario.sut.load()

        // then
        #expect(scenario.sut.cameraCount == .known(1))
    }

    @Test func `given one camera when loading then the count reads singular`() async {
        // given
        let scenario = Scenario(cameras: .success([camera("attic")]))

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.cameraCountText == "1 camera")
    }

    @Test func `given several cameras when loading then the count reads plural`() async {
        // given
        let scenario = Scenario(cameras: .success([camera("attic"), camera("garage")]))

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.cameraCountText == "2 cameras")
    }

    @Test func `given nothing stored when appearing then the dynamic camera order reads on`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.usesDynamicCameraOrder)
    }

    @Test func `given the dynamic camera order is off when appearing then it is prefilled off`() {
        // given
        let scenario = Scenario()
        scenario.settings.savedDynamicCameraOrder = false

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.usesDynamicCameraOrder == false)
    }

    @Test func `when the dynamic camera order is turned off then it is saved immediately`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.usesDynamicCameraOrder = false

        // then
        #expect(scenario.settings.savedDynamicCameraOrder == false)
    }

    @Test func `given the platform cannot switch icons when appearing then the app icon is absent`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.appIcon == nil)
    }

    @Test func `given the signal icon is current when appearing then the app icon is signal`() {
        // given
        let scenario = Scenario(currentIcon: .signal)

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.appIcon == .signal)
    }
}

private func camera(_ name: String) -> Camera {
    Camera(name: CameraName(name), friendlyName: nil, isEnabled: true, streamNames: [])
}

private func connection(local: ServerAddress?) -> ConnectionSettings {
    ConnectionSettings(
        remote: ServerAddress(scheme: .https, host: "frigate.ts.net", port: 8_971),
        local: local,
        username: "admin",
        password: "hunter2"
    )
}

@MainActor
private struct Scenario {
    let settings: FakeSettingsRepository
    let cameras: FakeCamerasRepository?
    let sut: SettingsViewModel

    init(
        theme: ThemePreference = .system,
        connection: ConnectionSettings? = nil,
        activeRoute: ServerRoute = .remote,
        cameras: Result<[Camera], CamerasError>? = nil,
        currentIcon: AppIconPreference? = nil
    ) {
        settings = FakeSettingsRepository(connection: connection, theme: theme)
        self.cameras = cameras.map(FakeCamerasRepository.init)
        sut = SettingsViewModel(
            loadTheme: LoadTheme(repository: settings),
            saveTheme: SaveTheme(repository: settings),
            loadConnection: LoadConnection(repository: settings),
            activeServer: connection.map { connection in
                switch activeRoute {
                case .local: connection.localServer ?? connection.remoteServer
                case .remote: connection.remoteServer
                }
            },
            loadDynamicCameraOrder: LoadDynamicCameraOrder(repository: settings),
            saveDynamicCameraOrder: SaveDynamicCameraOrder(repository: settings),
            getCameras: self.cameras.map(GetCameras.init),
            loadAppIcon: currentIcon.map { LoadAppIcon(switcher: FakeAppIconSwitcher(current: $0)) }
        )
    }
}
