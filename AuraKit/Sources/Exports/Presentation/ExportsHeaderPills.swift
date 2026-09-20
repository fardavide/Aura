import SwiftUI

import CommonDesign

/// "Updating" — status, not a control. Not focusable, no tap target, and the list underneath stays
/// fully interactive while it is up.
struct ExportsUpdatingPill: View {
    @Environment(\.designMotion) private var designMotion

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.mini)
                .tint(.auroraGradientViolet)
                // A spinner is an idle animation; the snapshot suite needs it held still.
                .opacity(designMotion == .animated ? 1 : 0.6)
            Text(ExportCopy.updating)
                .auroraText(.chip)
                .foregroundStyle(.auroraTextSecondary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.auroraChipFill, in: Capsule())
        .overlay { Capsule().strokeBorder(.auroraChipBorder, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

/// "3 downloading" with a determinate ring — the answer to "where did my download go" once the
/// card has been scrolled away. Tapping brings the transferring card back into view.
struct ExportsDownloadPill: View {
    let count: Int
    let fraction: Double?
    let scrollToTransfer: () -> Void

    var body: some View {
        Button(action: scrollToTransfer) {
            HStack(spacing: 8) {
                ring
                Text(ExportCopy.transferring(count: count))
                    .auroraText(.chip)
                    .foregroundStyle(.auroraTextPrimary)
                    // The pill keeps its shape: left to flex against the screen title it wraps to
                    // "1 downloa…", which is the one word that makes it mean anything.
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.auroraChipFill, in: Capsule())
            .overlay { Capsule().strokeBorder(.auroraChipBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ExportCopy.transferring(count: count))
        .accessibilityHint("Double tap to show the clip being downloaded.")
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.auroraWell, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(.auroraGradientViolet, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // Zero is at three o'clock; the ring has to start at the top.
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
        .animation(.linear(duration: 0.25), value: fraction)
    }
}

/// "Couldn't refresh. Showing the list from 20:14." — a failed refresh costs the banner, never the
/// rows underneath it.
struct ExportsStaleBanner: View {
    let lastUpdated: Date?
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text(ExportCopy.staleBanner(lastUpdated: lastUpdated))
                .auroraText(.captionEmphasis)
                .foregroundStyle(.auroraAlertTagText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(ExportCopy.tryAgain, action: retry)
                .buttonStyle(ExportChipButtonStyle())
                .fixedSize()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.auroraAlertTagFill, in: shape)
        .overlay { shape.strokeBorder(.auroraAlertTagBorder, lineWidth: 1) }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}
