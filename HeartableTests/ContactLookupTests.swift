import XCTest
@testable import Heartable

final class ContactLookupTests: XCTestCase {
    func testEmailsNormalizeWithoutChangingAddressSemantics() {
        XCTAssertEqual(ContactEmailLookup.hash("  Person@Example.COM\n"), ContactEmailLookup.hash("person@example.com"))
        XCTAssertNotEqual(ContactEmailLookup.hash("person+music@example.com"), ContactEmailLookup.hash("person@example.com"))
        XCTAssertEqual(ContactEmailLookup.hash("person@example.com")?.count, 64)
        XCTAssertNil(ContactEmailLookup.hash(" "))
        XCTAssertNil(ContactEmailLookup.hash("not-an-email"))
    }
}
