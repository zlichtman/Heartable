import SwiftUI

struct MixtapeLinkSheet: View {
    @Environment(ThemeStore.self) private var theme
    let mixtapeID: UUID
    @State private var status: MixtapeLinkStatus?
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        HeartableDrawer {
            VStack(alignment: .leading, spacing: 18) {
                Text("Share mixtape").font(Typography.heading(24))
                Text("Anyone with the link can view the songs, notes, and photos you publish. Later edits stay private until you update the shared version.")
                    .font(Typography.body(15)).foregroundStyle(theme.palette.textSecondary)
                if let token = status?.token, let url = SharedMixtapeRoute.webURL(token: token) {
                    ShareLink(item: url) {
                        Label("Share link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                    Button("Update shared version") { Task { await act("publish") } }.frame(minHeight: 44)
                    Button("Revoke link", role: .destructive) { Task { await act("revoke") } }.frame(minHeight: 44)
                    Text("Revoking stops new access. Already opened images can remain visible briefly, and saved copies cannot be recalled.")
                        .font(Typography.body(13)).foregroundStyle(theme.palette.textSecondary)
                } else if loaded {
                    Button("Publish link") { Task { await act("publish") } }
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
                }
                if busy { ProgressView().tint(theme.palette.rose) }
                if let error {
                    Text(error).font(Typography.body(14)).foregroundStyle(theme.palette.textSecondary)
                    if !loaded { Button("Try again") { Task { await act("status") } }.frame(minHeight: 44) }
                }
            }
            .foregroundStyle(theme.palette.text).tint(theme.palette.rose)
            .padding(24).disabled(busy)
        }.task { await act("status") }
    }

    private func act(_ action: String) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            status = try await BackendAPI.shared.manageMixtapeLink(id: mixtapeID, action: action)
            loaded = true
        } catch { self.error = "Couldn’t update sharing. Please try again." }
    }
}
