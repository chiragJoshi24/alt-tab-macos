import Cocoa

/// Plays the ring collapsing into its hub when search replaces the Orbit layout. By the time it plays, the
/// panel already shows the search list (its tiles are recycled into it, and the panel has resized), so the
/// ring is redrawn here, in its own click-through window over where the panel was, and that window is put
/// away once the animation ends. It is never key, so typing goes to the search field throughout.
final class OrbitCollapseWindow: NSWindow {
    private static var shared: OrbitCollapseWindow?
    private let container = FlippedView()
    private let ring = OrbitView()
    private let backdrop = noAnimation { CAShapeLayer() }
    private var icons = [CALayer]()
    private var generation = 0

    private convenience init() {
        self.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .popUpMenu
        container.wantsLayer = true
        container.layer!.addSublayer(backdrop)
        container.addSubview(ring)
        contentView = container
    }

    /// The ring as it stood, read before its tiles are recycled into the search list.
    struct Snapshot {
        struct Icon {
            var image: CGImage?
            var bounds: CGRect
            var position: CGPoint
            var transform: CATransform3D
        }

        /// Where the panel was, in screen coordinates.
        var frame: NSRect
        var result: OrbitLayout.Result
        var center: CGPoint
        var hubRadius: CGFloat
        var focused: Int?
        var selected: Window?
        var icons: [Icon]

        init(frame: NSRect, _ orbit: (result: OrbitLayout.Result, center: CGPoint, tiles: [TileView]), hubRadius: CGFloat,
             focused: Int?, selected: Window?) {
            self.frame = frame
            result = orbit.result
            center = orbit.center
            self.hubRadius = hubRadius
            self.focused = focused
            self.selected = selected
            icons = orbit.tiles.map { tile in
                Icon(image: tile.window_?.icon, bounds: tile.appIcon.bounds,
                    position: CGPoint(x: tile.frame.minX + tile.appIcon.position.x, y: tile.frame.minY + tile.appIcon.position.y),
                    transform: tile.appIcon.transform)
            }
        }
    }

    static func play(_ snapshot: Snapshot) {
        let window = shared ?? OrbitCollapseWindow()
        shared = window
        window.show(snapshot)
    }

    private func show(_ snapshot: Snapshot) {
        generation &+= 1
        let current = generation
        caTransaction {
            setFrame(snapshot.frame, display: false)
            let bounds = CGRect(origin: .zero, size: snapshot.frame.size)
            container.frame = bounds
            ring.frame = bounds
            ring.update(snapshot.result, center: snapshot.center, hubRadius: snapshot.hubRadius)
            ring.updateHighlight(focused: snapshot.focused, hovered: nil)
            ring.showWindow(snapshot.selected)
            drawBackdrop(bounds)
            drawIcons(snapshot.icons)
        }
        orderFront(nil)
        OrbitView.animateCollapse(container.layer!, around: snapshot.center)
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbitView.transitionDuration) { [weak self] in
            guard let self, self.generation == current else { return }
            self.orderOut(nil)
        }
    }

    /// The panel's glass can't be redrawn outside the panel, so a tinted disc stands in for it.
    private func drawBackdrop(_ bounds: CGRect) {
        backdrop.frame = bounds
        backdrop.path = CGPath(ellipseIn: bounds, transform: nil)
        let isDark = Appearance.currentTheme == .dark
        backdrop.fillColor = NSColor(white: isDark ? 0.12 : 0.96, alpha: 0.55).cgColor
    }

    private func drawIcons(_ snapshot: [Snapshot.Icon]) {
        icons.forEach { $0.removeFromSuperlayer() }
        icons = snapshot.map { snapshotIcon in
            let icon = noAnimation { CALayer() }
            icon.contents = snapshotIcon.image
            icon.contentsGravity = .resizeAspect
            icon.bounds = snapshotIcon.bounds
            icon.position = snapshotIcon.position
            icon.transform = snapshotIcon.transform
            container.layer!.addSublayer(icon)
            return icon
        }
    }
}
