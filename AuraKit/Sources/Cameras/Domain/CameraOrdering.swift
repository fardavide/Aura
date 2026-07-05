import CamerasEntities

extension [Camera] {
    /// The saved order first; cameras it doesn't name keep their relative order after it;
    /// names it contains that no longer exist are ignored.
    public func sorted(byPreference order: [CameraName]) -> [Camera] {
        let preferred = order.compactMap { name in first { $0.name == name } }
        let remaining = filter { !order.contains($0.name) }
        return preferred + remaining
    }
}
