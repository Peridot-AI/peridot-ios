import XCTest
@testable import Peridot

/// The same cases as the Android app's LinksTest.
final class LinksTests: XCTestCase {
    func testLinksPointAtTheWebsite() {
        XCTAssertEqual(shareLink("abc123", web: URL(string: "https://tryperidot.io/")!), "https://tryperidot.io/share/abc123")
        XCTAssertEqual(inviteLink("qr7auyzw", web: URL(string: "https://tryperidot.io")!), "https://tryperidot.io/?ref=qr7auyzw")
    }

    func testPricesInEuros() {
        XCTAssertEqual(euros(1000), "€ 10")
        XCTAssertEqual(euros(750), "€ 7.50")
        XCTAssertEqual(euros(5), "€ 0.05")
    }
}
