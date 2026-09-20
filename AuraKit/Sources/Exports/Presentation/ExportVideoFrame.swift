import SwiftUI

import CommonDesign

/// The card's 16:9 still, and the two things that stand in for one. The image arrives already
/// decoded — decoding in `body` churns the attribute graph, so the card owns that in a `.task`.
///
/// Hidden from VoiceOver in every variant: it carries nothing the card's label does not already
/// say, and a placeholder announced as an image is worse than silence.
struct ExportVideoFrame: View {
    let image: Image?
    let isProcessing: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.auroraNoFootage)
            .aspectRatio(16 / 9, contentMode: .fit)
            .auroraFrame(cornerRadius: ExportCardStyle.frameCornerRadius)
            // The rim recedes while there is nothing behind it to frame.
            .opacity(isProcessing ? 0.5 : 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if isProcessing {
            // The same hatch the timeline draws for "no footage here" — in both places it means
            // there is nothing to show yet, rather than that something went wrong.
            ExportHatch()
        } else if let image {
            image.resizable().aspectRatio(contentMode: .fill)
        } else {
            // A server that kept no still is ordinary, so this carries no warning colour and no
            // exclamation mark — it must not read as an error.
            Image(systemName: "film")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.auroraTextMuted)
        }
    }
}

/// 45° hatch at a 6pt pitch, `HatchLine` over `HatchFill`.
private struct ExportHatch: View {
    private let pitch: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: AuroraTrack.hatchFill)
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += pitch
            }
            context.stroke(path, with: AuroraTrack.hatchLine, lineWidth: 1)
        }
    }
}
