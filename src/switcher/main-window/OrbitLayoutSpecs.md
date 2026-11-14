# OrbitLayout — Specs

## Summary

The **Orbit** appearance style draws the switcher as a round panel: a hub in the middle that previews the
selected window, ringed by one segment per window, each showing the window's app icon. The segments of a
ring share it equally, so with 2 windows each takes half the ring, and with 8 each takes an eighth.

`OrbitLayout` is the geometry as arithmetic. `TilesView` keeps the AppKit half (filling tiles, assigning
frames, sizing the panel, drawing the rings), and this owns the decisions: how many rings, how many tiles on
each, where each segment starts and ends, which tile is under the pointer, and which tile up/down lands on.

### Coordinates

Points are relative to the hub's center, in the document view's flipped space, so **y grows downward**.
Angles are in radians, **0 at 12 o'clock, growing clockwise**, so the tile order reads clockwise from the
top, starting with ring 0 (the innermost).

## Behavior & edge cases

- **A ring holds as many icons as fit side by side along its middle circle**, each icon plus
  `iconSpacing`. A ring always holds at least 1.
- **Rings are added only when the tiles don't fit in the ones before.** Once there are several, the tiles
  are spread across all of them in proportion to their capacities, by largest remainder. The counts always
  add up to the tile count, no ring is over capacity, and no ring is left empty.
- **Segment 0 of each ring is centered on 12 o'clock.** A segment's start and end angles are the lines
  through the center that split the ring between neighbors.
- **The gap between neighbor segments is a straight band of constant width**, `segmentGap`, not a wedge
  pointing at the center. `OrbitView` draws each segment's straight edges parallel to the dividing line,
  half the gap away from it, and rounds the segment's four corners.
- **A lone tile takes the whole ring**, with no gap cut out of it.
- **No tile** leaves only the hub: no segment, no ring, and the outer radius is the hub's.
- **Hit-testing counts the gap between two segments as part of the nearest one**, so the pointer never
  falls through it. The hub, the gaps between rings, and anything beyond the last
  ring hit nothing.
- **Up/down moves between rings**, landing on the tile of the target ring whose middle is the closest to
  the current tile's middle, measured the short way around the circle (across 12 o'clock too).

## Test coverage

| Scenario | Test |
| --- | --- |
| No tile leaves only the hub | `testNoTileLeavesOnlyTheHub` |
| One tile takes the whole ring, with no gap | `testOneTileTakesTheWholeRingWithNoGap` |
| Two tiles take half the ring each, clockwise from the top | `testTwoTilesTakeHalfTheRingEachClockwiseFromTheTop` |
| The first tile sits straight above the hub | `testFirstTileSitsStraightAboveTheHub` |
| A ring holds as many icons as fit along its middle | `testRingHoldsAsManyIconsAsFitAlongItsMiddle` |
| Overflow spreads tiles across rings by capacity | `testOverflowSpreadsTilesAcrossRingsByCapacity` |
| Ring counts always add up, with no empty ring | `testRingCountsAlwaysAddUpAndStayWithinCapacity` |
| The outer radius is the last ring's outer edge | `testOuterRadiusIsTheLastRingsOuterEdge` |
| The pointer on a segment finds its tile | `testPointerOnASegmentFindsItsTile` |
| Just left of 12 o'clock is still the first tile | `testPointerJustLeftOfTwelveOClockIsStillTheFirstTile` |
| The hub and outside the rings hit nothing | `testPointerOnTheHubOrOutsideTheRingsFindsNothing` |
| The outer ring's segments are found too | `testPointerOnTheOuterRingFindsAnOuterTile` |
| Up/down picks the closest middle, across 12 o'clock | `testNearestSegmentPicksTheClosestMiddleAcrossTwelveOClock` |
