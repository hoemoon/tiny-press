#if os(macOS)
import XCTest

@testable import TinyPressKit

final class TailscaleServeAdapterTests: XCTestCase {
    /// Detect should at least move out of `.unknown` once it has run.
    /// On a machine without `tailscale` it lands on `.unavailable`; on
    /// one with the daemon up and running it lands on `.idle`. Either is
    /// acceptable — we just need to know the probe completed.
    @MainActor
    func testDetectLeavesUnknownState() async {
        let adapter = TailscaleServeAdapter()
        XCTAssertEqual(adapter.state, .unknown)
        await adapter.detect()
        XCTAssertNotEqual(
            adapter.state, .unknown,
            "detect() must leave .unknown — got \(adapter.state)"
        )
    }

    /// The integration is meaningful only when the local daemon is up.
    /// Skip otherwise so CI on plain VMs without Tailscale stays green.
    @MainActor
    func testDetectFindsTailnetHostnameWhenAvailable() async throws {
        let adapter = TailscaleServeAdapter()
        await adapter.detect()
        guard case .idle = adapter.state else {
            try XCTSkipIf(true, "tailscale not running on this host: \(adapter.state)")
            return
        }
        let host = try XCTUnwrap(adapter.hostname)
        XCTAssertTrue(host.hasSuffix(".ts.net"), "Unexpected hostname \(host)")
    }
}
#endif
