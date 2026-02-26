import AppKit

@MainActor
final class CADCanvasView: NSView {
    enum ToolMode {
        case select
        case line
        case circle
        case rectangle
        case polyline
    }

    var document: DXFDocument = .empty {
        didSet { needsDisplay = true }
    }

    var toolMode: ToolMode = .select {
        didSet {
            pendingPoint = nil
            needsDisplay = true
        }
    }

    var onLineCreated: ((DXFPoint, DXFPoint) -> Void)?
    var onCircleCreated: ((DXFPoint, CGFloat) -> Void)?
    var onRectangleCreated: ((DXFPoint, DXFPoint) -> Void)?
    var onPolylineSegmentCreated: ((DXFPoint, DXFPoint) -> Void)?
    var onDocumentChanged: ((DXFDocument) -> Void)?
    var onViewTransformChanged: ((CGFloat, CGPoint) -> Void)?
    var gridStep: CGFloat = 10 {
        didSet { needsDisplay = true }
    }
    var snapStep: CGFloat = 5
    var isSnapEnabled: Bool = true
    var isOrthoEnabled: Bool = false

    private var zoom: CGFloat = 1.0
    private var panOffset = CGPoint.zero
    private var pendingPoint: DXFPoint?
    private var selectedEntityIndex: Int?
    private var dragMode: DragMode = .none
    private var isPanningCamera = false
    private var lastPanLocation = CGPoint.zero
    private var isSpacePressed = false
    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 10.0

