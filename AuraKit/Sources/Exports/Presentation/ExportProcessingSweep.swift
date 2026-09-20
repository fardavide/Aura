import SwiftUI

import CommonDesign

/// The server's indeterminate progress: a 3pt segment travelling the card's top edge.
///
/// There is no percentage to draw — `/api/exports` reports only a boolean — so this must never
/// look like the determinate transfer bar. It sits on the edge rather than in the body for exactly
/// that reason, and it carries no information VoiceOver needs: the reason text beside the disabled
/// controls says the same thing in words.
struct ExportProcessingSweep: View {
    @Environment(\.designMotion) private var designMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .auroraGradientViolet, .auroraGradientBlue, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 0.4)
                .offset(x: isAnimated ? width * 1.2 : -width * 0.6)
                .animation(
                    isAnimated
                        ? .linear(duration: ExportCardStyle.sweepDuration).repeatForever(autoreverses: false)
                        : nil,
                    value: isAnimated
                )
        }
        .frame(height: ExportCardStyle.sweepHeight)
        .accessibilityHidden(true)
    }

    /// Held on its first frame for the snapshot suite, and stopped outright under Reduce Motion —
    /// where the pulsing dot and the reason text carry the state instead.
    private var isAnimated: Bool {
        designMotion == .animated && !reduceMotion
    }
}

/// "Still processing on the server", with the violet dot that pulses beside it.
struct ExportProcessingReason: View {
    @Environment(\.designMotion) private var designMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDim = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(.auroraGradientViolet)
                .frame(width: 7, height: 7)
                .opacity(isDim ? 0.35 : 1)
            Text(ExportCopy.processingReason)
                .auroraText(.caption)
                .foregroundStyle(.auroraTextSecondary)
        }
        .onAppear {
            guard designMotion == .animated, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: ExportCardStyle.sweepDuration).repeatForever()) {
                isDim = true
            }
        }
        // Said in the card's own label already; repeating it as a separate element would make
        // VoiceOver read the reason twice.
        .accessibilityHidden(true)
    }
}
