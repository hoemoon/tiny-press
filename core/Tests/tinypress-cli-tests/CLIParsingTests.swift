import ArgumentParser
import Testing

@testable import tinypress_cli

@Suite("CLI argument parsing")
struct CLIParsingTests {
    @Test func rootCommandRegistersInitAndBuild() {
        let names = TinyPressCLI.configuration.subcommands.compactMap {
            $0.configuration.commandName
        }
        #expect(names.contains("init"))
        #expect(names.contains("build"))
    }

    @Test func initCommandParsesPathAndTitle() throws {
        let cmd = try InitCommand.parse(["mysite", "--title", "Hello"])
        #expect(cmd.path == "mysite")
        #expect(cmd.title == "Hello")
    }

    @Test func initCommandRequiresPath() {
        #expect(throws: (any Error).self) {
            _ = try InitCommand.parse([])
        }
    }

    @Test func buildCommandDefaults() throws {
        let cmd = try BuildCommand.parse([])
        #expect(cmd.source == ".")
        #expect(cmd.output == nil)
        #expect(cmd.includeDrafts == false)
    }

    @Test func buildCommandAcceptsFlagsAndOptions() throws {
        let cmd = try BuildCommand.parse([
            "--source", "./site",
            "--output", "./out",
            "--include-drafts",
        ])
        #expect(cmd.source == "./site")
        #expect(cmd.output == "./out")
        #expect(cmd.includeDrafts == true)
    }
}
