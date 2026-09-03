import SwiftUI

/// App-wide Heartable notifications. Every short-lived success, error, and
/// informational message enters this one queue instead of being rendered as a
/// screen-local toast. Hosts are attached to both the app shell and presented
/// sheets so the active notification is always above the surface being used.
@MainActor
@Observable
final class BannerCenter {
    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: Style
    }

    enum Style: Equatable {
        case success, error, info
        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            case .info: "bell.fill"
            }
        }
    }

    private(set) var current: Banner?
    private var pending: [Banner] = []
    private var dismissTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?

    func show(_ message: String, style: Style = .info) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let banner = Banner(message: trimmed, style: style)
        guard current == nil, advanceTask == nil else {
            // Avoid stacking the same provider error several times when two
            // refresh paths finish together.
            if current?.message != banner.message,
               pending.last?.message != banner.message {
                pending.append(banner)
            }
            return
        }
        present(banner)
    }

    private func present(_ banner: Banner) {
        current = banner
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(banner.style == .error ? 4.2 : 2.8))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func success(_ message: String) { show(message, style: .success) }
    func error(_ message: String) { show(message, style: .error) }
    func info(_ message: String) { show(message, style: .info) }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        guard !pending.isEmpty else { return }
        let next = pending.removeFirst()
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.advanceTask = nil
            self?.present(next)
        }
    }
}

private struct BannerHost: ViewModifier {
    @Environment(ThemeStore.self) private var theme
    let center: BannerCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let banner = center.current {
                bannerCard(banner)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismiss() }
                    .zIndex(1000)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: center.current)
    }

    private func bannerCard(_ banner: BannerCenter.Banner) -> some View {
        HStack(spacing: 10) {
            Image(systemName: banner.style.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint(banner.style))
            Text(banner.message)
                .font(Typography.semibold(14))
                .foregroundStyle(theme.palette.text)
                .lineLimit(3)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(theme.palette.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private func tint(_ style: BannerCenter.Style) -> Color {
        switch style {
        case .success: theme.palette.emerald
        case .error: theme.palette.danger
        case .info: theme.palette.rose
        }
    }
}

extension View {
    /// Hosts app-wide Heartable notifications at the top of this presentation.
    func heartableNotificationHost(_ center: BannerCenter) -> some View {
        modifier(BannerHost(center: center))
    }

    /// Compatibility for older call sites while notification terminology becomes
    /// the sole product language.
    func bannerHost(_ center: BannerCenter) -> some View {
        heartableNotificationHost(center)
    }
}
