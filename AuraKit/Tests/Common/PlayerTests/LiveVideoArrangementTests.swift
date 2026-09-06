import SwiftUI
import Testing

import CommonDesign
import CommonPlayer

/// Pure rules for `LiveVideoArrangement` — which arrangement a size class produces, whether the
/// controls auto-hide, which glass they wear, and the geometry of the card. No fakes, no
/// `@MainActor`, no `AVPlayer`: `LiveVideoArrangement` / `LiveVideoMetrics` are plain value types.
struct LiveVideoArrangementTests {

    // MARK: - Deriving the arrangement from a vertical size class

    @Test func `given a compact vertical size class when deriving the arrangement then the video fills`() {
        // given / when
        let arrangement = LiveVideoArrangement(verticalSizeClass: .compact)

        // then
        #expect(arrangement == .fill)
    }

    @Test func `given a regular vertical size class when deriving the arrangement then it is a card`() {
        // given / when
        let arrangement = LiveVideoArrangement(verticalSizeClass: .regular)

        // then
        #expect(arrangement == .card)
    }

    @Test func `given no vertical size class when deriving the arrangement then it is a card`() {
        // given / when
        let arrangement = LiveVideoArrangement(verticalSizeClass: nil)

        // then
        #expect(arrangement == .card)
    }

    // MARK: - Auto-hide

    @Test func `given the card arrangement when asked whether controls auto hide then it is false`() {
        // given / when / then
        #expect(LiveVideoArrangement.card.autoHidesControls == false)
    }

    @Test func `given the fill arrangement when asked whether controls auto hide then it is true`() {
        // given / when / then
        #expect(LiveVideoArrangement.fill.autoHidesControls == true)
    }

    // MARK: - Control surface

    @Test func `given the card arrangement when asked for the control surface then it is chrome`() {
        // given / when / then
        #expect(LiveVideoArrangement.card.controlSurface == .chrome)
    }

    @Test func `given the fill arrangement when asked for the control surface then it is video`() {
        // given / when / then
        #expect(LiveVideoArrangement.fill.controlSurface == .video)
    }

    // MARK: - Card geometry

    @Test func `given a tall canvas when sizing the card video then it is width bound at sixteen by nine`() throws {
        // given — iPhone portrait: 390×600
        let metrics = LiveVideoArrangement.card.metrics(canvas: CGSize(width: 390, height: 600))

        // then
        let size = try #require(metrics.videoSize)
        #expect(abs(size.width - 358) < 0.5)
        #expect(abs(size.height - 201.4) < 0.5)
    }

    @Test func `given a wide short canvas when sizing the card video then it is height bound and fits inside it`() throws {
        // given — iPad/macOS landscape: 1194×500
        let canvas = CGSize(width: 1194, height: 500)
        let metrics = LiveVideoArrangement.card.metrics(canvas: canvas)

        // then
        let size = try #require(metrics.videoSize)
        #expect(abs(size.width - 888.9) < 0.5)
        #expect(size.height == 500)
        #expect(size.width <= canvas.width)
        #expect(size.height <= canvas.height)
    }

    @Test func `given the fill arrangement when sizing the video then it has no fixed size`() {
        // given / when
        let metrics = LiveVideoArrangement.fill.metrics(canvas: CGSize(width: 844, height: 390))

        // then
        #expect(metrics.videoSize == nil)
    }

    // MARK: - LIVE pill placement

    @Test func `given the card arrangement when placing the live pill then it sits inside the video card`() throws {
        // given — the pill inset is the card's own origin plus 14 (mock L81)
        let canvas = CGSize(width: 390, height: 600)
        let metrics = LiveVideoArrangement.card.metrics(canvas: canvas)

        // when
        let size = try #require(metrics.videoSize)
        let expectedX = ((canvas.width - size.width) / 2) + 14
        let expectedY = ((canvas.height - size.height) / 2) + 14

        // then
        #expect(abs(metrics.livePillInset.x - expectedX) < 0.5)
        #expect(abs(metrics.livePillInset.y - expectedY) < 0.5)
    }

    @Test func `given the fill arrangement when placing the live pill then it sits twenty points inside the canvas`() {
        // given / when
        let metrics = LiveVideoArrangement.fill.metrics(canvas: CGSize(width: 844, height: 390))

        // then
        #expect(metrics.livePillInset == CGPoint(x: 20, y: 20))
    }
}
