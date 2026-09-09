import XCTest
import SwiftUI
@testable import Heartable

@MainActor
final class DrawerLayoutTests: XCTestCase {
    func testThreeChoiceDrawerFitsItsContentOnIPhone() async throws {
        try await verifyDrawer(optionCount: 3, expectedHeight: 230...450)
    }

    func testLongDrawerClampsToScreenAndRemainsScrollable() async throws {
        try await verifyDrawer(optionCount: 24, expectedHeight: 650...1_000)
    }

    func testProviderPriorityDrawerDoesNotUseAFullScreenForTwoServices() async throws {
        try await verifyDrawer(optionCount: 2, expectedHeight: 180...350, reorder: true)
    }

    func testAccessibilityTextStillFitsAndUsesTheTheme() async throws {
        try await verifyDrawer(optionCount: 4, expectedHeight: 350...1_000,
                               dynamicType: .accessibility3, dark: true)
    }

    private func verifyDrawer(optionCount: Int, expectedHeight: ClosedRange<CGFloat>,
                              reorder: Bool = false, dynamicType: DynamicTypeSize = .large,
                              dark: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        if dynamicType.isAccessibilitySize {
            window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        }
        let theme = ThemeStore()
        let originalTheme = theme.currentKey
        if dark {
            theme.setTheme("gruvbox-dark")
            XCTAssertEqual(theme.currentKey, "gruvbox-dark")
        }
        defer { theme.setTheme(originalTheme) }
        let fixture = DrawerFixture(optionCount: optionCount, reorder: reorder, dynamicType: dynamicType)
            .environment(theme).environment(\.dynamicTypeSize, dynamicType)
        let host = UIHostingController(rootView: fixture)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        try await Task.sleep(for: .seconds(1))
        let sheet = try XCTUnwrap(host.presentedViewController)
        let frame = try XCTUnwrap(sheet.presentationController?.frameOfPresentedViewInContainerView)
        XCTAssertTrue(expectedHeight.contains(frame.height), "Unexpected drawer height: \(frame.height)")
        XCTAssertLessThanOrEqual(frame.height, window.bounds.height)
        if optionCount > 20 {
            let scroll = try XCTUnwrap(scrollViews(in: sheet.view).first { $0.contentSize.height > $0.bounds.height + 100 })
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertGreaterThan(scroll.contentOffset.y, 100)
        }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Drawer-\(optionCount)-options"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}

private struct DrawerFixture: View {
    @State private var presented = false
    let optionCount: Int
    let reorder: Bool
    let dynamicType: DynamicTypeSize
    var body: some View {
        Color.clear
            .task { presented = true }
            .sheet(isPresented: $presented) {
                if reorder {
                    HeartableReorderSheet(title: "Creator priority", items: [ProviderID.spotify, .apple], onMove: { _, _ in }) { id in
                        Text(ProviderCatalog.entry(id)?.label ?? id.rawValue)
                    }
                } else {
                HeartableChoiceSheet(
                    title: "Playback mode",
                    items: (0..<optionCount).map {
                        HeartableChoiceItem(id: String($0), icon: "shuffle", title: "Option \($0 + 1)")
                    },
                    onCancel: { presented = false },
                    onSelect: { _ in }
                )
                .environment(\.dynamicTypeSize, dynamicType)
                }
            }
    }
}
