import CamerasDomain
import CamerasEntities

extension ConfigDto {
    /// Maps the raw config into domain cameras: `enabled` defaults to true (Frigate's
    /// default), stream sources are taken from `live.streams` values, sorted for stable
    /// output. All cameras are returned — filtering to enabled ones is a use-case concern.
    func toCameras() -> [Camera] {
        cameras
            .map { name, dto in
                Camera(
                    name: CameraName(name),
                    friendlyName: dto.friendlyName,
                    isEnabled: dto.enabled ?? true,
                    streamNames: (dto.live?.streams?.values).map { $0.sorted() } ?? []
                )
            }
            .sorted { $0.name < $1.name }
    }
}
