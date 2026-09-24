import SwiftUI

/// Reusable themed container for every settings/profile sub-screen. Wraps content
/// in a `ScrollView` over the theme background and sets the navigation title, so
/// each screen reads the same and only supplies its own rows.
struct SettingsScaffold<Content: View>: View {
    @Environment(ThemeStore.self) private var theme
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single settings list row styled as a card: an SF Symbol in a tinted square,
/// a label, an optional subtitle, and a trailing chevron. Drop inside a
/// `NavigationLink` (or a `Button`) — it carries no tap handling itself.
///
/// A condensed grouped container (iOS Settings style): stacks its rows with no
/// gaps inside one bordered card. Pair with rows that draw their own dividers.
struct SettingsGroup<Content: View>: View {
    @Environment(ThemeStore.self) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(theme.palette.border, lineWidth: 1)
            }
    }
}

struct SettingsRow: View {
    @Environment(ThemeStore.self) private var theme
    let icon: String
    let label: String
    var subtitle: String? = nil
    /// Override the icon-square tint + label color (used for destructive rows).
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint ?? theme.palette.rose)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.semibold(15))
                    .foregroundStyle(tint ?? theme.palette.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.palette.textMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

/// A stable, themed decision surface for destructive settings actions.
/// Callers retain ownership of the operation and its success or error handling.
struct HeartableDestructiveConfirmation: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let icon: String
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    var tone: HeartableModalTone = .destructive
    var isBusy = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var tint: Color {
        switch tone {
        case .accent: theme.palette.rose
        case .destructive: theme.palette.danger
        }
    }

    var body: some View {
        HeartableDrawer { content }
            .interactiveDismissDisabled(isBusy)
            .accessibilityAction(.escape) {
                guard !isBusy else { return }
                onCancel()
            }
    }

    private var content: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 20) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(Typography.semibold(21))
                    .foregroundStyle(theme.palette.text)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(role: .destructive, action: onConfirm) {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: icon)
                        }
                        Text(isBusy ? "Working…" : confirmTitle)
                    }
                    .font(Typography.semibold(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Button(action: onCancel) {
                    Text(cancelTitle)
                        .font(Typography.semibold(15))
                        .foregroundStyle(theme.palette.text)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(theme.palette.card, in: Capsule())
                        .overlay(Capsule().stroke(theme.palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 12 : 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(theme.palette.bg.ignoresSafeArea())
    }
}
