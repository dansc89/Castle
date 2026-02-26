import AppKit
import CoreGraphics
import Foundation

enum DXFCodecError: Error {
    case invalidUTF8
}

enum DXFCodec {
    static func parse(data: Data, defaultName: String = "Untitled") throws -> DXFDocument {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DXFCodecError.invalidUTF8
        }
        return parse(text: text, defaultName: defaultName)
    }

    static func parse(text: String, defaultName: String = "Untitled") -> DXFDocument {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var pairs: [(String, String)] = []
        var i = 0
        while i + 1 < lines.count {
            let code = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            pairs.append((code, value))
            i += 2
        }

        var entities: [DXFEntity] = []
        var units: DXFUnits = .millimeters
        var layerStyles: [String: DXFLayerStyle] = [:]
        var currentSection = ""
        var blockDefinitions: [String: [DXFEntity]] = [:]
        var currentBlockName: String?
        var currentBlockEntities: [DXFEntity] = []
        var index = 0

        while index < pairs.count {
            let (code, value) = pairs[index]
            let type = value.uppercased()

            if code == "0", type == "SECTION" {
                if index + 1 < pairs.count, pairs[index + 1].0 == "2" {
                    currentSection = pairs[index + 1].1.uppercased()
                    index += 2
                    continue
                }
            }
            if code == "0", type == "ENDSEC" {
                if let blockName = currentBlockName {
                    blockDefinitions[blockName] = currentBlockEntities
                    currentBlockName = nil
                    currentBlockEntities = []
                }
                currentSection = ""
                index += 1
                continue
            }

            if code == "9", value.uppercased() == "$INSUNITS" {
                if index + 1 < pairs.count, pairs[index + 1].0 == "70" {
                    let rawUnits = Int(pairs[index + 1].1) ?? DXFUnits.millimeters.rawValue
                    units = DXFUnits(rawValue: rawUnits) ?? .millimeters
                    index += 2
                    continue
                }
            }

            if currentSection == "TABLES", code == "0", type == "LAYER" {
                let parsed = parseLayerStyle(pairs: pairs, startIndex: index)
                layerStyles[parsed.name] = parsed.style
                index = parsed.nextIndex
                continue
            }

            if currentSection == "BLOCKS", code == "0", type == "BLOCK" {
                let payloadStart = index + 1
                var cursor = payloadStart
                var blockName = ""
                while cursor < pairs.count {
                    let (c, v) = pairs[cursor]
                    if c == "0" { break }
                    if c == "2" { blockName = v }
                    cursor += 1
                }
                currentBlockName = blockName
                currentBlockEntities = []
                index = cursor
                continue
            }

            if currentSection == "BLOCKS", code == "0", type == "ENDBLK" {
                if let blockName = currentBlockName {
                    blockDefinitions[blockName] = currentBlockEntities
                }
                currentBlockName = nil
                currentBlockEntities = []
                index += 1
                continue
            }

            if code == "0" {
                switch type {
                case "LINE":
                    let parsed = parseLine(pairs: pairs, startIndex: index)
                    if currentSection == "ENTITIES" {
                        entities.append(parsed.entity)
                    } else if currentSection == "BLOCKS", currentBlockName != nil {
                        currentBlockEntities.append(parsed.entity)
                    }
                    index = parsed.nextIndex
                    continue
                case "CIRCLE":
                    let parsed = parseCircle(pairs: pairs, startIndex: index)
                    if currentSection == "ENTITIES" {
                        entities.append(parsed.entity)
                    } else if currentSection == "BLOCKS", currentBlockName != nil {
                        currentBlockEntities.append(parsed.entity)
                    }
                    index = parsed.nextIndex
                    continue
                case "ARC":
                    let parsed = parseArcAsLines(pairs: pairs, startIndex: index)
                    if currentSection == "ENTITIES" {
                        entities.append(contentsOf: parsed.entities)
                    } else if currentSection == "BLOCKS", currentBlockName != nil {
                        currentBlockEntities.append(contentsOf: parsed.entities)
                    }
                    index = parsed.nextIndex
                    continue
                case "LWPOLYLINE":
                    let parsed = parseLWPolylineAsLines(pairs: pairs, startIndex: index)
                    if currentSection == "ENTITIES" {
                        entities.append(contentsOf: parsed.entities)
                    } else if currentSection == "BLOCKS", currentBlockName != nil {
                        currentBlockEntities.append(contentsOf: parsed.entities)
                    }
                    index = parsed.nextIndex
                    continue
                case "POLYLINE":
                    let parsed = parsePolylineAsLines(pairs: pairs, startIndex: index)
                    if currentSection == "ENTITIES" {
                        entities.append(contentsOf: parsed.entities)
                    } else if currentSection == "BLOCKS", currentBlockName != nil {
                        currentBlockEntities.append(contentsOf: parsed.entities)
                    }
                    index = parsed.nextIndex
                    continue
                case "INSERT":
                    if currentSection == "ENTITIES" {
                        let parsed = parseInsert(pairs: pairs, startIndex: index)
                        if let blockEntities = blockDefinitions[parsed.blockName] {
                            entities.append(contentsOf: blockEntities.map {
                                transform(entity: $0, insertion: parsed.insertion, scaleX: parsed.scaleX, scaleY: parsed.scaleY, rotationDegrees: parsed.rotation)
                            })
                        }
                        index = parsed.nextIndex
                        continue
                    }
                default:
                    break
                }
            }
            index += 1
        }

        return DXFDocument(name: defaultName, units: units, layerStyles: layerStyles, entities: entities)
    }

    static func serialize(document: DXFDocument) -> String {
        var lines: [String] = []
        func append(_ code: String, _ value: String) {
            lines.append(code)
            lines.append(value)
        }

        append("0", "SECTION")
        append("2", "HEADER")
        append("9", "$INSUNITS")
        append("70", "\(document.units.rawValue)")
        append("0", "ENDSEC")
        append("0", "SECTION")
        append("2", "ENTITIES")

        for entity in document.entities {
            switch entity {
            case let .line(start, end, layer, style):
                append("0", "LINE")
                append("8", layer)
                appendStyle(style, append: append)
                append("10", format(start.x))
                append("20", format(start.y))
                append("11", format(end.x))
                append("21", format(end.y))
            case let .circle(center, radius, layer, style):
                append("0", "CIRCLE")
                append("8", layer)
                appendStyle(style, append: append)
                append("10", format(center.x))
                append("20", format(center.y))
                append("40", format(radius))
            }
        }

        append("0", "ENDSEC")
        append("0", "EOF")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.6f", Double(value))
    }

    private static func appendStyle(_ style: DXFEntityStyle, append: (_ code: String, _ value: String) -> Void) {
        if let color = style.color {
            append("420", "\(encodeTrueColor(color))")
        }
        if let lineWeight = style.lineWeight {
            append("370", "\(Int((lineWeight * 100).rounded()))")
        }
    }

    private static func parseLayerStyle(
        pairs: [(String, String)],
        startIndex: Int
    ) -> (name: String, style: DXFLayerStyle, nextIndex: Int) {
        var name = "0"
        var aci: Int?
        var trueColor: Int?
        var lineWeightRaw: Int?
        var index = startIndex + 1
        while index < pairs.count {
            let (c, v) = pairs[index]
            if c == "0" { break }
            switch c {
            case "2": name = v
            case "62": aci = Int(v)
            case "420": trueColor = Int(v)
            case "370": lineWeightRaw = Int(v)
            default: break
            }
            index += 1
        }
        return (
            name,
            DXFLayerStyle(
                color: resolveColor(aci: aci, trueColor: trueColor),
                lineWeight: resolveLineWeight(raw: lineWeightRaw)
            ),
            index
        )
    }

    private static func parseLine(
        pairs: [(String, String)],
        startIndex: Int
    ) -> (entity: DXFEntity, nextIndex: Int) {
        var layer = "0"
        var x1: CGFloat = 0
        var y1: CGFloat = 0
        var x2: CGFloat = 0
        var y2: CGFloat = 0
        var aci: Int?
        var trueColor: Int?
        var lineWeightRaw: Int?
        var index = startIndex + 1
        while index < pairs.count {
            let (c, v) = pairs[index]
            if c == "0" { break }
            switch c {
            case "8": layer = v
            case "10": x1 = CGFloat(Double(v) ?? 0)
            case "20": y1 = CGFloat(Double(v) ?? 0)
            case "11": x2 = CGFloat(Double(v) ?? 0)
            case "21": y2 = CGFloat(Double(v) ?? 0)
            case "62": aci = Int(v)
            case "420": trueColor = Int(v)
            case "370": lineWeightRaw = Int(v)
            default: break
            }
            index += 1
        }
        let style = DXFEntityStyle(color: resolveColor(aci: aci, trueColor: trueColor), lineWeight: resolveLineWeight(raw: lineWeightRaw))
        return (.line(start: .init(x: x1, y: y1), end: .init(x: x2, y: y2), layer: layer, style: style), index)
    }

    private static func parseCircle(
        pairs: [(String, String)],
        startIndex: Int
    ) -> (entity: DXFEntity, nextIndex: Int) {
        var layer = "0"
        var x: CGFloat = 0
        var y: CGFloat = 0
        var radius: CGFloat = 0
        var aci: Int?
        var trueColor: Int?
        var lineWeightRaw: Int?
        var index = startIndex + 1
        while index < pairs.count {
            let (c, v) = pairs[index]
            if c == "0" { break }
            switch c {
            case "8": layer = v
            case "10": x = CGFloat(Double(v) ?? 0)
            case "20": y = CGFloat(Double(v) ?? 0)
            case "40": radius = CGFloat(Double(v) ?? 0)
            case "62": aci = Int(v)
            case "420": trueColor = Int(v)
            case "370": lineWeightRaw = Int(v)
            default: break
            }
            index += 1
        }
        let style = DXFEntityStyle(color: resolveColor(aci: aci, trueColor: trueColor), lineWeight: resolveLineWeight(raw: lineWeightRaw))
        return (.circle(center: .init(x: x, y: y), radius: radius, layer: layer, style: style), index)
    }

    private static func parseArcAsLines(
        pairs: [(String, String)],
        startIndex: Int
    ) -> (entities: [DXFEntity], nextIndex: Int) {
        var layer = "0"
        var cx: CGFloat = 0
        var cy: CGFloat = 0
        var radius: CGFloat = 0
        var startAngle: CGFloat = 0
        var endAngle: CGFloat = 0
        var aci: Int?
        var trueColor: Int?
        var lineWeightRaw: Int?
        var index = startIndex + 1
        while index < pairs.count {
            let (c, v) = pairs[index]
            if c == "0" { break }
            switch c {
            case "8": layer = v
            case "10": cx = CGFloat(Double(v) ?? 0)
            case "20": cy = CGFloat(Double(v) ?? 0)
            case "40": radius = CGFloat(Double(v) ?? 0)
            case "50": startAngle = CGFloat(Double(v) ?? 0)
            case "51": endAngle = CGFloat(Double(v) ?? 0)
            case "62": aci = Int(v)
            case "420": trueColor = Int(v)
            case "370": lineWeightRaw = Int(v)
            default: break
            }
            index += 1
        }
        guard radius > 0 else { return ([], index) }

        let style = DXFEntityStyle(color: resolveColor(aci: aci, trueColor: trueColor), lineWeight: resolveLineWeight(raw: lineWeightRaw))
        var sweep = endAngle - startAngle
        if sweep <= 0 { sweep += 360 }
        let segments = max(8, Int(ceil(abs(sweep) / 12)))
        var entities: [DXFEntity] = []
        var previous = arcPoint(cx: cx, cy: cy, r: radius, deg: startAngle)
        for step in 1...segments {
            let t = CGFloat(step) / CGFloat(segments)
            let angle = startAngle + sweep * t
            let current = arcPoint(cx: cx, cy: cy, r: radius, deg: angle)
            entities.append(.line(start: previous, end: current, layer: layer, style: style))
            previous = current
        }
        return (entities, index)
    }

    private static func parseLWPolylineAsLines(
        pairs: [(String, String)],
        startIndex: Int
    ) -> (entities: [DXFEntity], nextIndex: Int) {
        var layer = "0"
        var flags = 0
        var points: [DXFPoint] = []
        var pendingX: CGFloat?
        var aci: Int?
        var trueColor: Int?
        var lineWeightRaw: Int?
        var index = startIndex + 1
        while index < pairs.count {
            let (c, v) = pairs[index]
            if c == "0" { break }
            switch c {
            case "8": layer = v
            case "70": flags = Int(v) ?? 0
            case "10": pendingX = CGFloat(Double(v) ?? 0)
            case "20":
                let y = CGFloat(Double(v) ?? 0)
                if let x = pendingX {
                    points.append(DXFPoint(x: x, y: y))
                    pendingX = nil
                }
            case "62": aci = Int(v)
            case "420": trueColor = Int(v)
            case "370": lineWeightRaw = Int(v)
            default: break
            }
            index += 1
        }
        let style = DXFEntityStyle(color: resolveColor(aci: aci, trueColor: trueColor), lineWeight: resolveLineWeight(raw: lineWeightRaw))
        return (polylineSegments(points: points, closed: (flags & 1) == 1, layer: layer, style: style), index)
    }

    private static func parsePolylineAsLines(
        pairs: [(String, String)],
        startIndex: Int
    ) -> (entities: [DXFEntity], nextIndex: Int) {
        var layer = "0"
        var flags = 0
        var points: [DXFPoint] = []
        var aci: Int?
        var trueColor: Int?
        var lineWeightRaw: Int?
        var index = startIndex + 1

        while index < pairs.count {
            let (c, v) = pairs[index]
            if c == "0" { break }
            switch c {
            case "8": layer = v
            case "70": flags = Int(v) ?? 0
            case "62": aci = Int(v)
            case "420": trueColor = Int(v)
            case "370": lineWeightRaw = Int(v)
            default: break
            }
            index += 1
        }

        while index < pairs.count {
            let (c, v) = pairs[index]
            if c != "0" { index += 1; continue }
            let kind = v.uppercased()
            if kind == "SEQEND" {
                index += 1
                break
            }
            if kind != "VERTEX" { break }
            var vx: CGFloat = 0
            var vy: CGFloat = 0
            var cursor = index + 1
            while cursor < pairs.count {
                let (vc, vv) = pairs[cursor]
                if vc == "0" { break }
                switch vc {
                case "10": vx = CGFloat(Double(vv) ?? 0)
                case "20": vy = CGFloat(Double(vv) ?? 0)
                default: break
                }
                cursor += 1
            }
            points.append(DXFPoint(x: vx, y: vy))
            index = cursor
        }

        let style = DXFEntityStyle(color: resolveColor(aci: aci, trueColor: trueColor), lineWeight: resolveLineWeight(raw: lineWeightRaw))
        return (polylineSegments(points: points, closed: (flags & 1) == 1, layer: layer, style: style), index)
    }

    private static func parseInsert(
        pairs: [(String, String)],
        startIndex: Int
    ) -> (blockName: String, insertion: DXFPoint, scaleX: CGFloat, scaleY: CGFloat, rotation: CGFloat, nextIndex: Int) {
        var blockName = ""
        var x: CGFloat = 0
        var y: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var rotation: CGFloat = 0
        var index = startIndex + 1
        while index < pairs.count {
            let (c, v) = pairs[index]
            if c == "0" { break }
            switch c {
            case "2": blockName = v
            case "10": x = CGFloat(Double(v) ?? 0)
            case "20": y = CGFloat(Double(v) ?? 0)
            case "41": scaleX = CGFloat(Double(v) ?? 1)
            case "42": scaleY = CGFloat(Double(v) ?? 1)
            case "50": rotation = CGFloat(Double(v) ?? 0)
            default: break
            }
            index += 1
        }
        return (blockName, DXFPoint(x: x, y: y), scaleX, scaleY, rotation, index)
    }

    private static func polylineSegments(points: [DXFPoint], closed: Bool, layer: String, style: DXFEntityStyle) -> [DXFEntity] {
        guard points.count >= 2 else { return [] }
        var entities: [DXFEntity] = []
        for i in 0..<(points.count - 1) {
            entities.append(.line(start: points[i], end: points[i + 1], layer: layer, style: style))
        }
        if closed {
            entities.append(.line(start: points[points.count - 1], end: points[0], layer: layer, style: style))
        }
        return entities
    }

    private static func arcPoint(cx: CGFloat, cy: CGFloat, r: CGFloat, deg: CGFloat) -> DXFPoint {
        let rad = deg * .pi / 180
        return DXFPoint(x: cx + cos(rad) * r, y: cy + sin(rad) * r)
    }

    private static func transform(
        entity: DXFEntity,
        insertion: DXFPoint,
        scaleX: CGFloat,
        scaleY: CGFloat,
        rotationDegrees: CGFloat
    ) -> DXFEntity {
        let rad = rotationDegrees * .pi / 180
        let cosA = cos(rad)
        let sinA = sin(rad)

        func transformPoint(_ p: DXFPoint) -> DXFPoint {
            let sx = p.x * scaleX
            let sy = p.y * scaleY
            return DXFPoint(x: sx * cosA - sy * sinA + insertion.x, y: sx * sinA + sy * cosA + insertion.y)
        }

        switch entity {
        case let .line(start, end, layer, style):
            return .line(start: transformPoint(start), end: transformPoint(end), layer: layer, style: style)
        case let .circle(center, radius, layer, style):
            let c = transformPoint(center)
            let scale = max(0.0001, (abs(scaleX) + abs(scaleY)) * 0.5)
            return .circle(center: c, radius: radius * scale, layer: layer, style: style)
        }
    }

    private static func resolveLineWeight(raw: Int?) -> CGFloat? {
        guard let raw else { return nil }
        if raw < 0 { return nil }
        return CGFloat(raw) / 100.0
    }

    private static func resolveColor(aci: Int?, trueColor: Int?) -> DXFColor? {
        if let trueColor {
            return decodeTrueColor(trueColor)
        }
        guard let aci else { return nil }
        if aci == 0 || aci == 256 || aci == 257 { return nil }
        return colorFromACI(abs(aci))
    }

    private static func decodeTrueColor(_ value: Int) -> DXFColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return DXFColor(r: r, g: g, b: b)
    }

    private static func encodeTrueColor(_ color: DXFColor) -> Int {
        let r = max(0, min(255, Int((color.r * 255).rounded())))
        let g = max(0, min(255, Int((color.g * 255).rounded())))
        let b = max(0, min(255, Int((color.b * 255).rounded())))
        return (r << 16) | (g << 8) | b
    }

    private static func colorFromACI(_ index: Int) -> DXFColor {
        switch index {
        case 1: return DXFColor(r: 1.0, g: 0.0, b: 0.0)
        case 2: return DXFColor(r: 1.0, g: 1.0, b: 0.0)
        case 3: return DXFColor(r: 0.0, g: 1.0, b: 0.0)
        case 4: return DXFColor(r: 0.0, g: 1.0, b: 1.0)
        case 5: return DXFColor(r: 0.0, g: 0.0, b: 1.0)
        case 6: return DXFColor(r: 1.0, g: 0.0, b: 1.0)
        case 7: return DXFColor(r: 1.0, g: 1.0, b: 1.0)
        case 8: return DXFColor(r: 0.55, g: 0.55, b: 0.55)
        case 9: return DXFColor(r: 0.75, g: 0.75, b: 0.75)
        default:
            let hue = CGFloat((index % 255)) / 255.0
            let color = NSColor(calibratedHue: hue, saturation: 0.85, brightness: 0.95, alpha: 1)
            return DXFColor(r: color.redComponent, g: color.greenComponent, b: color.blueComponent)
        }
    }
}
