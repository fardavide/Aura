import SwiftUI

import CommonDesign

/// A failure on a card that otherwise still works — the Events alert-tag palette at strip scale.
///
/// Sits inside the card, under the row, so the clip's own controls are untouched: Play still
/// plays, because a failed *copy* never owned the clip.
struct ExportErrorStrip: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .auroraText(.captionEmphasis)
            Text(message)
                .auroraText(.captionEmphasis)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(ExportCopy.tryAgain, action: retry)
                .buttonStyle(ExportChipButtonStyle())
                // The chip keeps its shape whatever the message does — two flexible pieces on one
                // line both break rather than one yielding.
                .fixedSize()
        }
        .foregroundStyle(.auroraAlertTagText)
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(.auroraAlertTagFill, in: shape)
        .overlay { shape.strokeBorder(.auroraAlertTagBorder, lineWidth: 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ExportCardStyle.stripCornerRadius, style: .continuous)
    }
}

/// A glass chip with a tap area bigger than its ink — 30pt tall, 44pt reachable.
struct ExportChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .auroraText(.chip)
            .foregroundStyle(.auroraTextPrimary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.auroraChipFill, in: Capsule())
            .overlay { Capsule().strokeBorder(.auroraChipBorder, lineWidth: 1) }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
