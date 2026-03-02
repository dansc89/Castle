import AppKit

@MainActor
final class CADCanvasView: NSView {
    enum Workspace {
        case model
        case layout
    }

    enum ToolMode {
        case select
        case line
        case circle
        case rectangle
        case polyline
    }

    enum ObjectSnapMode: String, CaseIterable, Hashable {
        case endpoint
        case midpoint
        case center
        case intersection

        var label: String {
            switch self {
            case .endpoint: return "END"
            case .midpoint: return "MID"
            case .center: return "CEN"
            case .intersection: return "INT"
            }
        }
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
    var isObjectSnapEnabled: Bool = true
    var objectSnapModes: Set<ObjectSnapMode> = [.endpoint, .midpoint, .center, .intersection]
    var workspace: Workspace = .model {
        didSet { needsDisplay = true }
    }
    var activeLayout: LayoutSheet? {
        didSet {
            if let selectedViewportID,
               let activeLayout,
               !activeLayout.viewports.contains(where: { $0.id == selectedViewportID }) {
                self.selectedViewportID = nil
            }
            needsDisplay = true
        }
    }
    var onLayoutChanged: ((LayoutSheet) -> Void)?

    private var zoom: CGFloat = 1.0
    private var panOffset = CGPoint.zero
    private var pendingPoint: DXFPoint?
    private var lastMouseWorld = DXFPoint(x: 1, y: 0)
    private var lastDirectionVector = CGVector(dx: 1, dy: 0)
    private var selectedEntityIndex: Int?
    private var dragMode: DragMode = .none
    private var hasPendingDragCommit = false
    private var selectedViewportID: UUID?
    private var layoutDragMode: LayoutDragMode = .none
    private var layoutPreviewPaperRect: CGRect?
    private var hasPendingLayoutCommit = false
    private var isPanningCamera = false
    private var lastPanLocation = CGPoint.zero
    private var isSpacePressed = false
    private var mouseTrackingArea: NSTrackingArea?
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

    private enum LayoutDragMode {
        case none
        case create(anchorViewPoint: CGPoint)
        case move(viewportID: UUID, anchorViewPoint: CGPoint, originalRect: CGRect)
        case panModel(viewportID: UUID, anchorViewPoint: CGPoint, originalCenter: DXFPoint, modelUnitsPerPixel: CGFloat)
        case resize(viewportID: UUID, handle: LayoutHandle, anchorViewPoint: CGPoint, originalRect: CGRect)
    }

    private enum LayoutHandle {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
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

    override func updateTrackingAreas() {
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        mouseTrackingArea = area
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NordTheme.polarNight0.cgColor)
        context.fill(bounds)

        if workspace == .layout {
            drawLayoutSheet(in: context)
        } else {
            drawGrid(in: context)
            drawEntities(in: context)
            drawPendingPreview(in: context)
        }

