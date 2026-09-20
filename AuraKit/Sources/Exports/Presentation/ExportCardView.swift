import SwiftUI

import CommonDesign
import CommonPlayer
import ExportsDomain

/// One clip in the library — five variants of one shell: ready, ready without a still, processing,
/// downloading, and download-failed.
///
/// The whole card is a single accessibility element with custom actions rather than four stops: a
/// library of twelve clips would otherwise be forty-eight swipes.
struct ExportCardView: View {
    /// How the card arranges itself. A narrow column gets the row; a wide one gets the vertical
    /// card, where the 16:9 frame runs the card's full width — which is what makes a 480pt card
    /// worth having instead of a row with a dead gap down its middle.
    enum Layout {
        case row
        /// The row in a narrow split column, where a full-size frame would leave the meta line too
        /// little width to keep its time — which is the part that tells two clips apart.
        case compactRow
        case stacked
    }

    let export: Export
    let layout: Layout
    let cameraName: String
    let downloadState: ExportDownloadState?
    let loadThumbnail: (Export) async -> Data?
    let onPlay: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var image: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: ExportCardStyle.rowToStrip) {
            if isStacked {
                stackedLayout
            } else {
                rowLayout
            }
            stateStrip
        }
        .padding(ExportCardStyle.padding)
        .auroraCard(cornerRadius: ExportCardStyle.cornerRadius)
        .overlay(alignment: .top) {
            if export.isProcessing {
                ExportProcessingSweep()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ExportCardStyle.cornerRadius, style: .continuous))
        .task(id: export.id) {
            image = await loadThumbnail(export).flatMap(platformImage(from:))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(accessibilityTraits)
        .accessibilityCustomContent("File name", ExportCopy.fileNameContent(export.name))
        .accessibilityActions { accessibilityActions }
    }

    // MARK: Layout

    /// A wide column takes the vertical card; so does an accessibility text size, where the row
    /// cannot hold a 104pt frame, two 44pt circles and a file name at once.
    private var isStacked: Bool {
        layout == .stacked || dynamicTypeSize.isAccessibilitySize
    }

    private var frameSize: CGSize {
        layout == .compactRow ? ExportCardStyle.narrowFrameSize : ExportCardStyle.frameSize
    }

    /// Only the accessibility size trades the circles for labelled buttons. An iPad is still a
    /// touch device, so its stacked card keeps the same 44 × 44 circles the phone has.
    private var usesLabelledActions: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var rowLayout: some View {
        HStack(spacing: ExportCardStyle.frameToIdentity) {
            // The card's own tap area, which deliberately stops short of the circles — otherwise
            // aiming for Download and missing by two points plays the clip instead.
            HStack(spacing: ExportCardStyle.frameToIdentity) {
                ExportVideoFrame(image: image, isProcessing: export.isProcessing)
                    .frame(width: frameSize.width, height: frameSize.height)
                identity
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { if export.isReady { onPlay() } }

            HStack(spacing: ExportCardStyle.betweenActions) {
                playButton
                trailingActionButton
            }
        }
    }

    /// The frame runs the card's full width with the identity under it, and — at an accessibility
    /// text size only — the circles become labelled full-width buttons.
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: ExportCardStyle.frameToIdentity) {
            ExportVideoFrame(image: image, isProcessing: export.isProcessing)
                .contentShape(Rectangle())
                .onTapGesture { if export.isReady { onPlay() } }
            if usesLabelledActions {
                identity
                if export.isProcessing {
                    // At this size the reason sits above the controls rather than beside them.
                    ExportProcessingReason()
                }
                VStack(spacing: ExportCardStyle.betweenActions) {
                    labelledAction(ExportCopy.play, systemImage: "play.fill", action: onPlay)
                        .disabled(!export.isReady)
                    labelledAction(trailingActionTitle, systemImage: trailingActionSymbol, action: trailingAction)
                        .disabled(!isTrailingActionEnabled)
                }
            } else {
                HStack(spacing: ExportCardStyle.frameToIdentity) {
                    identity
                        .contentShape(Rectangle())
                        .onTapGesture { if export.isReady { onPlay() } }
                    Spacer(minLength: 0)
                    HStack(spacing: ExportCardStyle.betweenActions) {
                        playButton
                        trailingActionButton
                    }
                }
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(export.name)
                // The tail can be lost here: everything it encodes is restated in words below, and
                // the player shows the name in full.
                .auroraText(.bodyEmphasis)
                .foregroundStyle(.auroraTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(meta)
                .auroraText(.caption)
                .foregroundStyle(.auroraTextSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                // The name above may truncate — everything it encodes is restated here. This line
                // may not: losing its tail costs the time, which is what tells two clips from the
                // same camera apart. A longer camera name shrinks the line instead of cutting it.
                .minimumScaleFactor(0.8)
        }
    }

    /// "Driveway · 18 Sep, 14:30" — the dot at 40% so it separates without competing.
    ///
    /// Day and time are formatted separately and joined with a comma rather than through one
    /// combined style: the combined one renders "18 Sep at 14:30", and those three extra
    /// characters are enough to push the time out of the card's narrow identity column.
    private var meta: AttributedString {
        var separator = AttributedString(" · ")
        separator.foregroundColor = .auroraTextSecondary.opacity(0.4)
        let day = export.createdAt.formatted(.dateTime.day().month(.abbreviated))
        let time = export.createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
        return AttributedString(cameraName) + separator + AttributedString("\(day), \(time)")
    }

    @ViewBuilder private var stateStrip: some View {
        switch downloadState {
        case .transferring(let transfer):
            ExportTransferBar(transfer: transfer)
        case .failed(let error):
            ExportErrorStrip(message: ExportCopy.downloadFailure(error), retry: onDownload)
        case .cancelled:
            Text(ExportCopy.cancelledNotice)
                .auroraText(.caption)
                .foregroundStyle(.auroraTextSecondary)
        case .readyToSave, .none:
            if export.isProcessing, !dynamicTypeSize.isAccessibilitySize {
                ExportProcessingReason()
            }
        }
    }

    // MARK: Controls

    private var playButton: some View {
        Button(action: onPlay) { Image(systemName: "play.fill") }
            .buttonStyle(ExportActionButtonStyle())
            // Deliberately live while a copy runs: the clip streams from the server, and the
            // transfer does not own it.
            .disabled(!export.isReady)
            .accessibilityHidden(true)
    }

    private var trailingActionButton: some View {
        Button(action: trailingAction) { Image(systemName: trailingActionSymbol) }
            .buttonStyle(ExportActionButtonStyle())
            .disabled(!isTrailingActionEnabled)
            .accessibilityHidden(true)
    }

    private func labelledAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ExportChipButtonStyle())
        .accessibilityHidden(true)
    }

    /// Download becomes Cancel in place while bytes are moving, and Try again after a failure —
    /// never a control that looks identical to the one that just failed.
    private var trailingActionSymbol: String {
        switch downloadState {
        case .transferring: "xmark"
        case .failed: "arrow.clockwise"
        case .readyToSave, .cancelled, .none: "arrow.down.to.line"
        }
    }

    private var trailingActionTitle: String {
        switch downloadState {
        case .transferring: ExportCopy.cancelDownload
        case .failed: ExportCopy.tryAgain
        case .readyToSave, .cancelled, .none: ExportCopy.download
        }
    }

    private func trailingAction() {
        switch downloadState {
        case .transferring: onCancelDownload()
        case .failed, .readyToSave, .cancelled, .none: onDownload()
        }
    }

    private var isTrailingActionEnabled: Bool {
        guard export.isReady else { return false }
        if case .readyToSave = downloadState { return false }
        return true
    }

    // MARK: VoiceOver

    private var accessibilityLabel: String {
        if export.isProcessing {
            return ExportCopy.processingCardLabel(camera: cameraName, createdAt: export.createdAt)
        }
        if downloadState?.isTransferring == true {
            return ExportCopy.downloadingCardLabel(camera: cameraName, createdAt: export.createdAt)
        }
        return ExportCopy.cardLabel(camera: cameraName, createdAt: export.createdAt)
    }

    private var accessibilityValue: String {
        guard case .transferring(let transfer) = downloadState else { return "" }
        return ExportCopy.transferValue(transfer)
    }

    private var accessibilityHint: String {
        export.isProcessing ? ExportCopy.processingHint : ExportCopy.readyHint
    }

    /// A processing card activates nothing, so it is not a button — and `.updatesFrequently` is
    /// only true while bytes are actually moving, never for the decorative server sweep.
    private var accessibilityTraits: AccessibilityTraits {
        if export.isProcessing { return [] }
        return downloadState?.isTransferring == true ? [.isButton, .updatesFrequently] : [.isButton]
    }

    @ViewBuilder private var accessibilityActions: some View {
        if export.isReady {
            Button(ExportCopy.play, action: onPlay)
            if downloadState?.isTransferring == true {
                Button(ExportCopy.cancelDownload, action: onCancelDownload)
            } else if isTrailingActionEnabled {
                Button(trailingActionTitle, action: trailingAction)
            }
        }
    }
}
