import XCTest
import SwiftUI
@testable import Heartable

@MainActor
final class DrawerPresentationTests: XCTestCase {
    func testWarmSearchDrawer() async throws { try await render(themeKey: Themes.defaultKey) }
    func testDarkSearchDrawer() async throws { try await render(themeKey: "gruvbox-dark") }

    private func render(themeKey: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let theme = ThemeStore()
        let previousTheme = theme.currentKey
        theme.setTheme(themeKey)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: DrawerFixture().environment(theme))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            previous?.makeKey()
            theme.setTheme(previousTheme)
        }
        try await Task.sleep(for: .milliseconds(1100))
        let sheet = try XCTUnwrap(host.presentedViewController)
        XCTAssertGreaterThan(sheet.view.bounds.height, 200)
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Search-drawer-\(themeKey)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct DrawerFixture: View {
    @State private var shown = false
    @State private var selected: Set<ProviderID> = [.heartable, .spotify, .apple]
    private let ids: [ProviderID] = [.heartable, .apple, .spotify, .audius, .deezer, .internetArchive, .wsum]
    var body: some View {
        LinearGradient(colors: [.orange, .blue], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            .task { shown = true }
            .sheet(isPresented: $shown) {
                HeartableChoiceSheet(
                    title: "Search in",
                    items: ids.map {
                        .init(id: $0.rawValue, icon: "music.note",
                              title: $0 == .heartable ? "Heartable" : ProviderCatalog.entry($0)!.label,
                              isSelected: selected.contains($0), providerID: $0)
                    },
                    dismissOnSelection: false,
                    onCancel: { shown = false },
                    onSelect: {
                        guard let id = ProviderID(rawValue: $0.id) else { return }
                        if !selected.insert(id).inserted { selected.remove(id) }
                    }
                )
            }
    }
}
