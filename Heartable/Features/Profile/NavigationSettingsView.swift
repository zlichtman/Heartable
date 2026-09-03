import SwiftUI

/// A single, composed personalization surface. Home-screen icons remain independent
/// from the in-app palette, but both choices are visible without nested settings.
struct AppearanceView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("heartable.navigation.showNames")
    private var showNavigationNames = false

    @State private var editingTheme: CustomTheme?
    @State private var showingThemePicker = false

    /// One deliberately mixed palette rack. The set stays compact enough to scan,
    /// while covering warm, cool, light, dark, muted, and high-energy directions.
    private let presetThemeKeys = [
        Themes.defaultKey, "blossom", "lavender", "sunset", "champagne",
        "rosegold", "matcha", "forest", "ocean", "midnight", "eclipse",
        "carbon", "ember", "aurora", "grape", "catppuccin-mocha", "nord",
        "tokyo-night",
    ]

    private var shownThemeKeys: Set<String> {
        Set(presetThemeKeys)
    }

    private var legacyCurrentTheme: ThemeDef? {
        guard !CustomTheme.isCustomKey(theme.currentKey),
              !shownThemeKeys.contains(theme.currentKey)
        else { return nil }
        return Themes.all.first { $0.key == theme.currentKey }
    }

    private var iconColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 12),
            count: count
        )
    }

    private var selectableThemes: [ThemeDef] {
        var result = presetThemeKeys.compactMap { key in
            Themes.all.first { $0.key == key }
        }
        if let legacyCurrentTheme {
            result.append(legacyCurrentTheme)
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                iconSection
                themeSection
                navigationSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTheme) { draft in
            ThemeEditorView(editing: draft)
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePickerSheet(presets: selectableThemes)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("APP ICON")
            LazyVGrid(columns: iconColumns, spacing: 16) {
                ForEach(AppIconCatalog.choices) { choice in
                    Button {
                        theme.setAppIcon(choice.id)
                    } label: {
                        iconCell(choice)
                    }
                    .buttonStyle(.plain)
                    .disabled(theme.isChangingAppIcon)
                    .accessibilityLabel("\(choice.label) app icon")
                    .accessibilityValue(
                        choice.id == theme.appIconKey ? "Selected" : ""
                    )
                }
            }

        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("APP THEME")

            HStack(spacing: 10) {
                Button {
                    showingThemePicker = true
                } label: {
                    currentThemeSelector
                }
                .buttonStyle(
                    TactileThemeButtonStyle(shadow: theme.palette.text.opacity(0.16))
                )
                .accessibilityLabel("App theme")
                .accessibilityValue(theme.current.label)
                .accessibilityHint("Shows every available app theme")

                customThemeButton
            }
        }
    }

    private var currentThemeSelector: some View {
        HStack(spacing: 12) {
            ThemeColorPills(definition: theme.current, outlinedFor: theme.palette.card)

            VStack(alignment: .leading, spacing: 2) {
                Text("Theme")
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
                Text(theme.current.key == Themes.defaultKey ? "Heartable" : theme.current.label)
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.palette.textMuted)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(theme.palette.card, in: Capsule())
        .overlay(Capsule().stroke(theme.palette.border, lineWidth: 1))
    }

    private var customThemeButton: some View {
        Button {
            editingTheme = CustomTheme.draft()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    AngularGradient(
                        colors: [.pink, .orange, .yellow, .green, .blue, .purple, .pink],
                        center: .center
                    ),
                    in: Circle()
                )
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(
            TactileThemeButtonStyle(shadow: theme.palette.text.opacity(0.16))
        )
        .accessibilityLabel("Add custom app theme")
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("NAVIGATION")
            Toggle(isOn: $showNavigationNames) {
                Label("Show page names", systemImage: "text.below.photo")
                    .font(Typography.medium(15))
                    .foregroundStyle(theme.palette.text)
            }
            .tint(theme.palette.rose)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(theme.palette.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(theme.palette.border, lineWidth: 1)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
    }

    private func iconCell(_ choice: AppIconChoice) -> some View {
        let selected = choice.id == theme.appIconKey
        return VStack(spacing: 7) {
            Image(choice.previewAssetName)
                .resizable()
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(
                        selected ? theme.palette.rose : theme.palette.border,
                        lineWidth: selected ? 3 : 1
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.palette.rose)
                        .background(Circle().fill(theme.palette.card).padding(2))
                        .offset(x: 3, y: 3)
                }
            }

            Text(choice.label)
                .font(Typography.medium(10))
                .foregroundStyle(
                    selected ? theme.palette.rose : theme.palette.textSecondary
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }

}

private struct ThemePickerSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let presets: [ThemeDef]

    @State private var editingTheme: CustomTheme?

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible(), spacing: 10)]
        } else {
            [GridItem(.adaptive(minimum: 132), spacing: 10)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerHeader

            Rectangle()
                .fill(theme.palette.border)
                .frame(height: 1)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(presets) { option(definition: $0) }
                    ForEach(theme.customThemes.all) { custom in
                        option(definition: custom.themeDef(), custom: custom)
                    }
                }
                .padding(16)
            }
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .sheet(item: $editingTheme) { ThemeEditorView(editing: $0) }
        .sensoryFeedback(.selection, trigger: theme.currentKey)
        .presentationDetents([.large])
        .heartableSheetChrome(dragIndicator: .hidden)
        .accessibilityAction(.escape) { dismiss() }
    }

    /// Deliberately outside the scroll view: the title and one Heartable dismiss
    /// affordance remain anchored and readable as the selected palette changes.
    private var pickerHeader: some View {
        HStack(spacing: 12) {
            Text("Theme")
                .font(Typography.heading(23))
                .foregroundStyle(theme.palette.text)

            Spacer(minLength: 8)

            HeartableSheetDismissButton(
                accessibilityLabel: "Dismiss theme picker",
                drawsSurface: true
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(theme.palette.bg)
    }

    private func option(
        definition: ThemeDef,
        custom: CustomTheme? = nil
    ) -> some View {
        let selected = definition.key == theme.currentKey
        return ZStack(alignment: .bottomTrailing) {
            Button {
                theme.setTheme(definition.key)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        ThemeColorPills(
                            definition: definition,
                            outlinedFor: definition.palette.card
                        )
                        Spacer(minLength: 6)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }

                    Text(
                        definition.key == Themes.defaultKey
                            ? "Heartable"
                            : definition.label
                    )
                    .font(Typography.semibold(13))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .padding(.trailing, custom == nil ? 0 : 34)
                }
                .foregroundStyle(definition.palette.text)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [definition.palette.surface, definition.palette.card],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            selected ? definition.palette.rose : definition.palette.border,
                            lineWidth: selected ? 2 : 1
                        )
                }
            }
            .buttonStyle(
                TactileThemeButtonStyle(shadow: theme.palette.text.opacity(0.14))
            )
            .accessibilityLabel("\(definition.label) app theme")
            .accessibilityValue(selected ? "Selected" : "")
            .accessibilityAddTraits(selected ? .isSelected : [])

            if let custom {
                Button {
                    editingTheme = custom
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(definition.palette.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit or delete \(definition.label)")
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            if let custom { editingTheme = custom }
        }
    }
}

private struct ThemeColorPills: View {
    let definition: ThemeDef
    let outlinedFor: Color

    var body: some View {
        HStack(spacing: -5) {
            pill(definition.palette.grad1)
            pill(definition.palette.grad2)
            pill(definition.palette.grad3)
        }
        .accessibilityHidden(true)
    }

    private func pill(_ color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 24, height: 18)
            .overlay(Capsule().stroke(outlinedFor.opacity(0.85), lineWidth: 1.5))
    }
}

private struct TactileThemeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let shadow: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                !reduceMotion && configuration.isPressed ? 0.97 : 1
            )
            .offset(
                y: !reduceMotion && configuration.isPressed ? 2 : 0
            )
            .shadow(
                color: configuration.isPressed ? .clear : shadow,
                radius: configuration.isPressed ? 0 : 2,
                y: configuration.isPressed ? 0 : 2
            )
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.2, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}
