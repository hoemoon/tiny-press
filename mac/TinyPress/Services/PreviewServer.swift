import Foundation
import Hummingbird
import HummingbirdCore
import Logging
import NIOCore

/// Local HTTP server that serves a built tinypress site and pushes a
/// `reload` event over Server-Sent Events whenever the build pipeline
/// completes a fresh render.
///
/// Built on Hummingbird 2.x: `FileMiddleware` fronts the static tree,
/// while `/__tinypress_reload` keeps an SSE stream open for the browser.
final class PreviewServer: @unchecked Sendable {
    private let rootDirectory: URL
    private let host: String
    private let preferredPort: Int

    private var task: Task<Void, Error>?
    private let reloadStream: AsyncStream<Void>
    private let reloadContinuation: AsyncStream<Void>.Continuation

    private(set) var port: Int?

    init(
        rootDirectory: URL,
        host: String = "127.0.0.1",
        preferredPort: Int = 8080
    ) {
        self.rootDirectory = rootDirectory
        self.host = host
        self.preferredPort = preferredPort
        var continuation: AsyncStream<Void>.Continuation!
        self.reloadStream = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(8)) {
            continuation = $0
        }
        self.reloadContinuation = continuation
    }

    /// Start the server on the first available port at-or-after
    /// `preferredPort`. Returns the port that was actually bound.
    func start() async throws -> Int {
        let chosen = try findAvailablePort(startingAt: preferredPort)
        let app = makeApplication(port: chosen)
        let task = Task<Void, Error> { try await app.runService() }
        self.task = task
        self.port = chosen
        // Give NIO a moment to bind before the caller assumes the URL is
        // reachable.
        try? await Task.sleep(nanoseconds: 50_000_000)
        return chosen
    }

    /// Stop the server. Idempotent.
    func stop() async {
        task?.cancel()
        task = nil
        port = nil
    }

    /// Notify connected browsers that the site was rebuilt.
    func notifyClientsToReload() {
        reloadContinuation.yield(())
    }

    // MARK: Routing

    private func makeApplication(port: Int) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        router.add(middleware: LiveReloadInjectionMiddleware<BasicRequestContext>())
        router.add(
            middleware: FileMiddleware<BasicRequestContext, LocalFileSystem>(
                rootDirectory.path,
                searchForIndexHtml: true
            )
        )
        let stream = reloadStream
        router.get("/__tinypress_reload") { _, _ -> Response in
            let body = ResponseBody { writer in
                try await writer.write(ByteBuffer(string: ": connected\n\n"))
                for await _ in stream {
                    try await writer.write(ByteBuffer(string: "data: reload\n\n"))
                }
                try await writer.finish(nil)
            }
            return Response(
                status: .ok,
                headers: [
                    .contentType: "text/event-stream",
                    .cacheControl: "no-cache",
                    .connection: "keep-alive",
                ],
                body: body
            )
        }

        var logger = Logger(label: "tinypress.preview")
        logger.logLevel = .warning

        return Application(
            router: router,
            configuration: .init(address: .hostname(host, port: port)),
            logger: logger
        )
    }

    // MARK: Port selection

    private func findAvailablePort(startingAt start: Int) throws -> Int {
        for candidate in start..<(start + 50) {
            if isPortAvailable(candidate) { return candidate }
        }
        throw PreviewServerError.noFreePort(searchedFrom: start)
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound == 0
    }
}

/// Errors surfaced by `PreviewServer`.
enum PreviewServerError: Error {
    /// No free port found within the search window.
    case noFreePort(searchedFrom: Int)
}

/// External storage for `CollectingWriter`. `ResponseBody.write(_:)`
/// consumes the writer, so we keep the buffer in a class instance the
/// caller still has a reference to.
private final class BufferBox {
    var buffer = ByteBuffer()
}

/// Buffers a `ResponseBody` into a single `ByteBuffer`. Used by
/// `LiveReloadInjectionMiddleware` to rewrite served HTML — fine for
/// small local files; not appropriate for streaming responses.
private struct CollectingWriter: ResponseBodyWriter {
    let box: BufferBox
    mutating func write(_ buf: ByteBuffer) async throws {
        var b = buf
        box.buffer.writeBuffer(&b)
    }
    mutating func write(contentsOf buffers: some Sequence<ByteBuffer>) async throws {
        for b in buffers {
            var c = b
            box.buffer.writeBuffer(&c)
        }
    }
    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
}

/// Injects a tiny `<script>` snippet into served HTML so the browser
/// reconnects to `/__tinypress_reload` and reloads on every push.
///
/// We do this in middleware rather than burning the script into rendered
/// pages so the kit stays oblivious to live-reload concerns.
private struct LiveReloadInjectionMiddleware<Context: RequestContext>: RouterMiddleware {
    static var snippet: String {
        """
        <script>
        (function(){
          if (window.__tinypressLiveReload) return;
          window.__tinypressLiveReload = true;
          var s = new EventSource('/__tinypress_reload');
          s.onmessage = function(){ location.reload(); };
        })();
        </script>
        """
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        var response = try await next(request, context)
        guard
            let contentType = response.headers[.contentType],
            contentType.hasPrefix("text/html")
        else { return response }

        let box = BufferBox()
        let collector = CollectingWriter(box: box)
        let body = response.body
        try await body.write(collector)
        guard let html = box.buffer.readString(length: box.buffer.readableBytes) else {
            return response
        }
        let injected = inject(into: html)
        var newBody = ByteBuffer()
        newBody.writeString(injected)
        response.body = ResponseBody(byteBuffer: newBody)
        return response
    }

    private func inject(into html: String) -> String {
        let snippet = Self.snippet
        if let range = html.range(of: "</body>", options: .caseInsensitive) {
            return html.replacingCharacters(in: range, with: "\(snippet)</body>")
        }
        return html + snippet
    }
}
