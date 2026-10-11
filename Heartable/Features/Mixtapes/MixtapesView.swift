import SwiftUI

/// The Mixtapes tab: your own mixtapes plus ones friends sent you. Every mixtape
/// is made for one friend: the + action asks who it's for, creates an untitled
/// draft addressed to them, and opens the editor, where Send delivers it. Your
/// own open in the editor; received ones open read-only (the editor hides edit
/// controls when `mine` is false).
struct MixtapesView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(BannerCenter.self) private var banners

    @State private var mine: [MixtapeDTO] = []
    @State private var shared: [MixtapeDTO] = []

    @State private var choosingRecipient = false
    /// Accepted friends' display names by user id, for labeling drafts.
    @State private var friendNames: [UUID: String] = [:]
    /// Recipient names for drafts created here before the list reloads.
    @State private var createdRecipients: [UUID: String] = [:]
    @State private var loaded = false
    @State private var deletingMixtape: MixtapeDTO?
    @State private var deleting = false

    /// Owned by the tab shell so re-tapping the tab pops back to the list.
    @Binding var path: [UUID]
    /// Switches to the Heartable tab's friend search.
    var onFindFriends: (() -> Void)? = nil

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                theme.palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HeartablePageHeader(tab: .mixtapes, action: .init(
                            title: "Create mixtape", symbol: "plus",
                            perform: { choosingRecipient = true }, iconOnly: true
                        ))
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                        if !mine.isEmpty {
                            sectionHeader("My Mixtapes")
                            ForEach(mine) { m in
                                NavigationLink(value: m.id) { card(m) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete mixtape", systemImage: "trash", role: .destructive) {
                                            deletingMixtape = m
                                        }
                                    }
                            }
                        }

                        if !shared.isEmpty {
                            sectionHeader("Sent to me")
                            ForEach(shared) { m in
                                NavigationLink(value: m.id) { card(m) }
                                    .buttonStyle(.plain)
                            }
                        }

                        if !loaded {
                            Text("Loading mixtapes…").font(Typography.body(15)).padding(.vertical, 20)
                        } else if mine.isEmpty && shared.isEmpty {
                            emptyCard
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                MixtapeEditorView(mixtapeID: id, recipientName: recipientName(forMixtape: id))
                    .toolbar(.visible, for: .navigationBar)
            }
            .sheet(isPresented: $choosingRecipient) {
                MixtapeRecipientSheet(
                    onCreated: { id, name in
                        createdRecipients[id] = name
                        path.append(id)
                    },
                    onFindFriends: onFindFriends
                )
            }
            .sheet(item: $deletingMixtape) { tape in
                HeartableDestructiveConfirmation(
                    icon: "trash", title: "Delete mixtape?",
                    message: "This removes the mixtape. This can’t be undone.",
                    confirmTitle: "Delete mixtape", cancelTitle: "Keep mixtape", isBusy: deleting,
                    onCancel: { deletingMixtape = nil },
                    onConfirm: { Task { await delete(tape) } }
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
        async let list = BackendAPI.shared.listMixtapes()
        async let friends = try? BackendAPI.shared.fetchFriends()
        let (tapes, friendRows) = await (list, friends)
        mine = tapes.mine
        shared = tapes.shared
        // A failed friends read keeps the last known names.
        if let friendRows {
            friendNames = Dictionary(
                friendRows.compactMap { $0.profile.map { ($0.userId, MixtapeRecipientSheet.name(of: $0)) } },
                uniquingKeysWith: { first, _ in first }
            )
        }
        loaded = true
    }

    private func recipientName(forMixtape id: UUID) -> String? {
        if let name = createdRecipients[id] { return name }
        return mine.first { $0.id == id }?.recipientId.flatMap { friendNames[$0] }
    }

    private func delete(_ tape: MixtapeDTO) async {
        guard tape.mine, !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await BackendAPI.shared.deleteMixtape(id: tape.id)
            mine.removeAll { $0.id == tape.id }
            deletingMixtape = nil
            banners.success("Mixtape deleted")
        } catch { banners.error("Couldn’t delete the mixtape. Try again.") }
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
                if let recipient = recipientLine(m) {
                    Text(recipient)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                } else if let created = m.createdAt, !relativeLong(created).isEmpty {
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

    /// "For Ava · Draft" on your own mixtapes once the recipient is known.
    private func recipientLine(_ m: MixtapeDTO) -> String? {
        guard m.mine, let name = recipientName(forMixtape: m.id) else { return nil }
        return m.sentAt == nil ? "For \(name) · Draft" : "For \(name)"
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
            Text("No mixtapes yet. Make one for a friend: add songs, notes, and photos, then send it.")
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
