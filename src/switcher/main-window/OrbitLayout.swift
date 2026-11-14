import Foundation

/// The Orbit style's geometry, as arithmetic. Tiles sit on concentric rings around a central hub, and each
/// ring is cut into equal segments, one per tile: 2 tiles take half a ring each, 8 take an eighth. A ring
/// holds only as many tiles as fit side by side at its middle radius; past that, more rings are added and
/// the tiles are spread across them in proportion to what each can hold, so no outer ring is left holding a
/// single lonely tile. `TilesView` owns the AppKit half (frames, drawing), and this owns the placement, so
/// it can be pinned by unit tests.
///
/// Coordinates are relative to the hub's center, in the document view's flipped space (y grows downward).
/// Angles are in radians, 0 at 12 o'clock, growing clockwise, so tile order reads clockwise from the top.
enum OrbitLayout {
    struct Input: Equatable {
        var count: Int
        var iconSize: CGFloat
        var hubRadius: CGFloat
        var ringThickness: CGFloat
        var ringGap: CGFloat
        /// The width of the straight band of space between two neighbor segments.
        var segmentGap: CGFloat
        /// The least distance kept between two neighbor icons, measured along the ring's middle circle.
        var iconSpacing: CGFloat
    }

    /// `startAngle` and `endAngle` are the lines through the center that split the ring between neighbors.
    /// The shape drawn stays `gap / 2` away from each of them, so the space between two neighbors is a
    /// straight band of constant width, not a wedge pointing at the center.
    struct Segment: Equatable {
        var ring: Int
        var startAngle: CGFloat
        var endAngle: CGFloat
        var gap: CGFloat
        var innerRadius: CGFloat
        var outerRadius: CGFloat

        var midAngle: CGFloat { (startAngle + endAngle) / 2 }
        var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }
        var center: CGPoint { OrbitLayout.point(angle: midAngle, radius: midRadius) }
    }

    struct Result: Equatable {
        /// One per tile, in tile order: ring 0 first, clockwise from 12 o'clock within each ring.
        var segments: [Segment]
        var ringCounts: [Int]
        /// The outer edge of the last ring, or of the hub when there is no tile.
        var outerRadius: CGFloat
    }

    static func compute(_ input: Input) -> Result {
        guard input.count > 0 else { return Result(segments: [], ringCounts: [], outerRadius: input.hubRadius) }
        let counts = ringCounts(input)
        var segments = [Segment]()
        for (ring, count) in counts.enumerated() {
            segments += ringSegments(ring, count, input)
        }
        return Result(segments: segments, ringCounts: counts, outerRadius: outerRadius(counts.count - 1, input))
    }

    /// How many tiles each ring holds: the fewest rings that fit them all, filled in proportion to their
    /// capacities by largest remainder, so the counts always add up to `input.count` and none is over capacity.
    static func ringCounts(_ input: Input) -> [Int] {
        var capacities = [Int]()
        while capacities.reduce(0, +) < input.count {
            capacities.append(capacity(capacities.count, input))
        }
        let total = CGFloat(capacities.reduce(0, +))
        let shares = capacities.map { CGFloat(input.count) * CGFloat($0) / total }
        var counts = shares.map { Int($0.rounded(.down)) }
        let byRemainder = shares.indices.sorted { shares[$0] - CGFloat(counts[$0]) > shares[$1] - CGFloat(counts[$1]) }
        var missing = input.count - counts.reduce(0, +)
        for ring in byRemainder where missing > 0 && counts[ring] < capacities[ring] {
            counts[ring] += 1
            missing -= 1
        }
        return counts
    }

    /// The tile under `point`, as an index into `result.segments`. The gap between two segments counts as
    /// part of the nearest one, so the pointer never falls through it.
    static func segmentIndex(at point: CGPoint, _ result: Result) -> Int? {
        let radius = hypot(point.x, point.y)
        let angle = self.angle(of: point)
        var ringStart = 0
        for count in result.ringCounts {
            let ring = result.segments[ringStart..<ringStart + count]
            if let first = ring.first, radius >= first.innerRadius, radius <= first.outerRadius {
                let span = 2 * CGFloat.pi / CGFloat(count)
                let position = Int(((angle + span / 2) / span).rounded(.down)) % count
                return ringStart + position
            }
            ringStart += count
        }
        return nil
    }

    /// The tile of `ring` whose middle is the closest to `angle`, as an index into `result.segments`.
    static func nearestSegment(toAngle angle: CGFloat, inRing ring: Int, _ result: Result) -> Int? {
        let indexes = result.segments.indices.filter { result.segments[$0].ring == ring }
        return indexes.min { angularDistance(result.segments[$0].midAngle, angle) < angularDistance(result.segments[$1].midAngle, angle) }
    }

    static func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: sin(angle) * radius, y: -cos(angle) * radius)
    }

    /// In [0, 2π), 0 at 12 o'clock, growing clockwise.
    static func angle(of point: CGPoint) -> CGFloat {
        let angle = atan2(point.x, -point.y)
        return angle < 0 ? angle + 2 * CGFloat.pi : angle
    }

    private static func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let distance = abs(a - b).truncatingRemainder(dividingBy: 2 * CGFloat.pi)
        return min(distance, 2 * CGFloat.pi - distance)
    }

    private static func innerRadius(_ ring: Int, _ input: Input) -> CGFloat {
        input.hubRadius + input.ringGap + CGFloat(ring) * (input.ringThickness + input.ringGap)
    }

    private static func outerRadius(_ ring: Int, _ input: Input) -> CGFloat {
        innerRadius(ring, input) + input.ringThickness
    }

    private static func capacity(_ ring: Int, _ input: Input) -> Int {
        let midRadius = innerRadius(ring, input) + input.ringThickness / 2
        return max(1, Int((2 * CGFloat.pi * midRadius / (input.iconSize + input.iconSpacing)).rounded(.down)))
    }

    /// Segment 0 is centered on 12 o'clock. A lone segment is the whole ring, with no gap to cut.
    private static func ringSegments(_ ring: Int, _ count: Int, _ input: Input) -> [Segment] {
        let inner = innerRadius(ring, input)
        let outer = inner + input.ringThickness
        let span = 2 * CGFloat.pi / CGFloat(count)
        let gap = count == 1 ? 0 : input.segmentGap
        return (0..<count).map { position in
            let start = CGFloat(position) * span - span / 2
            return Segment(ring: ring, startAngle: start, endAngle: start + span, gap: gap, innerRadius: inner, outerRadius: outer)
        }
    }
}
