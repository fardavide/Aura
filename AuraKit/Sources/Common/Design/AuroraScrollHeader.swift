import SwiftUI

/// A left-aligned title (+ optional trailing action) pinned above a screen's scrolling content,
/// with a glass surface that fades in once content has scrolled behind it — the same "content
/// scrolls behind glass" read a system navigation bar gives for free, without losing the
/// left-aligned, Aurora-styled title a system toolbar cannot render (a `.principal` toolbar item
/// centres its content; `.topBarLeading` collapses anything wider than an icon into an overflow
/// menu — verified empirically, neither renders this design). Pair with `.auroraTrackingScrollGlass`
/// on the sibling `ScrollView`.
public struct AuroraScrollHeader<Leading: View, Trailing: View>: View {
    private let isGlass: Bool
    private let leading: Leading
    private let trailing: Trailing

    public init(
        isGlass: Bool,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.isGlass = isGlass
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background {
            if isGlass {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(.auroraSheetTint), in: Rectangle())
                    .ignoresSafeArea(edges: .top)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isGlass)
    }
}

extension View {
    /// Reports whether the scroll view has moved past its top edge, for a sibling
    /// `AuroraScrollHeader`'s `isGlass`. `threshold` absorbs the small negative offsets a bounce
    /// or a rubber-band overscroll produces at rest, so the glass doesn't flicker on a tiny nudge.
    public func auroraTrackingScrollGlass(isGlass: Binding<Bool>, threshold: CGFloat = 8) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > threshold
        } action: { _, isPast in
            isGlass.wrappedValue = isPast
        }
    }
}
