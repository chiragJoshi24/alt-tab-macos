import Cocoa

/// Paints the Orbit style behind its tiles: one shape per segment, and the hub that previews the selected
/// window. The tiles stay `TileView`s laid on top, so clicks, hover, badges and drag-and-drop work as in
/// every other style; this view only paints, and lets every click through to them.
class OrbitView: FlippedView {
    private static let highlightDuration = CFTimeInterval(0.14)
    private var segmentLayers = [CAShapeLayer]()
    private let hubLayer = noAnimation { CAShapeLayer() }
    private let previewLayer = LightImageLayer()
    private let appNameLayer = noAnimation { CATextLayer() }
    private let titleLayer = noAnimation { CATextLayer() }
    private var center = CGPoint.zero
    private var hubRadius = CGFloat(0)
    private var focusedPosition: Int?
    private var hoveredPosition: Int?

    // periphery:ignore - AppKit private overrides, found by the ObjC runtime rather than called
    @objc func _windowChangedKeyState() {}
    // periphery:ignore - AppKit private overrides, found by the ObjC runtime rather than called
    @objc func _layoutSubtreeWithOldSize(_ oldSize: NSSize) {}

    convenience init() {
        self.init(frame: .zero)
        wantsLayer = true
        layer!.masksToBounds = false
        previewLayer.cornerRadius = 10
        previewLayer.cornerCurve = .continuous
        previewLayer.masksToBounds = true
        previewLayer.contentsGravity = .resizeAspect
        for text in [appNameLayer, titleLayer] {
            text.alignmentMode = .center
            text.truncationMode = .end
        }
        titleLayer.isWrapped = true
        layer!.addSublayer(hubLayer)
        layer!.addSublayer(previewLayer)
        layer!.addSublayer(appNameLayer)
        layer!.addSublayer(titleLayer)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `center` is the hub's center in this view's coordinates.
    func update(_ result: OrbitLayout.Result, center: CGPoint, hubRadius: CGFloat) {
        self.center = center
        self.hubRadius = hubRadius
        addSegmentLayersIfNeeded(result.segments.count)
        for (position, layer) in segmentLayers.enumerated() {
            layer.isHidden = position >= result.segments.count
            guard !layer.isHidden else { continue }
            layer.path = Self.path(result.segments[position], center)
            layer.shadowPath = layer.path
        }
        hubLayer.path = CGPath(ellipseIn: CGRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2), transform: nil)
        applyTheme()
        focusedPosition = nil
        hoveredPosition = nil
        for position in 0..<result.segments.count { paint(position, animated: false) }
    }

    func updateHighlight(focused: Int?, hovered: Int?) {
        let changed = Set([focusedPosition, hoveredPosition, focused, hovered].compactMap { $0 })
        focusedPosition = focused
        hoveredPosition = hovered
        for position in changed where position < segmentLayers.count { paint(position, animated: true) }
    }

    /// The hub previews the window's latest capture, framed to its aspect ratio; with no capture yet (or a
    /// windowless app, which never has one) it shows the app icon instead.
    func showWindow(_ window: Window?) {
        guard let window else {
            previewLayer.isHidden = true
            appNameLayer.string = nil
            titleLayer.string = nil
            return
        }
        let appName = window.application.localizedName ?? ""
        appNameLayer.string = appName
        titleLayer.string = window.title.isEmpty || window.title == appName ? nil : window.title
        showPreview(window)
        layoutHubContent()
    }

