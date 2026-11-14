import XCTest

/// Pins the Orbit style's ring arithmetic: how tiles split across rings, where each segment starts and ends,
/// which tile the pointer is over, and which tile up/down lands on. Pure numbers in, numbers out.
///
/// Groups: A one ring · B more rings · C hit-testing · D up/down.
final class OrbitLayoutTests: XCTestCase {
    private func input(_ count: Int) -> OrbitLayout.Input {
        OrbitLayout.Input(count: count, iconSize: 50, hubRadius: 100, ringThickness: 80, ringGap: 10, segmentGap: 6, iconSpacing: 20)
    }

    // MARK: - A. One ring

    func testNoTileLeavesOnlyTheHub() {
        let result = OrbitLayout.compute(input(0))
        XCTAssertEqual(result.segments, [])
        XCTAssertEqual(result.ringCounts, [])
        XCTAssertEqual(result.outerRadius, 100)
    }

    func testOneTileTakesTheWholeRingWithNoGap() {
        let result = OrbitLayout.compute(input(1))
        XCTAssertEqual(result.ringCounts, [1])
        let segment = result.segments[0]
        XCTAssertEqual(segment.endAngle - segment.startAngle, 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(segment.gap, 0)
        XCTAssertEqual(segment.innerRadius, 110)
        XCTAssertEqual(segment.outerRadius, 190)
    }

    func testTwoTilesTakeHalfTheRingEachClockwiseFromTheTop() {
        let result = OrbitLayout.compute(input(2))
        XCTAssertEqual(result.ringCounts, [2])
        XCTAssertEqual(result.segments[0].midAngle, 0, accuracy: 1e-9)
        XCTAssertEqual(result.segments[1].midAngle, .pi, accuracy: 1e-9)
        XCTAssertEqual(result.segments[0].endAngle - result.segments[0].startAngle, .pi, accuracy: 1e-9)
        XCTAssertEqual(result.segments[0].gap, 6)
    }

    func testFirstTileSitsStraightAboveTheHub() {
        let center = OrbitLayout.compute(input(4)).segments[0].center
        XCTAssertEqual(center.x, 0, accuracy: 1e-9)
        XCTAssertEqual(center.y, -150, accuracy: 1e-9)
    }

    // MARK: - B. More rings

    func testRingHoldsAsManyIconsAsFitAlongItsMiddle() {
        // 2π·150 / (50+20) = 13.46
        XCTAssertEqual(OrbitLayout.ringCounts(input(13)), [13])
    }

    func testOverflowSpreadsTilesAcrossRingsByCapacity() {
        // capacities 13 and 2π·240 / 70 = 21: 14 tiles split 14·13/34 = 5.35 and 14·21/34 = 8.65
        XCTAssertEqual(OrbitLayout.ringCounts(input(14)), [5, 9])
    }

    func testRingCountsAlwaysAddUpAndStayWithinCapacity() {
        for count in 1...80 {
            let counts = OrbitLayout.ringCounts(input(count))
            XCTAssertEqual(counts.reduce(0, +), count)
            XCTAssertFalse(counts.contains(0), "count \(count): \(counts)")
        }
    }

    func testOuterRadiusIsTheLastRingsOuterEdge() {
        XCTAssertEqual(OrbitLayout.compute(input(14)).outerRadius, 280)
    }

    // MARK: - C. Hit-testing

    func testPointerOnASegmentFindsItsTile() {
        let result = OrbitLayout.compute(input(4))
        XCTAssertEqual(OrbitLayout.segmentIndex(at: CGPoint(x: 0, y: -150), result), 0)
        XCTAssertEqual(OrbitLayout.segmentIndex(at: CGPoint(x: 150, y: 0), result), 1)
        XCTAssertEqual(OrbitLayout.segmentIndex(at: CGPoint(x: 0, y: 150), result), 2)
        XCTAssertEqual(OrbitLayout.segmentIndex(at: CGPoint(x: -150, y: 0), result), 3)
    }

    func testPointerJustLeftOfTwelveOClockIsStillTheFirstTile() {
        let result = OrbitLayout.compute(input(4))
        XCTAssertEqual(OrbitLayout.segmentIndex(at: CGPoint(x: -1, y: -150), result), 0)
    }

    func testPointerOnTheHubOrOutsideTheRingsFindsNothing() {
        let result = OrbitLayout.compute(input(4))
        XCTAssertNil(OrbitLayout.segmentIndex(at: .zero, result))
        XCTAssertNil(OrbitLayout.segmentIndex(at: CGPoint(x: 0, y: -195), result))
    }

    func testPointerOnTheOuterRingFindsAnOuterTile() {
        let result = OrbitLayout.compute(input(14))
        XCTAssertEqual(OrbitLayout.segmentIndex(at: CGPoint(x: 0, y: -240), result), 5)
    }

    // MARK: - D. Up/down

    func testNearestSegmentPicksTheClosestMiddleAcrossTwelveOClock() {
        let result = OrbitLayout.compute(input(14))
        let lastOfOuterRing = result.segments.count - 1
        let justBeforeTwelve = result.segments[lastOfOuterRing].midAngle + 0.01
        XCTAssertEqual(OrbitLayout.nearestSegment(toAngle: justBeforeTwelve, inRing: 1, result), lastOfOuterRing)
        XCTAssertEqual(OrbitLayout.nearestSegment(toAngle: 0.01, inRing: 1, result), 5)
    }
}
