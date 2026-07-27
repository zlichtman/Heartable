import SwiftUI

/// Add friend — search profiles by name/handle/invite-code/service username and
/// send a friend request. Prefills + auto-searches a pending invite code from a
/// `heartable://add-friend?code=…` deep link. Ported from the RN AddFriendScreen.
struct AddFriendView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(FriendLinks.self) private var friendLinks
    @Environment(BannerCenter.self) private var banners
    @Environment(AuthStore.self) private var auth

    @State private var query = ""
    @State private var results: [FoundProfileDTO] = []
    @State private var searched = false
    @State private var busy = false
    @State private var sent: Set<UUID> = []
    @State private var acting: Set<UUID> = []
    @State private var relationshipNote: String?

    var body: some View {
        ZStack {
            theme.palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Find friend")
                    Text("Search by name, @handle, invite code, or a music-service username they have connected.")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                        .padding(.bottom, 12)

                    searchRow

                    ForEach(results) { r in resultCard(r) }

                    if searched && results.isEmpty {
                        Text(relationshipNote ?? "No matches. Friends must have opened Heartable at least once.")
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textSecondary)
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .navigationTitle("Add friend")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let code = friendLinks.take() {
                query = code
                await search()
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            TextField("name, @handle, or username", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
                .font(Typography.body(15))
                .foregroundStyle(theme.palette.text)
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))

            Button { Task { await search() } } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 46)
                    .background(theme.palette.rose, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel("Search")
        }
    }

    private func resultCard(_ r: FoundProfileDTO) -> some View {
        let isSent = sent.contains(r.userId)
        let isActing = acting.contains(r.userId)
        return HStack(spacing: 12) {
            AvatarCircle(urlString: r.avatarUrl, name: r.displayName ?? r.spotifyId, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.displayName ?? r.spotifyId ?? "Listener")
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                if let sid = r.spotifyId, r.displayName != nil {
                    Text(sid)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            Spacer(minLength: 4)
            Button(isActing ? "Sending…" : (isSent ? "Requested" : "Add")) {
                Task { await add(r) }
            }
            .font(Typography.semibold(13))
            .foregroundStyle(isSent ? theme.palette.textSecondary : .white)
            .padding(.vertical, 9).padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(isSent ? theme.palette.border : theme.palette.rose, in: Capsule())
            .buttonStyle(.plain)
            .disabled(isSent || isActing)
        }
        .padding(14)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        )
        .padding(.top, 12)
    }

    // MARK: Actions

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        searched = false
        results = []
        relationshipNote = nil
        do {
            let found = try await BackendAPI.shared.findProfiles(query: q)
                .filter { $0.userId != auth.userID }
            var addable: [FoundProfileDTO] = []
            for profile in found {
                switch try await BackendAPI.shared.relationship(with: profile.userId) {
                case .none:
                    addable.append(profile)
                case .friends:
                    relationshipNote = "You’re already friends."
                case .outgoing:
                    relationshipNote = "Your friend request is already pending."
                case .incoming:
                    relationshipNote = "They already sent you a request. Accept it from Friends → Find."
                case .blocked:
                    relationshipNote = "This profile isn’t available to add."
                }
            }
            results = addable
            searched = true
            if found.isEmpty {
                banners.info("No one found. Try a username, name, or invite code.")
            }
        } catch {
            searched = true
            relationshipNote = "Couldn’t check friendship status. Please try again."
            banners.error(error.localizedDescription)
        }
    }

    private func add(_ r: FoundProfileDTO) async {
        guard !acting.contains(r.userId) else { return }
        acting.insert(r.userId)
        defer { acting.remove(r.userId) }
        do {
            switch try await BackendAPI.shared.sendFriendRequest(addresseeID: r.userId) {
            case .sent:
                sent.insert(r.userId)
                friendLinks.markRelationshipsChanged()
                banners.success("Friend request sent")
            case .alreadyFriends:
                results.removeAll { $0.userId == r.userId }
                relationshipNote = "You’re already friends."
                banners.info("You’re already friends")
            case .outgoingPending:
                sent.insert(r.userId)
                banners.info("Friend request already pending")
            case .incomingPending:
                results.removeAll { $0.userId == r.userId }
                relationshipNote = "They already sent you a request. Accept it from Friends → Find."
                banners.info("They already sent you a friend request")
            case .blocked:
                results.removeAll { $0.userId == r.userId }
                banners.error("This profile isn’t available to add")
            }
        } catch {
            banners.error(error.localizedDescription)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
