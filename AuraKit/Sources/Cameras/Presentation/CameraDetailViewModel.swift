import Observation

import CamerasDomain
import CamerasEntities

@Observable
@MainActor
public final class CameraDetailViewModel {
    public enum State: Equatable {
        case playing(CameraStreamSource)
        case unavailable
    }

    public let title: String
    public let state: State

    public init(camera: Camera, streamProvider: any CameraStreamProviding) {
        title = camera.friendlyName ?? camera.name.value
        if let source = streamProvider.streamSource(for: camera) {
            state = .playing(source)
        } else {
            state = .unavailable
        }
    }
}
