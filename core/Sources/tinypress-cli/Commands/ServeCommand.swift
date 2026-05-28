#if os(macOS)
import ArgumentParser
import Dispatch
import Foundation
import TinyPressKit

/// Static-file HTTP server for an already-built tinypress site.
///
/// `serve` is the "headless" counterpart to ``preview``: it brings up
/// the same Hummingbird stack but skips the FolderWatcher + auto-rebuild
/// loop. Use it as a launchd daemon when the build is driven elsewhere
/// (e.g. `naverp sync` invokes `tinypress build` after writing markdown).
///
/// Eliminates the FSEvents → debounce → rebuild cascade that the preview
/// daemon can fall into when macOS background processes (Spotlight,
/// Time Machine snapshots, xattr writes) keep poking the source tree.
struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "이미 빌드된 사이트를 로컬에서 정적으로 서빙합니다 (watcher 없음)."
    )

    @Option(name: .shortAndLong, help: "서빙할 _site 폴더. (이미 빌드되어 있어야 합니다)")
    var root: String

    @Option(name: .shortAndLong, help: "선호 로컬 포트 (사용 중이면 자동으로 다음 빈 포트).")
    var port: Int = 8080

    @Option(name: .long, help: "바인드 호스트.")
    var host: String = "127.0.0.1"

    @MainActor
    func run() async throws {
        let rootURL = URL(fileURLWithPath: root).standardized
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            Log.error("Site root not found: \(rootURL.path). Run `tinypress build` first.")
            throw ExitCode(1)
        }

        let server = PreviewServer(rootDirectory: rootURL, host: host, preferredPort: port)
        let chosenPort = try await server.start()
        let localURL = "http://\(host):\(chosenPort)/"
        Log.info("Static server listening at \(localURL)")
        Log.info("Serving \(rootURL.path) — Ctrl-C to stop.")
        print(localURL)

        await Self.waitForInterrupt()

        Log.info("Stopping…")
        await server.stop()
    }

    /// Suspend until SIGINT (Ctrl-C). Mirrors the helper in
    /// ``PreviewCommand`` — we redeclare it locally so the two
    /// commands stay independent.
    private static func waitForInterrupt() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "tinypress.serve.signal")
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
            signal(SIGINT, SIG_IGN)
            source.setEventHandler {
                source.cancel()
                cont.resume()
            }
            source.resume()
        }
    }
}
#endif
