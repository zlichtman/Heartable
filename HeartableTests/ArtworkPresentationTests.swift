import XCTest
import SwiftUI
@testable import Heartable

@MainActor
final class ArtworkPresentationTests: XCTestCase {
    func testWaitingAvatarUpdatesWhenAnotherScreenCachesItsPhoto() async throws {
        // A non-network URL lets the first request finish without an image.
        // Publishing a decoded image later models another screen's success.
        let url = URL(string: "artwork-fixture://\(UUID().uuidString)")!
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let probe = PlaceholderProbe()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView:
            CachedArtworkImage(url: url) { probe.placeholder() }
                .frame(width: 120, height: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
        )
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(try dominantChannel(in: window), 0, "The original request displays the red placeholder")

        let renders = probe.renders
        let unrelated = URL(string: "artwork-fixture://\(UUID().uuidString)")!
        ArtworkImageCache.shared.remember(UIImage(), for: unrelated, encodedByteCount: 0)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(probe.renders, renders, "Unrelated image loads must not redraw this view")

        for (color, channel) in [(UIColor.green, 1), (UIColor.blue, 2)] {
            let photo = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            }
            ArtworkImageCache.shared.remember(photo, for: url, encodedByteCount: 400)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(try dominantChannel(in: window), channel,
                           "An already mounted avatar must update without navigation or changing its URL")
        }
    }

    private func dominantChannel(in window: UIWindow) throws -> Int {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cg = try XCTUnwrap(screenshot.cgImage)
        let center = try XCTUnwrap(cg.cropping(to: CGRect(x: cg.width / 2, y: cg.height / 2, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try XCTUnwrap((0..<3).max(by: { pixel[$0] < pixel[$1] }))
    }
}

@MainActor private final class PlaceholderProbe {
    var renders = 0
    func placeholder() -> Color {
        renders += 1
        return .red
    }
}
