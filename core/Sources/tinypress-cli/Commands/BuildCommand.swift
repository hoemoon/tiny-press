import ArgumentParser
import Foundation
import TinyPressKit

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "--source의 사이트를 --output 폴더로 렌더링합니다."
    )

    @Option(name: .shortAndLong, help: "소스 폴더. 기본값은 현재 디렉터리.")
    var source: String = "."

    @Option(name: .shortAndLong, help: "출력 폴더. 기본값은 <source>/_site.")
    var output: String?

    @Flag(name: .long, help: "draft: true로 표시된 포스트도 포함.")
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
