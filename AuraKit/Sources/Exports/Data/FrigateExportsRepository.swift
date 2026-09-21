import Foundation

import CamerasEntities
import CommonFrigate
import CommonNetwork
import ExportsDomain

/// Reads the server's export library from Frigate's `/api/exports`, decoding + mapping to the
/// domain. `in_progress` is carried through untouched: readiness is the server's answer, never
/// inferred from how long a clip has been sitting there.
public struct FrigateExportsRepository: ExportsRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func exports() async throws(ExportsError) -> [Export] {
        let data = try await get(.exports)
        do {
            return try JSONDecoder().decode([ExportDto].self, from: data).toExports(base: config.baseUrl)
        } catch {
            throw ExportsError.invalidData
        }
    }

    public func export(id: ExportId) async throws(ExportsError) -> Export {
        let data = try await get(.export(id: id.value))
        let dto: ExportDto
        do {
            dto = try JSONDecoder().decode(ExportDto.self, from: data)
        } catch {
            throw ExportsError.invalidData
        }
        // A row the media resolver refuses is not decodable into anything this app can act on, so
        // it reads as bad data rather than as a missing export.
        guard let export = dto.toExport(base: config.baseUrl) else { throw ExportsError.invalidData }
        return export
    }

    /// `POST /api/export/{camera}/start/{start}/end/{end}` — real-time playback of the recordings,
    /// with no `name` so Frigate supplies its own timestamp-derived one.
    ///
    /// The bounds go into the *path* as integers, which is what the handler uses regardless; the
    /// body carries only the two knobs this app exercises. `chapters` and `image_path` are omitted
    /// rather than sent null — the server treats absent and null differently for optional bodies.
    public func createExport(camera: CameraName, from: Date, to: Date) async throws(ExportsError) -> ExportId {
        let endpoint = FrigateEndpoint.startExport(
            camera: camera.value,
            start: Int(from.timeIntervalSince1970.rounded(.down)),
            end: Int(to.timeIntervalSince1970.rounded(.down))
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(ExportRequestDto(playback: "realtime", source: "recordings"))
        } catch {
            throw ExportsError.invalidData
        }
        let data: Data
        do {
            data = try await api.post(endpoint.url(base: config.baseUrl), body: body)
        } catch {
            throw ExportsError(error)
        }
        do {
            return ExportId(try JSONDecoder().decode(ExportCreationDto.self, from: data).exportId)
        } catch {
            throw ExportsError.invalidData
        }
    }

    private func get(_ endpoint: FrigateEndpoint) async throws(ExportsError) -> Data {
        do {
            return try await api.get(endpoint.url(base: config.baseUrl))
        } catch {
            throw ExportsError(error)
        }
    }
}

extension ExportsError {
    /// Translates the shared Frigate transport error into the feature's domain error at the Data
    /// boundary, so the Domain never sees Frigate vocabulary.
    init(_ error: FrigateApiError) {
        switch error {
        case .unreachable: self = .unreachable
        case .notAuthorized: self = .notAuthorized
        case .rejected: self = .rejected
        case .serverUnavailable: self = .serverUnavailable
        case .unknown: self = .unknown
        }
    }
}
