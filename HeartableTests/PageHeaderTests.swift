import XCTest
import SwiftUI
@testable import Heartable

@MainActor
final class PageHeaderTests: XCTestCase {
    func testChatsActionFitsSmallAndLargeTextLayouts() async throws {
        try await checkHeader(title: "Chats", subtitle: AppTab.chats.subtitle)
    }

    func testMixtapesActionFitsSmallAndLargeTextLayouts() async throws {
        try await checkHeader(title: "Mixtapes", subtitle: nil)
    }

    func testContactRetryCardFitsCompactWidth() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ContactsLookupCard(
            running: false, searched: true,
            errorMessage: "Couldn’t search contacts. Please try again in a minute.",
            hasMatches: false, onSearch: {}
        ).padding(16).environment(ThemeStore()))
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(250))
        let fitted = host.sizeThatFits(in: CGSize(width: 320, height: 1000))
        XCTAssertLessThanOrEqual(fitted.width, 320)
        XCTAssertLessThan(fitted.height, 320, "Retry stays inside one compact card")
    }

    private func checkHeader(title: String, subtitle: String?) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        for (width, textSize) in [(CGFloat(320), DynamicTypeSize.large), (390, .large), (320, .accessibility3)] {
            let window = UIWindow(windowScene: scene)
            let root = HeartablePageHeader(title: title, subtitle: subtitle, action: .init(title: "Create mixtape", symbol: "plus", perform: {}, iconOnly: true))
                .padding(16).environment(ThemeStore()).environment(\.dynamicTypeSize, textSize)
            let host = UIHostingController(rootView: root)
            // A real compact phone viewport, not a fixed-height header crop:
            // accessibility text is allowed to stack above the conversation list.
            window.frame = CGRect(x: 0, y: 0, width: width, height: 568)
            window.rootViewController = host
            host.view.frame = window.bounds
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let fitted = host.sizeThatFits(in: CGSize(width: width, height: 1000))
            XCTAssertLessThanOrEqual(fitted.width, width)
            XCTAssertLessThan(fitted.height, textSize.isAccessibilitySize ? 380 : 230)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(title)-header-\(Int(width))-\(textSize)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
        previous?.makeKey()
    }
}
