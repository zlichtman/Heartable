import SwiftUI

/// Creates a private untitled draft addressed to a friend, then goes straight to
/// the full editor. No naming prompt or decorative placeholder button precedes
/// editing.
struct MixtapeComposerSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    let friendID: UUID
    let onCreated: (UUID) -> Void
    @State private var creating = false
    @State private var failed = false

    var body: some View {
        HeartableDrawer {
            VStack(alignment: .leading, spacing: 16) {
                Text(failed ? "Couldn’t open the editor" : "Opening editor…")
                    .font(Typography.heading(23)).foregroundStyle(theme.palette.text)
                if failed {
                    Button("Try again") { Task { await create() } }
                        .font(Typography.semibold(16)).foregroundStyle(theme.palette.rose)
                        .frame(minHeight: 44)
                }
            }.padding(24)
        }
        .interactiveDismissDisabled(creating)
        .task { await create() }
    }

    private func create() async {
        guard !creating else { return }
        creating = true
        failed = false
        defer { creating = false }
        let owner = AccountSessionStore.currentOwnerID
        do {
            guard let id = try await BackendAPI.shared.createMixtape(
                title: "Untitled mixtape",
                recipientID: friendID
            ) else {
                failed = true
                return
            }
            guard owner == AccountSessionStore.currentOwnerID else { dismiss(); return }
            dismiss()
            onCreated(id)
        } catch { failed = true }
    }
}

/// Asks who a new mixtape is for. Lists the signed-in user's accepted friends;
/// picking one hands off to `MixtapeComposerSheet` in the same sheet, which
/// creates the draft addressed to that friend and reports its id. With no
/// friends yet, it points the user to friend search instead.
struct MixtapeRecipientSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(FriendRelationships.self) private var relationships
    @Environment(\.dismiss) private var dismiss

    /// The new draft's id and the recipient's display name.
    let onCreated: (UUID, String) -> Void
    /// Opens friend search; the empty state shows a button only when set.
    var onFindFriends: (() -> Void)? = nil

    @State private var friends: [ProfileDTO] = []
    @State private var phase: Phase = .loading
    @State private var recipient: ProfileDTO?

    private enum Phase { case loading, failed, loaded }

    static func name(of profile: ProfileDTO) -> String {
        if let name = profile.displayName, !name.isEmpty { return name }
        if let handle = profile.handle, !handle.isEmpty { return handle }
        return "Friend"
    }

    var body: some View {
        if let recipient {
            MixtapeComposerSheet(friendID: recipient.userId) { id in
                onCreated(id, Self.name(of: recipient))
            }
        } else {
            HeartableDrawer { content }
                .task(id: relationships.revision) { await load() }
        }
    }

    private func load() async {
        do {
            friends = try await BackendAPI.shared.fetchFriends().compactMap(\.profile)
            phase = .loaded
        } catch {
            // Keep a previously loaded list; only a first failure shows the retry.
            if phase != .loaded { phase = .failed }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Who’s it for?")
                    .font(Typography.heading(23))
                    .foregroundStyle(theme.palette.text)
                Text("Every mixtape is made for one friend. Add songs, notes, and photos, then send it.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch phase {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading friends…")
                        .font(Typography.body(14))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .frame(minHeight: 56)
            case .failed:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn’t load your friends.")
                        .font(Typography.body(14))
                        .foregroundStyle(theme.palette.textSecondary)
                    Button("Try again") { Task { await load() } }
                        .font(Typography.semibold(15))
                        .foregroundStyle(theme.palette.rose)
                        .frame(minHeight: 44)
                }
            case .loaded where friends.isEmpty:
                emptyState
            case .loaded:
                VStack(spacing: 9) {
                    ForEach(friends) { friend in row(friend) }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("Add a friend first to make them a mixtape.")
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let onFindFriends {
                Button {
                    dismiss()
                    onFindFriends()
                } label: {
                    Label("Find friends", systemImage: "person.badge.plus")
                        .font(Typography.semibold(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(theme.palette.rose, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func row(_ friend: ProfileDTO) -> some View {
        let name = Self.name(of: friend)
        return Button { recipient = friend } label: {
            HStack(spacing: 12) {
                AvatarCircle(urlString: friend.avatarUrl, name: name, size: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                        .lineLimit(1)
                    if let handle = friend.handle, !handle.isEmpty, handle != name {
                        Text("@\(handle)")
                            .font(Typography.body(11))
                            .foregroundStyle(theme.palette.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.palette.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(theme.palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(theme.palette.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Make a mixtape for \(name)")
    }
}
