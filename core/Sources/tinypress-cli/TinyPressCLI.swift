import ArgumentParser

@main
struct TinyPressCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tinypress",
        abstract: "tiny press — a tiny static site generator.",
        version: "0.1.0",
        subcommands: [InitCommand.self, BuildCommand.self],
        defaultSubcommand: nil
    )
}
