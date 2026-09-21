import SwiftUI

import CommonDesign

/// What the transport row becomes in export mode: cancel, play the selection, create the export.
///
/// Every control here asks `ExportEditorState` whether it exists at all. Nothing decides its own
/// fate locally, which is how the dead-control audit stays enforceable by a test rather than by
/// reading the view.
struct ExportActionRow: View {
    let state: ExportEditorState
    let isPlayingSelection: Bool
    let isStacked: Bool
    let onCancel: () -> Void
    let onPlaySelection: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if isStacked {
                HStack(spacing: 8) {
                    if state.showsCancel { cancelButton }
                    if state.showsPlaySelection { playButton }
                    if state.showsCreate { createButton }
                }
            } else {
                VStack(spacing: 8) {
                    if state.showsPlaySelection { playButton.frame(maxWidth: .infinity) }
                    if state.showsCreate { createButton }
                    if state.showsCancel { cancelButton.frame(maxWidth: .infinity) }
                }
            }
            // The reason and the control it explains are one unit — never shipped apart.
            if let reason = state.createDisabledReason {
                caption(reason)
            }
            if let advisory = state.longClipAdvisory {
                caption(advisory)
            }
            if let notice = state.gapNotice {
                caption(notice)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .auroraText(.caption)
            .foregroundStyle(.auroraTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var createButton: some View {
        Button(action: onCreate) {
            Text(state.createTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ExportPrimaryButtonStyle())
        .disabled(!state.canCreate)
        .accessibilityLabel("Create export")
        .accessibilityValue(state.createDisabledReason ?? ExportEditorState.clockText(state.selection.duration))
    }

    private var playButton: some View {
        Button(action: onPlaySelection) {
            Label(
                isPlayingSelection ? "Stop" : "Play selection",
                systemImage: isPlayingSelection ? "stop.fill" : "play.fill"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(ExportSecondaryButtonStyle(isFilled: isPlayingSelection))
        .accessibilityLabel("Play selection")
        .accessibilityValue(isPlayingSelection ? "Playing" : "Paused")
        .accessibilityHint("Plays only between the clip start and end, then returns to the start.")
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Label("Cancel", systemImage: "xmark").labelStyle(.iconOnly)
        }
        .buttonStyle(ExportSecondaryButtonStyle(isFilled: false))
        .accessibilityLabel("Cancel export")
    }
}

/// The screen's one committing action, so it takes the full brand gradient and the glow that goes
/// with it. Disabled is 45 % ink rather than a grey fill — the reason beneath keeps full contrast,
/// which a blanket opacity would have taken with it.
struct ExportPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    /// Nested so `@Environment(\.isEnabled)` actually updates — a `ButtonStyle` is not a `View`,
    /// the same trap `TransportCircleButtonStyle` documents.
    struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .auroraText(.button)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: height)
                .background(AuroraGradient.diagonal, in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.28), lineWidth: 1) }
                .shadow(color: isEnabled ? .auroraGradientPink.opacity(0.5) : .clear, radius: 16, y: 8)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
        }

        #if os(macOS)
        private var height: CGFloat { 40 }
        private var shape: AnyInsettableShape { AnyInsettableShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
        #else
        private var height: CGFloat { 44 }
        private var shape: AnyInsettableShape { AnyInsettableShape(Capsule()) }
        #endif
    }
}

/// Glass, 36 tall, equal width in a row. `isFilled` is the one exception — Stop is solid ink,
/// because it is the only control here that ends something rather than starting it.
struct ExportSecondaryButtonStyle: ButtonStyle {
    let isFilled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .auroraText(.chip)
            .foregroundStyle(isFilled ? Color.auroraBase : .auroraTextPrimary)
            .frame(minWidth: 44)
            .frame(height: isFilled ? 44 : 36)
            .background(isFilled ? AnyShapeStyle(Color.auroraTextPrimary) : AnyShapeStyle(Color.auroraChipFill), in: Capsule())
            .overlay { if !isFilled { Capsule().strokeBorder(.auroraChipBorder, lineWidth: 1) } }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// A type-erased shape that can still be stroked as a border — `AnyShape` loses `InsettableShape`,
/// which `strokeBorder` needs.
struct AnyInsettableShape: InsettableShape {
    private let makePath: @Sendable (CGRect) -> Path
    private let makeInset: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        makePath = { shape.path(in: $0) }
        makeInset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { makePath(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { makeInset(amount) }
}
