import SwiftUI

/// Mixtapes — list of the user's own mixtapes plus ones shared with them.
/// A "New Mixtape" toolbar button prompts for a title, creates it, and pushes
/// the editor. Tapping one of your own opens the editor; shared ones are
/// read-only in the editor (it hides edit affordances when `mine` is false).
/// Ported from the RN MixtapesScreen.
struct MixtapesView: View {
    @Environment(ThemeStore.self) private var theme

    @State private var mine: [MixtapeDTO] = []
    @State private var shared: [MixtapeDTO] = []

    // New-mixtape prompt.
    @State private var creating = false
    @State private var newTitle = ""

    // Programmatic push to a freshly-created mixtape's editor.
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                theme.palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !mine.isEmpty {
                            sectionHeader("My Mixtapes")
                            ForEach(mine) { m in
                                NavigationLink(value: m.id) { card(m) }
                                    .buttonStyle(.plain)
                            }
                        }

                        if !shared.isEmpty {
                            sectionHeader("Shared with me")
                            ForEach(shared) { m in
                                NavigationLink(value: m.id) { card(m) }
                                    .buttonStyle(.plain)
                            }
                        }

                        if mine.isEmpty && shared.isEmpty {
                            emptyCard
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
            .navigationTitle("Mixtapes")
            .navigationDestination(for: UUID.self) { id in
                MixtapeEditorView(mixtapeID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newTitle = ""
                        creating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(theme.palette.rose)
                }
            }
            .sheet(isPresented: $creating) {
                HeartablePromptSheet(
                    icon: "rectangle.stack.badge.plus",
                    title: "New Mixtape",
                    message: "Give it a name. You can add songs, notes, and friends next.",
                    placeholder: "Mixtape title",
                    text: $newTitle,
                    actionTitle: "Create",
                    onCancel: {
                        newTitle = ""
                        creating = false
                    },
                    onSubmit: {
                        let title = newTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        guard !title.isEmpty else { return }
                        newTitle = ""
                        creating = false
                        Task { await create(title) }
                    }
                )
            }
            .task { await load() }
            .refreshable { await load() }
            // Reload when returning from the editor (path shrinks) so a renamed
            // title / new cover / deleted mixtape is reflected in the list.
            .onChange(of: path) { old, new in
                if new.count < old.count { Task { await load() } }
            }
        }
    }

    // MARK: Data

    private func load() async {
        let list = await BackendAPI.shared.listMixtapes()
        mine = list.mine
        shared = list.shared
    }

    private func create(_ title: String) async {
        guard let id = try? await BackendAPI.shared.createMixtape(title: title) else { return }
        await load()
        path.append(id)
    }

    // MARK: Rows

    private func card(_ m: MixtapeDTO) -> some View {
        HStack(spacing: 14) {
            cover(m)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title?.isEmpty == false ? m.title! : "Untitled mixtape")
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                if let created = m.createdAt, !relativeLong(created).isEmpty {
                    Text(relativeLong(created))
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                } else if let desc = m.description, !desc.isEmpty {
                    Text(desc)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.palette.textMuted)
        }
        .padding(12)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        )
        .padding(.bottom, 8)
        .contentShape(Rectangle())
    }

    private func cover(_ m: MixtapeDTO) -> some View {
        Group {
            if let urlString = m.coverUrl, let url = URL(string: urlString) {
                CachedArtworkImage(url: url) { coverPlaceholder }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [theme.palette.grad1, theme.palette.grad3],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "heart.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: Atoms

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart")
                .font(.system(size: 28))
                .foregroundStyle(theme.palette.textMuted)
            Text("No mixtapes yet. Make one: add songs, leave notes, and share it with a friend.")
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        )
        .padding(.top, 16)
    }
}