        // Workspace frame so users always see the drafting canvas bounds.
        context.setStrokeColor(NordTheme.polarNight3.cgColor)
        context.setLineWidth(1)
        context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard workspace == .model else {
            handleLayoutMouseDown(event)
            return
        }
        if isSpacePressed {
            beginPan(with: event)
            return
        }
        let rawWorld = viewToWorld(convert(event.locationInWindow, from: nil))
        lastMouseWorld = rawWorld
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
        guard workspace == .model else {
            handleLayoutMouseDragged(event)
            return
        }
        if isPanningCamera {
            updatePan(with: event)
            return
        }
        if toolMode == .select {
            let rawWorld = viewToWorld(convert(event.locationInWindow, from: nil))
            lastMouseWorld = rawWorld
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

    override func mouseMoved(with event: NSEvent) {
        guard workspace == .model else { return }
        let rawWorld = viewToWorld(convert(event.locationInWindow, from: nil))
        lastMouseWorld = rawWorld
    }

    override func mouseUp(with event: NSEvent) {
        guard workspace == .model else {
            handleLayoutMouseUp(event)
            return
        }
        if isPanningCamera {
            endPan()
            return
        }
        if hasPendingDragCommit {
            hasPendingDragCommit = false
            onDocumentChanged?(document)
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
        guard workspace == .model else { return }
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
        guard workspace == .model else { return }
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
        if isEntityLocked(document.entities[selectedEntityIndex]) {
            NSSound.beep()
            return false
        }
        var next = document
        next.entities.remove(at: selectedEntityIndex)
        document = next
        self.selectedEntityIndex = nil
        onDocumentChanged?(next)
        return true
    }

    func hasPendingLineInput() -> Bool {
        pendingPoint != nil && (toolMode == .line || toolMode == .polyline)
    }

    @discardableResult
    func completePendingSegment(withDistance distance: CGFloat) -> Bool {
        guard distance > 0.0001, workspace == .model, let start = pendingPoint else { return false }
        guard toolMode == .line || toolMode == .polyline else { return false }

        let dirTarget = applyOrthoIfEnabled(lastMouseWorld, anchor: start)
        var dx = dirTarget.x - start.x
        var dy = dirTarget.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        if length <= 0.0001 {
            dx = lastDirectionVector.dx
            dy = lastDirectionVector.dy
        } else {
            dx /= length
            dy /= length
            lastDirectionVector = CGVector(dx: dx, dy: dy)
        }

        var end = DXFPoint(x: start.x + dx * distance, y: start.y + dy * distance)
        end = snapIfEnabled(end)

        if toolMode == .line {
            onLineCreated?(start, end)
            pendingPoint = nil
        } else {
            onPolylineSegmentCreated?(start, end)
            pendingPoint = end
        }
        needsDisplay = true
        return true
    }

    @discardableResult
    func cancelActiveOperation() -> Bool {
        var didCancel = false
        if pendingPoint != nil {
            pendingPoint = nil
            didCancel = true
        }
        if case .none = dragMode {
            // no-op
        } else {
            dragMode = .none
            hasPendingDragCommit = false
            didCancel = true
        }
        if isPanningCamera {
            endPan()
            didCancel = true
        }
        if didCancel {
            needsDisplay = true
        }
        return didCancel
    }

    func selectedEntityInfo() -> (index: Int, entity: DXFEntity)? {
        guard let selectedEntityIndex, document.entities.indices.contains(selectedEntityIndex) else {
            return nil
        }
        return (selectedEntityIndex, document.entities[selectedEntityIndex])
    }

    @discardableResult
    func selectEntity(at index: Int?) -> Bool {
        guard let index else {
            selectedEntityIndex = nil
            needsDisplay = true
            return true
        }
        guard document.entities.indices.contains(index) else {
            NSSound.beep()
            return false
        }
        selectedEntityIndex = index
        needsDisplay = true
        return true
    }

    @discardableResult
    func selectLastEntity() -> Bool {
        guard !document.entities.isEmpty else {
            NSSound.beep()
            return false
        }
        return selectEntity(at: document.entities.count - 1)
    }

    @discardableResult
    func selectNextEntity() -> Bool {
        guard !document.entities.isEmpty else {
            NSSound.beep()
            return false
        }
        let next: Int
        if let selectedEntityIndex {
            next = (selectedEntityIndex + 1) % document.entities.count
        } else {
            next = 0
        }
        return selectEntity(at: next)
    }

    @discardableResult
    func selectPreviousEntity() -> Bool {
        guard !document.entities.isEmpty else {
            NSSound.beep()
            return false
        }
        let previous: Int
        if let selectedEntityIndex {
            previous = (selectedEntityIndex - 1 + document.entities.count) % document.entities.count
        } else {
            previous = document.entities.count - 1
        }
        return selectEntity(at: previous)
    }

    func configureDrafting(
        gridStep: CGFloat,
        snapStep: CGFloat,
        snapEnabled: Bool,
        orthoEnabled: Bool,
        objectSnapEnabled: Bool,
        objectSnapModes: Set<ObjectSnapMode>
    ) {
        self.gridStep = max(0.1, gridStep)
        self.snapStep = max(0.1, snapStep)
        isSnapEnabled = snapEnabled
        isOrthoEnabled = orthoEnabled
        isObjectSnapEnabled = objectSnapEnabled
        self.objectSnapModes = objectSnapModes
        needsDisplay = true
    }

    private func drawLayoutSheet(in context: CGContext) {
        guard let activeLayout else { return }
        let paper = activeLayout.size.inches
        let sheetRect = fittedSheetRect(sizeInInches: paper)
        guard sheetRect.width > 2, sheetRect.height > 2 else { return }

        context.saveGState()
        context.setFillColor(NordTheme.snowStorm2.cgColor)
        context.fill(sheetRect)
        context.setStrokeColor(NordTheme.polarNight3.cgColor)
        context.setLineWidth(1.2)
        context.stroke(sheetRect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()

        for viewport in activeLayout.viewports {
            let viewportRect = paperRectToViewRect(viewport.rectInPaperInches, sheetRect: sheetRect, paperSize: paper)
            guard viewportRect.width > 4, viewportRect.height > 4 else { continue }

            context.saveGState()
            context.addRect(viewportRect)
            context.clip()
            drawModelEntities(in: context, viewportRect: viewportRect, viewport: viewport)
            context.restoreGState()

            context.saveGState()
            context.setStrokeColor(NordTheme.frost3.cgColor)
            context.setLineWidth(1.2)
            context.stroke(viewportRect.insetBy(dx: 0.5, dy: 0.5))
            context.restoreGState()
        }
        drawSelectedViewportGrips(in: context, layout: activeLayout, sheetRect: sheetRect, paperSize: paper)
        drawLayoutPreview(in: context, sheetRect: sheetRect, paperSize: paper)
    }

    private func drawSelectedViewportGrips(in context: CGContext, layout: LayoutSheet, sheetRect: CGRect, paperSize: CGSize) {
        guard let selectedViewportID,
              let viewport = layout.viewports.first(where: { $0.id == selectedViewportID }) else { return }
        let rect = paperRectToViewRect(viewport.rectInPaperInches, sheetRect: sheetRect, paperSize: paperSize)
        let handles = layoutHandlePoints(for: rect)
        context.saveGState()
        context.setFillColor(NordTheme.frost1.cgColor)
        for p in handles {
            context.fill(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }
        context.restoreGState()
    }

    private func drawLayoutPreview(in context: CGContext, sheetRect: CGRect, paperSize: CGSize) {
        guard let layoutPreviewPaperRect else { return }
        let rect = paperRectToViewRect(layoutPreviewPaperRect, sheetRect: sheetRect, paperSize: paperSize)
        context.saveGState()
        context.setStrokeColor(NordTheme.frost1.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawModelEntities(in context: CGContext, viewportRect: CGRect, viewport: LayoutViewport) {
        let pxPerPaperInch = viewportRect.width / max(0.001, viewport.rectInPaperInches.width)
        let modelUnitsPerPaperInch = max(0.0001, viewport.scale.modelUnitsPerPaperInch)
        let modelUnitsToPx = pxPerPaperInch / modelUnitsPerPaperInch

        for entity in document.entities {
            if !isEntityVisible(entity) { continue }
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
            context.setLineWidth(1.0)
            switch entity {
            case let .line(start, end, _, _):
                context.move(to: modelPointToLayoutView(start, viewportRect: viewportRect, viewport: viewport, scale: modelUnitsToPx))
                context.addLine(to: modelPointToLayoutView(end, viewportRect: viewportRect, viewport: viewport, scale: modelUnitsToPx))
                context.strokePath()
            case let .circle(center, radius, _, _):
                let c = modelPointToLayoutView(center, viewportRect: viewportRect, viewport: viewport, scale: modelUnitsToPx)
                let vr = radius * modelUnitsToPx
                context.strokeEllipse(in: CGRect(x: c.x - vr, y: c.y - vr, width: vr * 2, height: vr * 2))
            }
        }
    }

    private func modelPointToLayoutView(_ p: DXFPoint, viewportRect: CGRect, viewport: LayoutViewport, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: viewportRect.midX + (p.x - viewport.modelCenter.x) * scale,
            y: viewportRect.midY + (p.y - viewport.modelCenter.y) * scale
        )
    }

    private func fittedSheetRect(sizeInInches: CGSize) -> CGRect {
        let margin: CGFloat = 36
        let maxRect = bounds.insetBy(dx: margin, dy: margin)
        guard sizeInInches.width > 0, sizeInInches.height > 0, maxRect.width > 0, maxRect.height > 0 else {
            return .zero
        }
        let sx = maxRect.width / sizeInInches.width
        let sy = maxRect.height / sizeInInches.height
        let scale = min(sx, sy)
        let w = sizeInInches.width * scale
        let h = sizeInInches.height * scale
        return CGRect(x: maxRect.midX - w * 0.5, y: maxRect.midY - h * 0.5, width: w, height: h)
    }

    private func layoutHandlePoints(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY)
        ]
    }

    private func layoutContext() -> (layout: LayoutSheet, paperSize: CGSize, sheetRect: CGRect)? {
        guard let layout = activeLayout else { return nil }
        let paperSize = layout.size.inches
        let sheetRect = fittedSheetRect(sizeInInches: paperSize)
        guard sheetRect.width > 1, sheetRect.height > 1 else { return nil }
        return (layout, paperSize, sheetRect)
    }

    private func hitTestLayoutViewport(_ point: CGPoint, layout: LayoutSheet, paperSize: CGSize, sheetRect: CGRect) -> UUID? {
        for viewport in layout.viewports.reversed() {
            let rect = paperRectToViewRect(viewport.rectInPaperInches, sheetRect: sheetRect, paperSize: paperSize)
            if rect.contains(point) { return viewport.id }
        }
        return nil
    }

    private func hitTestLayoutGrip(_ point: CGPoint, layout: LayoutSheet, paperSize: CGSize, sheetRect: CGRect) -> (viewportID: UUID, handle: LayoutHandle)? {
        guard let selectedViewportID,
              let viewport = layout.viewports.first(where: { $0.id == selectedViewportID }) else { return nil }
        let rect = paperRectToViewRect(viewport.rectInPaperInches, sheetRect: sheetRect, paperSize: paperSize)
        let handles: [(LayoutHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY))
        ]
        for (handle, hp) in handles {
            if pointDistance(point, hp) <= 10 {
                return (selectedViewportID, handle)
            }
        }
        return nil
    }

    private func viewPointToPaperPoint(_ point: CGPoint, paperSize: CGSize, sheetRect: CGRect) -> CGPoint {
        let px = (point.x - sheetRect.minX) / max(0.001, sheetRect.width)
        let py = (point.y - sheetRect.minY) / max(0.001, sheetRect.height)
        return CGPoint(x: px * paperSize.width, y: py * paperSize.height)
    }

    private func clampPaperPoint(_ point: CGPoint, paperSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), paperSize.width),
            y: min(max(0, point.y), paperSize.height)
        )
    }

