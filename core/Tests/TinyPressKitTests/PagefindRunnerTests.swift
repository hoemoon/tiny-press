import Foundation
import Testing
@testable import TinyPressKit

@Suite("PagefindRunner")
struct PagefindRunnerTests {
    private let runner = PagefindRunner()

    @Test func honorsExplicitOverrideEnv() {
        // If TINYPRESS_PAGEFIND points at an executable, it wins.
        let here = "/bin/ls"
        setenv("TINYPRESS_PAGEFIND", here, 1)
        defer { unsetenv("TINYPRESS_PAGEFIND") }
        let invocation = runner.resolveInvocation()
        #expect(invocation?.executable == here)
        #expect(invocation?.arguments == [])
    }

    @Test func ignoresOverrideIfNotExecutable() {
        setenv("TINYPRESS_PAGEFIND", "/nonexistent/path/that/should/not/exist", 1)
        defer { unsetenv("TINYPRESS_PAGEFIND") }
        // Falls through to PATH lookup or npx; we don't assert which is found,
        // only that the override didn't poison the result.
        let invocation = runner.resolveInvocation()
        if let invocation {
            #expect(invocation.executable != "/nonexistent/path/that/should/not/exist")
        }
    }
}
