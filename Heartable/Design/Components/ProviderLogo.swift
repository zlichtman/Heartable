import SwiftUI
import UIKit

/// Uncropped service app artwork for menus. Heartable resolves through the same
/// installed-icon selection as Appearance, so it updates without reopening a sheet.
struct ProviderLogo: View {
    @Environment(ThemeStore.self) private var theme
    let id: ProviderID
    var size: CGFloat = 40

    static func assetName(for id: ProviderID, heartableIconKey: String) -> String {
        if id == .heartable {
            return (AppIconCatalog.choice(for: heartableIconKey)
                    ?? AppIconCatalog.choices[0]).previewAssetName
        }
        return "\(id.rawValue)-logo"
    }

    var body: some View {
        let name = Self.assetName(for: id, heartableIconKey: theme.appIconKey)
        Group {
            if let image = UIImage(named: name) {
                Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
            } else {
                Image(systemName: ProviderCatalog.entry(id)?.sfSymbol ?? "music.note")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(theme.palette.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.palette.surface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
    }
}
