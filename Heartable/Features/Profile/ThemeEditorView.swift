import SwiftUI

/// Create-your-own theme editor. The user picks a handful of seed colors, names
/// the theme, and watches a live mock of representative UI (player card, nav bar,
/// track row) recolor as they go. Saving persists it and selects it.
///
/// The remaining ~20 semantic slots are derived from these seeds by
/// `PaletteBuilder`, which also guarantees the text stays legible against the
/// background, so a user can't build an unreadable theme.
struct ThemeEditorView: View {
    private enum SeedSlot: String, CaseIterable, Identifiable {
        case background = "Background"
        case surface = "Surface"
        case card = "Card"
        case accent = "Accent"
        case accent2 = "Accent 2"
        case text = "Text"

        var id: String { rawValue }
    }

    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The theme being edited (create passes a fresh `.draft()`).
    let editing: CustomTheme

    @State private var name: String
    @State private var bg: Color
    @State private var surface: Color
    @State private var card: Color
    @State private var accent: Color
    @State private var accent2: Color
    @State private var text: Color
    @State private var confirmingDelete = false
    @State private var selectedSlot: SeedSlot = .accent
    @State private var washColor = Color.clear
    @State private var washOpacity = 0.0
    @State private var washTask: Task<Void, Never>?
    @State private var quickColorSelectionRevision = 0
    @AppStorage("heartable.navigation.showNames")
    private var showNavigationNames = false

    init(editing: CustomTheme) {
        self.editing = editing
        _name = State(initialValue: editing.name)
        _bg = State(initialValue: editing.bg.color)
        _surface = State(initialValue: editing.surface.color)
        _card = State(initialValue: editing.card.color)
        _accent = State(initialValue: editing.accent.color)
        _accent2 = State(initialValue: editing.accent2.color)
        _text = State(initialValue: editing.text.color)
    }

