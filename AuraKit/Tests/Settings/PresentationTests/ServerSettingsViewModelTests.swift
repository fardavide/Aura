import Testing

import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct ServerSettingsViewModelTests {

    @Test func `given a new setup with only a remote host when saving then direct live streaming uses the default port`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.onAppear()
        sut.remoteAddress = "frigate.example.net"

        // when
        sut.save()

        // then
        #expect(repository.savedConnection?.remoteLive == LiveConnectionSettings(scheme: .http, port: 1984))
        #expect(repository.savedConnection?.localLive == nil)
        #expect(sut.didSave)
    }

    @Test(arguments: [ServerRoute.remote, .local])
    func `given a nonnumeric live port when saving then the live stream route is named`(route: ServerRoute) {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteAddress = "frigate.example.net"
        sut.localAddress = "192.168.1.50"
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

    @Test func `given a local live port without a local server when saving then the unused live settings are dropped`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteAddress = "frigate.example.net"
        sut.localLivePort = "1984"

        // when
        sut.save()

        // then
        #expect(sut.errorMessage == nil)
        #expect(repository.savedConnection?.localLive == nil)
        #expect(sut.didSave)
    }

    @Test func `given live ports when saving then both routes retain their API settings and credentials`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteAddress = "https://frigate.example.net:8971"
        sut.localAddress = "192.168.1.50"
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
        #expect(sut.remoteAddress == "https://frigate.ts.net:8971")
        #expect(sut.localAddress == "http://192.168.1.50:5000")
        #expect(sut.remoteLivePort.isEmpty)
        #expect(sut.localLivePort.isEmpty)
        #expect(sut.username == "admin")
        #expect(sut.password == "pw")
    }

    @Test func `given a saved connection with no local address when appearing then the field is empty`() {
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
        #expect(sut.localAddress.isEmpty)
    }

    @Test func `given valid fields when saving then the connection is persisted`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteAddress = "frigate.ts.net"

        // when
        sut.save()

        // then
        #expect(repository.savedConnection == ConnectionSettings(
            remote: ServerAddress(scheme: .http, host: "frigate.ts.net", port: 5000),
            local: nil,
            remoteLive: LiveConnectionSettings(scheme: .http, port: 1984),
            localLive: nil,
            username: nil,
            password: nil
        ))
        #expect(sut.didSave)
        #expect(sut.errorMessage == nil)
    }

    @Test func `given only a local host when saving then the connection is local only`() throws {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.localAddress = "192.168.1.50"

        // when
        sut.save()

        // then
        try #require(sut.didSave, "\(sut.errorMessage ?? "")")
        let saved = try #require(repository.savedConnection)
        #expect(saved.remote == nil)
        #expect(saved.local == ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000))
    }

    @Test func `given both addresses when saving then the connection carries the local one`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteAddress = "https://frigate.ts.net:8971"
        sut.localAddress = "http://192.168.1.50:5000"

        // when
        sut.save()

        // then
        #expect(repository.savedConnection?.local == ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000))
        #expect(repository.savedConnection?.localLive == LiveConnectionSettings(scheme: .http, port: 1984))
    }

    @Test func `given a cleared local address when saving then the local route is dropped`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteAddress = "frigate.ts.net"
        sut.localAddress = "   "

        // when
        sut.save()

        // then
        #expect(sut.didSave)
        #expect(repository.savedConnection?.local == nil)
    }

    @Test func `given neither address when saving then it asks for a local or remote address`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteAddress = "   "

        // when
        sut.save()

        // then
        #expect(sut.errorMessage == "Enter a local or remote address.")
        #expect(repository.savedConnection == nil)
        #expect(sut.didSave == false)
    }

    @Test func `given an out of range remote port when saving then the error names the remote address`() {
        // given
        let sut = makeViewModel()
        sut.remoteAddress = "frigate.ts.net:65536"

        // when
        sut.save()

        // then
        #expect(sut.errorMessage == "The remote port must be a number between 1 and 65535.")
    }

    @Test func `given an out of range local port when saving then the error names the local address`() {
        // given
        let sut = makeViewModel()
        sut.remoteAddress = "frigate.ts.net"
        sut.localAddress = "192.168.1.50:65536"

        // when
        sut.save()

        // then
        #expect(sut.errorMessage == "The local port must be a number between 1 and 65535.")
    }

    @Test(arguments: [
        AddressInput(value: "https://frigate.example.net", expected: ServerAddress(
            scheme: .https, host: "frigate.example.net", port: 443
        )),
        AddressInput(value: "frigate.example.net:8971", expected: ServerAddress(
            scheme: .http, host: "frigate.example.net", port: 8971
        )),
        AddressInput(value: "http://[2001:db8::1]:5001", expected: ServerAddress(
            scheme: .http, host: "[2001:db8::1]", port: 5001
        )),
        AddressInput(value: "https://operator:secret@frigate.example.net", expected: nil)
    ])
    func `given an address entry when saving then only a valid endpoint is persisted`(input: AddressInput) {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.remoteAddress = input.value

        // when
        sut.save()

        // then
        #expect(sut.didSave == (input.expected != nil))
        #expect(repository.savedConnection?.remote == input.expected)
    }

    struct AddressInput: Sendable {
        let value: String
        let expected: ServerAddress?
    }
}

@MainActor
private func makeViewModel(_ repository: FakeSettingsRepository = FakeSettingsRepository()) -> ServerSettingsViewModel {
    ServerSettingsViewModel(
        loadConnection: LoadConnection(repository: repository),
        saveConnection: SaveConnection(repository: repository)
    )
}
