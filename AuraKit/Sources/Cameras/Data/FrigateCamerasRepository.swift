import Foundation

import CamerasDomain
import CommonFrigate

/// Reads cameras from a Frigate server. The name carries the implementation detail —
/// `CamerasRepository` is the abstraction the rest of the app depends on.
///
/// Deliberately re-reads the config rather than accepting the shared cached copy: this is the read
/// behind a pull-to-refresh, so it must reflect the server as of now. It still coalesces with the
/// summary's reads, so a screen load costs one `/api/config` request in total.
public struct FrigateCamerasRepository: CamerasRepository {
    private let configProvider: FrigateConfigProvider

    public init(configProvider: FrigateConfigProvider) {
        self.configProvider = configProvider
    }

    public func cameras() async throws(CamerasError) -> [Camera] {
        let data: Data
        do throws(FrigateApiError) {
            data = try await configProvider.reloadConfig()
        } catch {
            throw CamerasError(error)
        }
        do {
            return try JSONDecoder().decode(ConfigDto.self, from: data).toCameras()
        } catch {
            throw CamerasError.invalidData
        }
    }
}
