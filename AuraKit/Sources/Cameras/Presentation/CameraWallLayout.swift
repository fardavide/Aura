import SwiftUI

/// The pure, unit-testable geometry behind `CameraWallLayout`. All cells are 16:9 unless noted.
enum CameraWallGeometry {
    static func frames(
        style: CameraWallLayout.Style, count: Int, width: CGFloat, spacing: CGFloat
    ) -> [CGRect] {
        guard count > 0, width > 0 else { return [] }
        switch style {
        case .uniform(let columns):
            return uniformFrames(columns: columns, count: count, width: width, spacing: spacing)
        case .heroTop:
            return heroTopFrames(count: count, width: width, spacing: spacing)
        case .heroLeading:
            return heroLeadingFrames(count: count, width: width, spacing: spacing)
        }
    }

    static func height(
        style: CameraWallLayout.Style, count: Int, width: CGFloat, spacing: CGFloat
    ) -> CGFloat {
        frames(style: style, count: count, width: width, spacing: spacing).map(\.maxY).max() ?? 0
    }

    private static func uniformFrames(
        columns: Int, count: Int, width: CGFloat, spacing: CGFloat
    ) -> [CGRect] {
        let cellWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let cellHeight = cellWidth * 9 / 16
        return (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            let x = CGFloat(column) * (cellWidth + spacing)
            let y = CGFloat(row) * (cellHeight + spacing)
            return CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
        }
    }

    /// The hero spans the full width at 16:9; the rest pair up in two equal columns below it.
    private static func heroTopFrames(count: Int, width: CGFloat, spacing: CGFloat) -> [CGRect] {
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

    /// The hero fills two thirds of the width on the left, at most two side tiles stack in the
    /// remaining third on the right (decision #6's "hero spans two rows"), and any further camera
    /// flows in full-width rows of three below both.
    private static func heroLeadingFrames(count: Int, width: CGFloat, spacing: CGFloat) -> [CGRect] {
        // A single tile is full width — settled ahead of the formula below so the two can never
        // disagree, rather than falling out of `sideCount == 0` by coincidence.
        if count == 1 {
            return [CGRect(x: 0, y: 0, width: width, height: width * 9 / 16)]
        }

        let sideWidth = (width - spacing) / 3
        let heroWidth = 2 * sideWidth
        let sideHeight = sideWidth * 9 / 16
        let sideCount = min(2, count - 1)
        // Floors the hero at 16:9 so one or two side tiles never letterbox it.
        let heroHeight = max(
            CGFloat(sideCount) * sideHeight + CGFloat(sideCount - 1) * spacing,
            heroWidth * 9 / 16
        )

        var frames = [CGRect(x: 0, y: 0, width: heroWidth, height: heroHeight)]
        let sideX = heroWidth + spacing
        for index in 0..<sideCount {
            let y = CGFloat(index) * (sideHeight + spacing)
            frames.append(CGRect(x: sideX, y: y, width: sideWidth, height: sideHeight))
        }

        let flowCount = count - 1 - sideCount
        guard flowCount > 0 else { return frames }
        // A fresh 3-up grid across the full width, independent of the hero/side split above it —
        // the same "three across" arithmetic `.uniform(columns: 3)` uses.
        let flowWidth = (width - 2 * spacing) / 3
        let flowHeight = flowWidth * 9 / 16
        let flowY = heroHeight + spacing
        for index in 0..<flowCount {
            let column = index % 3
            let row = index / 3
            let x = CGFloat(column) * (flowWidth + spacing)
            let y = flowY + CGFloat(row) * (flowHeight + spacing)
            frames.append(CGRect(x: x, y: y, width: flowWidth, height: flowHeight))
        }
        return frames
    }
}

/// The camera wall: one `Layout` hosting every camera tile behind a single `ForEach`, so a hero swap
/// (a size/style change) never re-parents a tile into a different container — the move that would
/// destroy its identity and rebuild its decoded-image `@State`. SwiftUI has no span-capable grid, so
/// a custom `Layout` is the only construction that keeps identity while changing the composition.
struct CameraWallLayout: Layout {
    let style: Style
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = CameraWallGeometry.height(style: style, count: subviews.count, width: width, spacing: spacing)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = CameraWallGeometry.frames(style: style, count: subviews.count, width: bounds.width, spacing: spacing)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    enum Style: Equatable, Sendable {
        /// Compact width: hero full-width at top, the rest in two columns below.
        case heroTop
        /// Regular width: hero at 2fr on the left (at most two side tiles at 1fr on the right).
        case heroLeading
        /// Compact height (no hero): a uniform grid of `columns` columns.
        case uniform(columns: Int)

        /// The one flag `CameraGridView` reads to decide both the ordered source (`wallCameras` vs.
        /// `visibleCameras`) and which tile, if any, gets `.hero` styling.
        var hasHero: Bool {
            switch self {
            case .heroTop, .heroLeading: true
            case .uniform: false
            }
        }
    }
}
