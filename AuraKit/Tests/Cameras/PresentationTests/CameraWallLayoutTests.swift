import Foundation
import Testing

@testable import CamerasPresentation

/// Pure geometry tests for `CameraWallGeometry` — no fakes, no SwiftUI host. Every expected `CGRect`
/// is built from the same arithmetic the production code documents, spelled out again here rather
/// than by calling the production formula, so a regression in the arithmetic itself fails the test.
@MainActor
struct CameraWallLayoutTests {

    @Test func `given the hero top style when laying out four tiles then the hero spans the width and the rest form two columns`() {
        // given
        let width: CGFloat = 330
        let spacing: CGFloat = 10
        let heroHeight = width * 9 / 16
        let columnWidth = (width - spacing) / 2
        let columnHeight = columnWidth * 9 / 16

        // when
        let frames = CameraWallGeometry.frames(style: .heroTop, count: 4, width: width, spacing: spacing)

        // then
        #expect(frames == [
            CGRect(x: 0, y: 0, width: width, height: heroHeight),
            CGRect(x: 0, y: heroHeight + spacing, width: columnWidth, height: columnHeight),
            CGRect(x: columnWidth + spacing, y: heroHeight + spacing, width: columnWidth, height: columnHeight),
            CGRect(x: 0, y: heroHeight + spacing + columnHeight + spacing, width: columnWidth, height: columnHeight),
        ])
    }

    @Test func `given the hero leading style when laying out three tiles then the hero fills two thirds beside two stacked tiles`() {
        // given
        let width: CGFloat = 310
        let spacing: CGFloat = 10
        let sideWidth = (width - spacing) / 3
        let heroWidth = 2 * sideWidth
        let sideHeight = sideWidth * 9 / 16
        let heroHeight = max(2 * sideHeight + spacing, heroWidth * 9 / 16)

        // when
        let frames = CameraWallGeometry.frames(style: .heroLeading, count: 3, width: width, spacing: spacing)

        // then
        #expect(frames == [
            CGRect(x: 0, y: 0, width: heroWidth, height: heroHeight),
            CGRect(x: heroWidth + spacing, y: 0, width: sideWidth, height: sideHeight),
            CGRect(x: heroWidth + spacing, y: sideHeight + spacing, width: sideWidth, height: sideHeight),
        ])
    }

    @Test func `given the hero leading style when laying out one tile then the hero takes the full width`() {
        // given
        let width: CGFloat = 310
        let spacing: CGFloat = 10

        // when
        let frames = CameraWallGeometry.frames(style: .heroLeading, count: 1, width: width, spacing: spacing)

        // then
        #expect(frames == [CGRect(x: 0, y: 0, width: width, height: width * 9 / 16)])
    }

    @Test func `given the hero leading style when laying out two tiles then the hero keeps its sixteen by nine height`() {
        // given
        let width: CGFloat = 310
        let spacing: CGFloat = 10
        let sideWidth = (width - spacing) / 3
        let heroWidth = 2 * sideWidth
        let sideHeight = sideWidth * 9 / 16
        let heroHeight = max(sideHeight, heroWidth * 9 / 16)

        // when
        let frames = CameraWallGeometry.frames(style: .heroLeading, count: 2, width: width, spacing: spacing)

        // then
        #expect(heroHeight == heroWidth * 9 / 16)
        #expect(frames == [
            CGRect(x: 0, y: 0, width: heroWidth, height: heroHeight),
            CGRect(x: heroWidth + spacing, y: 0, width: sideWidth, height: sideHeight),
        ])
    }

    @Test func `given the hero leading style when laying out four tiles then the fourth tile flows below the hero`() {
        // given
        let width: CGFloat = 310
        let spacing: CGFloat = 10
        let sideWidth = (width - spacing) / 3
        let heroWidth = 2 * sideWidth
        let sideHeight = sideWidth * 9 / 16
        let heroHeight = max(2 * sideHeight + spacing, heroWidth * 9 / 16)
        let flowWidth = (width - 2 * spacing) / 3
        let flowHeight = flowWidth * 9 / 16
        let flowY = heroHeight + spacing

        // when
        let frames = CameraWallGeometry.frames(style: .heroLeading, count: 4, width: width, spacing: spacing)

        // then
        #expect(frames == [
            CGRect(x: 0, y: 0, width: heroWidth, height: heroHeight),
            CGRect(x: heroWidth + spacing, y: 0, width: sideWidth, height: sideHeight),
            CGRect(x: heroWidth + spacing, y: sideHeight + spacing, width: sideWidth, height: sideHeight),
            CGRect(x: 0, y: flowY, width: flowWidth, height: flowHeight),
        ])
    }

    @Test func `given the hero leading style when laying out six tiles then two tiles stack beside the hero and three flow below`() {
        // given
        let width: CGFloat = 310
        let spacing: CGFloat = 10
        let sideWidth = (width - spacing) / 3
        let heroWidth = 2 * sideWidth
        let sideHeight = sideWidth * 9 / 16
        let heroHeight = max(2 * sideHeight + spacing, heroWidth * 9 / 16)
        let flowWidth = (width - 2 * spacing) / 3
        let flowHeight = flowWidth * 9 / 16
        let flowY = heroHeight + spacing

        // when
        let frames = CameraWallGeometry.frames(style: .heroLeading, count: 6, width: width, spacing: spacing)

        // then
        #expect(frames == [
            CGRect(x: 0, y: 0, width: heroWidth, height: heroHeight),
            CGRect(x: heroWidth + spacing, y: 0, width: sideWidth, height: sideHeight),
            CGRect(x: heroWidth + spacing, y: sideHeight + spacing, width: sideWidth, height: sideHeight),
            CGRect(x: 0, y: flowY, width: flowWidth, height: flowHeight),
            CGRect(x: flowWidth + spacing, y: flowY, width: flowWidth, height: flowHeight),
            CGRect(x: 2 * (flowWidth + spacing), y: flowY, width: flowWidth, height: flowHeight),
        ])
    }

    @Test func `given the uniform style when laying out four tiles then they form rows of three`() {
        // given
        let width: CGFloat = 330
        let spacing: CGFloat = 10
        let cellWidth = (width - 2 * spacing) / 3
        let cellHeight = cellWidth * 9 / 16

        // when
        let frames = CameraWallGeometry.frames(style: .uniform(columns: 3), count: 4, width: width, spacing: spacing)

        // then
        #expect(frames == [
            CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight),
            CGRect(x: cellWidth + spacing, y: 0, width: cellWidth, height: cellHeight),
            CGRect(x: 2 * (cellWidth + spacing), y: 0, width: cellWidth, height: cellHeight),
            CGRect(x: 0, y: cellHeight + spacing, width: cellWidth, height: cellHeight),
        ])
    }

    @Test func `given no tiles when laying out then the wall has no height`() {
        // when
        let frames = CameraWallGeometry.frames(style: .uniform(columns: 3), count: 0, width: 330, spacing: 10)
        let height = CameraWallGeometry.height(style: .uniform(columns: 3), count: 0, width: 330, spacing: 10)

        // then
        #expect(frames.isEmpty)
        #expect(height == 0)
    }
}
