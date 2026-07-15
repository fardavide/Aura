/// The `service.storage` slice of `GET /api/stats`. Internal — it never leaves the Data layer.
/// Values are mebibytes (Frigate divides the raw bytes by 2^20). A mount that isn't present on the
/// host is simply absent from the map, so every field is optional.
struct StatsDto: Decodable {
    let service: ServiceStatsDto?
}

struct ServiceStatsDto: Decodable {
    let storage: [String: StorageEntryDto]?
}

struct StorageEntryDto: Decodable {
    let total: Double?
    let used: Double?
    let free: Double?
}