    private enum DragMode {
        case none
        case lineStart(index: Int, end: DXFPoint, layer: String, style: DXFEntityStyle)
        case lineEnd(index: Int, start: DXFPoint, layer: String, style: DXFEntityStyle)
        case circleCenter(index: Int, radius: CGFloat, layer: String, style: DXFEntityStyle, anchor: DXFPoint, originalCenter: DXFPoint)
        case circleRadius(index: Int, center: DXFPoint, layer: String, style: DXFEntityStyle)
        case moveEntity(index: Int, originalEntity: DXFEntity, anchor: DXFPoint)
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Use AppKit draw(_:) path directly for deterministic grid rendering.
        wantsLayer = false
        needsDisplay = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 1).cgColor)
        context.fill(bounds)

        drawGrid(in: context)
        drawEntities(in: context)
        drawPendingPreview(in: context)

        // Workspace frame so users always see the drafting canvas bounds.
        context.setStrokeColor(NSColor(calibratedWhite: 0.20, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isSpacePressed {
            beginPan(with: event)
            return
        }
        let rawWorld = viewToWorld(convert(event.locationInWindow, from: nil))
        let world = draftingPoint(rawWorld, anchor: pendingPoint)
        let clickPoint = convert(event.locationInWindow, from: nil)
        switch toolMode {
        case .select:
            if let hit = hitTestGrip(at: clickPoint) {
                selectedEntityIndex = hit.index
                dragMode = hit.dragMode
            } else if let index = hitTestEntity(at: clickPoint) {
                selectedEntityIndex = index
                dragMode = .moveEntity(index: index, originalEntity: document.entities[index], anchor: snapIfEnabled(rawWorld))
            } else {
                selectedEntityIndex = nil
                dragMode = .none
            }
        case .line:
            selectedEntityIndex = nil
            dragMode = .none
            if let start = pendingPoint {
                onLineCreated?(start, world)
                pendingPoint = nil
            } else {
                pendingPoint = world
            }
        case .circle:
            selectedEntityIndex = nil
            dragMode = .none
            if let center = pendingPoint {
                let radius = distance(center, world)
                if radius > 0.0001 {
                    onCircleCreated?(center, radius)
                }
                pendingPoint = nil
            } else {
                pendingPoint = world
            }
        case .rectangle:
            selectedEntityIndex = nil
            dragMode = .none
            if let cornerA = pendingPoint {
                onRectangleCreated?(cornerA, world)
                pendingPoint = nil
            } else {
                pendingPoint = world
            }
        case .polyline:
            selectedEntityIndex = nil
            dragMode = .none
            if let previous = pendingPoint {
                if distance(previous, world) > 0.0001 {
                    onPolylineSegmentCreated?(previous, world)
                    pendingPoint = world
                }
                if event.clickCount > 1 {
                    pendingPoint = nil
                }
            } else {
                pendingPoint = world
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanningCamera {
            updatePan(with: event)
            return
        }
        if toolMode == .select {
            let rawWorld = viewToWorld(convert(event.locationInWindow, from: nil))
            switch dragMode {
            case .none:
                break
            case let .lineStart(index, end, layer, style):
                let world = draftingPoint(rawWorld, anchor: end)
                replaceEntity(at: index, with: .line(start: world, end: end, layer: layer, style: style))
            case let .lineEnd(index, start, layer, style):
                let world = draftingPoint(rawWorld, anchor: start)
                replaceEntity(at: index, with: .line(start: start, end: world, layer: layer, style: style))
            case let .circleCenter(index, radius, layer, style, anchor, originalCenter):
                let world = snapIfEnabled(rawWorld)
                let dx = world.x - anchor.x
                let dy = world.y - anchor.y
                let newCenter = DXFPoint(x: originalCenter.x + dx, y: originalCenter.y + dy)
                replaceEntity(at: index, with: .circle(center: newCenter, radius: radius, layer: layer, style: style))
            case let .circleRadius(index, center, layer, style):
                let world = snapIfEnabled(rawWorld)
                let radius = max(1, distance(center, world))
                replaceEntity(at: index, with: .circle(center: center, radius: radius, layer: layer, style: style))
            case let .moveEntity(index, originalEntity, anchor):
                let world = snapIfEnabled(rawWorld)
                let dx = world.x - anchor.x
                let dy = world.y - anchor.y
                replaceEntity(at: index, with: translated(entity: originalEntity, dx: dx, dy: dy))
            }
            return
        }

        // Left-drag pan is only active while holding Space (AutoCAD-style temporary hand tool).
        if isSpacePressed {
            beginPan(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isPanningCamera {
            endPan()
            return
        }
        dragMode = .none
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        super.rightMouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            beginPan(with: event)
            return
        }
        super.otherMouseDown(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == 2, isPanningCamera {
            updatePan(with: event)
            return
        }
        super.otherMouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, isPanningCamera {
            endPan()
            return
        }
        super.otherMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // AutoCAD-like defaults: wheel zooms at cursor, modifiers can pan.
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift) {
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
            panOffset.x -= event.scrollingDeltaX * step
            panOffset.y -= event.scrollingDeltaY * step
            notifyViewTransformChanged()
            needsDisplay = true
            return
        }

        if event.hasPreciseScrollingDeltas {
            let factor = exp(event.deltaY * 0.0065)
            zoomAtViewPoint(location, factor: factor)
        } else {
            let factor: CGFloat = event.deltaY > 0 ? 1.12 : (1.0 / 1.12)
            zoomAtViewPoint(location, factor: factor)
        }
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let factor = 1.0 + event.magnification
        zoomAtViewPoint(location, factor: factor)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpacePressed = true
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            _ = deleteSelectedEntity()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if toolMode == .polyline {
                pendingPoint = nil
                needsDisplay = true
                return
            }
        }
        if event.keyCode == 53 {
            pendingPoint = nil
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpacePressed = false
            if isPanningCamera { endPan() }
            return
        }
        super.keyUp(with: event)
    }

    func resetView() {
        zoom = 1
        panOffset = .zero
        pendingPoint = nil
        notifyViewTransformChanged()
        needsDisplay = true
    }

    func zoomToExtents() {
        guard let extents = entityExtents() else {
            resetView()
            return
        }
        let width = max(1, extents.maxX - extents.minX)
        let height = max(1, extents.maxY - extents.minY)
        let fitX = bounds.width / width
        let fitY = bounds.height / height
        let targetZoom = max(minZoom, min(maxZoom, min(fitX, fitY) * 0.9))
        zoom = targetZoom
        let center = DXFPoint(x: (extents.minX + extents.maxX) * 0.5, y: (extents.minY + extents.maxY) * 0.5)
        panOffset.x = bounds.midX - center.x * zoom
        panOffset.y = bounds.midY - center.y * zoom
        pendingPoint = nil
        notifyViewTransformChanged()
        needsDisplay = true
    }

    func deleteSelectedEntity() -> Bool {
        guard let selectedEntityIndex, document.entities.indices.contains(selectedEntityIndex) else {
            return false
        }
        var next = document
        next.entities.remove(at: selectedEntityIndex)
        document = next
        self.selectedEntityIndex = nil
        onDocumentChanged?(next)
        return true
    }

    func configureDrafting(gridStep: CGFloat, snapStep: CGFloat, snapEnabled: Bool, orthoEnabled: Bool) {
        self.gridStep = max(0.1, gridStep)
        self.snapStep = max(0.1, snapStep)
        isSnapEnabled = snapEnabled
        isOrthoEnabled = orthoEnabled
        needsDisplay = true
    }

    private func drawGrid(in context: CGContext) {
        context.saveGState()
        let baseSpacing = max(1, gridStep * zoom)
        let spacingMultiplier = max(1, ceil(12 / baseSpacing))
        let minorSpacing: CGFloat = baseSpacing * spacingMultiplier
        guard minorSpacing > 6 else {
            context.restoreGState()
            return
        }
        let majorSpacing = minorSpacing * 5
        let originX = bounds.midX + panOffset.x
        let originY = bounds.midY + panOffset.y

        func drawVerticalGrid(spacing: CGFloat, color: NSColor, lineWidth: CGFloat) {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            var x = originX.truncatingRemainder(dividingBy: spacing)
            if x < 0 { x += spacing }
            while x <= bounds.maxX {
                context.move(to: CGPoint(x: x, y: bounds.minY))
                context.addLine(to: CGPoint(x: x, y: bounds.maxY))
                x += spacing
            }
            context.strokePath()
        }

        func drawHorizontalGrid(spacing: CGFloat, color: NSColor, lineWidth: CGFloat) {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            var y = originY.truncatingRemainder(dividingBy: spacing)
            if y < 0 { y += spacing }
            while y <= bounds.maxY {
                context.move(to: CGPoint(x: bounds.minX, y: y))
                context.addLine(to: CGPoint(x: bounds.maxX, y: y))
                y += spacing
            }
            context.strokePath()
        }

        drawVerticalGrid(spacing: minorSpacing, color: NSColor(calibratedWhite: 0.70, alpha: 0.16), lineWidth: 0.8)
        drawHorizontalGrid(spacing: minorSpacing, color: NSColor(calibratedWhite: 0.70, alpha: 0.16), lineWidth: 0.8)
        drawVerticalGrid(spacing: majorSpacing, color: NSColor(calibratedWhite: 0.72, alpha: 0.26), lineWidth: 1.0)
        drawHorizontalGrid(spacing: majorSpacing, color: NSColor(calibratedWhite: 0.72, alpha: 0.26), lineWidth: 1.0)

        context.setStrokeColor(NSColor(calibratedRed: 0.66, green: 0.82, blue: 1.0, alpha: 0.55).cgColor)
        context.setLineWidth(1.2)
        context.move(to: CGPoint(x: bounds.minX, y: originY))
        context.addLine(to: CGPoint(x: bounds.maxX, y: originY))
        context.move(to: CGPoint(x: originX, y: bounds.minY))
        context.addLine(to: CGPoint(x: originX, y: bounds.maxY))
        context.strokePath()
        context.restoreGState()
    }

    private func drawEntities(in context: CGContext) {
        context.saveGState()

        for (index, entity) in document.entities.enumerated() {
            if index == selectedEntityIndex {
                context.setStrokeColor(NSColor(calibratedRed: 0.62, green: 0.8, blue: 0.98, alpha: 1).cgColor)
                context.setLineWidth(1.8)
            } else {
                let layer: String
                let style: DXFEntityStyle
                switch entity {
                case let .line(_, _, l, s):
                    layer = l
                    style = s
                case let .circle(_, _, l, s):
                    layer = l
                    style = s
                }
                context.setStrokeColor(resolvedStrokeColor(entityStyle: style, layer: layer).cgColor)
                context.setLineWidth(resolvedStrokeWidth(entityStyle: style, layer: layer))
            }
            switch entity {
            case let .line(start, end, _, _):
                context.move(to: worldToView(start))
                context.addLine(to: worldToView(end))
                context.strokePath()
            case let .circle(center, radius, _, _):
                let c = worldToView(center)
                let vr = radius * zoom
                context.strokeEllipse(in: CGRect(x: c.x - vr, y: c.y - vr, width: vr * 2, height: vr * 2))
            }
        }
        context.restoreGState()
        drawSelectionGrips(in: context)
    }

    private func drawPendingPreview(in context: CGContext) {
        guard let pendingPoint else { return }
        context.saveGState()
        context.setStrokeColor(NSColor(calibratedRed: 0.62, green: 0.8, blue: 0.98, alpha: 1).cgColor)
        context.setLineWidth(1.2)
        let p = worldToView(pendingPoint)
        context.strokeEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        context.restoreGState()
    }

    private func worldToView(_ point: DXFPoint) -> CGPoint {
        CGPoint(
            x: bounds.midX + panOffset.x + point.x * zoom,
            y: bounds.midY + panOffset.y + point.y * zoom
        )
    }

    private func viewToWorld(_ point: CGPoint) -> DXFPoint {
        DXFPoint(
            x: (point.x - bounds.midX - panOffset.x) / zoom,
            y: (point.y - bounds.midY - panOffset.y) / zoom
        )
    }

    private func snapToStep(_ point: DXFPoint, step: CGFloat) -> DXFPoint {
        DXFPoint(
            x: (point.x / step).rounded() * step,
            y: (point.y / step).rounded() * step
        )
    }

    private func distance(_ a: DXFPoint, _ b: DXFPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }

    private func drawSelectionGrips(in context: CGContext) {
        guard let selectedEntityIndex, document.entities.indices.contains(selectedEntityIndex) else { return }
        context.saveGState()
        context.setFillColor(NSColor(calibratedRed: 0.62, green: 0.8, blue: 0.98, alpha: 1).cgColor)
        for handle in handles(for: document.entities[selectedEntityIndex]) {
            let p = worldToView(handle)
            context.fill(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }
        context.restoreGState()
    }

    private func handles(for entity: DXFEntity) -> [DXFPoint] {
        switch entity {
        case let .line(start, end, _, _):
            return [start, end]
        case let .circle(center, radius, _, _):
            return [center, DXFPoint(x: center.x + radius, y: center.y)]
        }
    }

    private func hitTestEntity(at viewPoint: CGPoint) -> Int? {
        let threshold: CGFloat = 8
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, entity) in document.entities.enumerated() {
            let d = distanceFromViewPoint(viewPoint, to: entity)
            if d < threshold, d < bestDistance {
                bestDistance = d
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func hitTestGrip(at viewPoint: CGPoint) -> (index: Int, dragMode: DragMode)? {
        guard let selectedEntityIndex, document.entities.indices.contains(selectedEntityIndex) else {
            return nil
        }
        let threshold: CGFloat = 10
        let entity = document.entities[selectedEntityIndex]
        switch entity {
        case let .line(start, end, layer, style):
            if pointDistance(viewPoint, worldToView(start)) <= threshold {
                return (selectedEntityIndex, .lineStart(index: selectedEntityIndex, end: end, layer: layer, style: style))
            }
            if pointDistance(viewPoint, worldToView(end)) <= threshold {
                return (selectedEntityIndex, .lineEnd(index: selectedEntityIndex, start: start, layer: layer, style: style))
            }
        case let .circle(center, radius, layer, style):
            if pointDistance(viewPoint, worldToView(center)) <= threshold {
                let anchor = snapIfEnabled(viewToWorld(viewPoint))
                return (
                    selectedEntityIndex,
                    .circleCenter(index: selectedEntityIndex, radius: radius, layer: layer, style: style, anchor: anchor, originalCenter: center)
                )
            }
            let radiusHandle = DXFPoint(x: center.x + radius, y: center.y)
            if pointDistance(viewPoint, worldToView(radiusHandle)) <= threshold {
                return (selectedEntityIndex, .circleRadius(index: selectedEntityIndex, center: center, layer: layer, style: style))
            }
        }
        return nil
    }

    private func distanceFromViewPoint(_ point: CGPoint, to entity: DXFEntity) -> CGFloat {
        switch entity {
        case let .line(start, end, _, _):
            return pointToSegmentDistance(point, worldToView(start), worldToView(end))
        case let .circle(center, radius, _, _):
            let c = worldToView(center)
            let vr = radius * zoom
            return abs(pointDistance(point, c) - vr)
        }
    }

    private func pointToSegmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let denom = abx * abx + aby * aby
        if denom < 0.0001 { return pointDistance(p, a) }
        let t = max(0, min(1, (apx * abx + apy * aby) / denom))
        let proj = CGPoint(x: a.x + abx * t, y: a.y + aby * t)
        return pointDistance(p, proj)
    }

    private func pointDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func replaceEntity(at index: Int, with entity: DXFEntity) {
        guard document.entities.indices.contains(index) else { return }
        var next = document
        next.entities[index] = entity
        document = next
        onDocumentChanged?(next)
    }

    private func translated(entity: DXFEntity, dx: CGFloat, dy: CGFloat) -> DXFEntity {
        switch entity {
        case let .line(start, end, layer, style):
            return .line(
                start: DXFPoint(x: start.x + dx, y: start.y + dy),
                end: DXFPoint(x: end.x + dx, y: end.y + dy),
                layer: layer,
                style: style
            )
        case let .circle(center, radius, layer, style):
            return .circle(center: DXFPoint(x: center.x + dx, y: center.y + dy), radius: radius, layer: layer, style: style)
        }
    }

    private func beginPan(with event: NSEvent) {
        isPanningCamera = true
        lastPanLocation = convert(event.locationInWindow, from: nil)
    }

    private func updatePan(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        panOffset.x += current.x - lastPanLocation.x
        panOffset.y += current.y - lastPanLocation.y
        lastPanLocation = current
        notifyViewTransformChanged()
        needsDisplay = true
    }

    private func endPan() {
        isPanningCamera = false
    }

    private func zoomAtViewPoint(_ viewPoint: CGPoint, factor: CGFloat) {
        let worldAnchor = viewToWorld(viewPoint)
        zoom = max(minZoom, min(maxZoom, zoom * factor))
        panOffset.x = viewPoint.x - bounds.midX - worldAnchor.x * zoom
        panOffset.y = viewPoint.y - bounds.midY - worldAnchor.y * zoom
        notifyViewTransformChanged()
        needsDisplay = true
    }

    private func snapIfEnabled(_ point: DXFPoint) -> DXFPoint {
        guard isSnapEnabled else { return point }
        return snapToStep(point, step: snapStep)
    }

    private func applyOrthoIfEnabled(_ point: DXFPoint, anchor: DXFPoint?) -> DXFPoint {
        guard isOrthoEnabled, let anchor else { return point }
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        if abs(dx) >= abs(dy) {
            return DXFPoint(x: point.x, y: anchor.y)
        }
        return DXFPoint(x: anchor.x, y: point.y)
    }

    private func draftingPoint(_ rawPoint: DXFPoint, anchor: DXFPoint?) -> DXFPoint {
        let orthoPoint = applyOrthoIfEnabled(rawPoint, anchor: anchor)
        return snapIfEnabled(orthoPoint)
    }

    private func notifyViewTransformChanged() {
        onViewTransformChanged?(zoom, panOffset)
    }

    private func entityExtents() -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat)? {
        guard !document.entities.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        func include(_ p: DXFPoint) {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }

        for entity in document.entities {
            switch entity {
            case let .line(start, end, _, _):
                include(start)
                include(end)
            case let .circle(center, radius, _, _):
                include(DXFPoint(x: center.x - radius, y: center.y - radius))
                include(DXFPoint(x: center.x + radius, y: center.y + radius))
            }
        }

        return (minX, minY, maxX, maxY)
    }

    private func resolvedStrokeColor(entityStyle: DXFEntityStyle, layer: String) -> NSColor {
        if let color = entityStyle.color {
            return NSColor(calibratedRed: color.r, green: color.g, blue: color.b, alpha: 1)
        }
        if let color = document.layerStyles[layer]?.color {
            return NSColor(calibratedRed: color.r, green: color.g, blue: color.b, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.9, alpha: 1)
    }

    private func resolvedStrokeWidth(entityStyle: DXFEntityStyle, layer: String) -> CGFloat {
        let mmWeight = entityStyle.lineWeight ?? document.layerStyles[layer]?.lineWeight ?? 0.25
        return max(0.8, mmWeight * 2.2)
    }
}
