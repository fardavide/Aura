import Foundation

import CommonFrigate
import CommonNetwork
import ExportsDomain

/// Copies an export's bytes to a temporary file through the authenticated download transport,
/// reporting progress as they arrive.
///
/// The file is Aura's only for as long as it takes to hand it to the platform's destination UI —
/// `discard` deletes it, and every caller path (hand-off, dismissal, cancellation, failure) ends
/// there, so no hidden second library accumulates.
public struct FrigateExportDownloader: ExportDownloading {
    private let config: ServerConfig
    private let downloadClient: any HttpDownloadClient

    public init(config: ServerConfig, downloadClient: any HttpDownloadClient) {
        self.config = config
        self.downloadClient = downloadClient
    }

    public func download(
        _ export: Export,
        onProgress: @escaping @Sendable (ExportTransfer) -> Void
    ) async throws(ExportsError) -> DownloadedExport {
        guard let url = FrigateExportMediaUrl.media(base: config.baseUrl, serverPath: export.videoPath) else {
            throw ExportsError.invalidData
        }
        var request = URLRequest(url: url)
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let fileUrl: URL
        let response: HTTPURLResponse
        do {
            (fileUrl, response) = try await downloadClient.download(request) { received, expected in
                onProgress(ExportTransfer(bytesReceived: received, bytesExpected: expected))
            }
        } catch {
            throw ExportsError.unreachable
        }
        guard (200...299).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: fileUrl)
            throw ExportsError(FrigateApiError(statusCode: response.statusCode))
        }
        return DownloadedExport(fileUrl: fileUrl, fileName: Self.fileName(for: export))
    }

    public func discard(_ download: DownloadedExport) {
        try? FileManager.default.removeItem(at: download.fileUrl)
    }

    /// Frigate's own name for the clip, carrying the extension from the server path so the type is
    /// right whatever the server wrote. The name is what the card and the player show, so the
    /// filename the share sheet pre-fills is the one the user was just looking at; the path's own
    /// basename (`{camera}_{start}-{end}_{id}.mp4`) is stable but unreadable.
    static func fileName(for export: Export) -> String {
        let pathExtension = URL(filePath: export.videoPath).pathExtension
        let stem = export.name.isEmpty ? URL(filePath: export.videoPath).deletingPathExtension().lastPathComponent : export.name
        return pathExtension.isEmpty ? stem : "\(stem).\(pathExtension)"
    }
}

private extension FrigateApiError {
    /// The download transport reports its own status, so the shared status ladder is reused here
    /// rather than duplicated.
    init(statusCode: Int) {
        switch statusCode {
        case 400: self = .rejected
        case 401, 403: self = .notAuthorized
        case 500...599: self = .serverUnavailable
        default: self = .unknown
        }
    }
}
