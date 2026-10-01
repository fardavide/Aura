import Testing

import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct ServerSettingsViewModelTests {

    @Test(arguments: [ServerRoute.remote, .local])
    func `given a nonnumeric live port when saving then the live stream route is named`(route: ServerRoute) {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteHost = "frigate.example.net"
        sut.localHost = "192.168.1.50"
        switch route {
        case .remote:
            sut.remoteLivePort = "invalid"
        case .local:
            sut.localLivePort = "invalid"
        }

        // when
        sut.save()

        // then
        let routeName = route == .remote ? "remote" : "local"
        #expect(sut.errorMessage == "The \(routeName) live stream port must be a number between 1 and 65535.")
        #expect(repository.savedConnection == nil)
        #expect(!sut.didSave)
    }

    @Test func `given cleared live ports when saving then both direct live configurations are removed`() {
        // given
        let repository = FakeSettingsRepository(connection: ConnectionSettings(
            remote: ServerAddress(scheme: .https, host: "frigate.example.net", port: 8971),
            local: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000),
            remoteLive: LiveConnectionSettings(scheme: .https, port: 8443),
            localLive: LiveConnectionSettings(scheme: .http, port: 1984),
            username: "operator",
            password: "secret"
        ))
        let sut = makeViewModel(repository)
        sut.onAppear()
        sut.remoteLivePort = "   "
        sut.localLivePort = ""

        // when
        sut.save()

        // then
        #expect(sut.didSave)
        #expect(repository.savedConnection?.remoteLive == nil)
        #expect(repository.savedConnection?.localLive == nil)
        #expect(repository.savedConnection?.username == "operator")
        #expect(repository.savedConnection?.password == "secret")
    }

    @Test func `given a local live stream without a local server when saving then the form explains the missing address`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteHost = "frigate.example.net"
        sut.localLivePort = "1984"

        // when
        sut.save()

        // then
        #expect(sut.errorMessage == "Enter a local server address before adding a local live port.")
        #expect(repository.savedConnection == nil)
        #expect(!sut.didSave)
    }

    @Test func `given live ports when saving then both routes retain their API settings and credentials`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteHost = "frigate.example.net"
        sut.remotePort = "8971"
        sut.remoteScheme = .https
        sut.localHost = "192.168.1.50"
        sut.remoteLiveScheme = .https
        sut.remoteLivePort = "8443"
        sut.localLivePort = "1984"
        sut.username = "operator"
        sut.password = "secret"

        // when
        sut.save()

        // then
        #expect(repository.savedConnection == ConnectionSettings(
            remote: ServerAddress(scheme: .https, host: "frigate.example.net", port: 8971),
            local: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000),
            remoteLive: LiveConnectionSettings(scheme: .https, port: 8443),
            localLive: LiveConnectionSettings(scheme: .http, port: 1984),
            username: "operator",
            password: "secret"
        ))
        #expect(sut.didSave)
        #expect(sut.errorMessage == nil)
    }

    @Test func `given saved live configurations when appearing then each route's scheme and port are prefilled`() {
        // given
        let repository = FakeSettingsRepository(connection: ConnectionSettings(
            remote: ServerAddress(scheme: .https, host: "frigate.example.net", port: 8971),
            local: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000),
            remoteLive: LiveConnectionSettings(scheme: .https, port: 8443),
            localLive: LiveConnectionSettings(scheme: .http, port: 1984),
            username: "operator",
            password: "secret"
        ))
        let sut = makeViewModel(repository)

        // when
        sut.onAppear()

        // then
        #expect(sut.remoteLiveScheme == .https)
        #expect(sut.remoteLivePort == "8443")
        #expect(sut.localLiveScheme == .http)
        #expect(sut.localLivePort == "1984")
    }

    @Test func `given a saved connection when appearing then the fields are prefilled`() {
        // given
        let repository = FakeSettingsRepository()
        repository.savedConnection = ConnectionSettings(
            remote: ServerAddress(scheme: .https, host: "frigate.ts.net", port: 8_971),
            local: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000),
            remoteLive: nil,
            localLive: nil,
            username: "admin",
            password: "pw"
        )
        let sut = makeViewModel(repository)

        // when
        sut.onAppear()

        // then
        #expect(sut.remoteScheme == .https)
        #expect(sut.remoteHost == "frigate.ts.net")
        #expect(sut.remotePort == "8971")
        #expect(sut.localScheme == .http)
        #expect(sut.localHost == "192.168.1.50")
        #expect(sut.localPort == "5000")
        #expect(sut.username == "admin")
        #expect(sut.password == "pw")
    }

    @Test func `given a saved connection with no local address when appearing then the local host is empty`() {
        // given
        let repository = FakeSettingsRepository()
        repository.savedConnection = ConnectionSettings(
            remote: ServerAddress(scheme: .https, host: "frigate.ts.net", port: 8_971),
            local: nil,
            remoteLive: nil,
            localLive: nil,
            username: nil,
            password: nil
        )
        let sut = makeViewModel(repository)

        // when
        sut.onAppear()

        // then
        #expect(sut.localHost.isEmpty)
    }

    @Test func `given valid fields when saving then the connection is persisted`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteHost = "frigate.ts.net"
        sut.remotePort = "5000"

        // when
        sut.save()

        // then
        #expect(repository.savedConnection == ConnectionSettings(
            remote: ServerAddress(scheme: .http, host: "frigate.ts.net", port: 5000),
            local: nil,
            remoteLive: nil,
            localLive: nil,
            username: nil,
            password: nil
        ))
        #expect(sut.didSave)
        #expect(sut.errorMessage == nil)
    }

    @Test func `given both addresses when saving then the connection carries the local one`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteHost = "frigate.ts.net"
        sut.remotePort = "8971"
        sut.remoteScheme = .https
        sut.localHost = "192.168.1.50"
        sut.localPort = "5000"

        // when
        sut.save()

        // then
        #expect(repository.savedConnection?.local == ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000))
    }

    @Test func `given a cleared local host when saving then the local address is dropped`() {
        // given — the port keeps whatever it had; an empty host is the form's "no local address"
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteHost = "frigate.ts.net"
        sut.localHost = "   "
        sut.localPort = "5000"

        // when
        sut.save()

        // then
        #expect(sut.didSave)
        #expect(repository.savedConnection?.local == nil)
    }

    @Test func `given an empty remote host when saving then it errors and does not persist`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteHost = "   "

        // when
        sut.save()

        // then
        #expect(sut.errorMessage == "Enter a valid remote host.")
        #expect(repository.savedConnection == nil)
        #expect(sut.didSave == false)
    }

    @Test func `given a non-numeric remote port when saving then the error names the remote address`() {
        // given
        let sut = makeViewModel()
        sut.remoteHost = "frigate.ts.net"
        sut.remotePort = "abc"

        // when
        sut.save()

        // then
        #expect(sut.errorMessage == "The remote port must be a number between 1 and 65535.")
    }

    @Test func `given a non-numeric local port when saving then the error names the local address`() {
        // given
        let sut = makeViewModel()
        sut.remoteHost = "frigate.ts.net"
        sut.localHost = "192.168.1.50"
        sut.localPort = "abc"

        // when
        sut.save()

        // then
        #expect(sut.errorMessage == "The local port must be a number between 1 and 65535.")
    }
}

@MainActor
private func makeViewModel(_ repository: FakeSettingsRepository = FakeSettingsRepository()) -> ServerSettingsViewModel {
    ServerSettingsViewModel(
        loadConnection: LoadConnection(repository: repository),
        saveConnection: SaveConnection(repository: repository)
    )
}
