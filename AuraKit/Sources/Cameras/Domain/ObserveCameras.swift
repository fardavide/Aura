import CamerasEntities
import SettingsDomain

/// Streams the enabled cameras sorted by the user's preferred order, re-emitting the
/// re-sorted list whenever the preference changes.
public struct ObserveCameras: Sendable {
    private let getCameras: GetCameras
    private let observeCameraOrder: ObserveCameraOrder

    public init(getCameras: GetCameras, observeCameraOrder: ObserveCameraOrder) {
        self.getCameras = getCameras
        self.observeCameraOrder = observeCameraOrder
    }

    public func execute() async throws(CamerasError) -> AsyncStream<[Camera]> {
        let cameras = try await getCameras.execute()
        let orders = observeCameraOrder.execute()
        return AsyncStream { continuation in
            let task = Task {
                for await order in orders {
                    continuation.yield(cameras.sorted(byPreference: order))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
