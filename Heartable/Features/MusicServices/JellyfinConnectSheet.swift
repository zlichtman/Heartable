import SwiftUI

/// Sign in to a Jellyfin server: address + username + password. Presented from
/// Music Services when the user taps Connect on Jellyfin. Server and username
/// prefill from the last connection; the password is never stored.
struct JellyfinConnectSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(ProvidersStore.self) private var providers
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dismiss) private var dismiss

    @State private var server = JellyfinProvider.storedServer ?? ""
    @State private var username = JellyfinProvider.storedUsername ?? ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        HeartableDrawer {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ProviderBadge(id: .jellyfin, size: 44, connected: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect Jellyfin").font(Typography.heading(22))
                            .foregroundStyle(theme.palette.text)
                        Text("Your own server, your own music")
                            .font(Typography.semibold(12))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                    Spacer(minLength: 8)
                }

                Text("Enter your Jellyfin server address and account. Full tracks stream straight from your server and play right in the app.")
                    .font(Typography.body(14))
                    .foregroundStyle(theme.palette.textSecondary)

                VStack(spacing: 10) {
                    field("http://192.168.1.20:8096", text: $server, keyboard: .URL)
                    field("username", text: $username, keyboard: .default)
                    secureField("password", text: $password)
                }

                if let error {
                    Text(error)
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: connect) {
                    Group {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Connect").font(Typography.semibold(15))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.palette.rose, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(busy || server.trimmingCharacters(in: .whitespaces).isEmpty
                          || username.trimmingCharacters(in: .whitespaces).isEmpty)

                Text("On your home network, the address usually looks like http://192.168.1.20:8096. For a server reachable from anywhere, use its https address.")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textMuted)
            }
            .padding(20)
        }
        .background(theme.palette.bg.ignoresSafeArea())
    }

    private func connect() {
        busy = true
        error = nil
        Task {
            do {
                try await JellyfinProvider.link(server: server, username: username, password: password)
                try await providers.recordConnected(.jellyfin)
                banners.success("Connected Jellyfin")
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    // MARK: Field helpers (AuthView idiom)

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(theme.palette.textMuted))
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(theme.palette.text)
            .padding(14)
            .background(theme.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(theme.palette.textMuted))
            .foregroundStyle(theme.palette.text)
            .padding(14)
            .background(theme.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}
