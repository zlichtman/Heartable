import SwiftUI

/// App-wide, Apple-style feedback banners. Inject `BannerCenter` into the
/// environment and call `banners.success("…")` / `.error("…")` / `.info("…")`
/// from anywhere; a single host overlay (see `bannerHost`) renders the current
/// banner sliding in from the top and auto-dismisses it.
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
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Style = .info) {
        current = Banner(message: message, style: style)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(style == .error ? 3.5 : 2.4))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func success(_ message: String) { show(message, style: .success) }
    func error(_ message: String) { show(message, style: .error) }
    func info(_ message: String) { show(message, style: .info) }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
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
                .lineLimit(2)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private func tint(_ style: BannerCenter.Style) -> Color {
        switch style {
        case .success: .green
        case .error: theme.palette.danger
        case .info: theme.palette.rose
        }
    }
}

extension View {
    /// Hosts the app-wide feedback banners at the top of this view.
    func bannerHost(_ center: BannerCenter) -> some View {
        modifier(BannerHost(center: center))
    }
}
