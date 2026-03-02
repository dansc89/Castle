import AppKit

@MainActor
final class MainViewController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let headerTitleLabel = NSTextField(labelWithString: "Castle")
    private let documentTabButton = NSButton(title: "Untitled", target: nil, action: nil)
    private let summaryLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let statusNavLabel = NSTextField(labelWithString: "")
    private let statusDocLabel = NSTextField(labelWithString: "")
    private let inspectorTitleLabel = NSTextField(labelWithString: "Inspector")
    private let entityBreakdownLabel = NSTextField(labelWithString: "")
    private let layersPanelTitleLabel = NSTextField(labelWithString: "Layers")
    private let propertiesPanelTitleLabel = NSTextField(labelWithString: "Properties")
    private let propertiesLabel = NSTextField(labelWithString: "")
    private let layerTableView = NSTableView()
    private let layerTableScrollView = NSScrollView()
    private var inspectorLayers: [String] = []

    private let canvasView = CADCanvasView()
    private let selectToolButton = NSButton(title: "Select  V", target: nil, action: nil)
    private let lineToolButton = NSButton(title: "Line  L", target: nil, action: nil)
    private let polylineToolButton = NSButton(title: "Polyline  ⇧P", target: nil, action: nil)
    private let rectToolButton = NSButton(title: "Rect  R", target: nil, action: nil)
    private let circleToolButton = NSButton(title: "Circle  E", target: nil, action: nil)
    private let resetViewButton = NSButton(title: "Reset View", target: nil, action: nil)
    private let unitsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gridPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let snapPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let layerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let layerOnButton = NSButton(title: "ON", target: nil, action: nil)
    private let layerLockButton = NSButton(title: "LOCK", target: nil, action: nil)
    private let layerFreezeButton = NSButton(title: "FRZ", target: nil, action: nil)
    private let lineTypePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let lineWeightPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let snapToggle = NSButton(checkboxWithTitle: "Snap", target: nil, action: nil)
    private let orthoToggle = NSButton(checkboxWithTitle: "Ortho", target: nil, action: nil)
    private let commandLabel = NSTextField(labelWithString: "Command")
    private let commandField = NSTextField(string: "")
    private let spaceTabs = NSSegmentedControl(labels: ["Model", "Layout"], trackingMode: .selectOne, target: nil, action: nil)
    private let osnapMasterButton = NSButton(checkboxWithTitle: "OSNAP", target: nil, action: nil)
    private let osnapEndButton = NSButton(title: "END", target: nil, action: nil)
    private let osnapMidButton = NSButton(title: "MID", target: nil, action: nil)
    private let osnapCenterButton = NSButton(title: "CEN", target: nil, action: nil)
    private let osnapIntButton = NSButton(title: "INT", target: nil, action: nil)
    private let splitView = NSSplitView()
    private let inspectorWidth: CGFloat = 340
    private var sourcePanel: NSPanel?
    private let sourceTextView = NSTextView()
    private let gridStepValues: [CGFloat] = [1, 2, 5, 10, 25, 50, 100]
    private let snapStepValues: [CGFloat] = [0.5, 1, 2, 5, 10, 25]
    private var currentGridStep: CGFloat = 10
    private var currentSnapStep: CGFloat = 5
    private var isSnapEnabled = true
    private var isOrthoEnabled = false
    private var isObjectSnapEnabled = true
    private var objectSnapModes: Set<CADCanvasView.ObjectSnapMode> = [.endpoint, .midpoint, .center, .intersection]
    private var currentLayer = "0"
    private var currentEntityLineType: DXFLineType? = nil
    private var currentEntityColor: DXFColor? = nil
    private var currentEntityLineWeight: CGFloat? = nil
    private var layouts: [LayoutSheet] = [LayoutSheet(name: "Layout1", size: .archD)]
    private var activeLayoutID: UUID?
    private var isInLayoutSpace = false
    private var commandBasePoint = DXFPoint(x: 0, y: 0)
    private var undoStack: [DXFDocument] = []
    private var redoStack: [DXFDocument] = []
    private let maxHistoryDepth = 300
    private var isAutoCompletingCommand = false
    private var suppressCommandHistoryPopup = false
    private var commandHistory: [String] = []
    private let maxCommandHistory = 200
    private var historyCursorFromNewest: Int?
    private var draftCommandBeforeHistory = ""
    private var lastEscapeTimestamp: TimeInterval = 0
    private var escapePressCount = 0
    private let commandAliasMap: [String: String] = [
        "l": "line",
        "c": "circle",
        "co": "copy",
        "m": "move",
        "v": "select",
        "u": "undo",
        "z": "zoom",
        "os": "osnap",
        "la": "layer",
        "frz": "layfrz",
        "thw": "laythw",
        "col": "color",
        "lt": "linetype",
        "lw": "lineweight",
        "pl": "pline",
        "rec": "rect",
        "mv": "mview",
        "vp": "mview"
    ]
    private let commandVocabulary: [String] = [
        "line", "circle", "rect", "rectangle", "pline", "polyline", "move", "copy",
        "layer", "color", "linetype", "lineweight", "select", "zoom", "grid", "snap", "osnap",
        "ortho", "units", "undo", "redo", "erase", "delete", "new", "layout", "model",
        "layfrz", "laythw", "freeze", "thaw",
        "mview", "vpscale", "pagesetup"
    ]

    private(set) var document: DXFDocument = .empty {
        didSet {
            canvasView.document = document
            refreshUI()
        }
    }

    override func loadView() {
        let dropView = DXFDropHostView()
        dropView.onDropDrawing = { url, sourceWindow in
            (NSApp.delegate as? AppDelegate)?.openDocumentFromDrop(url, sourceWindow: sourceWindow)
        }
        view = dropView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        wireCanvasCallbacks()
        activeLayoutID = layouts.first?.id
        setDocumentBaseline(.empty)
        applyDraftingSettings()
        applyWorkspace()
        updateNavigationStatus(zoom: 1.0, pan: .zero)
    }

    func newDocument() {
        setDocumentBaseline(.empty)
    }

    func loadDocument(from url: URL) throws {
        let data = try Data(contentsOf: url)
        setDocumentBaseline(try DXFCodec.parse(data: data, defaultName: url.deletingPathExtension().lastPathComponent))
        DispatchQueue.main.async { [weak self] in
            self?.canvasView.zoomToExtents()
        }
    }

    func saveDocument(to url: URL) throws {
        let text = DXFCodec.serialize(document: document)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    func publishPDF(to url: URL) throws {
        try PDFPublisher.publish(document: document, to: url)
    }

    private var currentEntityStyle: DXFEntityStyle {
        DXFEntityStyle(color: currentEntityColor, lineWeight: currentEntityLineWeight, lineType: currentEntityLineType)
    }

    func appendLine(start: DXFPoint, end: DXFPoint, layer: String? = nil) {
        let resolvedLayer = normalizedLayerName(layer)
        var next = document
        ensureLayerExists(named: resolvedLayer, in: &next)
        next.entities.append(.line(start: start, end: end, layer: resolvedLayer, style: currentEntityStyle))
        commitDocumentChange(next)
    }

    func appendCircle(center: DXFPoint, radius: CGFloat, layer: String? = nil) {
        let resolvedLayer = normalizedLayerName(layer)
        var next = document
        ensureLayerExists(named: resolvedLayer, in: &next)
        next.entities.append(.circle(center: center, radius: radius, layer: resolvedLayer, style: currentEntityStyle))
        commitDocumentChange(next)
    }

    func appendRectangle(cornerA: DXFPoint, cornerB: DXFPoint, layer: String? = nil) {
        let resolvedLayer = normalizedLayerName(layer)
        let p1 = cornerA
        let p2 = DXFPoint(x: cornerB.x, y: cornerA.y)
        let p3 = cornerB
        let p4 = DXFPoint(x: cornerA.x, y: cornerB.y)
        appendLine(start: p1, end: p2, layer: resolvedLayer)
        appendLine(start: p2, end: p3, layer: resolvedLayer)
        appendLine(start: p3, end: p4, layer: resolvedLayer)
        appendLine(start: p4, end: p1, layer: resolvedLayer)
    }

    func appendPolylineSegment(start: DXFPoint, end: DXFPoint, layer: String? = nil) {
        appendLine(start: start, end: end, layer: layer)
    }

    @discardableResult
    func deleteSelectedEntity() -> Bool {
        canvasView.deleteSelectedEntity()
    }

    @discardableResult
    func undoLastChange() -> Bool {
        guard let previous = undoStack.popLast() else {
            NSSound.beep()
            return false
        }
        redoStack.append(document)
        document = previous
        _ = canvasView.selectEntity(at: nil)
        return true
    }

    @discardableResult
    func redoLastChange() -> Bool {
        guard let next = redoStack.popLast() else {
            NSSound.beep()
            return false
        }
        pushUndoSnapshot(document)
        document = next
        _ = canvasView.selectEntity(at: nil)
        return true
    }

    func canUndo() -> Bool {
        !undoStack.isEmpty
    }

    func canRedo() -> Bool {
        !redoStack.isEmpty
    }

    @discardableResult
    func moveSelectedEntity(by delta: DXFPoint) -> Bool {
        guard let selected = canvasView.selectedEntityInfo(), document.entities.indices.contains(selected.index) else {
            NSSound.beep()
            return false
        }
        var next = document
        next.entities[selected.index] = translated(entity: selected.entity, dx: delta.x, dy: delta.y)
        commitDocumentChange(next)
        _ = canvasView.selectEntity(at: selected.index)
        return true
    }

    @discardableResult
    func copySelectedEntity(by delta: DXFPoint) -> Bool {
        guard let selected = canvasView.selectedEntityInfo() else {
            NSSound.beep()
            return false
        }
        var next = document
        let duplicated = translated(entity: selected.entity, dx: delta.x, dy: delta.y)
        next.entities.append(duplicated)
        commitDocumentChange(next)
        _ = canvasView.selectEntity(at: next.entities.count - 1)
        return true
    }

    private func configureUI() {
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NordTheme.polarNight0.cgColor

        headerTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        headerTitleLabel.textColor = NordTheme.snowStorm2
        headerTitleLabel.setContentHuggingPriority(.required, for: .horizontal)

        documentTabButton.bezelStyle = .rounded
        documentTabButton.font = .systemFont(ofSize: 11, weight: .medium)
        documentTabButton.isBordered = true
        documentTabButton.bezelColor = NordTheme.polarNight3
        documentTabButton.contentTintColor = NordTheme.snowStorm1
        documentTabButton.title = "Untitled.dxf"
        documentTabButton.setContentHuggingPriority(.required, for: .horizontal)

        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = NordTheme.frost0

        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = NordTheme.snowStorm0.withAlphaComponent(0.75)
        hintLabel.stringValue = "Cmd: LINE/MOVE/COPY + LAYOUT NEW Layout2 24x36 + MVIEW 1,1 10,7 1/8 + VPSCALE 1 1/4."

        inspectorTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        inspectorTitleLabel.textColor = NordTheme.snowStorm1
        entityBreakdownLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        entityBreakdownLabel.textColor = NordTheme.snowStorm0
        entityBreakdownLabel.lineBreakMode = .byWordWrapping
        entityBreakdownLabel.maximumNumberOfLines = 0

        layersPanelTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        layersPanelTitleLabel.textColor = NordTheme.snowStorm1
        propertiesPanelTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        propertiesPanelTitleLabel.textColor = NordTheme.snowStorm1

        propertiesLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        propertiesLabel.textColor = NordTheme.snowStorm0
        propertiesLabel.lineBreakMode = .byWordWrapping
        propertiesLabel.maximumNumberOfLines = 0

        let layerNameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layerName"))
        layerNameColumn.title = "Layer"
        layerNameColumn.width = 150
        let layerStateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layerState"))
        layerStateColumn.title = "State"
        layerStateColumn.width = 120
        layerTableView.addTableColumn(layerNameColumn)
        layerTableView.addTableColumn(layerStateColumn)
        layerTableView.headerView = nil
        layerTableView.intercellSpacing = NSSize(width: 6, height: 2)
        layerTableView.rowHeight = 18
        layerTableView.backgroundColor = NordTheme.polarNight1
        layerTableView.delegate = self
        layerTableView.dataSource = self

        layerTableScrollView.hasVerticalScroller = true
        layerTableScrollView.borderType = .lineBorder
        layerTableScrollView.backgroundColor = NordTheme.polarNight1
        layerTableScrollView.documentView = layerTableView
        layerTableScrollView.translatesAutoresizingMaskIntoConstraints = false

        configureToolButton(selectToolButton, action: #selector(selectToolFromUI(_:)))
        configureToolButton(lineToolButton, action: #selector(lineToolFromUI(_:)))
        configureToolButton(polylineToolButton, action: #selector(polylineToolFromUI(_:)))
        configureToolButton(rectToolButton, action: #selector(rectToolFromUI(_:)))
        configureToolButton(circleToolButton, action: #selector(circleToolFromUI(_:)))

        resetViewButton.target = self
        resetViewButton.action = #selector(resetViewPressed(_:))
        resetViewButton.bezelStyle = .rounded
        resetViewButton.controlSize = .small
        resetViewButton.contentTintColor = NordTheme.snowStorm1
        resetViewButton.bezelColor = NordTheme.polarNight3

        configureScaleControls()
        configureStyleControls()
        configureCommandInput()
        configureObjectSnapControls()

        let topBar = NSView()
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NordTheme.polarNight1.cgColor
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let topBarStack = NSStackView(views: [
            headerTitleLabel,
            documentTabButton,
            summaryLabel,
            selectToolButton,
            lineToolButton,
            polylineToolButton,
            rectToolButton,
            circleToolButton,
            layerPopup,
            layerOnButton,
            layerLockButton,
            layerFreezeButton,
            lineTypePopup,
            colorPopup,
            lineWeightPopup,
            unitsPopup,
            gridPopup,
            snapPopup,
            snapToggle,
            orthoToggle,
            resetViewButton
        ])
        topBarStack.orientation = .horizontal
        topBarStack.spacing = 12
        topBarStack.alignment = .centerY
        topBarStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topBarStack)

        let propertiesStack = NSStackView(views: [propertiesPanelTitleLabel, propertiesLabel])
        propertiesStack.orientation = .vertical
        propertiesStack.spacing = 6
        propertiesStack.alignment = .leading

        let inspector = NSStackView(views: [
            hintLabel,
            inspectorTitleLabel,
            entityBreakdownLabel,
            layersPanelTitleLabel,
            layerTableScrollView,
            propertiesStack
        ])
        inspector.orientation = .vertical
        inspector.spacing = 10
        inspector.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        inspector.translatesAutoresizingMaskIntoConstraints = false
        inspector.wantsLayer = true
        inspector.layer?.backgroundColor = NordTheme.polarNight1.cgColor
        layerTableScrollView.heightAnchor.constraint(equalToConstant: 220).isActive = true

        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(canvasView)
        splitView.addArrangedSubview(inspector)
        canvasView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        canvasView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let statusBar = NSView()
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NordTheme.polarNight1.cgColor
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        statusNavLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusNavLabel.textColor = NordTheme.snowStorm0
        statusDocLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusDocLabel.textColor = NordTheme.snowStorm0

        spaceTabs.target = self
        spaceTabs.action = #selector(spaceTabsChanged(_:))
        spaceTabs.selectedSegment = 0
        spaceTabs.segmentStyle = .rounded
        spaceTabs.setWidth(70, forSegment: 0)
        spaceTabs.setWidth(70, forSegment: 1)
        spaceTabs.setLabel("Model", forSegment: 0)
        spaceTabs.setLabel("Layout", forSegment: 1)
        spaceTabs.setContentHuggingPriority(.required, for: .horizontal)

        let commandStack = NSStackView(views: [commandLabel, commandField])
        commandStack.orientation = .horizontal
        commandStack.spacing = 8
        commandStack.alignment = .centerY
        commandStack.translatesAutoresizingMaskIntoConstraints = false

        let osnapStack = NSStackView(views: [osnapMasterButton, osnapEndButton, osnapMidButton, osnapCenterButton, osnapIntButton])
        osnapStack.orientation = .horizontal
        osnapStack.spacing = 6
        osnapStack.alignment = .centerY
        osnapStack.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(commandStack)
        statusBar.addSubview(spaceTabs)
        statusBar.addSubview(statusNavLabel)
        statusBar.addSubview(statusDocLabel)
        statusBar.addSubview(osnapStack)
        spaceTabs.translatesAutoresizingMaskIntoConstraints = false
        statusNavLabel.translatesAutoresizingMaskIntoConstraints = false
        statusDocLabel.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView(views: [topBar, splitView, statusBar])
        root.orientation = .vertical
        root.spacing = 0
        root.alignment = .leading
        root.distribution = .fill
        root.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            topBar.heightAnchor.constraint(equalToConstant: 42),
            statusBar.heightAnchor.constraint(equalToConstant: 28),
            canvasView.widthAnchor.constraint(greaterThanOrEqualToConstant: 680),

            topBarStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 14),
            topBarStack.trailingAnchor.constraint(lessThanOrEqualTo: topBar.trailingAnchor, constant: -14),
            topBarStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            spaceTabs.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 14),
            spaceTabs.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusNavLabel.leadingAnchor.constraint(equalTo: spaceTabs.trailingAnchor, constant: 12),
            statusNavLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            osnapStack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -14),
            osnapStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusDocLabel.trailingAnchor.constraint(equalTo: osnapStack.leadingAnchor, constant: -12),
            statusDocLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            commandStack.centerXAnchor.constraint(equalTo: statusBar.centerXAnchor),
            commandStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            commandStack.leadingAnchor.constraint(greaterThanOrEqualTo: statusNavLabel.trailingAnchor, constant: 12),
            commandStack.trailingAnchor.constraint(lessThanOrEqualTo: statusDocLabel.leadingAnchor, constant: -12),
            commandField.widthAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])
        let inspectorWidthConstraint = inspector.widthAnchor.constraint(equalToConstant: inspectorWidth)
        inspectorWidthConstraint.isActive = true
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.required, forSubviewAt: 1)
        DispatchQueue.main.async { [weak self] in
            self?.applyInspectorPosition()
            self?.canvasView.needsDisplay = true
        }

        applyActiveTool(.select)
    }

    private func wireCanvasCallbacks() {
        canvasView.onLineCreated = { [weak self] start, end in
            self?.appendLine(start: start, end: end)
        }
        canvasView.onCircleCreated = { [weak self] center, radius in
            self?.appendCircle(center: center, radius: radius)
        }
        canvasView.onRectangleCreated = { [weak self] a, b in
            self?.appendRectangle(cornerA: a, cornerB: b)
        }
        canvasView.onPolylineSegmentCreated = { [weak self] start, end in
            self?.appendPolylineSegment(start: start, end: end)
        }
        canvasView.onDocumentChanged = { [weak self] next in
            self?.commitDocumentChange(next)
        }
        canvasView.onViewTransformChanged = { [weak self] zoom, pan in
            self?.updateNavigationStatus(zoom: zoom, pan: pan)
        }
        canvasView.onSelectionChanged = { [weak self] _, _ in
            self?.refreshUI()
        }
    }

    private func refreshUI() {
        unitsPopup.selectItem(withTag: document.units.rawValue)
        refreshLayerPopup()
        syncStylePopups()
        let activeLayerStyle = resolvedLayerStyle(named: currentLayer, in: document)
        layerOnButton.state = activeLayerStyle.isVisible ? .on : .off
        layerOnButton.title = activeLayerStyle.isVisible ? "ON" : "OFF"
        layerLockButton.state = activeLayerStyle.isLocked ? .on : .off
        layerLockButton.title = activeLayerStyle.isLocked ? "LOCK" : "UNLOCK"
        layerFreezeButton.state = activeLayerStyle.isFrozen ? .on : .off
        layerFreezeButton.title = activeLayerStyle.isFrozen ? "FRZ" : "THAW"
        osnapMasterButton.state = isObjectSnapEnabled ? .on : .off
        osnapEndButton.state = objectSnapModes.contains(.endpoint) ? .on : .off
        osnapMidButton.state = objectSnapModes.contains(.midpoint) ? .on : .off
        osnapCenterButton.state = objectSnapModes.contains(.center) ? .on : .off
        osnapIntButton.state = objectSnapModes.contains(.intersection) ? .on : .off
        osnapEndButton.isEnabled = isObjectSnapEnabled
        osnapMidButton.isEnabled = isObjectSnapEnabled
        osnapCenterButton.isEnabled = isObjectSnapEnabled
        osnapIntButton.isEnabled = isObjectSnapEnabled
        let activeSpaceLabel = isInLayoutSpace ? (activeLayout()?.name ?? "Layout") : "Model"
        summaryLabel.stringValue = "\(activeSpaceLabel)  |  \(document.entities.count) entities"
        if isInLayoutSpace, let layout = activeLayout() {
            statusDocLabel.stringValue = "Sheet: \(layout.size.label)   Viewports: \(layout.viewports.count)   Units: \(document.units.label)"
        } else {
            let osnapStatus = isObjectSnapEnabled ? objectSnapModes.map(\.label).sorted().joined(separator: ",") : "OFF"
            let lt = currentEntityLineType?.rawValue ?? "BYLAYER"
            let lw = currentEntityLineWeight.map { String(format: "%.2f", $0) } ?? "BYLAYER"
            let col = currentEntityColor == nil ? "BYLAYER" : "OVERRIDE"
            let layerState = [
                activeLayerStyle.isVisible ? "ON" : "OFF",
                activeLayerStyle.isLocked ? "LOCK" : "UNLOCK",
                activeLayerStyle.isFrozen ? "FRZ" : "THAW"
            ].joined(separator: "/")
            statusDocLabel.stringValue = "Layer: \(currentLayer) [\(layerState)]   LT: \(lt)   LW: \(lw)   Color: \(col)   Units: \(document.units.label)   Grid: \(formatDraftValue(currentGridStep))   Snap: \(isSnapEnabled ? formatDraftValue(currentSnapStep) : "OFF")   O-Snap: \(osnapStatus)   Ortho: \(isOrthoEnabled ? "ON" : "OFF")   Entities: \(document.entities.count)"
        }
        documentTabButton.title = "\(document.name).dxf"
        let layoutLabel = activeLayout()?.name ?? "Layout"
        spaceTabs.setLabel(layoutLabel, forSegment: 1)
        spaceTabs.selectedSegment = isInLayoutSpace ? 1 : 0
        entityBreakdownLabel.stringValue = entityBreakdownText(for: document)
        refreshInspectorPanels()
        updateDXFSourcePreviewIfVisible()
    }

    private func refreshLayerPopup() {
        let existing = Set(document.layerStyles.keys).union(allEntityLayers(in: document)).union([currentLayer, "0"])
        let sortedLayers = existing.sorted()
        layerPopup.removeAllItems()
        for layer in sortedLayers {
            layerPopup.addItem(withTitle: "Layer: \(layer)")
            layerPopup.lastItem?.representedObject = layer
        }
        if let index = sortedLayers.firstIndex(of: currentLayer) {
            layerPopup.selectItem(at: index)
        } else if let index = sortedLayers.firstIndex(of: "0") {
            currentLayer = "0"
            layerPopup.selectItem(at: index)
        }
    }

    private func allEntityLayers(in document: DXFDocument) -> Set<String> {
        var layers: Set<String> = []
        for entity in document.entities {
            switch entity {
            case let .line(_, _, layer, _):
                layers.insert(layer)
            case let .circle(_, _, layer, _):
                layers.insert(layer)
            }
        }
        return layers
    }

    private func syncStylePopups() {
        if currentEntityLineType == nil {
            lineTypePopup.selectItem(at: 0)
        } else {
            let idx = (DXFLineType.allCases.firstIndex(of: currentEntityLineType!) ?? 0) + 1
            lineTypePopup.selectItem(at: idx)
        }
        if currentEntityColor == nil {
            colorPopup.selectItem(at: 0)
        } else {
            let entries = colorEntries()
            if let idx = entries.firstIndex(where: { $0.color == currentEntityColor }) {
                colorPopup.selectItem(at: idx + 1)
            }
        }
        if currentEntityLineWeight == nil {
            lineWeightPopup.selectItem(at: 0)
        } else if let value = currentEntityLineWeight {
            let options: [Double] = [0.13, 0.18, 0.25, 0.35, 0.50, 0.70, 1.00]
            if let idx = options.firstIndex(where: { abs($0 - Double(value)) < 0.0001 }) {
                lineWeightPopup.selectItem(at: idx + 1)
            }
        }
    }

    private func colorEntries() -> [(name: String, color: DXFColor)] {
        [
            ("White", DXFColor(r: 0.95, g: 0.95, b: 0.95)),
            ("Red", DXFColor(r: 0.95, g: 0.3, b: 0.3)),
            ("Yellow", DXFColor(r: 0.95, g: 0.85, b: 0.25)),
            ("Green", DXFColor(r: 0.35, g: 0.9, b: 0.35)),
            ("Cyan", DXFColor(r: 0.3, g: 0.9, b: 0.9)),
            ("Blue", DXFColor(r: 0.4, g: 0.55, b: 0.95)),
            ("Magenta", DXFColor(r: 0.9, g: 0.45, b: 0.9))
        ]
    }

    private func updateDXFSourcePreviewIfVisible() {
        guard let panel = sourcePanel, panel.isVisible else { return }
        sourceTextView.string = DXFCodec.serialize(document: document)
    }

    private func updateNavigationStatus(zoom: CGFloat, pan: CGPoint) {
        statusNavLabel.stringValue = String(format: "Zoom: %.0f%%   Pan: x %.0f  y %.0f", zoom * 100, pan.x, pan.y)
    }

    private func refreshInspectorPanels() {
        inspectorLayers = Set(document.layerStyles.keys).union(allEntityLayers(in: document)).union([currentLayer, "0"]).sorted()
        layerTableView.reloadData()
        if let index = inspectorLayers.firstIndex(of: currentLayer) {
            layerTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            layerTableView.deselectAll(nil)
        }
        propertiesLabel.stringValue = selectedEntityPropertiesText()
    }

    private func selectedEntityPropertiesText() -> String {
        guard let selected = canvasView.selectedEntityInfo() else {
            return "Selection: None\nPick an object to see geometry and style properties."
        }
        let layer = entityLayer(selected.entity)
        let layerStyle = resolvedLayerStyle(named: layer, in: document)
        let typeText: String
        let geometryText: String
        switch selected.entity {
        case let .line(start, end, _, _):
            typeText = "LINE"
            let length = hypot(end.x - start.x, end.y - start.y)
            geometryText = String(
                format: "Start: %.3f, %.3f\nEnd: %.3f, %.3f\nLength: %.3f",
                start.x, start.y, end.x, end.y, length
            )
        case let .circle(center, radius, _, _):
            typeText = "CIRCLE"
            geometryText = String(
                format: "Center: %.3f, %.3f\nRadius: %.3f\nDiameter: %.3f",
                center.x, center.y, radius, radius * 2
            )
        }
        let style: DXFEntityStyle
        switch selected.entity {
        case let .line(_, _, _, s): style = s
        case let .circle(_, _, _, s): style = s
        }
        let lt = style.lineType?.rawValue ?? layerStyle.lineType?.rawValue ?? "CONTINUOUS"
        let lw = style.lineWeight ?? layerStyle.lineWeight ?? 0.25
        let colorText = style.color == nil ? (layerStyle.color == nil ? "ByLayer(Default)" : "ByLayer") : "Override"
        let state = [
            layerStyle.isVisible ? "ON" : "OFF",
            layerStyle.isLocked ? "LOCK" : "UNLOCK",
            layerStyle.isFrozen ? "FRZ" : "THAW"
        ].joined(separator: "/")
        return """
        Selection: #\(selected.index + 1) \(typeText)
        Layer: \(layer) [\(state)]
        Linetype: \(lt)
        Lineweight: \(String(format: "%.2f mm", lw))
        Color: \(colorText)
        \(geometryText)
        """
    }

    @objc private func resetViewPressed(_ sender: Any?) {
        canvasView.resetView()
    }

    @objc func commandShowDXFSource(_ sender: Any?) {
        if let sourcePanel {
            sourcePanel.makeKeyAndOrderFront(nil)
            updateDXFSourcePreviewIfVisible()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "DXF Source"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.center()

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NordTheme.polarNight0.cgColor
        panel.contentView = content

        sourceTextView.isEditable = false
        sourceTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        sourceTextView.textColor = NordTheme.snowStorm2
        sourceTextView.backgroundColor = NordTheme.polarNight1
        sourceTextView.textContainerInset = NSSize(width: 12, height: 12)
        let scroll = NSScrollView(frame: content.bounds)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.backgroundColor = NordTheme.polarNight1
        scroll.documentView = sourceTextView
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])

        sourcePanel = panel
        updateDXFSourcePreviewIfVisible()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func entityBreakdownText(for document: DXFDocument) -> String {
        var lineCount = 0
        var circleCount = 0
        for entity in document.entities {
            switch entity {
            case .line: lineCount += 1
            case .circle: circleCount += 1
            }
        }
        return """
        Active Tool Set:
        - Select / Move / Grips
        - LINE, PLINE, RECT, CIRCLE
        - Command-first edits: MOVE, COPY, LAYER, SELECT

        Drawing Summary:
        - Total: \(document.entities.count)
        - LINE: \(lineCount)
        - CIRCLE: \(circleCount)

        Use View -> DXF Source... when you need raw text.
        """
    }

    @objc func selectSelectionTool(_ sender: Any?) { applyActiveTool(.select) }
    @objc func selectLineTool(_ sender: Any?) { applyActiveTool(.line) }
    @objc func selectPolylineTool(_ sender: Any?) { applyActiveTool(.polyline) }
    @objc func selectRectangleTool(_ sender: Any?) { applyActiveTool(.rectangle) }
    @objc func selectCircleTool(_ sender: Any?) { applyActiveTool(.circle) }

    func handleShortcutEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 100 { // F8
            isOrthoEnabled.toggle()
            orthoToggle.state = isOrthoEnabled ? .on : .off
            applyDraftingSettings()
            return true
        }
        if event.keyCode == 101 { // F9
            isSnapEnabled.toggle()
            snapToggle.state = isSnapEnabled ? .on : .off
            applyDraftingSettings()
            return true
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.isDisjoint(with: [.command, .option, .control]) else { return false }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), let key = chars.first else { return false }

        if mods == [.shift], key == "p" {
            applyActiveTool(.polyline)
            return true
        }
        guard mods.isDisjoint(with: [.shift]) else { return false }
        switch key {
        case "v", "g":
            applyActiveTool(.select)
            return true
        case "l":
            applyActiveTool(.line)
            return true
        case "r":
            applyActiveTool(.rectangle)
            return true
        case "e":
            applyActiveTool(.circle)
            return true
        case "o":
            isOrthoEnabled.toggle()
            orthoToggle.state = isOrthoEnabled ? .on : .off
            applyDraftingSettings()
            return true
        default:
            return false
        }
    }

    func captureCommandTyping(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !mods.isDisjoint(with: [.command, .control, .option]) {
            return false
        }
        guard view.window?.isKeyWindow == true else { return false }

        if event.keyCode == 53 { // Escape
            if !commandField.stringValue.isEmpty {
                commandField.stringValue = ""
                resetHistoryNavigation()
                commandField.selectText(nil)
                if let editor = commandField.currentEditor() {
                    editor.selectedRange = NSRange(location: 0, length: 0)
                }
                return true
            }

            let now = Date().timeIntervalSinceReferenceDate
            if now - lastEscapeTimestamp <= 0.9 {
                escapePressCount += 1
            } else {
                escapePressCount = 1
            }
            lastEscapeTimestamp = now

            if canvasView.cancelActiveOperation() {
                return true
            }
            if escapePressCount >= 2, canvasView.toolMode != .select {
                applyActiveTool(.select)
                escapePressCount = 0
                return true
            }
            return true
        }

        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            let raw = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return false }
            commandField.stringValue = ""
            executeCommandOrDistanceInput(raw)
            return true
        }

        if event.keyCode == 126 { // Up
            return browseCommandHistory(older: true)
        }
        if event.keyCode == 125 { // Down
            return browseCommandHistory(older: false)
        }

        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
            if commandField.stringValue.isEmpty {
                return false
            }
            if view.window?.firstResponder !== commandField.currentEditor() {
                suppressCommandHistoryPopup = true
                _ = view.window?.makeFirstResponder(commandField)
            }
            if let editor = commandField.currentEditor() {
                if editor.selectedRange.length > 0 {
                    editor.delete(nil)
                } else {
                    editor.deleteBackward(nil)
                }
            } else {
                commandField.stringValue.removeLast()
            }
            commandField.selectText(nil)
            if let editor = commandField.currentEditor() {
                editor.selectedRange = NSRange(location: commandField.stringValue.count, length: 0)
            }
            return true
        }

        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
            return false
        }
        let scalarValues = chars.unicodeScalars
        guard scalarValues.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }

        if view.window?.firstResponder !== commandField.currentEditor() {
            suppressCommandHistoryPopup = true
            _ = view.window?.makeFirstResponder(commandField)
        }
        if let editor = commandField.currentEditor() {
            editor.insertText(chars)
        } else {
            commandField.stringValue += chars
        }
        resetHistoryNavigation()
        escapePressCount = 0
        return true
    }

    func captureCommandHistoryScroll(_ event: NSEvent) -> Bool {
        guard view.window?.isKeyWindow == true else { return false }
        guard !commandHistory.isEmpty else { return false }
        guard let window = view.window else { return false }

        let isEditingCommand = window.firstResponder === commandField.currentEditor()
        let hitCommandField: Bool = {
            let rectInWindow = commandField.convert(commandField.bounds, to: nil)
            return rectInWindow.contains(event.locationInWindow)
        }()
        guard isEditingCommand || hitCommandField else { return false }

        if event.scrollingDeltaY > 0 {
            return browseCommandHistory(older: true)
        }
        if event.scrollingDeltaY < 0 {
            return browseCommandHistory(older: false)
        }
        return false
    }

    private func configureToolButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .rounded
        button.bezelColor = NordTheme.polarNight3
        button.contentTintColor = NordTheme.snowStorm1
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
    }

    private func applyActiveTool(_ mode: CADCanvasView.ToolMode) {
        canvasView.toolMode = mode
        selectToolButton.state = mode == .select ? .on : .off
        lineToolButton.state = mode == .line ? .on : .off
        polylineToolButton.state = mode == .polyline ? .on : .off
        rectToolButton.state = mode == .rectangle ? .on : .off
        circleToolButton.state = mode == .circle ? .on : .off
    }

    @objc private func selectToolFromUI(_ sender: Any?) { applyActiveTool(.select) }
    @objc private func lineToolFromUI(_ sender: Any?) { applyActiveTool(.line) }
    @objc private func polylineToolFromUI(_ sender: Any?) { applyActiveTool(.polyline) }
    @objc private func rectToolFromUI(_ sender: Any?) { applyActiveTool(.rectangle) }
    @objc private func circleToolFromUI(_ sender: Any?) { applyActiveTool(.circle) }
    @objc private func spaceTabsChanged(_ sender: NSSegmentedControl) {
        isInLayoutSpace = sender.selectedSegment == 1
        applyWorkspace()
    }

    private func activeLayout() -> LayoutSheet? {
        guard let id = activeLayoutID else { return nil }
        return layouts.first(where: { $0.id == id })
    }

    private func activeLayoutIndex() -> Int? {
        guard let id = activeLayoutID else { return nil }
        return layouts.firstIndex(where: { $0.id == id })
    }

    private func applyWorkspace() {
        canvasView.workspace = isInLayoutSpace ? .layout : .model
        canvasView.activeLayout = isInLayoutSpace ? activeLayout() : nil
        refreshUI()
    }

    private func applyInspectorPosition() {
        guard splitView.arrangedSubviews.count >= 2 else { return }
        let dividerX = splitView.bounds.width - inspectorWidth - splitView.dividerThickness
        if dividerX.isFinite, dividerX > 0 {
            splitView.setPosition(dividerX, ofDividerAt: 0)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyInspectorPosition()
        canvasView.needsDisplay = true
    }

    private func configureScaleControls() {
        unitsPopup.target = self
        unitsPopup.action = #selector(unitsChanged(_:))
        unitsPopup.font = .systemFont(ofSize: 11, weight: .medium)
        unitsPopup.bezelColor = NordTheme.polarNight3
        unitsPopup.contentTintColor = NordTheme.snowStorm1
        for units in DXFUnits.allCases {
            unitsPopup.addItem(withTitle: "Units: \(units.label)")
            unitsPopup.lastItem?.tag = units.rawValue
        }
        unitsPopup.selectItem(withTag: document.units.rawValue)
        unitsPopup.sizeToFit()

        gridPopup.target = self
        gridPopup.action = #selector(gridChanged(_:))
        gridPopup.font = .systemFont(ofSize: 11, weight: .medium)
        gridPopup.bezelColor = NordTheme.polarNight3
        gridPopup.contentTintColor = NordTheme.snowStorm1
        for value in gridStepValues {
            gridPopup.addItem(withTitle: "Grid \(formatDraftValue(value))")
        }
        gridPopup.selectItem(at: 3)
        gridPopup.sizeToFit()

        snapPopup.target = self
        snapPopup.action = #selector(snapStepChanged(_:))
        snapPopup.font = .systemFont(ofSize: 11, weight: .medium)
        snapPopup.bezelColor = NordTheme.polarNight3
        snapPopup.contentTintColor = NordTheme.snowStorm1
        for value in snapStepValues {
            snapPopup.addItem(withTitle: "Snap \(formatDraftValue(value))")
        }
        snapPopup.selectItem(at: 3)
        snapPopup.sizeToFit()

        snapToggle.target = self
        snapToggle.action = #selector(snapToggleChanged(_:))
        snapToggle.font = .systemFont(ofSize: 11, weight: .medium)
        snapToggle.contentTintColor = NordTheme.frost1
        snapToggle.state = .on
        snapToggle.controlSize = .small

        orthoToggle.target = self
        orthoToggle.action = #selector(orthoToggleChanged(_:))
        orthoToggle.font = .systemFont(ofSize: 11, weight: .medium)
        orthoToggle.contentTintColor = NordTheme.frost1
        orthoToggle.state = .off
        orthoToggle.controlSize = .small
    }

    private func configureStyleControls() {
        layerPopup.target = self
        layerPopup.action = #selector(layerChanged(_:))
        layerPopup.font = .systemFont(ofSize: 11, weight: .medium)
        layerPopup.bezelColor = NordTheme.polarNight3
        layerPopup.contentTintColor = NordTheme.snowStorm1

        layerOnButton.target = self
        layerOnButton.action = #selector(layerOnToggled(_:))
        layerOnButton.setButtonType(.pushOnPushOff)
        layerOnButton.bezelStyle = .rounded
        layerOnButton.bezelColor = NordTheme.polarNight3
        layerOnButton.contentTintColor = NordTheme.snowStorm1
        layerOnButton.controlSize = .small
        layerOnButton.font = .systemFont(ofSize: 10, weight: .medium)

        layerLockButton.target = self
        layerLockButton.action = #selector(layerLockToggled(_:))
        layerLockButton.setButtonType(.pushOnPushOff)
        layerLockButton.bezelStyle = .rounded
        layerLockButton.bezelColor = NordTheme.polarNight3
        layerLockButton.contentTintColor = NordTheme.snowStorm1
        layerLockButton.controlSize = .small
        layerLockButton.font = .systemFont(ofSize: 10, weight: .medium)

        layerFreezeButton.target = self
        layerFreezeButton.action = #selector(layerFreezeToggled(_:))
        layerFreezeButton.setButtonType(.pushOnPushOff)
        layerFreezeButton.bezelStyle = .rounded
        layerFreezeButton.bezelColor = NordTheme.polarNight3
        layerFreezeButton.contentTintColor = NordTheme.snowStorm1
        layerFreezeButton.controlSize = .small
        layerFreezeButton.font = .systemFont(ofSize: 10, weight: .medium)

        lineTypePopup.target = self
        lineTypePopup.action = #selector(lineTypeChanged(_:))
        lineTypePopup.font = .systemFont(ofSize: 11, weight: .medium)
        lineTypePopup.bezelColor = NordTheme.polarNight3
        lineTypePopup.contentTintColor = NordTheme.snowStorm1
        lineTypePopup.removeAllItems()
        lineTypePopup.addItem(withTitle: "LType: ByLayer")
        lineTypePopup.lastItem?.representedObject = "BYLAYER"
        for lt in DXFLineType.allCases {
            lineTypePopup.addItem(withTitle: "LType: \(lt.label)")
            lineTypePopup.lastItem?.representedObject = lt
        }
        lineTypePopup.selectItem(at: 0)

        colorPopup.target = self
        colorPopup.action = #selector(colorChanged(_:))
        colorPopup.font = .systemFont(ofSize: 11, weight: .medium)
        colorPopup.bezelColor = NordTheme.polarNight3
        colorPopup.contentTintColor = NordTheme.snowStorm1
        colorPopup.removeAllItems()
        colorPopup.addItem(withTitle: "Color: ByLayer")
        colorPopup.lastItem?.representedObject = "BYLAYER"
        for entry in colorEntries() {
            colorPopup.addItem(withTitle: "Color: \(entry.name)")
            colorPopup.lastItem?.representedObject = entry.color
        }
        colorPopup.selectItem(at: 0)

        lineWeightPopup.target = self
        lineWeightPopup.action = #selector(lineWeightChanged(_:))
        lineWeightPopup.font = .systemFont(ofSize: 11, weight: .medium)
        lineWeightPopup.bezelColor = NordTheme.polarNight3
        lineWeightPopup.contentTintColor = NordTheme.snowStorm1
        lineWeightPopup.removeAllItems()
        lineWeightPopup.addItem(withTitle: "Weight: ByLayer")
        lineWeightPopup.lastItem?.representedObject = "BYLAYER"
        for value in [0.13, 0.18, 0.25, 0.35, 0.50, 0.70, 1.00] {
            lineWeightPopup.addItem(withTitle: String(format: "Weight: %.2f mm", value))
            lineWeightPopup.lastItem?.representedObject = value
        }
        lineWeightPopup.selectItem(at: 0)
    }

    private func configureCommandInput() {
        commandLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        commandLabel.textColor = NordTheme.snowStorm0
        commandField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        commandField.placeholderString = "LINE 0,0 120,0 | LAYOUT NEW A101 24x36 | MVIEW 1,1 12,8 1/8"
        commandField.textColor = NordTheme.snowStorm2
        commandField.backgroundColor = NordTheme.polarNight2
        commandField.drawsBackground = true
        commandField.focusRingType = .none
        commandField.delegate = self
        commandField.target = self
        commandField.action = #selector(commandSubmitted(_:))
    }

    private func configureObjectSnapControls() {
        osnapMasterButton.target = self
        osnapMasterButton.action = #selector(osnapMasterChanged(_:))
        osnapMasterButton.font = .systemFont(ofSize: 10, weight: .semibold)
        osnapMasterButton.controlSize = .small
        osnapMasterButton.contentTintColor = NordTheme.frost1
        osnapMasterButton.state = isObjectSnapEnabled ? .on : .off

        configureOsnapModeButton(osnapEndButton, mode: .endpoint, action: #selector(osnapEndChanged(_:)))
        configureOsnapModeButton(osnapMidButton, mode: .midpoint, action: #selector(osnapMidChanged(_:)))
        configureOsnapModeButton(osnapCenterButton, mode: .center, action: #selector(osnapCenterChanged(_:)))
        configureOsnapModeButton(osnapIntButton, mode: .intersection, action: #selector(osnapIntChanged(_:)))
    }

    private func configureOsnapModeButton(_ button: NSButton, mode: CADCanvasView.ObjectSnapMode, action: Selector) {
        button.target = self
        button.action = action
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .rounded
        button.bezelColor = NordTheme.polarNight3
        button.contentTintColor = NordTheme.snowStorm1
        button.controlSize = .small
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.state = objectSnapModes.contains(mode) ? .on : .off
    }

    private func applyDraftingSettings() {
        canvasView.configureDrafting(
            gridStep: currentGridStep,
            snapStep: currentSnapStep,
            snapEnabled: isSnapEnabled,
            orthoEnabled: isOrthoEnabled,
            objectSnapEnabled: isObjectSnapEnabled,
            objectSnapModes: objectSnapModes
        )
        refreshUI()
    }

    @objc private func osnapMasterChanged(_ sender: NSButton) {
        isObjectSnapEnabled = sender.state == .on
        applyDraftingSettings()
    }

    @objc private func osnapEndChanged(_ sender: NSButton) {
        setObjectSnapMode(.endpoint, enabled: sender.state == .on)
    }

    @objc private func osnapMidChanged(_ sender: NSButton) {
        setObjectSnapMode(.midpoint, enabled: sender.state == .on)
    }

    @objc private func osnapCenterChanged(_ sender: NSButton) {
        setObjectSnapMode(.center, enabled: sender.state == .on)
    }

    @objc private func osnapIntChanged(_ sender: NSButton) {
        setObjectSnapMode(.intersection, enabled: sender.state == .on)
    }

    private func setObjectSnapMode(_ mode: CADCanvasView.ObjectSnapMode, enabled: Bool) {
        if enabled {
            objectSnapModes.insert(mode)
        } else {
            objectSnapModes.remove(mode)
        }
        applyDraftingSettings()
    }

    private func toggleObjectSnapMode(_ mode: CADCanvasView.ObjectSnapMode) {
        if objectSnapModes.contains(mode) {
            objectSnapModes.remove(mode)
        } else {
            objectSnapModes.insert(mode)
        }
    }

    private func formatDraftValue(_ value: CGFloat) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    @objc private func unitsChanged(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        guard let units = DXFUnits(rawValue: tag) else { return }
        if document.units != units {
            var next = document
            next.units = units
            commitDocumentChange(next)
        }
    }

    @objc private func layerChanged(_ sender: NSPopUpButton) {
        guard let name = sender.selectedItem?.representedObject as? String else { return }
        currentLayer = name
        refreshUI()
    }

    @objc private func layerOnToggled(_ sender: NSButton) {
        let shouldBeVisible = sender.state == .on
        updateLayerStyle(for: currentLayer) { style in
            style.isVisible = shouldBeVisible
        }
        refreshUI()
    }

    @objc private func layerLockToggled(_ sender: NSButton) {
        let shouldBeLocked = sender.state == .on
        updateLayerStyle(for: currentLayer) { style in
            style.isLocked = shouldBeLocked
        }
        refreshUI()
    }

    @objc private func layerFreezeToggled(_ sender: NSButton) {
        let shouldBeFrozen = sender.state == .on
        if shouldBeFrozen {
            NSSound.beep()
            refreshUI()
            return
        }
        updateLayerStyle(for: currentLayer) { style in
            style.isFrozen = shouldBeFrozen
        }
        refreshUI()
    }

    @objc private func lineTypeChanged(_ sender: NSPopUpButton) {
        if sender.selectedItem?.representedObject as? String == "BYLAYER" {
            currentEntityLineType = nil
        } else {
            currentEntityLineType = sender.selectedItem?.representedObject as? DXFLineType
        }
        refreshUI()
    }

    @objc private func colorChanged(_ sender: NSPopUpButton) {
        if sender.selectedItem?.representedObject as? String == "BYLAYER" {
            currentEntityColor = nil
        } else {
            currentEntityColor = sender.selectedItem?.representedObject as? DXFColor
        }
        refreshUI()
    }

    @objc private func lineWeightChanged(_ sender: NSPopUpButton) {
        if sender.selectedItem?.representedObject as? String == "BYLAYER" {
            currentEntityLineWeight = nil
        } else if let value = sender.selectedItem?.representedObject as? Double {
            currentEntityLineWeight = CGFloat(value)
        }
        refreshUI()
    }

    @objc private func gridChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        currentGridStep = gridStepValues[sender.indexOfSelectedItem]
        applyDraftingSettings()
    }

    @objc private func snapStepChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        currentSnapStep = snapStepValues[sender.indexOfSelectedItem]
        applyDraftingSettings()
    }

    @objc private func snapToggleChanged(_ sender: NSButton) {
        isSnapEnabled = sender.state == .on
        applyDraftingSettings()
    }

    @objc private func orthoToggleChanged(_ sender: NSButton) {
        isOrthoEnabled = sender.state == .on
        applyDraftingSettings()
    }

    @objc private func commandSubmitted(_ sender: NSTextField) {
        let raw = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        sender.stringValue = ""
        executeCommandOrDistanceInput(raw)
    }

    private func executeCommand(_ text: String) {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let cmd = parts.first?.lowercased() else { return }
        switch cmd {
        case "model":
            isInLayoutSpace = false
            applyWorkspace()
        case "pagesetup":
            openPageSetupDialog()
        case "page":
            if parts.count >= 2, parts[1].lowercased() == "setup" {
                openPageSetupDialog()
            } else {
                NSSound.beep()
            }
        case "layout", "-layout":
            handleLayoutCommand(parts)
        case "mview", "mv", "vp", "viewport", "vport":
            handleMViewCommand(parts)
        case "vpscale":
            handleVPScaleCommand(parts)
        case "v", "select":
            if parts.count == 1 {
                applyActiveTool(.select)
            } else {
                let option = parts[1].lowercased()
                switch option {
                case "last":
                    _ = canvasView.selectLastEntity()
                case "next":
                    _ = canvasView.selectNextEntity()
                case "prev", "previous":
                    _ = canvasView.selectPreviousEntity()
                case "none", "clear":
                    _ = canvasView.selectEntity(at: nil)
                case let raw where Int(raw) != nil:
                    _ = canvasView.selectEntity(at: (Int(raw) ?? 1) - 1)
                default:
                    NSSound.beep()
                }
            }
        case "l", "line":
            guard !isInLayoutSpace else { NSSound.beep(); return }
            if parts.count >= 3, let p1 = parsePoint(parts[1], base: nil), let p2 = parsePoint(parts[2], base: p1) {
                appendLine(start: p1, end: p2)
                commandBasePoint = p2
            } else {
                applyActiveTool(.line)
            }
        case "c", "circle":
            guard !isInLayoutSpace else { NSSound.beep(); return }
            if parts.count >= 3, let center = parsePoint(parts[1], base: nil), let r = Double(parts[2]) {
                appendCircle(center: center, radius: CGFloat(max(0.0001, r)))
                commandBasePoint = center
            } else {
                applyActiveTool(.circle)
            }
        case "rec", "rect", "rectangle":
            guard !isInLayoutSpace else { NSSound.beep(); return }
            if parts.count >= 3, let p1 = parsePoint(parts[1], base: nil), let p2 = parsePoint(parts[2], base: p1) {
                appendRectangle(cornerA: p1, cornerB: p2)
                commandBasePoint = p2
            } else {
                applyActiveTool(.rectangle)
            }
        case "pl", "pline", "polyline":
            guard !isInLayoutSpace else { NSSound.beep(); return }
            if parts.count >= 3 {
                var last = parsePoint(parts[1], base: nil)
                for token in parts.dropFirst(2) {
                    guard let from = last, let to = parsePoint(token, base: from) else { break }
                    appendPolylineSegment(start: from, end: to)
                    last = to
                }
                if let last { commandBasePoint = last }
            } else {
                applyActiveTool(.polyline)
            }
        case "z", "zoom":
            if parts.count >= 2, ["e", "extents"].contains(parts[1].lowercased()) {
                canvasView.zoomToExtents()
            } else {
                canvasView.zoomToExtents()
            }
        case "grid":
            if parts.count >= 2, let v = Double(parts[1]), v > 0 {
                currentGridStep = CGFloat(v)
                applyDraftingSettings()
            }
        case "snap":
            if parts.count >= 2 {
                let arg = parts[1].lowercased()
                if arg == "on" {
                    isSnapEnabled = true
                } else if arg == "off" {
                    isSnapEnabled = false
                } else if let v = Double(arg), v > 0 {
                    currentSnapStep = CGFloat(v)
                    isSnapEnabled = true
                }
                snapToggle.state = isSnapEnabled ? .on : .off
                applyDraftingSettings()
            }
        case "osnap":
            if parts.count >= 2 {
                let arg = parts[1].lowercased()
                switch arg {
                case "on":
                    isObjectSnapEnabled = true
                case "off":
                    isObjectSnapEnabled = false
                case "end", "endpoint":
                    toggleObjectSnapMode(.endpoint)
                case "mid", "midpoint":
                    toggleObjectSnapMode(.midpoint)
                case "cen", "center":
                    toggleObjectSnapMode(.center)
                case "int", "intersection":
                    toggleObjectSnapMode(.intersection)
                default:
                    NSSound.beep()
                }
                applyDraftingSettings()
            }
        case "ortho":
            if parts.count >= 2 {
                let arg = parts[1].lowercased()
                if arg == "on" { isOrthoEnabled = true }
                if arg == "off" { isOrthoEnabled = false }
            } else {
                isOrthoEnabled.toggle()
            }
            orthoToggle.state = isOrthoEnabled ? .on : .off
            applyDraftingSettings()
        case "units":
            if parts.count >= 2, let u = parseUnits(parts[1]) {
                var next = document
                next.units = u
                commitDocumentChange(next)
            }
        case "layer", "-layer", "la":
            handleLayerCommand(parts)
        case "layfrz", "freeze":
            let target = parts.count >= 2 ? normalizedLayerName(parts[1]) : currentLayer
            if target == currentLayer {
                NSSound.beep()
                return
            }
            updateLayerStyle(for: target) { style in
                style.isFrozen = true
            }
            refreshUI()
        case "laythw", "thaw":
            let target = parts.count >= 2 ? normalizedLayerName(parts[1]) : currentLayer
            updateLayerStyle(for: target) { style in
                style.isFrozen = false
            }
            refreshUI()
        case "color":
            handleColorCommand(parts)
        case "ltype", "linetype":
            handleLineTypeCommand(parts)
        case "lweight", "lineweight":
            handleLineWeightCommand(parts)
        case "move", "m":
            guard !isInLayoutSpace else { NSSound.beep(); return }
            if parts.count >= 2, let vector = parseDisplacement(parts: parts) {
                _ = moveSelectedEntity(by: vector)
            } else {
                NSSound.beep()
            }
        case "copy", "co":
            guard !isInLayoutSpace else { NSSound.beep(); return }
            if parts.count >= 2, let vector = parseDisplacement(parts: parts) {
                _ = copySelectedEntity(by: vector)
            } else {
                NSSound.beep()
            }
        case "u", "undo":
            _ = undoLastChange()
        case "redo":
            _ = redoLastChange()
        case "erase", "delete", "del":
            _ = deleteSelectedEntity()
        case "new":
            setDocumentBaseline(.empty)
            canvasView.resetView()
        default:
            NSSound.beep()
        }
    }

    private func handleLayoutCommand(_ parts: [String]) {
        guard parts.count >= 2 else {
            NSSound.beep()
            return
        }
        let action = parts[1].lowercased()
        switch action {
        case "model":
            isInLayoutSpace = false
            applyWorkspace()
        case "set":
            guard parts.count >= 3 else { NSSound.beep(); return }
            let key = parts[2].lowercased()
            if let layout = layouts.first(where: { $0.name.lowercased() == key }) {
                activeLayoutID = layout.id
                isInLayoutSpace = true
                applyWorkspace()
            } else {
                NSSound.beep()
            }
        case "new":
            guard parts.count >= 3 else { NSSound.beep(); return }
            let layoutName = parts[2]
            let size = parts.count >= 4 ? (LayoutSheetSize.parse(parts[3]) ?? .archD) : .archD
            let sheet = LayoutSheet(name: layoutName, size: size)
            layouts.append(sheet)
            activeLayoutID = sheet.id
            isInLayoutSpace = true
            applyWorkspace()
        case "size":
            guard parts.count >= 3, let index = activeLayoutIndex(), let size = LayoutSheetSize.parse(parts[2]) else {
                NSSound.beep()
                return
            }
            layouts[index].size = size
            applyWorkspace()
        case "list":
            let names = layouts.map(\.name).joined(separator: ", ")
            if names.isEmpty {
                NSSound.beep()
            } else {
                commandField.stringValue = names
            }
        default:
            if let layout = layouts.first(where: { $0.name.lowercased() == action }) {
                activeLayoutID = layout.id
                isInLayoutSpace = true
                applyWorkspace()
            } else {
                NSSound.beep()
            }
        }
    }

    private func handleLayerCommand(_ parts: [String]) {
        guard parts.count >= 2 else { NSSound.beep(); return }
        let action = parts[1].lowercased()
        switch action {
        case "new":
            guard parts.count >= 3 else { NSSound.beep(); return }
            let name = normalizedLayerName(parts[2])
            var next = document
            ensureLayerExists(named: name, in: &next)
            commitDocumentChange(next)
            currentLayer = name
            refreshUI()
        case "set":
            guard parts.count >= 3 else { NSSound.beep(); return }
            currentLayer = normalizedLayerName(parts[2])
            var next = document
            ensureLayerExists(named: currentLayer, in: &next)
            commitDocumentChange(next)
            refreshUI()
        case "on", "off":
            let shouldBeVisible = action == "on"
            let target = parts.count >= 3 ? normalizedLayerName(parts[2]) : currentLayer
            if !shouldBeVisible, target == currentLayer {
                NSSound.beep()
                return
            }
            updateLayerStyle(for: target) { style in
                style.isVisible = shouldBeVisible
            }
            if target == currentLayer {
                refreshUI()
            }
        case "lock", "unlock":
            let shouldBeLocked = action == "lock"
            let target = parts.count >= 3 ? normalizedLayerName(parts[2]) : currentLayer
            updateLayerStyle(for: target) { style in
                style.isLocked = shouldBeLocked
            }
            if target == currentLayer {
                refreshUI()
            }
        case "freeze", "thaw":
            let shouldBeFrozen = action == "freeze"
            let target = parts.count >= 3 ? normalizedLayerName(parts[2]) : currentLayer
            if shouldBeFrozen, target == currentLayer {
                NSSound.beep()
                return
            }
            updateLayerStyle(for: target) { style in
                style.isFrozen = shouldBeFrozen
            }
            if target == currentLayer || !shouldBeFrozen {
                refreshUI()
            }
        case "color":
            guard parts.count >= 3 else { NSSound.beep(); return }
            guard let color = parseColorToken(parts[2]) else { NSSound.beep(); return }
            let target = parts.count >= 4 ? normalizedLayerName(parts[3]) : currentLayer
            updateLayerStyle(for: target) { style in
                style.color = color
            }
            refreshUI()
        case "ltype", "linetype":
            guard parts.count >= 3 else { NSSound.beep(); return }
            guard let lineType = parseLineTypeToken(parts[2]) else { NSSound.beep(); return }
            let target = parts.count >= 4 ? normalizedLayerName(parts[3]) : currentLayer
            updateLayerStyle(for: target) { style in
                style.lineType = lineType
            }
            refreshUI()
        case "lweight", "lineweight":
            guard parts.count >= 3, let value = Double(parts[2]), value > 0 else { NSSound.beep(); return }
            let target = parts.count >= 4 ? normalizedLayerName(parts[3]) : currentLayer
            updateLayerStyle(for: target) { style in
                style.lineWeight = CGFloat(value)
            }
            refreshUI()
        case "list":
            let ordered = Set(document.layerStyles.keys).union(allEntityLayers(in: document)).union([currentLayer, "0"]).sorted()
            let tokens = ordered.map { layerName -> String in
                let style = resolvedLayerStyle(named: layerName, in: document)
                let onOff = style.isVisible ? "ON" : "OFF"
                let lock = style.isLocked ? "LOCKED" : "UNLOCKED"
                let freeze = style.isFrozen ? "FROZEN" : "THAWED"
                return "\(layerName)[\(onOff),\(lock),\(freeze)]"
            }
            commandField.stringValue = tokens.joined(separator: " ")
        default:
            currentLayer = normalizedLayerName(parts[1])
            var next = document
            ensureLayerExists(named: currentLayer, in: &next)
            commitDocumentChange(next)
            refreshUI()
        }
    }

    private func handleColorCommand(_ parts: [String]) {
        guard parts.count >= 2 else { NSSound.beep(); return }
        let arg = parts[1].lowercased()
        if arg == "bylayer" {
            currentEntityColor = nil
            refreshUI()
            return
        }
        if let color = colorEntries().first(where: { $0.name.lowercased() == arg })?.color {
            currentEntityColor = color
            refreshUI()
            return
        }
        NSSound.beep()
    }

    private func handleLineTypeCommand(_ parts: [String]) {
        guard parts.count >= 2 else { NSSound.beep(); return }
        let arg = parts[1].lowercased()
        if arg == "bylayer" {
            currentEntityLineType = nil
            refreshUI()
            return
        }
        if let lineType = DXFLineType.allCases.first(where: { $0.label.lowercased().replacingOccurrences(of: " ", with: "") == arg || $0.rawValue.lowercased() == arg }) {
            currentEntityLineType = lineType
            refreshUI()
            return
        }
        NSSound.beep()
    }

    private func handleLineWeightCommand(_ parts: [String]) {
        guard parts.count >= 2 else { NSSound.beep(); return }
        let arg = parts[1].lowercased()
        if arg == "bylayer" {
            currentEntityLineWeight = nil
            refreshUI()
            return
        }
        if let value = Double(arg), value > 0 {
            currentEntityLineWeight = CGFloat(value)
            refreshUI()
            return
        }
        NSSound.beep()
    }

    private func openPageSetupDialog() {
        guard isInLayoutSpace, let layoutIndex = activeLayoutIndex() else {
            NSSound.beep()
            return
        }
        let currentSize = layouts[layoutIndex].size
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28), pullsDown: false)
        for size in LayoutSheetSize.allCases {
            popup.addItem(withTitle: size.label)
            popup.lastItem?.representedObject = size
        }
        if let idx = LayoutSheetSize.allCases.firstIndex(of: currentSize) {
            popup.selectItem(at: idx)
        }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
        popup.frame.origin = NSPoint(x: 10, y: 8)
        accessory.addSubview(popup)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Page Setup"
        alert.informativeText = "Choose sheet size for \(layouts[layoutIndex].name)."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let selected = popup.selectedItem?.representedObject as? LayoutSheetSize else { return }
        layouts[layoutIndex].size = selected
        applyWorkspace()
    }

    private func handleMViewCommand(_ parts: [String]) {
        guard isInLayoutSpace, let index = activeLayoutIndex() else {
            NSSound.beep()
            return
        }
        guard parts.count >= 3,
              let p1 = parsePoint(parts[1], base: nil),
              let p2 = parsePoint(parts[2], base: p1) else {
            NSSound.beep()
            return
        }

        let minX = min(p1.x, p2.x)
        let minY = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        guard width > 0.01, height > 0.01 else {
            NSSound.beep()
            return
        }
        let scale = parts.count >= 4 ? (parseViewportScale(parts[3]) ?? .eighthInch) : .eighthInch
        let viewport = LayoutViewport(
            rectInPaperInches: CGRect(x: minX, y: minY, width: width, height: height),
            modelCenter: .init(x: 0, y: 0),
            scale: scale
        )
        layouts[index].viewports.append(viewport)
        applyWorkspace()
    }

    private func handleVPScaleCommand(_ parts: [String]) {
        guard isInLayoutSpace, let layoutIndex = activeLayoutIndex() else {
            NSSound.beep()
            return
        }
        guard parts.count >= 3,
              let viewportOrdinal = Int(parts[1]),
              viewportOrdinal >= 1,
              layouts[layoutIndex].viewports.indices.contains(viewportOrdinal - 1),
              let scale = parseViewportScale(parts[2]) else {
            NSSound.beep()
            return
        }
        layouts[layoutIndex].viewports[viewportOrdinal - 1].scale = scale
        applyWorkspace()
    }

    private func parseViewportScale(_ token: String) -> LayoutViewportScale? {
        let normalized = token.lowercased().replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "1:1", "1":
            return .oneToOne
        case "1/4", "1/4=1'-0\"", "quarter":
            return .quarterInch
        case "1/8", "1/8=1'-0\"", "eighth":
            return .eighthInch
        case "1/16", "1/16=1'-0\"", "sixteenth":
            return .sixteenthInch
        default:
            if let numeric = Double(normalized), numeric > 0 {
                return LayoutViewportScale(label: "1:\(Int(numeric.rounded()))", modelUnitsPerPaperInch: CGFloat(numeric))
            }
            return nil
        }
    }

    private func setDocumentBaseline(_ next: DXFDocument) {
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
        layouts = [LayoutSheet(name: "Layout1", size: .archD)]
        activeLayoutID = layouts.first?.id
        isInLayoutSpace = false
        var normalized = next
        ensureLayerExists(named: "0", in: &normalized)
        currentLayer = inferredInitialLayer(for: normalized)
        document = normalized
        _ = canvasView.selectEntity(at: nil)
        applyWorkspace()
    }

    private func commitDocumentChange(_ next: DXFDocument) {
        guard next != document else { return }
        pushUndoSnapshot(document)
        redoStack.removeAll(keepingCapacity: true)
        document = next
    }

    private func pushUndoSnapshot(_ snapshot: DXFDocument) {
        undoStack.append(snapshot)
        if undoStack.count > maxHistoryDepth {
            undoStack.removeFirst(undoStack.count - maxHistoryDepth)
        }
    }

    private func normalizedLayerName(_ raw: String?) -> String {
        let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cleaned.isEmpty { return currentLayer }
        return cleaned
    }

    private func ensureLayerExists(named layer: String, in document: inout DXFDocument) {
        if document.layerStyles[layer] == nil {
            document.layerStyles[layer] = DXFLayerStyle(color: nil, lineWeight: nil, lineType: nil, isVisible: true, isLocked: false, isFrozen: false)
        }
    }

    private func resolvedLayerStyle(named layer: String, in document: DXFDocument) -> DXFLayerStyle {
        document.layerStyles[layer] ?? DXFLayerStyle(color: nil, lineWeight: nil, lineType: nil, isVisible: true, isLocked: false, isFrozen: false)
    }

    private func updateLayerStyle(for layer: String, mutate: (inout DXFLayerStyle) -> Void) {
        let target = normalizedLayerName(layer)
        var next = document
        var style = resolvedLayerStyle(named: target, in: next)
        mutate(&style)
        next.layerStyles[target] = style
        commitDocumentChange(next)
    }

    private func parseColorToken(_ raw: String) -> DXFColor? {
        let token = raw.lowercased()
        return colorEntries().first(where: { $0.name.lowercased() == token })?.color
    }

    private func parseLineTypeToken(_ raw: String) -> DXFLineType? {
        let token = raw.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        return DXFLineType.allCases.first {
            let labelToken = $0.label.lowercased().replacingOccurrences(of: " ", with: "")
            let rawToken = $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "")
            return token == labelToken || token == rawToken
        }
    }

    private func inferredInitialLayer(for document: DXFDocument) -> String {
        if document.layerStyles.keys.contains("0") { return "0" }
        if let layer = document.entities.compactMap({ entityLayer($0) }).first {
            return layer
        }
        return "0"
    }

    private func entityLayer(_ entity: DXFEntity) -> String {
        switch entity {
        case let .line(_, _, layer, _):
            return layer
        case let .circle(_, _, layer, _):
            return layer
        }
    }

    private func parseDisplacement(parts: [String]) -> DXFPoint? {
        if parts.count >= 3, let from = parsePoint(parts[1], base: nil), let to = parsePoint(parts[2], base: from) {
            return DXFPoint(x: to.x - from.x, y: to.y - from.y)
        }
        if parts.count >= 2 {
            return parseVector(parts[1])
        }
        return nil
    }

    private func parseVector(_ token: String) -> DXFPoint? {
        let cleaned = token.replacingOccurrences(of: "@", with: "")
        let coords = cleaned.split(separator: ",", omittingEmptySubsequences: false)
        guard coords.count == 2, let x = Double(coords[0]), let y = Double(coords[1]) else {
            return nil
        }
        return DXFPoint(x: CGFloat(x), y: CGFloat(y))
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

    func controlTextDidChange(_ obj: Notification) {
        guard !isAutoCompletingCommand,
              let field = obj.object as? NSTextField,
              field === commandField,
              let editor = field.currentEditor() else { return }

        let fullText = field.stringValue
        guard !fullText.isEmpty, !fullText.contains(where: \.isWhitespace) else { return }
        let token = fullText.lowercased()
        guard let completion = commandCompletion(for: token), completion != token else { return }

        isAutoCompletingCommand = true
        field.stringValue = completion
        editor.selectedRange = NSRange(location: token.count, length: completion.count - token.count)
        isAutoCompletingCommand = false
    }

    private func commandCompletion(for token: String) -> String? {
        commandAliasMap[token]
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === commandField else { return }
        if suppressCommandHistoryPopup {
            suppressCommandHistoryPopup = false
            return
        }
        // Click/focus should not pop a menu; history is scrubbed via wheel or Up/Down keys.
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard tableView === layerTableView else { return 0 }
        return inspectorLayers.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView === layerTableView, inspectorLayers.indices.contains(row) else { return nil }
        let layer = inspectorLayers[row]
        let identifier = NSUserInterfaceItemIdentifier("layerCell-\(tableColumn?.identifier.rawValue ?? "col")")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
        let textField: NSTextField
        if let existing = cell.textField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        textField.font = .monospacedSystemFont(ofSize: 11, weight: layer == currentLayer ? .semibold : .regular)
        textField.textColor = NordTheme.snowStorm0
        let style = resolvedLayerStyle(named: layer, in: document)
        if tableColumn?.identifier.rawValue == "layerName" {
            textField.stringValue = layer
        } else {
            var parts: [String] = []
            parts.append(style.isVisible ? "ON" : "OFF")
            if style.isLocked { parts.append("LOCK") }
            if style.isFrozen { parts.append("FRZ") }
            textField.stringValue = parts.joined(separator: " ")
        }
        cell.identifier = identifier
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView, tableView === layerTableView else { return }
        guard layerTableView.selectedRow >= 0, inspectorLayers.indices.contains(layerTableView.selectedRow) else { return }
        let selectedLayer = inspectorLayers[layerTableView.selectedRow]
        if selectedLayer != currentLayer {
            currentLayer = selectedLayer
            refreshUI()
        }
    }

    private func appendCommandHistory(_ command: String) {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if let last = commandHistory.last, last.caseInsensitiveCompare(normalized) == .orderedSame {
            return
        }
        commandHistory.append(normalized)
        if commandHistory.count > maxCommandHistory {
            commandHistory.removeFirst(commandHistory.count - maxCommandHistory)
        }
    }

    private func executeCommandOrDistanceInput(_ raw: String) {
        if tryCompletePendingDistance(raw) {
            escapePressCount = 0
            resetHistoryNavigation()
            return
        }
        appendCommandHistory(raw)
        resetHistoryNavigation()
        escapePressCount = 0
        executeCommand(raw)
    }

    private func tryCompletePendingDistance(_ raw: String) -> Bool {
        guard canvasView.hasPendingLineInput() else { return false }
        guard let distance = parseDistance(raw), distance > 0 else { return false }
        return canvasView.completePendingSegment(withDistance: distance)
    }

    private func parseDistance(_ raw: String) -> CGFloat? {
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard !token.isEmpty else { return nil }

        if token.contains("'") || token.contains("\"") {
            return parseImperialDistanceToken(token)
        }
        if let value = Double(token) {
            return CGFloat(value)
        }
        return nil
    }

    private func parseImperialDistanceToken(_ token: String) -> CGFloat? {
        let parts = token.split(separator: "'", maxSplits: 1, omittingEmptySubsequences: false)
        var feetValue: Double = 0
        var inchValue: Double = 0

        if parts.count == 2 {
            let feetText = String(parts[0])
            let inchText = String(parts[1]).replacingOccurrences(of: "\"", with: "")
            if !feetText.isEmpty {
                guard let feet = Double(feetText) else { return nil }
                feetValue = feet
            }
            if !inchText.isEmpty {
                guard let inches = Double(inchText) else { return nil }
                inchValue = inches
            }
        } else {
            let inchText = token.replacingOccurrences(of: "\"", with: "")
            guard let inches = Double(inchText) else { return nil }
            inchValue = inches
        }

        let totalInches = feetValue * 12 + inchValue
        switch document.units {
        case .inches, .unitless:
            return CGFloat(totalInches)
        case .feet:
            return CGFloat(totalInches / 12)
        case .millimeters:
            return CGFloat(totalInches * 25.4)
        case .centimeters:
            return CGFloat(totalInches * 2.54)
        case .meters:
            return CGFloat(totalInches * 0.0254)
        }
    }

    private func resetHistoryNavigation() {
        historyCursorFromNewest = nil
        draftCommandBeforeHistory = ""
    }

    private func browseCommandHistory(older: Bool) -> Bool {
        guard !commandHistory.isEmpty else { return false }
        if view.window?.firstResponder !== commandField.currentEditor() {
            suppressCommandHistoryPopup = true
            _ = view.window?.makeFirstResponder(commandField)
        }

        if historyCursorFromNewest == nil {
            draftCommandBeforeHistory = commandField.stringValue
            historyCursorFromNewest = -1
        }

        var next = historyCursorFromNewest ?? -1
        if older {
            next += 1
            if next >= commandHistory.count { next = commandHistory.count - 1 }
        } else {
            next -= 1
        }

        historyCursorFromNewest = next
        if next < 0 {
            commandField.stringValue = draftCommandBeforeHistory
            if let editor = commandField.currentEditor() {
                editor.selectedRange = NSRange(location: commandField.stringValue.count, length: 0)
            }
            return true
        }

        let index = commandHistory.count - 1 - next
        guard commandHistory.indices.contains(index) else { return false }
        commandField.stringValue = commandHistory[index]
        if let editor = commandField.currentEditor() {
            editor.selectedRange = NSRange(location: commandField.stringValue.count, length: 0)
        }
        return true
    }

    private func parsePoint(_ token: String, base: DXFPoint?) -> DXFPoint? {
        let raw = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRelative = raw.hasPrefix("@")
        let coordText = isRelative ? String(raw.dropFirst()) : raw
        let coords = coordText.split(separator: ",", omittingEmptySubsequences: false)
        guard coords.count == 2, let x = Double(coords[0]), let y = Double(coords[1]) else {
            return nil
        }
        if isRelative {
            let anchor = base ?? commandBasePoint
            return DXFPoint(x: anchor.x + CGFloat(x), y: anchor.y + CGFloat(y))
        }
        return DXFPoint(x: CGFloat(x), y: CGFloat(y))
    }

    private func parseUnits(_ token: String) -> DXFUnits? {
        switch token.lowercased() {
        case "unitless", "none", "0":
            return .unitless
        case "in", "inch", "inches", "1":
            return .inches
        case "ft", "foot", "feet", "2":
            return .feet
        case "mm", "millimeter", "millimeters", "4":
            return .millimeters
        case "cm", "centimeter", "centimeters", "5":
            return .centimeters
        case "m", "meter", "meters", "6":
            return .meters
        default:
            return nil
        }
    }
}