    private func handleLayoutMouseDown(_ event: NSEvent) {
        guard let ctx = layoutContext() else { return }
        let point = convert(event.locationInWindow, from: nil)

        if let grip = hitTestLayoutGrip(point, layout: ctx.layout, paperSize: ctx.paperSize, sheetRect: ctx.sheetRect),
           let viewport = ctx.layout.viewports.first(where: { $0.id == grip.viewportID }) {
            layoutDragMode = .resize(
                viewportID: grip.viewportID,
                handle: grip.handle,
                anchorViewPoint: point,
                originalRect: viewport.rectInPaperInches
            )
            return
        }

        if let viewportID = hitTestLayoutViewport(point, layout: ctx.layout, paperSize: ctx.paperSize, sheetRect: ctx.sheetRect),
           let viewport = ctx.layout.viewports.first(where: { $0.id == viewportID }) {
            selectedViewportID = viewportID
            if event.modifierFlags.contains(.option) {
                let viewRect = paperRectToViewRect(viewport.rectInPaperInches, sheetRect: ctx.sheetRect, paperSize: ctx.paperSize)
                let pxPerPaperInch = viewRect.width / max(0.001, viewport.rectInPaperInches.width)
                let modelUnitsPerPixel = viewport.scale.modelUnitsPerPaperInch / max(0.0001, pxPerPaperInch)
                layoutDragMode = .panModel(
                    viewportID: viewportID,
                    anchorViewPoint: point,
                    originalCenter: viewport.modelCenter,
                    modelUnitsPerPixel: modelUnitsPerPixel
                )
            } else {
                layoutDragMode = .move(
                    viewportID: viewportID,
                    anchorViewPoint: point,
                    originalRect: viewport.rectInPaperInches
                )
            }
            needsDisplay = true
            return
        }

        selectedViewportID = nil
        layoutPreviewPaperRect = nil
        layoutDragMode = .create(anchorViewPoint: point)
        needsDisplay = true
    }

