import ArgumentParser
import Foundation
import TinyPressKit

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Render the site at --source into the --output folder."
    )

    @Option(name: .shortAndLong, help: "Source folder. Defaults to the current directory.")
    var source: String = "."

    @Option(name: .shortAndLong, help: "Output folder. Defaults to <source>/_site.")
    var output: String?

    @Flag(name: .long, help: "Include posts marked draft: true.")
    var includeDrafts: Bool = false

    func run() async throws {
        let sourceURL = URL(fileURLWithPath: source).standardized
        let outputURL =
            output.map { URL(fileURLWithPath: $0).standardized }
            ?? sourceURL.appendingPathComponent("_site", isDirectory: true)

        Log.info("Building \(sourceURL.path) → \(outputURL.path)")

        let builder = SiteBuilder()
        do {
            let report = try await builder.build(
                sourceRoot: sourceURL,
                outputRoot: outputURL,
                includeDrafts: includeDrafts
            )
            let timing = String(format: "%.3fs", report.duration)
            Log.info(
                "Built \(report.pagesGenerated) page(s) and copied "
                    + "\(report.assetsCopied) asset(s) in \(timing)"
            )
            for warning in report.warnings {
                Log.info("warning: \(warning)")
            }
            print(outputURL.path)
        } catch {
            Log.error("\(error)")
            throw ExitCode(1)
        }
    }
}