    /// The seed colors resolved into the live palette shown in the preview.
    private var draft: CustomTheme {
        CustomTheme(
            id: editing.id, name: name,
            bg: RGBAColor(bg), surface: RGBAColor(surface), card: RGBAColor(card),
            accent: RGBAColor(accent), accent2: RGBAColor(accent2), text: RGBAColor(text)
        )
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    preview(draft.palette)
                    nameField
                    precisionColorEditor
                    if isExistingTheme {
                        deleteButton
                    }
                }
                .padding(16)
            }
            .background(theme.palette.bg.ignoresSafeArea())
            .navigationTitle(editing.name.isEmpty ? "New Theme" : "Edit Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(Typography.semibold(16))
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .sheet(isPresented: $confirmingDelete) {
            HeartableDestructiveConfirmation(
                icon: "trash.fill",
                title: "Delete theme?",
                message: "This custom theme will be permanently removed.",
                confirmTitle: "Delete theme",
                cancelTitle: "Keep theme",
                onCancel: { confirmingDelete = false },
                onConfirm: { deleteTheme() }
            )
        }
        .overlay {
            washColor
                .opacity(washOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: selectedSlot)
        .sensoryFeedback(.selection, trigger: quickColorSelectionRevision)
        .heartableSheetChrome()
        .onDisappear { washTask?.cancel() }
    }

    private var isExistingTheme: Bool {
        theme.customTheme(forKey: editing.key) != nil
    }

    private func save() {
        var result = draft
        result.name = trimmedName
        theme.saveCustomTheme(result)
        theme.setTheme(result.key)
        dismiss()
    }

    private func deleteTheme() {
        theme.deleteCustomTheme(editing.key)
        dismiss()
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Delete theme", systemImage: "trash")
                .font(Typography.semibold(15))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.danger)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(theme.palette.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(theme.palette.danger.opacity(0.35), lineWidth: 1)
        }
        .accessibilityHint("Permanently removes this custom theme")
    }

    // MARK: Color inputs

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THEME NAME")
                .font(Typography.semibold(11))
                .tracking(1)
                .foregroundStyle(theme.palette.textMuted)

            HStack {
                Image(systemName: "textformat")
                    .foregroundStyle(theme.palette.textMuted)
                TextField("My Theme", text: $name)
                    .font(Typography.medium(15))
                    .foregroundStyle(theme.palette.text)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(
                theme.palette.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(theme.palette.border, lineWidth: 1)
            }
        }
    }

    private var precisionColorEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("COLORS")
                .font(Typography.semibold(11))
                .tracking(1)
                .foregroundStyle(theme.palette.textMuted)

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(SeedSlot.allCases) { slot in
                        seedPill(slot)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            ColorPicker(
                selection: activeColorBinding,
                supportsOpacity: false
            ) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(activeColor)
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                        .shadow(color: activeColor.opacity(0.28), radius: 7)

                    Text(selectedSlot.rawValue)
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)

                    Spacer(minLength: 4)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.palette.rose)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 62)
                .background(
                    activeColor.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(activeColor.opacity(0.55), lineWidth: 1)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 34), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Array(quickColors.enumerated()), id: \.offset) { index, color in
                    Button {
                        quickColorSelectionRevision &+= 1
                        activeColorBinding.wrappedValue = color
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                            .shadow(color: color.opacity(0.22), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color option \(index + 1)")
                }
            }
        }
        .padding(16)
        .background(
            theme.palette.card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    private func seedPill(_ slot: SeedSlot) -> some View {
        let selected = slot == selectedSlot
        let color = color(for: slot)
        return Button {
            selectedSlot = slot
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                Text(slot.rawValue)
                    .font(Typography.semibold(12))
                    .foregroundStyle(selected ? theme.palette.text : theme.palette.textSecondary)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 40)
            .background(
                selected ? color.opacity(0.22) : theme.palette.surface,
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(
                    selected ? color : theme.palette.border,
                    lineWidth: selected ? 1.5 : 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "")
    }

    private var quickColors: [Color] {
        [
            Color(hex: 0xff6fa0), Color(hex: 0xff9e52), Color(hex: 0xf2d65c),
            Color(hex: 0x5fcf91), Color(hex: 0x4ca4e8), Color(hex: 0x8f7af5),
            Color(hex: 0xc56ee8), Color(hex: 0xf3eef2), Color(hex: 0x1f1824),
            Color(hex: 0x10131a), Color(hex: 0x283447), Color(hex: 0xd6e4ff),
        ]
    }

    private var activeColor: Color { color(for: selectedSlot) }

    private var activeColorBinding: Binding<Color> {
        Binding(
            get: { color(for: selectedSlot) },
            set: { newValue in
                setColor(newValue, for: selectedSlot)
                flash(newValue)
            }
        )
    }

    private func color(for slot: SeedSlot) -> Color {
        switch slot {
        case .background: bg
        case .surface: surface
        case .card: card
        case .accent: accent
        case .accent2: accent2
        case .text: text
        }
    }

    private func setColor(_ color: Color, for slot: SeedSlot) {
        switch slot {
        case .background: bg = color
        case .surface: surface = color
        case .card: card = color
        case .accent: accent = color
        case .accent2: accent2 = color
        case .text: text = color
        }
    }

    private func flash(_ color: Color) {
        washTask?.cancel()
        washColor = color
        if washOpacity < 0.01 {
            withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.08)) {
                washOpacity = reduceMotion ? 0.10 : 0.20
            }
        }
        washTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.08 : 0.28)) {
                washOpacity = 0
            }
        }
    }

    // MARK: Live preview of representative UI

    private func preview(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview")
                .font(Typography.medium(12))
                .foregroundStyle(theme.palette.textMuted)

            VStack(spacing: 14) {
                playerCard(p)
                trackRow(p)
                navBar(p)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(p.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(theme.palette.border, lineWidth: 1)
            )
        }
    }

    private func playerCard(_ p: Palette) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [p.grad1, p.grad3],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.9)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Now Playing").font(Typography.semibold(14)).foregroundStyle(p.text)
                Text("Your Custom Theme").font(Typography.body(12)).foregroundStyle(p.textSecondary)
                Capsule().fill(p.rose).frame(width: 90, height: 3).padding(.top, 3)
            }
            Spacer()
            Image(systemName: "play.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(p.rose))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(p.surface))
    }

    private func trackRow(_ p: Palette) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(p.roseDim)
                .frame(width: 40, height: 40)
                .overlay(Text("1").font(Typography.semibold(13)).foregroundStyle(p.rose))
            VStack(alignment: .leading, spacing: 2) {
                Text("Track Title").font(Typography.medium(13)).foregroundStyle(p.text)
                Text("Artist").font(Typography.body(11)).foregroundStyle(p.textMuted)
            }
            Spacer()
            Image(systemName: "heart.fill").foregroundStyle(p.rose).font(.system(size: 14))
            Image(systemName: "ellipsis").foregroundStyle(p.textMuted).font(.system(size: 14))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(p.card))
    }

    private func navBar(_ p: Palette) -> some View {
        HStack {
            navItem("music.note.house.fill", "Library", active: true, p)
            Spacer()
            navItem("sparkles", "Discover", active: false, p)
            Spacer()
            navItem("person.fill", "Profile", active: false, p)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(p.bgElevated))
    }

    private func navItem(_ icon: String, _ label: String, active: Bool, _ p: Palette) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 16))
            if showNavigationNames {
                Text(label).font(Typography.medium(9))
            }
        }
        .foregroundStyle(active ? p.rose : p.textMuted)
        .accessibilityLabel(label)
    }
}
