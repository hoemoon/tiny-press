import XCTest

@testable import TinyPress

final class SmokeTests: XCTestCase {
    func testAppDelegateClassExists() {
        // Sanity-check that the test target sees the app target.
        XCTAssertNotNil(NSStringFromClass(AppDelegate.self))
    }
}
