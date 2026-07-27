import SwiftUI

/// Brand fonts (bundled TTFs, registered via Info.plist `UIAppFonts`).
/// Playfair Display for headings, DM Sans for everything else.
enum Typography {
    static func heading(_ size: CGFloat) -> Font {
        .custom("PlayfairDisplay-Bold", size: size, relativeTo: headingStyle(for: size))
    }

    static func body(_ size: CGFloat) -> Font {
        .custom("DMSans-Regular", size: size, relativeTo: bodyStyle(for: size))
    }

    static func medium(_ size: CGFloat) -> Font {
        .custom("DMSans-Medium", size: size, relativeTo: bodyStyle(for: size))
    }

    static func semibold(_ size: CGFloat) -> Font {
        .custom("DMSans-SemiBold", size: size, relativeTo: bodyStyle(for: size))
    }

    /// Keep the existing visual scale while opting every branded font into the
    /// Dynamic Type curve that best matches its intended role.
    private static func headingStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 32...: .largeTitle
        case 26..<32: .title
        case 22..<26: .title2
        default: .title3
        }
    }

    private static func bodyStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 20...: .title3
        case 17..<20: .body
        case 15..<17: .callout
        case 13..<15: .subheadline
        case 12..<13: .footnote
        case ..<12: .caption
        default: .body
        }
    }
}