    private func handleLayoutMouseDragged(_ event: NSEvent) {
        guard var layout = activeLayout, let ctx = layoutContext() else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch layoutDragMode {
        case .none:
            return
        case let .create(anchorViewPoint):
            let p1 = clampPaperPoint(viewPointToPaperPoint(anchorViewPoint, paperSize: ctx.paperSize, sheetRect: ctx.sheetRect), paperSize: ctx.paperSize)
            let p2 = clampPaperPoint(viewPointToPaperPoint(point, paperSize: ctx.paperSize, sheetRect: ctx.sheetRect), paperSize: ctx.paperSize)
            layoutPreviewPaperRect = CGRect(
                x: min(p1.x, p2.x),
                y: min(p1.y, p2.y),
                width: abs(p2.x - p1.x),
                height: abs(p2.y - p1.y)
            )
            needsDisplay = true
        case let .move(viewportID, anchorViewPoint, originalRect):
            let anchorPaper = viewPointToPaperPoint(anchorViewPoint, paperSize: ctx.paperSize, sheetRect: ctx.sheetRect)
            let currentPaper = viewPointToPaperPoint(point, paperSize: ctx.paperSize, sheetRect: ctx.sheetRect)
            let dx = currentPaper.x - anchorPaper.x
            let dy = currentPaper.y - anchorPaper.y
            if let index = layout.viewports.firstIndex(where: { $0.id == viewportID }) {
                var rect = originalRect.offsetBy(dx: dx, dy: dy)
                rect.origin.x = min(max(0, rect.origin.x), ctx.paperSize.width - rect.width)
                rect.origin.y = min(max(0, rect.origin.y), ctx.paperSize.height - rect.height)
                layout.viewports[index].rectInPaperInches = rect
                activeLayout = layout
                hasPendingLayoutCommit = true
                needsDisplay = true
            }
        case let .panModel(viewportID, anchorViewPoint, originalCenter, modelUnitsPerPixel):
            if let index = layout.viewports.firstIndex(where: { $0.id == viewportID }) {
                let dx = point.x - anchorViewPoint.x
                let dy = point.y - anchorViewPoint.y
                layout.viewports[index].modelCenter = DXFPoint(
                    x: originalCenter.x - dx * modelUnitsPerPixel,
                    y: originalCenter.y - dy * modelUnitsPerPixel
                )
                activeLayout = layout
                hasPendingLayoutCommit = true
                needsDisplay = true
            }
        case let .resize(viewportID, handle, _, originalRect):
            if let index = layout.viewports.firstIndex(where: { $0.id == viewportID }) {
                let currentPaper = clampPaperPoint(viewPointToPaperPoint(point, paperSize: ctx.paperSize, sheetRect: ctx.sheetRect), paperSize: ctx.paperSize)
                var minX = originalRect.minX
                var minY = originalRect.minY
                var maxX = originalRect.maxX
                var maxY = originalRect.maxY
                switch handle {
                case .topLeft:
                    minX = currentPaper.x
                    maxY = currentPaper.y
                case .topRight:
                    maxX = currentPaper.x
                    maxY = currentPaper.y
                case .bottomLeft:
                    minX = currentPaper.x
                    minY = currentPaper.y
                case .bottomRight:
                    maxX = currentPaper.x
                    minY = currentPaper.y
                }
                let clampedMinX = min(max(0, minX), ctx.paperSize.width)
                let clampedMaxX = min(max(0, maxX), ctx.paperSize.width)
                let clampedMinY = min(max(0, minY), ctx.paperSize.height)
                let clampedMaxY = min(max(0, maxY), ctx.paperSize.height)
                var rect = CGRect(
                    x: min(clampedMinX, clampedMaxX),
                    y: min(clampedMinY, clampedMaxY),
                    width: abs(clampedMaxX - clampedMinX),
                    height: abs(clampedMaxY - clampedMinY)
                )
                if rect.width < 0.25 { rect.size.width = 0.25 }
                if rect.height < 0.25 { rect.size.height = 0.25 }
                layout.viewports[index].rectInPaperInches = rect
                activeLayout = layout
                hasPendingLayoutCommit = true
                needsDisplay = true
            }
        }
    }