    /// Entering and leaving search share one duration and curve, so both directions feel the same.
    static let transitionDuration = CFTimeInterval(0.22)
    private static let transitionCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)

    /// Plays when the ring appears: it grows out of the hub, as if the tiles fanned out from it.
    static func animateFanOut(_ layer: CALayer, around center: CGPoint) {
        grow(layer, from: 0.6, around: center)
    }

    /// Plays when the search list replaces the ring: it settles in from slightly smaller.
    static func animateSettle(_ layer: CALayer, around center: CGPoint) {
        grow(layer, from: 0.94, around: center)
    }

    /// The fan-out played backwards: the ring shrinks into its hub and fades. It holds its last frame, since
    /// the caller hides the layer only once the animation is over.
    static func animateCollapse(_ layer: CALayer, around center: CGPoint) {
        let group = scaleAndFade(layer, from: 1, to: 0.6, opacityFrom: 1, opacityTo: 0, around: center)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "grow")
    }

    private static func grow(_ layer: CALayer, from factor: CGFloat, around center: CGPoint) {
        layer.add(scaleAndFade(layer, from: factor, to: 1, opacityFrom: 0, opacityTo: 1, around: center), forKey: "grow")
    }

    /// Scales and fades `layer`'s sublayers, so pass the layer holding everything that should move (this
    /// view and the tiles). `center` is in `layer`'s coordinates, and the scale pivots on it whatever the
    /// layer's anchor point; the Orbit panel is square with the hub in its middle, so it reads the same
    /// whether or not AppKit flipped that layer.
    private static func scaleAndFade(_ layer: CALayer, from: CGFloat, to: CGFloat, opacityFrom: Float, opacityTo: Float,
                                     around center: CGPoint) -> CAAnimationGroup {
        let pivot = CGPoint(x: center.x - layer.anchorPoint.x * layer.bounds.width, y: center.y - layer.anchorPoint.y * layer.bounds.height)
        let scale = CABasicAnimation(keyPath: "sublayerTransform")
        scale.fromValue = NSValue(caTransform3D: Self.scale(from, around: pivot))
        scale.toValue = NSValue(caTransform3D: Self.scale(to, around: pivot))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacityFrom
        fade.toValue = opacityTo
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = transitionDuration
        group.timingFunction = transitionCurve
        return group
    }

    private func showPreview(_ window: Window) {
        previewLayer.isHidden = false
        if let thumbnail = window.thumbnail, !window.isWindowlessApp {
            previewLayer.updateContents(thumbnail, previewSize(window.thumbnailArea?.size))
            previewLayer.cornerRadius = 10
        } else {
            let side = (hubRadius * 0.62).rounded()
            previewLayer.updateContents(.cgImage(window.icon), NSSize(width: side, height: side))
            previewLayer.cornerRadius = 0
        }
    }

    private func previewSize(_ imageSize: NSSize?) -> NSSize {
        let box = NSSize(width: hubRadius * 1.4, height: hubRadius * 0.82)
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        return NSSize(width: (imageSize.width * scale).rounded(), height: (imageSize.height * scale).rounded())
    }

    /// Preview, app name, then title, stacked and centered on the hub as one block.
    private func layoutHubContent() {
        let textWidth = (hubRadius * 1.5).rounded()
        let appNameHeight = CGFloat(20)
        let titleHeight: CGFloat = titleLayer.string == nil ? 0 : 32
        let preview = previewLayer.frame.size
        let blockHeight = preview.height + 10 + appNameHeight + (titleHeight > 0 ? 2 + titleHeight : 0)
        var y = (center.y - blockHeight / 2).rounded()
        previewLayer.frame.origin = CGPoint(x: (center.x - preview.width / 2).rounded(), y: y)
        y += preview.height + 10
        appNameLayer.frame = CGRect(x: center.x - textWidth / 2, y: y, width: textWidth, height: appNameHeight)
        y += appNameHeight + 2
        titleLayer.frame = CGRect(x: center.x - textWidth / 2, y: y, width: textWidth, height: titleHeight)
    }

    private func addSegmentLayersIfNeeded(_ count: Int) {
        while segmentLayers.count < count {
            let segment = noAnimation { CAShapeLayer() }
            segment.lineWidth = 1
            segment.shadowRadius = 14
            segment.shadowOffset = .zero
            layer!.insertSublayer(segment, below: hubLayer)
            segmentLayers.append(segment)
        }
    }

    private func applyTheme() {
        let isDark = Appearance.currentTheme == .dark
        let scale = window?.backingScaleFactor ?? NSScreen.preferred.backingScaleFactor
        hubLayer.fillColor = NSColor(white: isDark ? 0 : 1, alpha: isDark ? 0.28 : 0.45).cgColor
        hubLayer.strokeColor = NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.12 : 0.08).cgColor
        hubLayer.lineWidth = 1
        previewLayer.borderWidth = 0.5
        previewLayer.borderColor = NSColor(white: isDark ? 1 : 0, alpha: 0.15).cgColor
        appNameLayer.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        appNameLayer.fontSize = 15
        appNameLayer.foregroundColor = Appearance.fontColor.cgColor
        titleLayer.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLayer.fontSize = 12
        titleLayer.foregroundColor = Appearance.fontColor.withAlphaComponent(0.6).cgColor
        for text in [appNameLayer, titleLayer] { text.contentsScale = scale }
        for segment in segmentLayers {
            segment.strokeColor = NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.10 : 0.07).cgColor
            segment.shadowColor = NSColor.systemAccentColor.cgColor
        }
    }

    /// Focused is a solid accent with a soft glow, hovered a faint accent wash, and the rest a quiet glass tint.
    private func paint(_ position: Int, animated: Bool) {
        let segment = segmentLayers[position]
        let isDark = Appearance.currentTheme == .dark
        let fill: NSColor
        if position == focusedPosition {
            fill = NSColor.systemAccentColor.withAlphaComponent(0.88)
        } else if position == hoveredPosition {
            fill = NSColor.systemAccentColor.withAlphaComponent(0.3)
        } else {
            fill = NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.07 : 0.05)
        }
        let shadowOpacity: Float = position == focusedPosition ? 0.55 : 0
        if animated {
            Self.fade(segment, "fillColor", from: segment.presentation()?.fillColor ?? segment.fillColor, to: fill.cgColor)
            Self.fade(segment, "shadowOpacity", from: segment.presentation()?.shadowOpacity ?? segment.shadowOpacity, to: shadowOpacity)
        }
        segment.fillColor = fill.cgColor
        segment.shadowOpacity = shadowOpacity
    }

    /// `noAnimation` layers answer every implicit action with none, so an animated change adds its own.
    private static func fade(_ layer: CALayer, _ keyPath: String, from: Any?, to: Any) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = highlightDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: keyPath)
    }

    private static func path(_ segment: OrbitLayout.Segment, _ center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let start = segment.startAngle - .pi / 2
        let end = segment.endAngle - .pi / 2
        path.addArc(center: center, radius: segment.outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: segment.innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    private static func scale(_ factor: CGFloat, around point: CGPoint) -> CATransform3D {
        let toOrigin = CATransform3DMakeTranslation(-point.x, -point.y, 0)
        let scaled = CATransform3DConcat(toOrigin, CATransform3DMakeScale(factor, factor, 1))
        return CATransform3DConcat(scaled, CATransform3DMakeTranslation(point.x, point.y, 0))
    }
}
