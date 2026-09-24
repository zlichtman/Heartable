import UIKit
import XCTest
@testable import Heartable

final class AppIconCatalogTests: XCTestCase {
    func testCatalogIsEightUniqueDarkIcons() {
        let choices = AppIconCatalog.choices
        XCTAssertEqual(choices.count, 8)
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
        XCTAssertTrue(choices.allSatisfy { $0.appearance == .dark })
        XCTAssertEqual(choices.first?.id, AppIconCatalog.coreKey)
    }

    func testEveryChoiceUsesABundledHeartablePreviewAsset() {
        for choice in AppIconCatalog.choices {
            XCTAssertNotNil(
                UIImage(named: choice.previewAssetName),
                "Missing real icon preview for \(choice.id)"
            )
        }
    }

    func testAlternateChoicesMapToInstalledThemeIconKeys() {
        let installedThemeKeys = Set(Themes.all.map(\.key))
        let alternateKeys = AppIconCatalog.choices
            .filter { $0.id != AppIconCatalog.coreKey }
            .map(\.id)

        XCTAssertTrue(alternateKeys.allSatisfy(installedThemeKeys.contains))
    }
}
