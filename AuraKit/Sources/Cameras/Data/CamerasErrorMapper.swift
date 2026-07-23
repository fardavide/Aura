import CamerasDomain
import CommonFrigate

extension CamerasError {
    /// Translates the shared Frigate transport error into the feature's domain error at the Data
    /// boundary, so the Domain never sees Frigate vocabulary.
    init(_ error: FrigateApiError) {
        switch error {
        case .unreachable: self = .unreachable
        case .notAuthorized: self = .notAuthorized
        case .serverUnavailable: self = .serverUnavailable
        case .unknown: self = .unknown
        }
    }
}
