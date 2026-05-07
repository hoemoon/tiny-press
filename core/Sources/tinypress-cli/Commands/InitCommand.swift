import ArgumentParser
import Foundation

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold a new tiny press site at the given path."
    )

    @Argument(help: "Folder where the new site will be created.")
    var path: String

    @Option(name: .long, help: "Title for the new site.")
    var title: String = "My Site"

    func run() async throws {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let contents = try fm.contentsOfDirectory(atPath: url.path)
            if !contents.isEmpty {
                Log.error("\(url.path) already exists and is not empty.")
                throw ExitCode(1)
            }
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: url.appendingPathComponent("content/posts"),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: url.appendingPathComponent("content/pages"),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: url.appendingPathComponent("static"),
            withIntermediateDirectories: true
        )

        let configYAML = """
            title: \(yamlEscape(title))
            description: A new tiny press site.
            theme: default
            language: en
            permalinkStyle: pretty
            """
        try configYAML.write(
            to: url.appendingPathComponent("tinypress.yml"),
            atomically: true,
            encoding: .utf8
        )

        let helloPost = """
            ---
            title: Hello, world
            date: \(currentDateString())
            tags: [intro]
            ---

            Welcome to your new tiny press site.

            Edit `content/posts/hello.md` and run `tinypress build` to render.
            """
        try helloPost.write(
            to: url.appendingPathComponent("content/posts/hello.md"),
            atomically: true,
            encoding: .utf8
        )

        let aboutPage = """
            ---
            title: About
            layout: page
            ---

            Tell readers a bit about yourself.
            """
        try aboutPage.write(
            to: url.appendingPathComponent("content/pages/about.md"),
            atomically: true,
            encoding: .utf8
        )

        Log.info("Created site at \(url.path)")
        Log.info("Next: cd \(path) && tinypress build")
        print(url.path)
    }

    private func yamlEscape(_ value: String) -> String {
        if value.contains(":") || value.contains("#") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func currentDateString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: Date())
    }
}
