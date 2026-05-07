#if os(macOS)
import ArgumentParser
import Dispatch
import Foundation
import TinyPressKit

struct PreviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview",
        abstract: "사이트를 빌드하고 변경을 감지하면서 로컬에서 라이브 리로드와 함께 서빙합니다."
    )

    @Option(name: .shortAndLong, help: "소스 폴더. 기본값은 현재 디렉터리.")
    var source: String = "."

    @Option(name: .shortAndLong, help: "출력 폴더. 기본값은 <source>/_site.")
    var output: String?

    @Option(name: .shortAndLong, help: "선호 로컬 포트 (사용 중이면 자동으로 다음 빈 포트).")
    var port: Int = 8080

    @Option(name: .long, help: "바인드 호스트.")
    var host: String = "127.0.0.1"

    @Flag(name: .long, help: "draft: true로 표시된 포스트도 포함.")
    var includeDrafts: Bool = false

    @Flag(name: .long, help: "`tailscale serve`로 tailnet에 프리뷰를 미러링.")
    var share: Bool = false

    @MainActor
    func run() async throws {
        let sourceURL = URL(fileURLWithPath: source).standardized
        let outputURL =
            output.map { URL(fileURLWithPath: $0).standardized }
            ?? sourceURL.appendingPathComponent("_site", isDirectory: true)

        Log.info("Building \(sourceURL.path) → \(outputURL.path)")
        let builder = SiteBuilder()
        do {
            _ = try await builder.build(
                sourceRoot: sourceURL,
                outputRoot: outputURL,
                includeDrafts: includeDrafts
            )
        } catch {
            Log.error("\(error)")
            throw ExitCode(1)
        }

        let server = PreviewServer(rootDirectory: outputURL, host: host, preferredPort: port)
        let chosenPort = try await server.start()
        let localURL = "http://\(host):\(chosenPort)/"
        Log.info("Preview server listening at \(localURL)")

        var tailscale: TailscaleServeAdapter?
        if share {
            let adapter = TailscaleServeAdapter()
            await adapter.detect()
            await adapter.enable(localPort: chosenPort)
            switch adapter.state {
            case .serving(let url):
                Log.info("Tailscale share: \(url.absoluteString)")
            case .unavailable(let reason), .failed(let reason):
                Log.error("Tailscale share unavailable: \(reason)")
            default:
                Log.error("Tailscale share unavailable: \(adapter.state)")
            }
            tailscale = adapter
        }

        let session = PreviewSession(
            builder: builder,
            sourceURL: sourceURL,
            outputURL: outputURL,
            includeDrafts: includeDrafts,
            server: server
        )

        let watcher = FolderWatcher(url: sourceURL, debounceInterval: 0.3)
        try watcher.start { [session] in
            Task { await session.rebuild() }
        }

        Log.info("Watching for changes — Ctrl-C to stop.")
        print(localURL)

        await Self.waitForInterrupt()

        Log.info("Stopping…")
        watcher.stop()
        await server.stop()
        if let tailscale {
            await tailscale.disable()
        }
    }

    /// Suspend until SIGINT (Ctrl-C). Returns once the user hits it,
    /// letting `run()` proceed to graceful teardown instead of `exit()`.
    private static func waitForInterrupt() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "tinypress.preview.signal")
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
            // libc must ignore SIGINT before the DispatchSource arms it,
            // otherwise the default handler kills us before we run.
            signal(SIGINT, SIG_IGN)
            source.setEventHandler {
                source.cancel()
                cont.resume()
            }
            source.resume()
        }
    }
}

/// Coalesces watcher fires into a single in-flight rebuild. Mirrors the
/// pattern used by `BuildCoordinator` in the macOS app — kept private to
/// the CLI because the kit doesn't currently expose a coordinator type.
@MainActor
private final class PreviewSession {
    let builder: SiteBuilder
    let sourceURL: URL
    let outputURL: URL
    let includeDrafts: Bool
    let server: PreviewServer

    private var rebuildInFlight = false
    private var rebuildPending = false

    init(
        builder: SiteBuilder,
        sourceURL: URL,
        outputURL: URL,
        includeDrafts: Bool,
        server: PreviewServer
    ) {
        self.builder = builder
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.includeDrafts = includeDrafts
        self.server = server
    }

    func rebuild() async {
        if rebuildInFlight {
            rebuildPending = true
            return
        }
        rebuildInFlight = true
        do {
            _ = try await builder.build(
                sourceRoot: sourceURL,
                outputRoot: outputURL,
                includeDrafts: includeDrafts
            )
            server.notifyClientsToReload()
            Log.info("Rebuilt.")
        } catch {
            Log.error("\(error)")
        }
        rebuildInFlight = false
        if rebuildPending {
            rebuildPending = false
            await rebuild()
        }
    }
}
#endif
