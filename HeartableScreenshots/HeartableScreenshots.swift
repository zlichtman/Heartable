import XCTest

/// Captures marketing screenshots from the debug fixtures on a real, rotated
/// simulator. Run with the HeartableScreenshots scheme and
/// `TEST_RUNNER_SCREENSHOT_DIR=<dir>`; PNGs land in that directory.
final class HeartableScreenshots: XCTestCase {
    private var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    private func capture(_ name: String, arguments: [String], orientation: UIDeviceOrientation, settle: TimeInterval) throws {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCUIDevice.shared.orientation = orientation
        if arguments.contains("mixtape") {
            XCTAssertTrue(app.navigationBars["Drive Home"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Share mixtape"].exists)
            XCTAssertTrue(app.buttons["Mixtape options"].exists)
        }
        Thread.sleep(forTimeInterval: settle)
        let screenshot = XCUIScreen.main.screenshot()
        if orientation.isLandscape {
            XCTAssertGreaterThan(screenshot.image.size.width, screenshot.image.size.height,
                                 "Vinyl capture must show the landscape shelf, not the portrait playlist")
        }
        let png = screenshot.pngRepresentation
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }

    func testVinylShelfLandscape() throws {
        try capture("vinyl", arguments: ["-HeartableScreenshot", "vinyl", "-heartable_theme", "noir"], orientation: .landscapeLeft, settle: 9)
    }

    func testMixtapePortrait() throws {
        try capture("mixtape", arguments: ["-HeartableScreenshot", "mixtape", "-heartable_theme", "midnight"], orientation: .portrait, settle: 7)
    }
}
