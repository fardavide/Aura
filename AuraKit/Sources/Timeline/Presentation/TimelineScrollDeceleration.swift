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

struct TimelineScrollCoast: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.scrollTargetBehavior(TimelineScrollTargetBehavior())
        #else
        content
        #endif
    }
}

#if os(iOS)
struct TimelineScrollTargetBehavior: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin = extendedOrigin(target.rect.origin, velocity: context.velocity, axes: context.axes)
    }

    func extendedOrigin(_ origin: CGPoint, velocity: CGVector, axes: Axis.Set) -> CGPoint {
        // Extend UIKit's fast projection by about 25 points for a 1,000 pt/s release.
        let extraProjectionTime: CGFloat = 0.025
        return CGPoint(
            x: origin.x + (axes.contains(.horizontal) ? velocity.dx * extraProjectionTime : 0),
            y: origin.y + (axes.contains(.vertical) ? velocity.dy * extraProjectionTime : 0)
        )
    }
}

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
