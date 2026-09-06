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

    @Test func `given a saved connection when appearing then the server summary is host and port`() {
        // given
        let scenario = Scenario(connection: ConnectionSettings(
            scheme: .https, host: "frigate.local", port: 8_971, username: "admin", password: "hunter2"
        ))

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.serverSummary == .configured(hostPort: "frigate.local:8971"))
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

@MainActor
private struct Scenario {
    let settings: FakeSettingsRepository
    let cameras: FakeCamerasRepository?
    let sut: SettingsViewModel

    init(
        theme: ThemePreference = .system,
        connection: ConnectionSettings? = nil,
        cameras: Result<[Camera], CamerasError>? = nil,
        currentIcon: AppIconPreference? = nil
    ) {
        settings = FakeSettingsRepository(connection: connection, theme: theme)
        self.cameras = cameras.map(FakeCamerasRepository.init)
        sut = SettingsViewModel(
            loadTheme: LoadTheme(repository: settings),
            saveTheme: SaveTheme(repository: settings),
            loadConnection: LoadConnection(repository: settings),
            getCameras: self.cameras.map(GetCameras.init),
            loadAppIcon: currentIcon.map { LoadAppIcon(switcher: FakeAppIconSwitcher(current: $0)) }
        )
    }
}
