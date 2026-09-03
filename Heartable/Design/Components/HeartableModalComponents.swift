import SwiftUI

enum HeartableModalTone {
    case accent
    case destructive
}

struct HeartableChoiceItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isSelected = false
    var isDestructive = false
    var isDisabled = false
}

/// Standard presentation chrome. It keeps every Heartable-owned drawer on the
/// active theme. Transient feedback is delivered by the native iOS notification
/// system, so sheets do not need their own overlay host.
private struct HeartableSheetChrome: ViewModifier {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let dragIndicator: Visibility

    func body(content: Content) -> some View {
        content
            .presentationBackground(theme.palette.bg)
            .presentationCornerRadius(30)
            .presentationDragIndicator(dragIndicator)
            .accessibilityAction(.escape) { dismiss() }
    }
}

/// Compact menus grow only as far as their content needs. The same content can
/// scroll when Dynamic Type or a small screen leaves less room than it needs.
struct HeartableDrawer<Content: View>: View {
    @Environment(ThemeStore.self) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .presentationSizing(.fitted)
        .heartableSheetChrome()
    }
}

extension View {
    func heartableSheetChrome(
        dragIndicator: Visibility = .visible
    ) -> some View {
        modifier(HeartableSheetChrome(dragIndicator: dragIndicator))
    }
}

/// Theme-owned replacement for app action menus. Native Photos, Files, Camera,
/// AirPlay, and share controllers remain system-owned after the user chooses one.
struct HeartableChoiceSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let title: String
    var subtitle: String? = nil
    let items: [HeartableChoiceItem]
    let onCancel: () -> Void
    let onSelect: (HeartableChoiceItem) -> Void

    var body: some View {
        HeartableDrawer { content }
        .accessibilityAction(.escape, onCancel)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typography.heading(23))
                        .foregroundStyle(theme.palette.text)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.body(13))
                            .foregroundStyle(theme.palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: 9) {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    item.isDestructive
                                        ? theme.palette.danger.opacity(0.12)
                                        : theme.palette.roseDim
                                )
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(
                                            item.isDestructive
                                                ? theme.palette.danger
                                                : theme.palette.rose
                                        )
                                }
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(Typography.semibold(14))
                                    .foregroundStyle(
                                        item.isDestructive
                                            ? theme.palette.danger
                                            : theme.palette.text
                                    )
                                if let subtitle = item.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(Typography.body(11))
                                        .foregroundStyle(theme.palette.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 8)
                            if item.isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(theme.palette.rose)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 13)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .background(theme.palette.card)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: Theme.Radius.md,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: Theme.Radius.md,
                                style: .continuous
                            )
                            .stroke(
                                item.isSelected
                                    ? theme.palette.rose.opacity(0.55)
                                    : theme.palette.border,
                                lineWidth: 1
                            )
                        }
                        .contentShape(Rectangle())
                        .opacity(item.isDisabled ? 0.42 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.isDisabled)
                    .accessibilityValue(item.isSelected ? "Selected" : "")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A themed single-field prompt for app-owned names and service handles.
struct HeartablePromptSheet: View {
    @Environment(ThemeStore.self) private var theme
    @FocusState private var focused: Bool

    let icon: String
    let title: String
    let message: String
    let placeholder: String
    @Binding var text: String
    let actionTitle: String
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrectionDisabled = false
    var isBusy = false
    let onCancel: () -> Void
    let onSubmit: () -> Void

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.palette.roseDim)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(theme.palette.rose)
                }
                .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text(title)
                    .font(Typography.heading(22))
                    .foregroundStyle(theme.palette.text)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(placeholder, text: $text)
                .font(Typography.body(16))
                .foregroundStyle(theme.palette.text)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(autocorrectionDisabled)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit {
                    guard !trimmed.isEmpty else { return }
                    onSubmit()
                }
                .padding(.horizontal, 15)
                .frame(minHeight: 50)
                .background(theme.palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(
                            focused ? theme.palette.rose : theme.palette.border,
                            lineWidth: 1
                        )
                }

            VStack(spacing: 10) {
                Button(action: onSubmit) {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(isBusy ? "Working…" : actionTitle)
                    }
                    .font(Typography.semibold(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(theme.palette.rose, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty || isBusy)

                Button(action: onCancel) {
                    Text("Cancel")
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
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(theme.palette.bg.ignoresSafeArea())
        .task { focused = true }
    }
}

/// Consistent typography, color, and hit target for modal toolbar actions.
struct HeartableToolbarAction: View {
    @Environment(ThemeStore.self) private var theme
    let title: String
    var isSecondary = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.semibold(14))
                .foregroundStyle(
                    isSecondary
                        ? theme.palette.textSecondary
                        : theme.palette.rose
                )
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
