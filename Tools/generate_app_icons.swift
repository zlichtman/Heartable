import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Procedurally draws every app icon: a heart filled with a vibrant linear gradient
// (the theme's logoColor at top-left to a lightened version at bottom-right) on a
// solid backdrop that's white for light themes and near-black for dark themes.
// No source art needed. One icon per theme; no light/dark variants.
//
// Run from the repo root: swift Tools/generate_app_icons.swift

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path
let catalog = "\(root)/Heartable/Resources/Assets.xcassets"
let palettesPath = "\(root)/Heartable/Design/Palettes.swift"
let defaultKey = "midnight"
let fm = FileManager.default

let lightBG: (CGFloat, CGFloat, CGFloat) = (1.0, 1.0, 1.0)        // white
let darkBG: (CGFloat, CGFloat, CGFloat) = (0.055, 0.055, 0.067)   // #0E0E11

struct Theme { let key: String; let isLight: Bool; let color: (CGFloat, CGFloat, CGFloat) }

func rgb(_ hex: Int) -> (CGFloat, CGFloat, CGFloat) {
    (CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255)
}

// Parse Palettes.swift: each theme is `key: "X", label: ..., group: .light|.dark,
// ... logoColor: Color(hex: 0xRRGGBB)`.
func parseThemes() -> [Theme] {
    guard let text = try? String(contentsOfFile: palettesPath, encoding: .utf8) else { return [] }
    var out: [Theme] = []
    let pattern = #"key:\s*"([a-z0-9-]+)",\s*label:[^\n]*?group:\s*\.(light|dark)[\s\S]*?logoColor:\s*Color\(hex:\s*0x([0-9a-fA-F]{6})\)"#
    let re = try! NSRegularExpression(pattern: pattern)
    let ns = text as NSString
    for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        let key = ns.substring(with: m.range(at: 1))
        let isLight = ns.substring(with: m.range(at: 2)) == "light"
        let hex = Int(ns.substring(with: m.range(at: 3)), radix: 16) ?? 0xe8457c
        out.append(Theme(key: key, isLight: isLight, color: rgb(hex)))
    }
    return out
}

// A rounded, upright heart filling ~56% of the icon, centered slightly high.
func heartPath(size: CGFloat) -> CGPath {
    let w = size * 0.56
    let h = size * 0.52
    let ox = (size - w) / 2
    let oy = size * 0.24
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * w, y: oy + y * h) }
    let path = CGMutablePath()
    path.move(to: p(0.5, 0.30))
    path.addCurve(to: p(0.0, 0.27), control1: p(0.42, 0.05), control2: p(0.10, 0.02))
    path.addCurve(to: p(0.5, 1.0), control1: p(-0.12, 0.55), control2: p(0.28, 0.80))
    path.addCurve(to: p(1.0, 0.27), control1: p(0.72, 0.80), control2: p(1.12, 0.55))
    path.addCurve(to: p(0.5, 0.30), control1: p(0.90, 0.02), control2: p(0.58, 0.05))
    path.closeSubpath()
    return path
}

// Blend a color `t` of the way toward white (0 = unchanged, 1 = white).
func lighten(_ c: (CGFloat, CGFloat, CGFloat), _ t: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    (c.0 + (1 - c.0) * t, c.1 + (1 - c.1) * t, c.2 + (1 - c.2) * t)
}

func render(size: Int, heart: (CGFloat, CGFloat, CGFloat), bg: (CGFloat, CGFloat, CGFloat)) -> CGImage? {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    let bgColor = CGColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 1)
    ctx.setFillColor(bgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    // CGContext y is bottom-up; flip so the y-down path math draws upright.
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)

    // Just the heart, no sound-wave arcs (the waves read as the Spotify mark; a
    // plain heart avoids any trademark/copyright concern). Fill it with a vibrant
    // linear gradient from logoColor (top-left) to a lightened version (bottom-right).
    let heartPathRef = heartPath(size: s)
    ctx.saveGState()
    ctx.addPath(heartPathRef)
    ctx.clip()
    let top = heart
    let bot = lighten(heart, 0.45)
    let comps: [CGFloat] = [top.0, top.1, top.2, 1, bot.0, bot.1, bot.2, 1]
    if let grad = CGGradient(colorSpace: cs, colorComponents: comps, locations: [0, 1], count: 2) {
        // Heart bounds in the flipped (y-down) space: see heartPath layout.
        let w = s * 0.56, h = s * 0.52
        let ox = (s - w) / 2, oy = s * 0.24
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: ox, y: oy),
            end: CGPoint(x: ox + w, y: oy + h),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    } else {
        ctx.setFillColor(CGColor(red: heart.0, green: heart.1, blue: heart.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    }
    ctx.restoreGState()
    return ctx.makeImage()
}

func write(_ img: CGImage, _ path: String) {
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
        UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let iphone: [(pt: Int, scale: Int)] = [(20,2),(20,3),(29,2),(29,3),(40,2),(40,3),(60,2),(60,3)]

let themes = parseThemes()
print("parsed \(themes.count) themes")

for t in themes {
    let bg = t.isLight ? lightBG : darkBG
    let dir = "\(catalog)/\(t.key).appiconset"
    guard fm.fileExists(atPath: dir) else { continue }
    for (pt, sc) in iphone {
        if let img = render(size: pt * sc, heart: t.color, bg: bg) {
            write(img, "\(dir)/\(t.key)-\(pt)@\(sc)x.png")
        }
    }
    if let big = render(size: 1024, heart: t.color, bg: bg) {
        write(big, "\(dir)/\(t.key)-1024.png")
    }
    // Preview imageset used in ThemesView.
    let preview = "\(catalog)/themeicon-\(t.key).imageset"
    if fm.fileExists(atPath: preview), let img = render(size: 180, heart: t.color, bg: bg) {
        write(img, "\(preview)/\(t.key).png")
    }
}

// Primary AppIcon: the canonical dark Heartable mark used on launch, TestFlight,
// and the App Store. Theme-specific alternates remain available after install.
if let def = themes.first(where: { $0.key == defaultKey }) {
    let bg = def.isLight ? lightBG : darkBG
    let dir = "\(catalog)/AppIcon.appiconset"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if let big = render(size: 1024, heart: def.color, bg: bg) { write(big, "\(dir)/AppIcon-1024.png") }
    // Remove any stale per-size + dark-appearance files from the old format.
    try? fm.removeItem(atPath: "\(dir)/AppIcon-1024-dark.png")
    for (pt, sc) in iphone { try? fm.removeItem(atPath: "\(dir)/AppIcon-\(pt)@\(sc)x.png") }
    let contents = """
    {
      "images" : [
        { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try? contents.write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
}

print("done: regenerated gradient themed icons + primary AppIcon")
