import SwiftUI

/// The compact-width grid: the first subview spans the full width at 16:9, the rest pair up in two
/// equal 16:9 columns below it. A custom `Layout` rather than `LazyVStack { hero; LazyVGrid { rest } }`
/// because SwiftUI identity is structural — moving a tile between two containers on a hero swap would
/// destroy and rebuild it (a fresh player, every `.task` re-running). One container, one `ForEach`
/// (`TimelineScreenViewModel.heroOrderedCameras(_:)` supplies the order) keeps each tile's identity
/// across the reorder. A handful of cameras needs no laziness, so the custom layout costs nothing.
struct HeroGridLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let frames = Self.frames(count: subviews.count, width: width, spacing: spacing)
        return CGSize(width: width, height: frames.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = Self.frames(count: subviews.count, width: bounds.width, spacing: spacing)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// The pure arithmetic behind the layout, so it is unit-tested without a layout pass. All tiles
    /// are 16:9; the hero occupies the full width, the rest split it two to a row.
    static func frames(count: Int, width: CGFloat, spacing: CGFloat) -> [CGRect] {
        guard count > 0, width > 0 else { return [] }
        let heroHeight = width * 9 / 16
        var frames = [CGRect(x: 0, y: 0, width: width, height: heroHeight)]
        guard count > 1 else { return frames }

        let columnWidth = (width - spacing) / 2
        let columnHeight = columnWidth * 9 / 16
        var column = 0
        var y = heroHeight + spacing
        for _ in 1..<count {
            let x = CGFloat(column) * (columnWidth + spacing)
            frames.append(CGRect(x: x, y: y, width: columnWidth, height: columnHeight))
            column += 1
            if column == 2 {
                column = 0
                y += columnHeight + spacing
            }
        }
        return frames
    }
}
