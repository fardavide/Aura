import Foundation

import ExportsDomain

/// Every user-visible string on the Exports tab, including the VoiceOver wording, in one place —
/// so what the screen says and what it announces cannot drift apart.
enum ExportCopy {
    static let title = "Exports"
    static let processingReason = "Still processing on the server"
    static let processingHint = "Play and Download become available when the server finishes."
    static let readyHint = "Double tap to play. Actions available."
    static let play = "Play"
    static let download = "Download"
    static let cancelDownload = "Cancel download"
    static let tryAgain = "Try again"
    static let cancelledNotice = "Download cancelled"
    static let updating = "Updating"
    static let serverSettings = "Server settings"
    static let openTimeline = "Open Timeline"

    static let emptyTitle = "No exports yet"
    /// Reworded from the approved design, which pointed at a Clip… control on the Timeline tab.
    /// That control ships with the range-selector release; until it does, saying so would send the
    /// user hunting for something that is not there.
    static let emptyBody = """
    Clips are cut on the Frigate server for now, and land in this list. \
    Cutting them from a camera's own timeline in Aura arrives in a later release.
    """

    static let unreachableTitle = "Can't reach the server"

    static func unreachableBody(server: String) -> String {
        "Aura couldn't reach \(server). Check the address and your connection, then try again."
    }

    static func retryingReason(server: String) -> String {
        "Contacting \(server)…"
    }

    /// "Couldn't refresh. Showing the list from 20:14." The timestamp is when the data on screen
    /// was fetched, so the banner says how old what you are looking at is.
    static func staleBanner(lastUpdated: Date?) -> String {
        guard let lastUpdated else { return "Couldn't refresh." }
        let time = lastUpdated.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
        return "Couldn't refresh. Showing the list from \(time)."
    }

    static func downloadFailure(_ error: ExportsError) -> String {
        switch error {
        case .unreachable: "Download failed — lost connection to the server"
        case .notAuthorized: "Download failed — the server refused these credentials"
        case .rejected: "Download failed — the server refused this clip"
        case .serverUnavailable: "Download failed — the server is unavailable"
        case .invalidData: "Download failed — the server sent something unreadable"
        case .unknown: "Download failed"
        }
    }

    /// How many transfers the header pill reports — "1 downloading", "3 downloading".
    static func transferring(count: Int) -> String {
        "\(count) downloading"
    }

    static func summary(_ summary: ExportsSummary) -> String {
        let clips = "\(summary.clipCount) clip\(summary.clipCount == 1 ? "" : "s")"
        let cameras = "\(summary.cameraCount) camera\(summary.cameraCount == 1 ? "" : "s")"
        return "\(clips) · \(cameras)"
    }

    // MARK: VoiceOver

    /// "Driveway. 18 September at 14:30." Camera first, because a list sorted by time is scanned
    /// by place. No duration — the server does not report one.
    static func cardLabel(camera: String, createdAt: Date) -> String {
        "\(camera). \(createdAt.formatted(.dateTime.day().month(.wide).hour(.twoDigits(amPM: .omitted)).minute()))."
    }

    static func processingCardLabel(camera: String, createdAt: Date) -> String {
        "\(cardLabel(camera: camera, createdAt: createdAt)) \(processingReason)."
    }

    static func downloadingCardLabel(camera: String, createdAt: Date) -> String {
        "\(cardLabel(camera: camera, createdAt: createdAt)) Downloading."
    }

    /// "62 percent. 3.4 megabytes of 5.5 megabytes." Re-read on change; the card throttles it.
    static func transferValue(_ transfer: ExportTransfer) -> String {
        guard let fraction = transfer.fraction, let expected = transfer.bytesExpected else {
            return "Downloading."
        }
        let received = transfer.bytesReceived.formatted(.byteCount(style: .file, spellsOutZero: false))
        let total = expected.formatted(.byteCount(style: .file, spellsOutZero: false))
        return "\(Int((fraction * 100).rounded())) percent. \(received) of \(total)."
    }

    /// Spoken as the file name is spelled out on the More Content rotor, not on every swipe.
    static func fileNameContent(_ name: String) -> String {
        "File name: \(name.replacingOccurrences(of: "_", with: " underscore "))"
    }

    static func readyAnnouncement(camera: String) -> String {
        "\(camera) clip is ready."
    }

    static func downloadedAnnouncement(camera: String) -> String {
        "\(camera) clip downloaded. Choose where to save it."
    }

    static func downloadFailedAnnouncement(camera: String, error: ExportsError) -> String {
        "\(camera) download failed. \(downloadFailure(error)). Try again action available."
    }
}
