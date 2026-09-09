import SwiftUI
import UIKit

/// App-theme picker: the core Heartable palette leads a curated set of colors,
/// including Classic Terminal, while custom color palettes live in the same
/// flow. Home-screen icon selection is intentionally handled separately.
/// Custom cells select on tap; long-press to edit or delete. The active theme
/// gets an accent ring and tapping re-skins the app instantly.
struct ThemesView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Non-nil while the editor sheet is presented (create or edit).
    @State private var editingTheme: CustomTheme?

    /// Brand theme first, curated colors after — plus the current selection if
    /// it's a preset outside the curated set, so its ring is never orphaned.
    private var presets: [ThemeDef] {
        var keys = Themes.galleryKeys
        if !CustomTheme.isCustomKey(theme.currentKey), !keys.contains(theme.currentKey) {
            keys.append(theme.currentKey)
        }
        return keys.compactMap { key in Themes.all.first { $0.key == key } }
    }

    /// Adaptive columns keep labels readable with Dynamic Type and use additional
    /// iPad/landscape width without device-specific column counts.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 120 : 92),
                  spacing: 10)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                customColorButton

                Text("PRESETS")
                    .font(Typography.semibold(12))
                    .tracking(1)
                    .foregroundStyle(theme.palette.textMuted)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(presets) { t in
                        Button { theme.setTheme(t.key) } label: {
                            cell(t, label: t.key == Themes.defaultKey ? "Heartable" : t.label)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t.key == Themes.defaultKey ? "Heartable theme" : "\(t.label) theme")
                        .accessibilityValue(t.key == theme.currentKey ? "Selected" : "")
                    }
                    ForEach(theme.customThemes.all) { c in
                        customCell(c)
                    }
                }
            }
            .padding(16)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("App Theme")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTheme) { draft in
            ThemeEditorView(editing: draft)
        }
    }

    // MARK: Custom themes

    private var customColorButton: some View {
        Button { editingTheme = CustomTheme.draft() } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        AngularGradient(
                            colors: [.pink, .orange, .yellow, .green, .blue, .purple, .pink],
                            center: .center
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "eyedropper.halffull")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom colors")
                        .font(Typography.semibold(15))
                        .foregroundStyle(theme.palette.text)
                    Text("Build a palette with color pickers")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.palette.textMuted)
            }
            .padding(14)
            .background(
                theme.palette.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(theme.palette.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create a custom color theme")
    }

    private func customCell(_ c: CustomTheme) -> some View {
        let t = c.themeDef()
        return Button { theme.setTheme(t.key) } label: { cell(t, label: t.label) }
            .buttonStyle(.plain)
            .accessibilityLabel("\(t.label) theme")
            .accessibilityValue(t.key == theme.currentKey ? "Selected" : "")
            .onLongPressGesture(minimumDuration: 0.4) {
                editingTheme = c
            }
    }

    // MARK: Shared cell

    private func cell(_ t: ThemeDef, label: String) -> some View {
        let selected = t.key == theme.currentKey
        let accent = theme.palette.rose
        return VStack(spacing: 6) {
            swatch(t)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(selected ? accent : theme.palette.border,
                                lineWidth: selected ? 2.5 : 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(accent)
                            .background(Circle().fill(.white).padding(2))
                            .offset(x: 4, y: 4)
                    }
                }

            Text(label)
                .font(Typography.medium(9))
                .foregroundStyle(selected ? accent : theme.palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            pills(t)
        }
    }

    /// The swatch is the theme's own app-icon art when present (presets only),
    /// otherwise its gradient (grad1 → grad3) — so custom themes and any preset
    /// missing art still render real palette color.
    @ViewBuilder
    private func swatch(_ t: ThemeDef) -> some View {
        if !CustomTheme.isCustomKey(t.key), let ui = UIImage(named: "themeicon-\(t.key)") {
            Image(uiImage: ui).resizable()
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [t.palette.grad1, t.palette.grad3],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.95))
                }
        }
    }

    /// Two pills previewing the gradient's endpoints, so the cell telegraphs the
    /// palette even when the icon art is missing.
    private func pills(_ t: ThemeDef) -> some View {
        HStack(spacing: 3) {
            pill(t.palette.grad1)
            pill(t.palette.grad3)
        }
    }

    private func pill(_ color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 13, height: 4)
            .overlay(Capsule().stroke(theme.palette.border, lineWidth: 0.5))
    }

}
