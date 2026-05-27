import ArgumentParser

@main
struct TinyPressCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tinypress",
        abstract: "tiny press — 작은 정적 사이트 생성기.",
        version: "0.4.0",
        subcommands: TinyPressCLI.allSubcommands,
        defaultSubcommand: nil
    )

    /// Subcommands available on the current platform. `preview` is
    /// macOS-only because the underlying `FolderWatcher` /
    /// `PreviewServer` are gated to macOS in `TinyPressKit`.
    private static var allSubcommands: [ParsableCommand.Type] {
        var list: [ParsableCommand.Type] = [InitCommand.self, BuildCommand.self]
        #if os(macOS)
        list.append(PreviewCommand.self)
        #endif
        return list
    }
}
