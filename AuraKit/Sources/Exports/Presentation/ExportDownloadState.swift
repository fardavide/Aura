import Foundation

import ExportsDomain

/// Where one export's copy has got to.
///
/// `cancelled` is a state rather than a return to nothing so the card can say "Download cancelled"
/// for a moment instead of silently snapping back — a control that visibly did something must
/// visibly say what.
public enum ExportDownloadState: Equatable, Sendable {
    case transferring(ExportTransfer)
    /// The bytes are on disk, waiting to be handed to the platform's destination UI.
    case readyToSave(DownloadedExport)
    case failed(ExportsError)
    case cancelled

    /// 0…1 while bytes are moving, else nil — what the card's bar and the header ring both read.
    public var fraction: Double? {
        guard case .transferring(let transfer) = self else { return nil }
        return transfer.fraction
    }

    public var isTransferring: Bool {
        if case .transferring = self { return true }
        return false
    }
}
