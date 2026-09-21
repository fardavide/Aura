import Foundation

import ExportsDomain
import TimelineDomain

/// Where an export request has got to. Editing is the only phase the selection can still change
/// in; from `creating` onward the range belongs to the server and the panel is reporting rather
/// than asking.
public enum ExportEditorPhase: Equatable, Sendable {
    case editing
    /// The request is in flight — posted, no id yet.
    case creating
    /// Accepted. The server is cutting, and says so through `in_progress` rather than elapsed time.
    case processing(ExportId)
    case ready(Export)
    case failed(ExportsError)
}

/// Everything the export editor renders, as values — so the whole module is a pure function of its
/// inputs and can be snapshot-tested with literal state, no player and no server. The same shape
/// `RecordingDetailState` already has for the screen around it.
///
/// The computed properties below **are** the dead-control audit. Every control on this module asks
/// one of them whether it exists, and each answer is one of the four permitted fates: working,
/// absent, disabled with its reason on screen, or enabled and saying the thing behind it is not
/// built yet. Keeping them here rather than in the view is what lets a test enforce that a control
/// is never merely dimmed and silent.
public struct ExportEditorState: Equatable, Sendable {
    public let selection: ExportSelection
    /// The history the selection may move within: `[start, live edge]`.
    public let span: TimeRange
    /// Where the video is — still meaningful in export mode, and not the same thing as either
    /// boundary.
    public let playhead: Date
    public let zoom: TimelineZoom
    public let gaps: [FootageGap]
    public let phase: ExportEditorPhase

    public init(
        selection: ExportSelection,
        span: TimeRange,
        playhead: Date,
        zoom: TimelineZoom,
        gaps: [FootageGap],
        phase: ExportEditorPhase
    ) {
        self.selection = selection
        self.span = span
        self.playhead = playhead
        self.zoom = zoom
        self.gaps = gaps
        self.phase = phase
    }

    // MARK: Validity

    /// The only condition that invalidates a selection. Spanning a gap does not — the server cuts
    /// the footage that exists and the clip is simply shorter than the range.
    public var hasRecording: Bool {
        selection.hasRecording(gaps: gaps)
    }

    public var isEditing: Bool {
        phase == .editing
    }

    // MARK: The action row

    public var showsCreate: Bool {
        isEditing
    }

    public var canCreate: Bool {
        isEditing && hasRecording
    }

    /// Rendered immediately below the disabled button, never instead of it. A disabled control and
    /// the sentence explaining it are one unit.
    public var createDisabledReason: String? {
        canCreate ? nil : "No recording anywhere in this range — move a handle onto footage"
    }

    /// Past ten minutes the button states the size it is about to ask for, so the commitment is
    /// legible before the press rather than after it.
    public var createTitle: String {
        selection.duration >= Self.longClipThreshold
            ? "Create \(Self.clockText(selection.duration)) clip"
            : "Create Export"
    }

    public var longClipAdvisory: String? {
        selection.duration >= Self.longClipThreshold ? "Long clips take the server a while to cut" : nil
    }

    /// Absent rather than disabled when there is nothing to play: `createDisabledReason` already
    /// states that fact once, and a second greyed control restates it without adding anything.
    public var showsPlaySelection: Bool {
        isEditing && hasRecording
    }

    public var showsCancel: Bool {
        isEditing
    }

    // MARK: Notices

    /// States the arithmetic rather than warning. Valid, and worth knowing.
    public var gapNotice: String? {
        let missing = selection.duration - selection.recordedSeconds(gaps: gaps)
        guard missing > 0, hasRecording else { return nil }
        return "Includes \(Self.clockText(missing)) with no recording"
    }

    // MARK: Handles

    /// A 1:30 clip is 3 pt wide at Day. Rather than draw a knob that cannot be hit, the selection
    /// becomes a mark and the handles go away — keyboard and VoiceOver adjustment keep working.
    public var showsHandles: Bool {
        zoom.showsExportHandles
    }

    public var showsZoomToAdjust: Bool {
        isEditing && !showsHandles
    }

    /// A committed range must not look draggable — a knob you can still grab implies the request
    /// could still change.
    public var handlesAreInteractive: Bool {
        isEditing && showsHandles
    }

    /// Appears only once scrubbing has taken the playhead out of the clip. At entry the seed is
    /// built around the playhead, so there is nothing to reset to and the control is absent.
    public var showsResetToPlayhead: Bool {
        isEditing && !(playhead >= selection.start && playhead < selection.end)
    }

    // MARK: Failure and follow-through

    /// Removed, not disabled, when re-sending could only fail the same way.
    public var showsRetry: Bool {
        guard case .failed(let error) = phase else { return false }
        return error.isRetryable
    }

    /// What to do instead, when there is no retry worth offering.
    public var failureHint: String? {
        guard case .failed(let error) = phase, !error.isRetryable else { return nil }
        return "Move a handle to try a different range"
    }

    /// Live from the moment the request is accepted — the row genuinely exists over there as
    /// `in_progress` by then, so the control has somewhere real to go.
    public var showsViewInExports: Bool {
        switch phase {
        case .processing, .ready: true
        case .editing, .creating, .failed: false
        }
    }

    // MARK: -

    /// Ten minutes: roughly where a real-time Frigate export stops feeling instant.
    static let longClipThreshold: TimeInterval = 600

    /// `1:30` under an hour, `1:24:00` over it — the same shape the readout uses, so the button
    /// and the duration cell never disagree about how long the clip is.
    static func clockText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3_600
        let paddedSeconds = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        guard hours > 0 else { return "\(minutes):\(paddedSeconds)" }
        let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        return "\(hours):\(paddedMinutes):\(paddedSeconds)"
    }
}

extension TimelineZoom {
    /// Whether a boundary can be grabbed at this density. The export editor's shortest useful clip
    /// is a second, and below Hour a second is under a tenth of a point.
    var showsExportHandles: Bool {
        switch self {
        case .minute, .hour: true
        case .day, .week: false
        }
    }
}
