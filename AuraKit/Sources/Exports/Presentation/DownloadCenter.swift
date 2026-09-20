import Foundation
import Observation

import ExportsDomain

/// Every copy in flight, owned at app scope rather than by the list.
///
/// This is why progress does not live on the card: the card and the player are two views onto the
/// same transfer, and scrolling a card away, leaving the tab or opening the player cannot interrupt
/// it or lose track of it. It is also the answer to "where did my download go" — the list header
/// reads `transferringCount` and `overallFraction` straight off this.
@Observable
@MainActor
public final class DownloadCenter {
    private let downloadExport: DownloadExport
    /// How long "Download cancelled" stays on the card. The design's three seconds — long enough to
    /// read, short enough that it never becomes chrome.
    private let cancelledNoticeDuration: Duration

    private var states: [ExportId: ExportDownloadState] = [:]
    private var tasks: [ExportId: Task<Void, Never>] = [:]

    public init(downloadExport: DownloadExport, cancelledNoticeDuration: Duration) {
        self.downloadExport = downloadExport
        self.cancelledNoticeDuration = cancelledNoticeDuration
    }

    public func state(for export: ExportId) -> ExportDownloadState? {
        states[export]
    }

    public var transferringCount: Int {
        states.values.count(where: \.isTransferring)
    }

    /// The header ring: the mean of everything in flight, so several transfers read as one figure.
    /// Nil while nothing is moving, or while no transfer has declared a length yet.
    public var overallFraction: Double? {
        let fractions = states.values.compactMap(\.fraction)
        guard !fractions.isEmpty else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    /// Starts a copy, replacing any state the export already had. A second press while one is
    /// running is ignored rather than starting a rival transfer.
    public func download(_ export: Export) {
        guard tasks[export.id] == nil else { return }
        states[export.id] = .transferring(ExportTransfer(bytesReceived: 0, bytesExpected: nil))
        tasks[export.id] = Task { [weak self] in
            await self?.run(export)
        }
    }

    /// Stops the transfer and discards the partial file. Instant and silent, bar the notice.
    public func cancel(_ export: ExportId) {
        guard let task = tasks[export] else { return }
        task.cancel()
        tasks[export] = nil
        states[export] = .cancelled
        clearNotice(for: export)
    }

    /// Called once the platform's destination UI is done with the file — whether it saved it,
    /// or the user dismissed the sheet without choosing anywhere. Dismissal is not a failure, so
    /// both paths land here and leave no message behind.
    public func finishSaving(_ export: ExportId) {
        if case .readyToSave(let download) = states[export] {
            downloadExport.discard(download)
        }
        states[export] = nil
    }

    /// Clears a failure so the card can go back to offering Download. The failure is otherwise
    /// sticky — it is the one transient state that survives a scroll.
    public func dismissFailure(_ export: ExportId) {
        guard case .failed = states[export] else { return }
        states[export] = nil
    }

    private func run(_ export: Export) async {
        let id = export.id
        do {
            let downloaded = try await downloadExport.execute(export) { [weak self] transfer in
                Task { @MainActor [weak self] in
                    // A progress callback that outlives its transfer (cancelled, or already
                    // finished) must not resurrect the card's bar.
                    guard let self, self.states[id]?.isTransferring == true else { return }
                    self.states[id] = .transferring(transfer)
                }
            }
            tasks[id] = nil
            guard !Task.isCancelled else {
                downloadExport.discard(downloaded)
                return
            }
            states[id] = .readyToSave(downloaded)
        } catch {
            tasks[id] = nil
            // Cancellation already wrote `.cancelled`; the thrown error that follows it is the
            // same event, not a second one to report as a failure.
            guard !Task.isCancelled, states[id]?.isTransferring == true else { return }
            states[id] = .failed(error)
        }
    }

    private func clearNotice(for export: ExportId) {
        Task { [weak self, cancelledNoticeDuration] in
            try? await Task.sleep(for: cancelledNoticeDuration)
            guard let self, self.states[export] == .cancelled else { return }
            self.states[export] = nil
        }
    }
}
