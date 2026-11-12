import SwiftUI
#if os(iOS)
import UIKit
#endif

struct TimelineScrollDeceleration: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.background { ScrollViewProbe().allowsHitTesting(false) }
        #else
        content
        #endif
    }
}

#if os(iOS)
private struct ScrollViewProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.configureScrollView()
    }

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureScrollView()
        }

        func configureScrollView() {
            // Mounted inside the histogram's scrolling content so the nearest scroll view
            // is the one we want to tune, even if the card is itself inside a scroll view.
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollView.decelerationRate = .fast
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
#endif
