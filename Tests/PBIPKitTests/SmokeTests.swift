import XCTest
@testable import PBIPKit

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(PBIPKit.version.isEmpty)
    }
}
