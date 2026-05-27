#if os(macOS)
import Foundation
import Observation

/// Drives `tailscale serve` so a registered site's local preview becomes
/// reachable at `https://<host>.<tailnet>.ts.net/` from any device on the
/// user's tailnet.
///
/// All shell-outs go through `Process` directly. Unsandboxed callers (the
/// `tinypress` CLI is one) can spawn `tailscale` freely; a hypothetical
/// sandboxed embedding would land on `.unavailable` because the binary
/// lookup paths are unreadable.
///
/// macOS-only: `Process` and the `tailscale` CLI are macOS concepts.
@MainActor
@Observable
public final class TailscaleServeAdapter {
    /// Lifecycle state surfaced to the UI.
    public enum State: Sendable, Equatable {
        /// Initial state before `detect()` runs.
        case unknown
        /// `tailscale` not installed, daemon down, etc. UI shows the reason.
        case unavailable(String)
        /// CLI located, hostname read, no serve config registered.
        case idle
        /// `enable` is in flight.
        case starting
        /// Successfully serving the local port at `url`.
        case serving(URL)
        /// Last operation failed with the given message.
        case failed(String)
    }

    public private(set) var state: State = .unknown

    /// MagicDNS hostname for this node, e.g. `host.tailnet.ts.net`.
    public private(set) var hostname: String?

    /// Local port currently registered with `tailscale serve`, if any.
    public private(set) var registeredPort: Int?

    private var binaryPath: String?

    public init() {}

    /// Probe for the CLI and read the current node's hostname.
    /// Idempotent — safe to call repeatedly (e.g. on app foreground).
    public func detect() async {
        guard let path = locateBinary() else {
            state = .unavailable("tailscale CLI not found in /opt/homebrew/bin, /usr/local/bin, or /Applications")
            return
        }
        binaryPath = path
        do {
            let json = try await runShell(path, arguments: ["status", "--json"])
            guard let host = parseHostname(jsonText: json) else {
                state = .unavailable("tailscale daemon returned no hostname (logged out?)")
                return
            }
            hostname = host
            // If we previously registered a port and `tailscale serve status`
            // still has it, restore .serving. Otherwise idle.
            if let port = registeredPort,
               let url = URL(string: "https://\(host)/")
            {
                state = .serving(url)
                _ = port  // (no-op, kept for future refresh logic)
            } else {
                state = .idle
            }
        } catch {
            state = .unavailable("tailscale not running: \(humanize(error))")
        }
    }

    /// Register the given local port with `tailscale serve --bg`.
    /// Replaces any prior registration.
    public func enable(localPort: Int) async {
        guard let path = binaryPath, let host = hostname else {
            await detect()
            // detect() already moved to .unavailable on failure.
            guard binaryPath != nil, hostname != nil else { return }
            await enable(localPort: localPort)
            return
        }
        if registeredPort == localPort, case .serving = state { return }
        state = .starting
        do {
            // Reset first so we don't pile path mappings or conflict on the
            // root path.
            _ = try? await runShell(path, arguments: ["serve", "reset"])
            _ = try await runShell(
                path,
                arguments: ["serve", "--bg", "http://127.0.0.1:\(localPort)"]
            )
            registeredPort = localPort
            guard let url = URL(string: "https://\(host)/") else {
                state = .failed("Could not form URL from hostname \(host)")
                return
            }
            state = .serving(url)
        } catch {
            state = .failed(humanize(error))
        }
    }

    /// Clear any active `tailscale serve` registration. Idempotent.
    public func disable() async {
        guard let path = binaryPath else {
            registeredPort = nil
            return
        }
        _ = try? await runShell(path, arguments: ["serve", "reset"])
        registeredPort = nil
        if hostname != nil {
            state = .idle
        }
    }

    // MARK: Process plumbing

    private func locateBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated func runShell(
        _ executable: String,
        arguments: [String]
    ) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            let outPipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = errPipe
            task.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    cont.resume(returning: stdout)
                } else {
                    let combined = stderr.isEmpty ? stdout : stderr
                    cont.resume(
                        throwing: ShellError.nonZeroExit(
                            status: proc.terminationStatus,
                            output: combined.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                }
            }
            do {
                try task.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    private nonisolated func parseHostname(jsonText: String) -> String? {
        guard let data = jsonText.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let selfDict = root["Self"] as? [String: Any] else { return nil }
        guard let dnsName = selfDict["DNSName"] as? String, !dnsName.isEmpty else { return nil }
        // `DNSName` is FQDN with trailing dot.
        return dnsName.hasSuffix(".") ? String(dnsName.dropLast()) : dnsName
    }

    private nonisolated func humanize(_ error: Error) -> String {
        if let shell = error as? ShellError {
            switch shell {
            case .nonZeroExit(let status, let output):
                return output.isEmpty ? "exit \(status)" : output
            }
        }
        return "\(error)"
    }

    /// Errors thrown by `runShell`.
    public enum ShellError: Error, Equatable, Sendable {
        case nonZeroExit(status: Int32, output: String)
    }
}
#endif