    private func handleLayoutMouseUp(_ event: NSEvent) {
        defer {
            layoutDragMode = .none
        }
        guard var layout = activeLayout else { return }

        if case .create = layoutDragMode,
           let preview = layoutPreviewPaperRect,
           preview.width > 0.1,
           preview.height > 0.1 {
            let viewport = LayoutViewport(
                rectInPaperInches: preview,
                modelCenter: .init(x: 0, y: 0),
                scale: .eighthInch
            )
            layout.viewports.append(viewport)
            selectedViewportID = viewport.id
            layoutPreviewPaperRect = nil
            hasPendingLayoutCommit = true
            activeLayout = layout
        } else {
            layoutPreviewPaperRect = nil
        }

        if hasPendingLayoutCommit, let activeLayout {
            hasPendingLayoutCommit = false
            onLayoutChanged?(activeLayout)
        }
        needsDisplay = true
    }

    private func paperRectToViewRect(_ paperRect: CGRect, sheetRect: CGRect, paperSize: CGSize) -> CGRect {
        let sx = sheetRect.width / max(0.001, paperSize.width)
        let sy = sheetRect.height / max(0.001, paperSize.height)
        return CGRect(
            x: sheetRect.minX + paperRect.minX * sx,
            y: sheetRect.minY + paperRect.minY * sy,
            width: paperRect.width * sx,
            height: paperRect.height * sy
        )
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

        drawVerticalGrid(spacing: minorSpacing, color: NordTheme.snowStorm2.withAlphaComponent(0.12), lineWidth: 0.8)
        drawHorizontalGrid(spacing: minorSpacing, color: NordTheme.snowStorm2.withAlphaComponent(0.12), lineWidth: 0.8)
        drawVerticalGrid(spacing: majorSpacing, color: NordTheme.snowStorm1.withAlphaComponent(0.2), lineWidth: 1.0)
        drawHorizontalGrid(spacing: majorSpacing, color: NordTheme.snowStorm1.withAlphaComponent(0.2), lineWidth: 1.0)

        context.setStrokeColor(NordTheme.frost2.withAlphaComponent(0.5).cgColor)
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
            if !isEntityVisible(entity) { continue }
            if index == selectedEntityIndex {
                context.setStrokeColor(NordTheme.frost1.cgColor)
                context.setLineWidth(1.8)
                context.setLineDash(phase: 0, lengths: [])
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
                context.setLineDash(phase: 0, lengths: resolvedLineDash(entityStyle: style, layer: layer))
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
        context.setStrokeColor(NordTheme.frost1.cgColor)
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
        context.setFillColor(NordTheme.frost1.cgColor)
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
            if !isEntityVisible(entity) { continue }
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
        if isEntityLocked(document.entities[index]) { return }
        var next = document
        next.entities[index] = entity
        guard next != document else { return }
        document = next
        hasPendingDragCommit = true
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
        if let snapped = objectSnapPoint(near: orthoPoint) {
            return snapped
        }
        return snapIfEnabled(orthoPoint)
    }

    private func objectSnapPoint(near point: DXFPoint) -> DXFPoint? {
        guard isObjectSnapEnabled, !objectSnapModes.isEmpty else { return nil }
        let threshold = 12 / max(0.001, zoom)
        var best: (point: DXFPoint, distance: CGFloat)?
        for candidate in objectSnapCandidates() {
            let d = distance(point, candidate)
            if d <= threshold, (best == nil || d < best!.distance) {
                best = (candidate, d)
            }
        }
        return best?.point
    }

    private func objectSnapCandidates() -> [DXFPoint] {
        var candidates: [DXFPoint] = []
        var lineSegments: [(DXFPoint, DXFPoint)] = []
        for entity in document.entities {
            if !isEntityVisible(entity) { continue }
            switch entity {
            case let .line(start, end, _, _):
                if objectSnapModes.contains(.endpoint) {
                    candidates.append(start)
                    candidates.append(end)
                }
                if objectSnapModes.contains(.midpoint) {
                    candidates.append(DXFPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5))
                }
                if objectSnapModes.contains(.intersection) {
                    lineSegments.append((start, end))
                }
            case let .circle(center, _, _, _):
                if objectSnapModes.contains(.center) {
                    candidates.append(center)
                }
            }
        }
        if objectSnapModes.contains(.intersection), lineSegments.count >= 2 {
            for i in 0..<(lineSegments.count - 1) {
                for j in (i + 1)..<lineSegments.count {
                    if let intersection = lineSegmentIntersection(lineSegments[i].0, lineSegments[i].1, lineSegments[j].0, lineSegments[j].1) {
                        candidates.append(intersection)
                    }
                }
            }
        }
        return candidates
    }

