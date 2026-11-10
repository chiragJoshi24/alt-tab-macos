import Cocoa

/// The switcher's search bar, styled after Spotlight: a tall capsule, a large magnifying glass, and large text.
class SpotlightSearchField: NSSearchField {
    static let height = CGFloat(40)
    static let fontSize = CGFloat(18)

    override class var cellClass: AnyClass? {
        get { SpotlightSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        sendsSearchStringImmediately = true
        sendsWholeSearchString = true
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: Self.fontSize, weight: .regular)
        textColor = .labelColor
        placeholderAttributedString = NSAttributedString(string: NSLocalizedString("Search", comment: ""), attributes: [
            .font: NSFont.systemFont(ofSize: Self.fontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        (cell as? SpotlightSearchFieldCell)?.removeBuiltInButtons()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }
}

/// Every geometry override below computes from `controlView.bounds` and ignores the rect AppKit passes in.
/// Unbezeled, `NSSearchFieldCell` reaches the text area through several paths (`titleRect`, `drawingRect`,
/// `searchTextRect`, then `edit`/`select` on an already-reduced frame), and they disagree on what they pass.
/// Computing from the bounds makes every path land on the same rect, however many times it is applied.
/// The magnifying glass is drawn here rather than by `searchButtonCell`, whose placement ignored our rect.
class SpotlightSearchFieldCell: NSSearchFieldCell {
    private static let horizontalInset = CGFloat(14)
    private static let iconPointSize = CGFloat(15)
    private static let iconTextSpacing = CGFloat(5)
    private static let capsuleInset = CGFloat(2)
    private lazy var magnifyingGlass = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: Self.iconPointSize, weight: .semibold))

    func removeBuiltInButtons() {
        searchButtonCell = nil
        cancelButtonCell = nil
    }

    private func bounds(_ fallback: NSRect) -> NSRect {
        controlView?.bounds ?? fallback
    }

    private func textRect(_ fallback: NSRect) -> NSRect {
        let bounds = bounds(fallback)
        let iconWidth = magnifyingGlass?.size.width ?? Self.iconPointSize
        let minX = bounds.minX + Self.horizontalInset + iconWidth + Self.iconTextSpacing
        let maxX = bounds.maxX - Self.horizontalInset
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: SpotlightSearchField.fontSize)))
        return NSRect(x: minX, y: (bounds.midY - lineHeight * 0.5).rounded(), width: max(0, maxX - minX), height: lineHeight)
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect { textRect(rect) }
    override func titleRect(forBounds rect: NSRect) -> NSRect { textRect(rect) }
    override func drawingRect(forBounds rect: NSRect) -> NSRect { textRect(rect) }
    override func searchButtonRect(forBounds rect: NSRect) -> NSRect { .zero }
    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect { .zero }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: textRect(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: textRect(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    /// A solid base under a tint, so the bar reads as a filled object over any wallpaper rather than a
    /// faint outline. The inset leaves room for the drop shadow inside the control's bounds.
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let bounds = bounds(cellFrame)
        drawCapsule(bounds.insetBy(dx: Self.capsuleInset, dy: Self.capsuleInset))
        drawMagnifyingGlass(bounds)
        drawInterior(withFrame: bounds, in: controlView)
    }

    private func drawCapsule(_ rect: NSRect) {
        let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.height * 0.5, yRadius: rect.height * 0.5)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.set()
        NSColor.windowBackgroundColor.withAlphaComponent(0.75).setFill()
        capsule.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        capsule.fill()
        NSColor.labelColor.withAlphaComponent(0.20).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
    }

    private func drawMagnifyingGlass(_ bounds: NSRect) {
        guard let glass = magnifyingGlass else { return }
        let tinted = NSImage(size: glass.size, flipped: false) { rect in
            glass.draw(in: rect)
            NSColor.secondaryLabelColor.set()
            rect.fill(using: .sourceIn)
            return true
        }
        let origin = NSPoint(x: bounds.minX + Self.horizontalInset, y: (bounds.midY - glass.size.height * 0.5).rounded())
        tinted.draw(in: NSRect(origin: origin, size: glass.size), from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: nil)
    }
}
