import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct WindowSession {
        var window: NSWindow
        var controller: MainViewController
        var documentURL: URL?
    }

    private var sessions: [ObjectIdentifier: WindowSession] = [:]
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = createWindowSession()
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
        openDocument(at: URL(fileURLWithPath: filename), inNewWindow: true, replacingWindow: nil)
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else {
            application.reply(toOpenOrPrint: .failure)
            return
        }
        let success = openDocument(at: URL(fileURLWithPath: first), inNewWindow: true, replacingWindow: nil)
        application.reply(toOpenOrPrint: success ? .success : .failure)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        _ = openDocument(at: first, inNewWindow: true, replacingWindow: nil)
    }

    func openDocumentFromDrop(_ url: URL, sourceWindow: NSWindow?) {
        let ext = url.pathExtension.lowercased()
        guard ext == "dxf" || ext == "dwg" else {
            NSSound.beep()
            return
        }
        _ = openDocument(at: url, inNewWindow: true, replacingWindow: sourceWindow)
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
        fileMenu.addItem(withTitle: "New Window", action: #selector(newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open DXF...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Import DWG (Convert to DXF)...", action: #selector(importDWG(_:)), keyEquivalent: "O")
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
        _ = createWindowSession()
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "dxf")!, .init(filenameExtension: "dwg")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = openDocument(at: url, inNewWindow: true, replacingWindow: nil)
    }

    @objc private func importDWG(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "dwg")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = openDocument(at: url, inNewWindow: true, replacingWindow: nil)
    }

    @objc private func saveDocument(_ sender: Any?) {
        guard let session = activeSession() else { return }
        if let url = session.documentURL {
            do {
                try session.controller.saveDocument(to: url)
            } catch {
                showError("Could not save DXF.", error: error)
            }
            return
        }
        saveDocumentAs(sender)
    }

    @objc private func saveDocumentAs(_ sender: Any?) {
        guard let session = activeSession() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "dxf")!]
        panel.nameFieldStringValue = "drawing.dxf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try session.controller.saveDocument(to: url)
            updateDocumentURL(url, for: session.window)
        } catch {
            showError("Could not save DXF.", error: error)
        }
    }

    @objc private func publishPDF(_ sender: Any?) {
        guard let session = activeSession() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "drawing.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try session.controller.publishPDF(to: url)
        } catch {
            showError("Could not publish PDF.", error: error)
        }
    }

    @objc private func deleteSelectedEntity(_ sender: Any?) {
        activeSession()?.controller.deleteSelectedEntity()
    }

    @objc private func selectToolMenu(_ sender: Any?) {
        activeSession()?.controller.selectSelectionTool(sender)
    }

    @objc private func lineToolMenu(_ sender: Any?) {
        activeSession()?.controller.selectLineTool(sender)
    }

    @objc private func polylineToolMenu(_ sender: Any?) {
        activeSession()?.controller.selectPolylineTool(sender)
    }

    @objc private func rectangleToolMenu(_ sender: Any?) {
        activeSession()?.controller.selectRectangleTool(sender)
    }

    @objc private func circleToolMenu(_ sender: Any?) {
        activeSession()?.controller.selectCircleTool(sender)
    }

    @objc private func toggleFullScreen(_ sender: Any?) {
        activeSession()?.window.toggleFullScreen(sender)
    }

    @objc private func showDXFSource(_ sender: Any?) {
        activeSession()?.controller.commandShowDXFSource(sender)
    }

    private func installShortcutMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let session = self.activeSession() else { return event }
            if session.controller.handleShortcutEvent(event) {
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

    private func createWindowSession() -> WindowSession {
        let controller = MainViewController()
        let window = makeWindow(contentViewController: controller)
        let session = WindowSession(window: window, controller: controller, documentURL: nil)
        sessions[ObjectIdentifier(window)] = session
        return session
    }

    private func makeWindow(contentViewController: NSViewController) -> NSWindow {
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
        window.contentViewController = contentViewController
        window.minSize = NSSize(width: 920, height: 600)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
        window.setFrame(rect, display: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        sessions.removeValue(forKey: ObjectIdentifier(window))
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }

    @discardableResult
    private func openDocument(at url: URL, inNewWindow: Bool, replacingWindow: NSWindow?) -> Bool {
        let ext = url.pathExtension.lowercased()
        let resolvedURL: URL
        if ext == "dwg" {
            do {
                let result = try DWGImportService.importDWG(sourceURL: url)
                resolvedURL = result.convertedDXFURL
                showImportResult(converter: result.converterUsed, reportURL: result.reportURL)
            } catch {
                showError("Could not import DWG.", error: error)
                return false
            }
        } else if ext == "dxf" {
            resolvedURL = url
        } else {
            showError("Could not open drawing.", error: NSError(domain: "Castle", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type: \(url.pathExtension)"]))
            return false
        }

        let targetSession: WindowSession
        if inNewWindow {
            targetSession = createWindowSession()
        } else if let active = activeSession() {
            targetSession = active
        } else {
            targetSession = createWindowSession()
        }

        do {
            try targetSession.controller.loadDocument(from: resolvedURL)
            updateDocumentURL(resolvedURL, for: targetSession.window)
            targetSession.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let replacingWindow, replacingWindow != targetSession.window {
                replacingWindow.performClose(nil)
            }
            return true
        } catch {
            showError("Could not open DXF.", error: error)
            if inNewWindow {
                targetSession.window.close()
            }
            return false
        }
    }

    private func showImportResult(converter: String, reportURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "DWG Imported"
        alert.informativeText = "Converted with \(converter).\nValidation report: \(reportURL.path)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func activeSession() -> WindowSession? {
        if let keyWindow = NSApp.keyWindow, let session = sessions[ObjectIdentifier(keyWindow)] {
            return session
        }
        return sessions.values.first
    }

    private func updateDocumentURL(_ url: URL?, for window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard var session = sessions[key] else { return }
        session.documentURL = url
        sessions[key] = session
    }
}
