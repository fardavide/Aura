import SwiftUI

import CommonDesign
import ExportsDomain

/// The determinate copy progress. Bytes are genuinely known, so the bar is honest — and it is
/// deliberately nothing like the server's indeterminate sweep, because the two mean different
/// things and can be true at once on different cards.
struct ExportTransferBar: View {
    let transfer: ExportTransfer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: ExportCardStyle.progressCornerRadius, style: .continuous)
                    .fill(AuroraGradient.vertical)
                    .frame(width: proxy.size.width * (transfer.fraction ?? 0))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: ExportCardStyle.progressBarHeight)
            .auroraTrackWell(cornerRadius: ExportCardStyle.progressCornerRadius)
            .animation(.linear(duration: 0.25), value: transfer.fraction)

            HStack(spacing: 0) {
                Text(caption)
                    .auroraText(.captionEmphasis)
                    .foregroundStyle(.auroraTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let percentage {
                    Text(percentage)
                        .auroraText(.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(.auroraTextPrimary)
                        .fixedSize()
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// "Downloading · 3.4 MB of 5.5 MB", or just "Downloading" until the server declares a length.
    private var caption: String {
        guard let expected = transfer.bytesExpected else { return "Downloading" }
        let received = transfer.bytesReceived.formatted(.byteCount(style: .file))
        return "Downloading · \(received) of \(expected.formatted(.byteCount(style: .file)))"
    }

    private var percentage: String? {
        transfer.fraction.map { "\(Int(($0 * 100).rounded()))%" }
    }
}
