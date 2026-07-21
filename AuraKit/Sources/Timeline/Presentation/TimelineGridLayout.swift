import CoreGraphics

/// Best-fit "video wall" sizing for the timeline's camera grid on regular-width layouts (iPad and
/// macOS): the column count that renders every 16:9 tile largest while all of them fit the
/// viewport. When even the best arrangement would drop below `minimumTileWidth` (many cameras,
/// small window), it falls back to as many minimum-width columns as the width holds and the grid
/// scrolls instead.
struct TimelineGridLayout: Equatable {
    let columnCount: Int
    let tileWidth: CGFloat

    static func bestFit(
        tileCount: Int,
        available: CGSize,
        spacing: CGFloat,
        minimumTileWidth: CGFloat
    ) -> TimelineGridLayout {
        guard tileCount > 0, available.width > 0 else {
            return TimelineGridLayout(columnCount: 1, tileWidth: max(0, available.width.rounded(.down)))
        }

        var fitted = TimelineGridLayout(columnCount: 1, tileWidth: 0)
        for columnCount in 1...tileCount {
            let rowCount = (tileCount + columnCount - 1) / columnCount
            let widthLimit = (available.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
            let rowHeight = (available.height - CGFloat(rowCount - 1) * spacing) / CGFloat(rowCount)
            let tileWidth = min(widthLimit, rowHeight * aspectRatio)
            if tileWidth > fitted.tileWidth {
                fitted = TimelineGridLayout(columnCount: columnCount, tileWidth: tileWidth)
            }
        }
        if fitted.tileWidth >= minimumTileWidth {
            return TimelineGridLayout(columnCount: fitted.columnCount, tileWidth: fitted.tileWidth.rounded(.down))
        }

        let columnCount = min(tileCount, max(1, Int((available.width + spacing) / (minimumTileWidth + spacing))))
        let tileWidth = (available.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        return TimelineGridLayout(columnCount: columnCount, tileWidth: tileWidth.rounded(.down))
    }
}

/// The tiles' 16:9 shape, as width over height.
private let aspectRatio: CGFloat = 16.0 / 9.0
