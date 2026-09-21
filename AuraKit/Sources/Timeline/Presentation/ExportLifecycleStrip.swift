import SwiftUI

import CommonDesign
import ExportsDomain

/// What replaces the action row once the request is the server's: cutting, ready, or failed.
///
/// The sweep and the failure palette are the Exports tab's own, unchanged — the same 3 pt bar at
/// the same 1.6 s period for server work, and the Events alert-tag colours for a failure on
/// something that otherwise still works. Server work should not read as two different things
/// depending on which screen you are looking at.
struct ExportLifecycleStrip: View {
    let phase: ExportEditorPhase
    let showsRetry: Bool
    let failureHint: String?
    let onRetry: () -> Void
    let onViewInExports: () -> Void
    let onPlay: () -> Void
    let onDone: () -> Void

    @Environment(\.designMotion) private var motion

    var body: some View {
        switch phase {
        case .editing:
            EmptyView()
        case .creating:
            working("Asking the server for the clip…", showsViewInExports: false)
        case .processing:
            working("Cutting the clip on the server…", showsViewInExports: true)
        case .ready:
            ready
        case .failed(let error):
            failure(error)
        }
    }

    // MARK: Server work

    private func working(_ text: String, showsViewInExports: Bool) -> some View {
        strip {
            HStack(spacing: 9) {
                Text(text)
                    .auroraText(.captionEmphasis)
                    .foregroundStyle(.auroraTextSecondary)
                Spacer(minLength: 8)
                if showsViewInExports { chip("View in Exports", action: onViewInExports) }
            }
        }
        .overlay(alignment: .top) { sweep }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    /// Indeterminate on purpose: Frigate reports no percentage for a cut in progress, and a bar
    /// that filled at a guessed rate would be inventing progress it cannot know.
    private var sweep: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, .auroraGradientViolet, .auroraGradientBlue, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: proxy.size.width * 0.4)
                .offset(x: motion == .animated ? proxy.size.width : -proxy.size.width * 0.4)
                .animation(
                    motion == .animated ? .linear(duration: 1.6).repeatForever(autoreverses: false) : nil,
                    value: motion
                )
        }
        .frame(height: 3)
    }

    // MARK: Outcomes

    private var ready: some View {
        strip {
            VStack(alignment: .leading, spacing: 8) {
                Label("Clip ready", systemImage: "checkmark.circle.fill")
                    .auroraText(.captionEmphasis)
                    .foregroundStyle(.auroraTextPrimary)
                HStack(spacing: 6) {
                    chip("Play", action: onPlay)
                    chip("View in Exports", action: onViewInExports)
                    Spacer(minLength: 0)
                    chip("Done", action: onDone, isProminent: true)
                }
            }
        }
    }

    private func failure(_ error: ExportsError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .auroraText(.captionEmphasis)
                Text(Self.message(for: error))
                    .auroraText(.captionEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // Absent, not disabled, when re-sending could only fail the same way.
                if showsRetry {
                    Button("Try again", action: onRetry)
                        .buttonStyle(ExportSecondaryButtonStyle(isFilled: false))
                        .fixedSize()
                }
            }
            if let failureHint {
                Text(failureHint)
                    .auroraText(.caption)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.auroraAlertTagText)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(.auroraAlertTagFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.auroraAlertTagBorder, lineWidth: 1)
        }
    }

    // MARK: -

    private func strip(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .auroraTrackWell(cornerRadius: 14)
    }

    private func chip(_ title: String, action: @escaping () -> Void, isProminent: Bool = false) -> some View {
        Button(title, action: action)
            .buttonStyle(ExportSecondaryButtonStyle(isFilled: false))
            .overlay {
                if isProminent {
                    Capsule().strokeBorder(AuroraGradient.diagonal, lineWidth: 1.5).allowsHitTesting(false)
                }
            }
            .fixedSize()
    }

    /// Reuses the Exports tab's own wording where the failure is the same failure.
    static func message(for error: ExportsError) -> String {
        switch error {
        case .unreachable: "Couldn't reach the server"
        case .notAuthorized: "The server refused these credentials"
        case .rejected: "No recordings in this range"
        case .serverUnavailable: "The server is unavailable"
        case .invalidData: "The server sent something unreadable"
        case .unknown: "Couldn't create the clip"
        }
    }
}
