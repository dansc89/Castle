import CoreGraphics
import Foundation

enum PDFPublisher {
    static func publish(document: DXFDocument, to url: URL, pageSize: CGSize = CGSize(width: 1224, height: 792)) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.beginPDFPage(nil)
        context.setFillColor(gray: 0.98, alpha: 1)
        context.fill(mediaBox)
        context.translateBy(x: mediaBox.midX, y: mediaBox.midY)
        context.scaleBy(x: 1, y: -1)
        context.setLineWidth(1.0)

        for entity in document.entities {
            switch entity {
            case let .line(start, end, layer, style):
                applyStrokeStyle(style: style, layer: layer, document: document, context: context)
                context.move(to: CGPoint(x: start.x, y: start.y))
                context.addLine(to: CGPoint(x: end.x, y: end.y))
                context.strokePath()
            case let .circle(center, radius, layer, style):
                applyStrokeStyle(style: style, layer: layer, document: document, context: context)
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.strokeEllipse(in: rect)
            }
        }

        context.endPDFPage()
        context.closePDF()
    }

    private static func applyStrokeStyle(style: DXFEntityStyle, layer: String, document: DXFDocument, context: CGContext) {
        let layerStyle = document.layerStyles[layer]
        let color = style.color ?? layerStyle?.color
        if let color {
            context.setStrokeColor(red: color.r, green: color.g, blue: color.b, alpha: 1)
        } else {
            context.setStrokeColor(gray: 0.1, alpha: 1)
        }

        let lineWeight = style.lineWeight ?? layerStyle?.lineWeight ?? 0.25
        context.setLineWidth(max(0.35, lineWeight))
    }
}
