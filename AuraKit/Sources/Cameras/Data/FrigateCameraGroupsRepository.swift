import Foundation

import CamerasDomain
import CommonFrigate

/// Reads the user's camera groups out of the shared `GET /api/config` body. The name carries the
/// Frigate detail — `CameraGroupsRepository` is the abstraction the rest of the app depends on.
public struct FrigateCameraGroupsRepository: CameraGroupsRepository {
    private let configProvider: FrigateConfigProvider

    public init(configProvider: FrigateConfigProvider) {
        self.configProvider = configProvider
    }

    public func observeGroups() -> AsyncStream<[CameraGroup]> {
        AsyncStream { continuation in
            let task = Task {
                var hasEmitted = false
                for await outcome in await configProvider.observeConfig() {
                    let groups: [CameraGroup]? = switch outcome {
                    case .success(let data):
                        (try? JSONDecoder().decode(GroupsConfigDto.self, from: data))?.toCameraGroups()
                    case .failure:
                        nil
                    }
                    if let groups {
                        continuation.yield(groups)
                        hasEmitted = true
                    } else if !hasEmitted {
                        // Nothing has been shown yet, so resolve the first read to "no chips"
                        // instead of leaving a caller waiting on a value that may never come.
                        continuation.yield([])
                        hasEmitted = true
                    }
                    // A later failure emits nothing at all: the chips already on screen stand.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
