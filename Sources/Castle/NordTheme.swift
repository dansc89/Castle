import AppKit

enum NordTheme {
    // Neutral macOS-like dark palette so the app chrome aligns with system dark menu/title bars.
    static let polarNight0 = NSColor(hex: 0x1E1E1E)
    static let polarNight1 = NSColor(hex: 0x252526)
    static let polarNight2 = NSColor(hex: 0x2D2D30)
    static let polarNight3 = NSColor(hex: 0x3C3C3C)
    static let snowStorm0 = NSColor(hex: 0xC8C8C8)
    static let snowStorm1 = NSColor(hex: 0xD4D4D4)
    static let snowStorm2 = NSColor(hex: 0xE6E6E6)
    static let frost0 = NSColor(hex: 0xBFBFBF)
    static let frost1 = NSColor(hex: 0xA9A9A9)
    static let frost2 = NSColor(hex: 0x8F8F8F)
    static let frost3 = NSColor(hex: 0x707070)
    static let auroraRed = NSColor(hex: 0xC75C5C)
}

private extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }
}
