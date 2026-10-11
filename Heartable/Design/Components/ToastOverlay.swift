import SwiftUI
import UIKit

// MARK: - Installation

/// Attaches the feedback toast window to whichever scene hosts this view. Put it
/// once in the app's root view hierarchy; repeated installs are no-ops.
struct ToastWindowInstaller: UIViewRepresentable {
    let banners: BannerCenter
    let theme: ThemeStore

    func makeUIView(context: Context) -> InstallerView {
        InstallerView(banners: banners, theme: theme)
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        private let banners: BannerCenter
        private let theme: ThemeStore

        init(banners: BannerCenter, theme: ThemeStore) {
            self.banners = banners
            self.theme = theme
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene else { return }
            ToastWindow.install(in: scene, banners: banners, theme: theme)
        }
    }
}

// MARK: - Window

/// A pass-through window one level above the app's main window, so toasts draw
/// over sheets and full-screen covers (the full player included). Touches only
/// land here when they hit the toast itself; everything else falls through to the
/// app. The window hides itself whenever no toast is showing.
final class ToastWindow: UIWindow {
    private static var installed: [ObjectIdentifier: ToastWindow] = [:]

    private let banners: BannerCenter
    private var toastFrame: CGRect = .null
    private var hideTask: Task<Void, Never>?

    static func install(in scene: UIWindowScene, banners: BannerCenter, theme: ThemeStore) {
        let key = ObjectIdentifier(scene)
        guard installed[key] == nil else { return }
        installed[key] = ToastWindow(scene: scene, banners: banners, theme: theme)
    }

    private init(scene: UIWindowScene, banners: BannerCenter, theme: ThemeStore) {
        self.banners = banners
        super.init(windowScene: scene)
        windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        backgroundColor = .clear
        let host = ToastHostController(rootView: ToastOverlayRoot(
            banners: banners,
            theme: theme,
            onToastFrameChange: { [weak self] in self?.toastFrame = $0 }
        ))
        host.view.backgroundColor = .clear
        rootViewController = host
        isHidden = true
        observeToasts()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard banners.current != nil, toastFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    /// Show the window as soon as a toast arrives; hide it once the last one has
    /// finished animating out, so an idle overlay never influences the status bar,
    /// orientation, or accessibility of the app beneath it.
    private func observeToasts() {
        withObservationTracking {
            _ = banners.current
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncVisibility()
                self.observeToasts()
            }
        }
    }

    private func syncVisibility() {
        hideTask?.cancel()
        if banners.current != nil {
            isHidden = false
        } else {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self, self.banners.current == nil else { return }
                self.isHidden = true
            }
        }
    }
}

/// Defers status-bar and orientation decisions to the app's own window so the
/// overlay never changes them while a toast is up.
private final class ToastHostController: UIHostingController<ToastOverlayRoot> {
    private var appController: UIViewController? {
        guard let windows = view.window?.windowScene?.windows,
              let main = windows.first(where: { !($0 is ToastWindow) && $0.isKeyWindow })
                ?? windows.first(where: { !($0 is ToastWindow) }),
              var top = main.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        appController?.preferredStatusBarStyle ?? .default
    }

    override var prefersStatusBarHidden: Bool {
        appController?.prefersStatusBarHidden ?? false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        appController?.supportedInterfaceOrientations ?? .all
    }
}

// MARK: - SwiftUI

struct ToastOverlayRoot: View {
    let banners: BannerCenter
    let theme: ThemeStore
    let onToastFrameChange: @MainActor (CGRect) -> Void

    var body: some View {
        ToastOverlay(onToastFrameChange: onToastFrameChange)
            .environment(banners)
            .environment(theme)
            .preferredColorScheme(theme.current.group == .dark ? .dark : .light)
    }
}

private struct ToastOverlay: View {
    @Environment(BannerCenter.self) private var banners
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onToastFrameChange: @MainActor (CGRect) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let toast = banners.current {
                ToastView(toast: toast) { banners.dismiss(toast.id) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        onToastFrameChange($0)
                    }
                    .id(toast.id)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15),
            value: banners.current?.id
        )
    }
}

private struct ToastView: View {
    @Environment(ThemeStore.self) private var theme

    let toast: BannerCenter.Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(Typography.semibold(14))
                .foregroundStyle(theme.palette.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .onTapGesture(perform: dismiss)
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -12 { dismiss() }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.style == .error ? "Error: \(toast.message)" : toast.message)
        .accessibilityAction(named: "Dismiss", dismiss)
    }

    private var icon: String {
        switch toast.style {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch toast.style {
        case .success: theme.palette.emerald
        case .error: theme.palette.danger
        case .info: theme.palette.rose
        }
    }
}
