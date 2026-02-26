import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let mainViewController = MainViewController()
    private var currentDocumentURL: URL?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let launchWidth = min(max(1420, visibleFrame.width * 0.94), visibleFrame.width * 0.99)
        let launchHeight = min(max(820, visibleFrame.height * 0.88), visibleFrame.height * 0.96)
        let rect = NSRect(
            x: visibleFrame.midX - launchWidth * 0.5,
            y: visibleFrame.midY - launchHeight * 0.5,
            width: launchWidth,
            height: launchHeight
        ).integral

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Castle"
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.alphaValue = 1.0
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0)
        window.isMovableByWindowBackground = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = mainViewController
        window.minSize = NSSize(width: 920, height: 600)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
        window.setFrame(rect, display: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        setupMainMenu()
        installShortcutMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openDocument(at: URL(fileURLWithPath: filename))
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else {
            application.reply(toOpenOrPrint: .failure)
            return
        }
        let success = openDocument(at: URL(fileURLWithPath: first))
        application.reply(toOpenOrPrint: success ? .success : .failure)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        _ = openDocument(at: first)
    }

    private func setupMainMenu() {
        let menu = NSMenu()

        let appItem = NSMenuItem()
        appItem.title = "Castle"
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Castle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        fileItem.title = "File"
        menu.addItem(fileItem)
        let fileMenu = NSMenu()
        fileMenu.addItem(withTitle: "New", action: #selector(newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open DXF...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: "Save As DXF...", action: #selector(saveDocumentAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(NSMenuItem.separator())
        let publish = fileMenu.addItem(withTitle: "Publish to PDF...", action: #selector(publishPDF(_:)), keyEquivalent: "p")
        publish.keyEquivalentModifierMask = [.command, .shift]
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        editItem.title = "Edit"
        menu.addItem(editItem)
        let editMenu = NSMenu()
        let deleteItem = editMenu.addItem(withTitle: "Delete Selected Entity", action: #selector(deleteSelectedEntity(_:)), keyEquivalent: "\u{8}")
        deleteItem.target = self
        editItem.submenu = editMenu

        let toolsItem = NSMenuItem()
        toolsItem.title = "Tools"
        menu.addItem(toolsItem)
        let toolsMenu = NSMenu()
        let selectToolItem = toolsMenu.addItem(withTitle: "Select Tool", action: #selector(selectToolMenu(_:)), keyEquivalent: "v")
        selectToolItem.keyEquivalentModifierMask = []
        selectToolItem.target = self
        let lineToolItem = toolsMenu.addItem(withTitle: "Line Tool", action: #selector(lineToolMenu(_:)), keyEquivalent: "l")
        lineToolItem.keyEquivalentModifierMask = []
        lineToolItem.target = self
        let polylineToolItem = toolsMenu.addItem(withTitle: "Polyline Tool", action: #selector(polylineToolMenu(_:)), keyEquivalent: "P")
        polylineToolItem.keyEquivalentModifierMask = [.shift]
        polylineToolItem.target = self
        let rectToolItem = toolsMenu.addItem(withTitle: "Rectangle Tool", action: #selector(rectangleToolMenu(_:)), keyEquivalent: "r")
        rectToolItem.keyEquivalentModifierMask = []
        rectToolItem.target = self
        let circleToolItem = toolsMenu.addItem(withTitle: "Circle Tool", action: #selector(circleToolMenu(_:)), keyEquivalent: "e")
        circleToolItem.keyEquivalentModifierMask = []
        circleToolItem.target = self
        toolsItem.submenu = toolsMenu

        let viewItem = NSMenuItem()
        viewItem.title = "View"
        menu.addItem(viewItem)
        let viewMenu = NSMenu()
        let sourceItem = viewMenu.addItem(withTitle: "DXF Source...", action: #selector(showDXFSource(_:)), keyEquivalent: "u")
        sourceItem.keyEquivalentModifierMask = [.command, .shift]
        sourceItem.target = self
        let fullscreenItem = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        fullscreenItem.target = self
        viewItem.submenu = viewMenu

        NSApp.mainMenu = menu
    }

    @objc private func newDocument(_ sender: Any?) {
        currentDocumentURL = nil
        mainViewController.newDocument()
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "dxf")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = openDocument(at: url)
    }

    @objc private func saveDocument(_ sender: Any?) {
        if let url = currentDocumentURL {
            do {
                try mainViewController.saveDocument(to: url)
            } catch {
                showError("Could not save DXF.", error: error)
            }
            return
        }
        saveDocumentAs(sender)
    }

    @objc private func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "dxf")!]
        panel.nameFieldStringValue = "drawing.dxf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try mainViewController.saveDocument(to: url)
            currentDocumentURL = url
        } catch {
            showError("Could not save DXF.", error: error)
        }
    }

    @objc private func publishPDF(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "drawing.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try mainViewController.publishPDF(to: url)
        } catch {
            showError("Could not publish PDF.", error: error)
        }
    }

    @objc private func deleteSelectedEntity(_ sender: Any?) {
        mainViewController.deleteSelectedEntity()
    }

    @objc private func selectToolMenu(_ sender: Any?) {
        mainViewController.selectSelectionTool(sender)
    }

    @objc private func lineToolMenu(_ sender: Any?) {
        mainViewController.selectLineTool(sender)
    }

    @objc private func polylineToolMenu(_ sender: Any?) {
        mainViewController.selectPolylineTool(sender)
    }

    @objc private func rectangleToolMenu(_ sender: Any?) {
        mainViewController.selectRectangleTool(sender)
    }

    @objc private func circleToolMenu(_ sender: Any?) {
        mainViewController.selectCircleTool(sender)
    }

    @objc private func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }

    @objc private func showDXFSource(_ sender: Any?) {
        mainViewController.commandShowDXFSource(sender)
    }

    private func installShortcutMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.mainViewController.handleShortcutEvent(event) {
                return nil
            }
            return event
        }
    }

    private func showError(_ message: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @discardableResult
    private func openDocument(at url: URL) -> Bool {
        do {
            try mainViewController.loadDocument(from: url)
            currentDocumentURL = url
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        } catch {
            showError("Could not open DXF.", error: error)
            return false
        }
    }
}
