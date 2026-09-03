import SwiftUI

/// First gate. Two ways in: Sign in with Apple, or email + password
/// (sign in / create account). Music-service pairing happens after Heartable auth.
struct AuthView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ThemeStore.self) private var theme

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var showsRecovery = false

    @State private var busy = false
    @State private var error: String?
    @State private var info: String?

    var body: some View {
        ZStack {
            theme.palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    appleButton
                    divider
                    fields
                    primaryButton
                    Button(isSignUp ? "Have an account? Sign in" : "New here? Create an account") {
                        isSignUp.toggle(); resetTransient()
                    }
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(minHeight: 44)
                    if let error { message(error, color: theme.palette.danger) }
                    if let info { message(info, color: theme.palette.textSecondary) }
                }
                .padding(24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showsRecovery) {
            PasswordRecoveryView(initialEmail: email)
                .environment(auth)
                .environment(theme)
                .presentationDetents([.medium])
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(theme.palette.rose)
            Text("Heartable")
                .font(Typography.heading(36))
                .foregroundStyle(theme.palette.text)
            Text("your music, with love")
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .padding(.top, 40)
        .padding(.bottom, 8)
    }

    private var appleButton: some View {
        Button {
            run { try await auth.signInWithApple() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                Text("Sign in with Apple").font(Typography.semibold(16))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.palette.text)
            .foregroundStyle(theme.palette.bg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.full))
        }
        .disabled(busy)
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(theme.palette.border).frame(height: 1)
            Text("or").font(Typography.body(12)).foregroundStyle(theme.palette.textMuted)
            Rectangle().fill(theme.palette.border).frame(height: 1)
        }
    }

    @ViewBuilder private var fields: some View {
        field("Email", text: $email, keyboard: .emailAddress)
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                passwordField
                Button { showsPassword.toggle() } label: {
                    Image(systemName: showsPassword ? "eye.slash" : "eye")
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
            }

            if !isSignUp {
                Button("Forgot password?") { showsRecovery = true }
                    .font(Typography.medium(13))
                    .foregroundStyle(theme.palette.rose)
                    .frame(minHeight: 44)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            primaryAction()
        } label: {
            Group {
                if busy { ProgressView().tint(.white) }
                else { Text(isSignUp ? "Create account" : "Sign in").font(Typography.semibold(16)) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.palette.rose)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.full))
        }
        .disabled(busy || email.isEmpty || password.isEmpty)
        .frame(minHeight: 44)
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Typography.body(13))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: Field helpers

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(theme.palette.textMuted))
            .keyboardType(keyboard)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(theme.palette.text)
            .padding(14)
            .background(theme.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    @ViewBuilder
    private var passwordField: some View {
        Group {
            if showsPassword {
                TextField("", text: $password,
                          prompt: Text("Password").foregroundStyle(theme.palette.textMuted))
            } else {
                SecureField("", text: $password,
                            prompt: Text("Password").foregroundStyle(theme.palette.textMuted))
            }
        }
        .textContentType(isSignUp ? .newPassword : .password)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(theme.palette.text)
        .padding(14)
        .frame(minHeight: 44)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    // MARK: Actions

    private func primaryAction() {
        run {
            if isSignUp {
                let needsConfirm = try await auth.signUp(email: email, password: password)
                if needsConfirm {
                    await MainActor.run { info = "Check your email to confirm, then sign in." }
                }
            } else {
                try await auth.signInWithPassword(email: email, password: password)
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true; error = nil; info = nil
        Task {
            do { try await work() }
            catch { await MainActor.run { self.error = error.localizedDescription } }
            await MainActor.run { busy = false }
        }
    }

    private func resetTransient() {
        error = nil; info = nil
    }
}

/// Lightweight recovery flow kept separate from the password field so its action
/// remains clear and password-manager affordances never collide with a reveal icon.
private struct PasswordRecoveryView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var busy = false
    @State private var error: String?
    @State private var sent = false

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reset your password")
                    .font(Typography.heading(26))
                    .foregroundStyle(theme.palette.text)
                Text(sent
                     ? "Check your inbox for a secure password-reset link."
                     : "Enter the email address for your Heartable account.")
                    .font(Typography.body(14))
                    .foregroundStyle(theme.palette.textSecondary)

                if !sent {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(theme.palette.text)
                        .padding(14)
                        .frame(minHeight: 44)
                        .background(theme.palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                    Button {
                        send()
                    } label: {
                        Group {
                            if busy {
                                ProgressView().tint(.white)
                            } else {
                                Text("Send reset link").font(Typography.semibold(16))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(theme.palette.rose)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.full))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let error {
                    Text(error)
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.danger)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .background(theme.palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HeartableSheetDismissButton(
                        accessibilityLabel: "Dismiss password recovery"
                    )
                }
            }
        }
        .heartableSheetChrome()
    }

    private func send() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        busy = true
        error = nil
        Task {
            do {
                try await auth.resetPassword(email: address)
                sent = true
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
