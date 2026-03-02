import CoreGraphics
import Foundation

struct LayoutSheet: Equatable, Identifiable {
    let id: UUID
    var name: String
    var size: LayoutSheetSize
    var viewports: [LayoutViewport]

    init(id: UUID = UUID(), name: String, size: LayoutSheetSize, viewports: [LayoutViewport] = []) {
        self.id = id
        self.name = name
        self.size = size
        self.viewports = viewports
    }
}

struct LayoutViewport: Equatable, Identifiable {
    let id: UUID
    var rectInPaperInches: CGRect
    var modelCenter: DXFPoint
    var scale: LayoutViewportScale

    init(
        id: UUID = UUID(),
        rectInPaperInches: CGRect,
        modelCenter: DXFPoint = .init(x: 0, y: 0),
        scale: LayoutViewportScale = .oneToOne
    ) {
        self.id = id
        self.rectInPaperInches = rectInPaperInches
        self.modelCenter = modelCenter
        self.scale = scale
    }
}

struct LayoutViewportScale: Equatable {
    var label: String
    var modelUnitsPerPaperInch: CGFloat

    static let oneToOne = LayoutViewportScale(label: "1:1", modelUnitsPerPaperInch: 1)
    static let quarterInch = LayoutViewportScale(label: "1/4\"=1'-0\"", modelUnitsPerPaperInch: 48)
    static let eighthInch = LayoutViewportScale(label: "1/8\"=1'-0\"", modelUnitsPerPaperInch: 96)
    static let sixteenthInch = LayoutViewportScale(label: "1/16\"=1'-0\"", modelUnitsPerPaperInch: 192)
}

enum LayoutSheetSize: String, CaseIterable, Equatable {
    case ansiA = "8.5x11"
    case ansiB = "11x17"
    case archC = "18x24"
    case archD = "24x36"
    case archE1 = "30x42"
    case archE = "36x48"

    var label: String {
        switch self {
        case .ansiA: return "ANSI A 8.5x11"
        case .ansiB: return "ANSI B 11x17"
        case .archC: return "ARCH C 18x24"
        case .archD: return "ARCH D 24x36"
        case .archE1: return "ARCH E1 30x42"
        case .archE: return "ARCH E 36x48"
        }
    }

    var inches: CGSize {
        switch self {
        case .ansiA: return .init(width: 8.5, height: 11)
        case .ansiB: return .init(width: 11, height: 17)
        case .archC: return .init(width: 18, height: 24)
        case .archD: return .init(width: 24, height: 36)
        case .archE1: return .init(width: 30, height: 42)
        case .archE: return .init(width: 36, height: 48)
        }
    }

    static func parse(_ token: String) -> LayoutSheetSize? {
        let normalized = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "a", "ansia", "8.5x11", "8.5x11in", "letter":
            return .ansiA
        case "b", "ansib", "11x17", "11x17in", "tabloid":
            return .ansiB
        case "c", "archc", "18x24", "18x24in":
            return .archC
        case "d", "archd", "24x36", "24x36in":
            return .archD
        case "e1", "arche1", "30x42", "30x42in":
            return .archE1
        case "e", "arche", "36x48", "36x48in":
            return .archE
        default:
            return nil
        }
    }
}