    private func lineSegmentIntersection(_ p1: DXFPoint, _ p2: DXFPoint, _ q1: DXFPoint, _ q2: DXFPoint) -> DXFPoint? {
        let r = DXFPoint(x: p2.x - p1.x, y: p2.y - p1.y)
        let s = DXFPoint(x: q2.x - q1.x, y: q2.y - q1.y)
        let denom = r.x * s.y - r.y * s.x
        if abs(denom) < 0.000001 { return nil }
        let qp = DXFPoint(x: q1.x - p1.x, y: q1.y - p1.y)
        let t = (qp.x * s.y - qp.y * s.x) / denom
        let u = (qp.x * r.y - qp.y * r.x) / denom
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return DXFPoint(x: p1.x + t * r.x, y: p1.y + t * r.y)
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
            if !isEntityVisible(entity) { continue }
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

    private func isEntityVisible(_ entity: DXFEntity) -> Bool {
        let layer = entityLayer(entity)
        let style = document.layerStyles[layer]
        let isOn = style?.isVisible ?? true
        let isFrozen = style?.isFrozen ?? false
        return isOn && !isFrozen
    }

    private func isEntityLocked(_ entity: DXFEntity) -> Bool {
        let layer = entityLayer(entity)
        let style = document.layerStyles[layer]
        return (style?.isLocked ?? false) || (style?.isFrozen ?? false)
    }

    private func entityLayer(_ entity: DXFEntity) -> String {
        switch entity {
        case let .line(_, _, layer, _):
            return layer
        case let .circle(_, _, layer, _):
            return layer
        }
    }

    private func resolvedStrokeColor(entityStyle: DXFEntityStyle, layer: String) -> NSColor {
        if let color = entityStyle.color {
            return NSColor(calibratedRed: color.r, green: color.g, blue: color.b, alpha: 1)
        }
        if let color = document.layerStyles[layer]?.color {
            return NSColor(calibratedRed: color.r, green: color.g, blue: color.b, alpha: 1)
        }
        return NordTheme.snowStorm0
    }

    private func resolvedStrokeWidth(entityStyle: DXFEntityStyle, layer: String) -> CGFloat {
        let mmWeight = entityStyle.lineWeight ?? document.layerStyles[layer]?.lineWeight ?? 0.25
        return max(0.8, mmWeight * 2.2)
    }

    private func resolvedLineDash(entityStyle: DXFEntityStyle, layer: String) -> [CGFloat] {
        let lineType = entityStyle.lineType ?? document.layerStyles[layer]?.lineType ?? .continuous
        switch lineType {
        case .continuous:
            return []
        case .dashed:
            return [12, 8]
        case .dotted:
            return [2, 6]
        case .dashDot:
            return [12, 6, 2, 6]
        }
    }
}
