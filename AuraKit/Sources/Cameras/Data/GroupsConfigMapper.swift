import CamerasDomain
import CamerasEntities

extension GroupsConfigDto {
    /// Maps the raw `camera_groups` into domain groups. `birdseye` is Frigate's composite view, not
    /// a real camera, so it's stripped from membership. `order` defaults to 0 (Frigate's default);
    /// sorting and dropping empty groups is the use case's concern.
    func toCameraGroups() -> [CameraGroup] {
        (cameraGroups ?? [:]).map { name, dto in
            CameraGroup(
                name: name,
                cameraNames: (dto.cameras?.values ?? [])
                    .filter { $0 != "birdseye" }
                    .map(CameraName.init),
                order: dto.order ?? 0
            )
        }
    }
}
