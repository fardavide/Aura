import Foundation

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
