import SwiftUI
import UIKit

/// A round brand mark for a music provider — the service's brand color with its
/// glyph (or its real logo, if bundled). Used on track rows, the Library header,
/// and the services screen so every item shows which service it came from.
///
/// Real logos: drop a PNG/asset named `<providerID>-logo` (e.g. `spotify-logo`,
/// `apple-logo`) into the asset catalog and it's used automatically; otherwise the
/// catalog's SF Symbol on the brand color is drawn. No trademarked art is bundled.
///
/// `connected` controls the live-vs-dim look: a connected service shows in full
/// brand color; a disconnected one is greyed so the header reads as a status row.
struct ProviderBadge: View {
    @Environment(ThemeStore.self) private var theme
    let id: ProviderID
    var size: CGFloat = 18
    /// Full brand color when true; muted/greyed when false (not connected).
    var connected: Bool = true
    /// Optional status ring: green = playable/available on a connected service,
    /// red = the owning service isn't connected. Nil draws a plain bg-colored ring.
    var ring: Color? = nil

    var body: some View {
        let ringWidth = max(1.5, size * 0.12)
        return mark
            .frame(width: size, height: size)
            .clipShape(Circle())
            .saturation(connected ? 1 : 0)
            .opacity(connected ? 1 : 0.5)
            .overlay(Circle().stroke(ring ?? theme.palette.bg, lineWidth: ring == nil ? max(1, size * 0.06) : ringWidth))
            .padding(ring == nil ? 0 : ringWidth * 0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(providerLabel)
            .accessibilityValue(connected ? "Connected" : "Not connected")
    }

    /// Real brand logo as a full-bleed circular mark when bundled; otherwise the
    /// catalog glyph on the brand color.
    @ViewBuilder private var mark: some View {
        if let logo {
            Image(uiImage: logo)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Circle()
                .fill(fill)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.52, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
    }

    /// The bundled brand logo if one exists in the asset catalog, else nil.
    private var logo: UIImage? {
        if id == .heartable {
            return UIImage(named: ProviderLogo.assetName(for: id, heartableIconKey: theme.appIconKey))
        }
        return UIImage(named: "\(id.rawValue)-logo")
    }

    private var fill: Color {
        if logo != nil { return .white } // logo art already carries the brand color
        if id == .heartable { return theme.palette.rose }
        return ProviderCatalog.entry(id)?.brandColor ?? theme.palette.textMuted
    }

    private var symbol: String {
        if id == .heartable { return "heart.fill" }
        return ProviderCatalog.entry(id)?.sfSymbol ?? "music.note"
    }

    private var providerLabel: String {
        id == .heartable ? "Heartable" : (ProviderCatalog.entry(id)?.label ?? id.rawValue)
    }
}
