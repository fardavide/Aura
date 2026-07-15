import Foundation

import CamerasDomain
import CamerasEntities

extension [ReviewItemDto] {
    /// Maps the *in-progress* review items (`end_time` still null — a completed item is past, not
    /// "now") whose severity we badge into domain activities. The label is the tracked object,
    /// capitalized; it falls back to the severity word when Frigate hasn't attached one yet.
    func toActiveActivity() -> [CameraActivity] {
        compactMap { dto in
            guard dto.endTime == nil, let severity = dto.severity.activitySeverity else {
                return nil
            }
            return CameraActivity(
                camera: CameraName(dto.camera),
                label: dto.data?.objects?.first?.capitalized ?? severity.fallbackLabel,
                severity: severity,
                startedAt: Date(timeIntervalSince1970: dto.startTime)
            )
        }
    }
}

private extension String {
    /// Maps Frigate's review severity, dropping `significant_motion` (we don't badge it).
    var activitySeverity: CameraActivity.Severity? {
        switch self {
        case "alert": .alert
        case "detection": .detection
        default: nil
        }
    }
}

private extension CameraActivity.Severity {
    var fallbackLabel: String {
        switch self {
        case .alert: "Alert"
        case .detection: "Motion"
        }
    }
}
