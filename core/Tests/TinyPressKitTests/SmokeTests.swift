import Testing
@testable import TinyPressKit

@Suite("Smoke")
struct SmokeTests {
    @Test func smoke() {
        #expect(TinyPressKit.version.isEmpty == false)
    }
}
