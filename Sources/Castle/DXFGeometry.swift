import CoreGraphics

struct DXFPoint: Equatable {
    var x: CGFloat
    var y: CGFloat
}

struct DXFColor: Equatable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
}

struct DXFEntityStyle: Equatable {
    var color: DXFColor?
    var lineWeight: CGFloat?

    static let `default` = DXFEntityStyle(color: nil, lineWeight: nil)
}

struct DXFLayerStyle: Equatable {
    var color: DXFColor?
    var lineWeight: CGFloat?
}

enum DXFEntity: Equatable {
    case line(start: DXFPoint, end: DXFPoint, layer: String, style: DXFEntityStyle)
    case circle(center: DXFPoint, radius: CGFloat, layer: String, style: DXFEntityStyle)
}

enum DXFUnits: Int, CaseIterable, Equatable {
    case unitless = 0
    case inches = 1
    case feet = 2
    case millimeters = 4
    case centimeters = 5
    case meters = 6

    var label: String {
        switch self {
        case .unitless: return "Unitless"
        case .inches: return "Inches"
        case .feet: return "Feet"
        case .millimeters: return "Millimeters"
        case .centimeters: return "Centimeters"
        case .meters: return "Meters"
        }
    }
}

struct DXFDocument: Equatable {
    var name: String
    var units: DXFUnits
    var layerStyles: [String: DXFLayerStyle]
    var entities: [DXFEntity]

    static let empty = DXFDocument(name: "Untitled", units: .millimeters, layerStyles: [:], entities: [])
}
