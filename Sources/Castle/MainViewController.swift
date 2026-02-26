import AppKit

@MainActor
final class MainViewController: NSViewController {
    private let headerTitleLabel = NSTextField(labelWithString: "Castle")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let statusNavLabel = NSTextField(labelWithString: "")
    private let statusDocLabel = NSTextField(labelWithString: "")
    private let inspectorTitleLabel = NSTextField(labelWithString: "Inspector")
    private let entityBreakdownLabel = NSTextField(labelWithString: "")

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
    private let snapToggle = NSButton(checkboxWithTitle: "Snap", target: nil, action: nil)
    private let orthoToggle = NSButton(checkboxWithTitle: "Ortho", target: nil, action: nil)
    private let commandLabel = NSTextField(labelWithString: "Command")
    private let commandField = NSTextField(string: "")
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
    private var commandBasePoint = DXFPoint(x: 0, y: 0)

    private(set) var document: DXFDocument = .empty {
        didSet {
            canvasView.document = document
            refreshUI()
        }
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        wireCanvasCallbacks()
        document = seedDocument()
        applyDraftingSettings()
        updateNavigationStatus(zoom: 1.0, pan: .zero)
    }

    func newDocument() {
        document = .empty
    }

    func loadDocument(from url: URL) throws {
        let data = try Data(contentsOf: url)
        document = try DXFCodec.parse(data: data, defaultName: url.deletingPathExtension().lastPathComponent)
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

    func appendLine(start: DXFPoint, end: DXFPoint, layer: String = "0") {
        var next = document
        next.entities.append(.line(start: start, end: end, layer: layer, style: .default))
        document = next
    }

    func appendCircle(center: DXFPoint, radius: CGFloat, layer: String = "0") {
        var next = document
        next.entities.append(.circle(center: center, radius: radius, layer: layer, style: .default))
        document = next
    }

    func appendRectangle(cornerA: DXFPoint, cornerB: DXFPoint, layer: String = "0") {
        let p1 = cornerA
        let p2 = DXFPoint(x: cornerB.x, y: cornerA.y)
        let p3 = cornerB
        let p4 = DXFPoint(x: cornerA.x, y: cornerB.y)
        appendLine(start: p1, end: p2, layer: layer)
        appendLine(start: p2, end: p3, layer: layer)
        appendLine(start: p3, end: p4, layer: layer)
        appendLine(start: p4, end: p1, layer: layer)
    }

    func appendPolylineSegment(start: DXFPoint, end: DXFPoint, layer: String = "0") {
        appendLine(start: start, end: end, layer: layer)
    }

    func deleteSelectedEntity() {
        _ = canvasView.deleteSelectedEntity()
    }

    private func configureUI() {
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor

        headerTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        headerTitleLabel.textColor = NSColor(calibratedWhite: 0.95, alpha: 1)

        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = NSColor(calibratedWhite: 0.82, alpha: 1)

        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        hintLabel.stringValue = "Tools: V Select, L Line, Shift+P Polyline, R Rect, E Circle. Nav: wheel zoom at cursor (AutoCAD direction), middle-drag pan."

        inspectorTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        inspectorTitleLabel.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        entityBreakdownLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        entityBreakdownLabel.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        entityBreakdownLabel.lineBreakMode = .byWordWrapping
        entityBreakdownLabel.maximumNumberOfLines = 0

        configureToolButton(selectToolButton, action: #selector(selectToolFromUI(_:)))
        configureToolButton(lineToolButton, action: #selector(lineToolFromUI(_:)))
        configureToolButton(polylineToolButton, action: #selector(polylineToolFromUI(_:)))
        configureToolButton(rectToolButton, action: #selector(rectToolFromUI(_:)))
        configureToolButton(circleToolButton, action: #selector(circleToolFromUI(_:)))

        resetViewButton.target = self
        resetViewButton.action = #selector(resetViewPressed(_:))
        resetViewButton.bezelStyle = .texturedRounded
        resetViewButton.controlSize = .small

        configureScaleControls()
        configureCommandInput()

        let topBar = NSView()
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let topBarStack = NSStackView(views: [
            headerTitleLabel,
            summaryLabel,
            selectToolButton,
            lineToolButton,
            polylineToolButton,
            rectToolButton,
            circleToolButton,
            unitsPopup,
            gridPopup,
            snapPopup,
            snapToggle,
            orthoToggle,
            commandLabel,
            commandField,
            resetViewButton
        ])
        topBarStack.orientation = .horizontal
        topBarStack.spacing = 12
        topBarStack.alignment = .centerY
        topBarStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topBarStack)

        let inspector = NSStackView(views: [hintLabel, inspectorTitleLabel, entityBreakdownLabel])
        inspector.orientation = .vertical
        inspector.spacing = 10
        inspector.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        inspector.translatesAutoresizingMaskIntoConstraints = false
        inspector.wantsLayer = true
        inspector.layer?.backgroundColor = NSColor(calibratedWhite: 0.095, alpha: 1).cgColor

        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(canvasView)
        splitView.addArrangedSubview(inspector)
        canvasView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        canvasView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let statusBar = NSView()
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        statusNavLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusNavLabel.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        statusDocLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusDocLabel.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)

        let statusStack = NSStackView(views: [statusNavLabel, statusDocLabel])
        statusStack.orientation = .horizontal
        statusStack.distribution = .fillEqually
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusStack)

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
            commandField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),

            statusStack.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 14),
            statusStack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -14),
            statusStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
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
            self?.document = next
        }
        canvasView.onViewTransformChanged = { [weak self] zoom, pan in
            self?.updateNavigationStatus(zoom: zoom, pan: pan)
        }
    }

    private func refreshUI() {
        unitsPopup.selectItem(withTag: document.units.rawValue)
        summaryLabel.stringValue = "\(document.name)  |  \(document.entities.count) entities"
        statusDocLabel.stringValue = "Units: \(document.units.label)   Grid: \(formatDraftValue(currentGridStep))   Snap: \(isSnapEnabled ? formatDraftValue(currentSnapStep) : "OFF")   Ortho: \(isOrthoEnabled ? "ON" : "OFF")   Entities: \(document.entities.count)"
        entityBreakdownLabel.stringValue = entityBreakdownText(for: document)
        sourceTextView.string = DXFCodec.serialize(document: document)
    }

    private func updateNavigationStatus(zoom: CGFloat, pan: CGPoint) {
        statusNavLabel.stringValue = String(format: "Zoom: %.0f%%   Pan: x %.0f  y %.0f", zoom * 100, pan.x, pan.y)
    }

    private func seedDocument() -> DXFDocument {
        DXFDocument(
            name: "Starter Plan",
            units: .millimeters,
            layerStyles: [:],
            entities: [
                .line(start: .init(x: -220, y: -140), end: .init(x: 220, y: -140), layer: "walls", style: .default),
                .line(start: .init(x: 220, y: -140), end: .init(x: 220, y: 140), layer: "walls", style: .default),
                .line(start: .init(x: 220, y: 140), end: .init(x: -220, y: 140), layer: "walls", style: .default),
                .line(start: .init(x: -220, y: 140), end: .init(x: -220, y: -140), layer: "walls", style: .default),
                .circle(center: .init(x: 0, y: 0), radius: 60, layer: "columns", style: .default)
            ]
        )
    }

    @objc private func resetViewPressed(_ sender: Any?) {
        canvasView.resetView()
    }

    @objc func commandShowDXFSource(_ sender: Any?) {
        if let sourcePanel {
            sourcePanel.makeKeyAndOrderFront(nil)
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
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor
        panel.contentView = content

        sourceTextView.isEditable = false
        sourceTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        sourceTextView.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        sourceTextView.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        sourceTextView.textContainerInset = NSSize(width: 12, height: 12)
        sourceTextView.string = DXFCodec.serialize(document: document)

        let scroll = NSScrollView(frame: content.bounds)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        scroll.documentView = sourceTextView
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])

        sourcePanel = panel
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

    private func configureToolButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .texturedRounded
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
        for units in DXFUnits.allCases {
            unitsPopup.addItem(withTitle: "Units: \(units.label)")
            unitsPopup.lastItem?.tag = units.rawValue
        }
        unitsPopup.selectItem(withTag: document.units.rawValue)
        unitsPopup.sizeToFit()

        gridPopup.target = self
        gridPopup.action = #selector(gridChanged(_:))
        gridPopup.font = .systemFont(ofSize: 11, weight: .medium)
        for value in gridStepValues {
            gridPopup.addItem(withTitle: "Grid \(formatDraftValue(value))")
        }
        gridPopup.selectItem(at: 3)
        gridPopup.sizeToFit()

        snapPopup.target = self
        snapPopup.action = #selector(snapStepChanged(_:))
        snapPopup.font = .systemFont(ofSize: 11, weight: .medium)
        for value in snapStepValues {
            snapPopup.addItem(withTitle: "Snap \(formatDraftValue(value))")
        }
        snapPopup.selectItem(at: 3)
        snapPopup.sizeToFit()

        snapToggle.target = self
        snapToggle.action = #selector(snapToggleChanged(_:))
        snapToggle.font = .systemFont(ofSize: 11, weight: .medium)
        snapToggle.state = .on
        snapToggle.controlSize = .small

        orthoToggle.target = self
        orthoToggle.action = #selector(orthoToggleChanged(_:))
        orthoToggle.font = .systemFont(ofSize: 11, weight: .medium)
        orthoToggle.state = .off
        orthoToggle.controlSize = .small
    }

    private func configureCommandInput() {
        commandLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        commandLabel.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        commandField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        commandField.placeholderString = "LINE x1,y1 x2,y2  |  ZOOM EXTENTS"
        commandField.focusRingType = .none
        commandField.target = self
        commandField.action = #selector(commandSubmitted(_:))
    }

    private func applyDraftingSettings() {
        canvasView.configureDrafting(
            gridStep: currentGridStep,
            snapStep: currentSnapStep,
            snapEnabled: isSnapEnabled,
            orthoEnabled: isOrthoEnabled
        )
        refreshUI()
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
            document = next
        }
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
        executeCommand(raw)
    }

    private func executeCommand(_ text: String) {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let cmd = parts.first?.lowercased() else { return }
        switch cmd {
        case "l", "line":
            if parts.count >= 3, let p1 = parsePoint(parts[1], base: nil), let p2 = parsePoint(parts[2], base: p1) {
                appendLine(start: p1, end: p2)
                commandBasePoint = p2
            } else {
                applyActiveTool(.line)
            }
        case "c", "circle":
            if parts.count >= 3, let center = parsePoint(parts[1], base: nil), let r = Double(parts[2]) {
                appendCircle(center: center, radius: CGFloat(max(0.0001, r)))
                commandBasePoint = center
            } else {
                applyActiveTool(.circle)
            }
        case "rec", "rect", "rectangle":
            if parts.count >= 3, let p1 = parsePoint(parts[1], base: nil), let p2 = parsePoint(parts[2], base: p1) {
                appendRectangle(cornerA: p1, cornerB: p2)
                commandBasePoint = p2
            } else {
                applyActiveTool(.rectangle)
            }
        case "pl", "pline", "polyline":
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
                document = next
            }
        default:
            NSSound.beep()
        }
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
