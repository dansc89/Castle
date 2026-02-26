import AppKit

@MainActor
final class DXFDropHostView: NSView {
    var onDropDrawing: ((URL, NSWindow?) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        firstDrawingURL(from: sender) == nil ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        firstDrawingURL(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstDrawingURL(from: sender) else { return false }
        onDropDrawing?(url, window)
        return true
    }

    private func firstDrawingURL(from sender: NSDraggingInfo) -> URL? {
        let pasteboard = sender.draggingPasteboard
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return nil
        }
        return items.first {
            let ext = $0.pathExtension
            return ext.caseInsensitiveCompare("dxf") == .orderedSame || ext.caseInsensitiveCompare("dwg") == .orderedSame
        }
    }
}
