import SwiftUI
import UIKit

/// A plain, `Sendable` + `Codable` sRGB color used everywhere a `Color` needs to
/// be stored (custom themes) or computed off the main actor (adaptive extraction).
///
/// `Color` itself is neither `Codable` nor cheap to introspect, so seed colors and
/// derived palettes are built on this value type and bridged to `Color` only when
/// a `Palette` is assembled. All the color math the theming system needs
/// (luminance, contrast, mix, lighten/darken, chroma) lives here so both the
/// custom-theme builder and the adaptive extractor share one implementation.
struct RGBAColor: Codable, Sendable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r.clamped01
        self.g = g.clamped01
        self.b = b.clamped01
        self.a = a.clamped01
    }

    // MARK: Bridging

    /// The SwiftUI color for this value.
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// Resolve a SwiftUI `Color` into components. Must run on the main actor
    /// because `UIColor(_:)` resolves environment-dependent colors there.
    @MainActor
    init(_ color: Color) {
        let ui = UIColor(color)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        if ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa) {
            self.init(r: Double(rr), g: Double(gg), b: Double(bb), a: Double(aa))
        } else {
            // Non-RGB (pattern / catalog) color: fall back to a neutral gray.
            var w: CGFloat = 0, wa: CGFloat = 0
            ui.getWhite(&w, alpha: &wa)
            self.init(r: Double(w), g: Double(w), b: Double(w), a: Double(wa))
        }
    }

    static let white = RGBAColor(r: 1, g: 1, b: 1)
    static let black = RGBAColor(r: 0, g: 0, b: 0)

    // MARK: Alpha / mixing

    func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(r: r, g: g, b: b, a: alpha)
    }

    /// Linear blend toward `other` by `t` (0 keeps self, 1 is `other`). Alpha is
    /// preserved from `self` so tinting bg toward black keeps it opaque.
    func mix(_ other: RGBAColor, _ t: Double) -> RGBAColor {
        let k = t.clamped01
        return RGBAColor(
            r: r + (other.r - r) * k,
            g: g + (other.g - g) * k,
            b: b + (other.b - b) * k,
            a: a
        )
    }

    func lighten(_ t: Double) -> RGBAColor { mix(.white, t) }
    func darken(_ t: Double) -> RGBAColor { mix(.black, t) }

    // MARK: Perceptual metrics

    /// WCAG relative luminance (0 black … 1 white).
    var luminance: Double {
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    var isDark: Bool { luminance < 0.5 }

    /// WCAG contrast ratio between two colors (1 … 21).
    func contrast(against other: RGBAColor) -> Double {
        let l1 = luminance, l2 = other.luminance
        let hi = max(l1, l2), lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Chroma proxy (max channel − min channel): how vivid the color is.
    var chroma: Double { Swift.max(r, g, b) - Swift.min(r, g, b) }

    /// HSB brightness (max channel).
    var brightnessValue: Double { Swift.max(r, g, b) }

    /// A "vividness" score used to rank extracted colors as accent candidates:
    /// vivid but not muddy, weighted away from near-black / near-white.
    var vividness: Double {
        let mid = 1 - abs(brightnessValue - 0.6) * 1.4
        return chroma * Swift.max(0.1, mid)
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
