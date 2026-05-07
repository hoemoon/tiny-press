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
        #if os(macOS)
        #expect(names.contains("preview"))
        #else
        #expect(!names.contains("preview"))
        #endif
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

    #if os(macOS)
    @Test func previewCommandDefaults() throws {
        let cmd = try PreviewCommand.parse([])
        #expect(cmd.source == ".")
        #expect(cmd.output == nil)
        #expect(cmd.port == 8080)
        #expect(cmd.host == "127.0.0.1")
        #expect(cmd.includeDrafts == false)
        #expect(cmd.share == false)
    }

    @Test func previewCommandAcceptsFlagsAndOptions() throws {
        let cmd = try PreviewCommand.parse([
            "--source", "./site",
            "--output", "./out",
            "--port", "9000",
            "--host", "0.0.0.0",
            "--include-drafts",
            "--share",
        ])
        #expect(cmd.source == "./site")
        #expect(cmd.output == "./out")
        #expect(cmd.port == 9000)
        #expect(cmd.host == "0.0.0.0")
        #expect(cmd.includeDrafts == true)
        #expect(cmd.share == true)
    }
    #endif
}
