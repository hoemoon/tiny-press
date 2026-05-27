import Foundation

/// Runs the `pagefind` binary against an already-rendered site so the
/// build output gains a `pagefind/` directory with a chunked search
/// index plus the prebuilt UI assets.
///
/// Pagefind is an external Rust tool. We resolve it from PATH, common
/// install prefixes, and finally `npx pagefind` as a last-resort
/// fallback. A missing binary is surfaced as a warning — never a fatal
/// build error — so sites that opt into search but lack the tooling
/// still render.
public struct PagefindRunner: Sendable {
    public init() {}

    /// Outcome of a single `run(...)` invocation.
    public enum Outcome: Sendable, Equatable {
        /// Pagefind ran to completion; the index now lives under
        /// `<outputRoot>/pagefind/`.
        case indexed
        /// No binary was found. Search UI in the theme should degrade
        /// gracefully (e.g. hide itself).
        case binaryMissing
        /// Binary found but exited non-zero. `stderr` is captured for
        /// the BuildReport warning surface.
        case failed(status: Int32, stderr: String)
    }

    /// Build the search index for the site at `outputRoot`. `site` lets
    /// the runner forward the configured language to Pagefind, which
    /// drives the CJK segmentation heuristic.
    public func run(outputRoot: URL, language: String) async -> Outcome {
        let invocation = resolveInvocation()
        guard let invocation else { return .binaryMissing }
        var arguments = invocation.arguments
        arguments.append(contentsOf: [
            "--site", outputRoot.path,
            "--root-selector", "main",
        ])
        return await execute(executable: invocation.executable, arguments: arguments)
    }

    // MARK: Binary resolution

    struct Invocation: Equatable {
        var executable: String
        var arguments: [String]
    }

    func resolveInvocation() -> Invocation? {
        // 1. Honor an explicit override so power users can pin a build.
        //    Use `getenv` directly so `setenv` inside the same process
        //    (notably in tests) is picked up — Foundation's
        //    `ProcessInfo.processInfo.environment` snapshots on first access
        //    on some platforms.
        if let raw = getenv("TINYPRESS_PAGEFIND"),
           let override = String(validatingCString: raw),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override)
        {
            return Invocation(executable: override, arguments: [])
        }

        // 2. Look on PATH and common install prefixes.
        let directCandidates = pagefindCandidates()
        if let direct = directCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            return Invocation(executable: direct, arguments: [])
        }

        // 3. Fall back to `npx pagefind`, the Pagefind project's first-line
        //    install path. npx is available in any Node toolchain.
        let npxCandidates = [
            "/opt/homebrew/bin/npx",
            "/usr/local/bin/npx",
            "/usr/bin/npx",
        ]
        if let npx = npxCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            return Invocation(executable: npx, arguments: ["--yes", "pagefind"])
        }

        return nil
    }

    private func pagefindCandidates() -> [String] {
        var seen: Set<String> = []
        var paths: [String] = []
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for entry in envPath.split(separator: ":") {
            let candidate = "\(entry)/pagefind"
            if seen.insert(candidate).inserted { paths.append(candidate) }
        }
        let extras = [
            "/opt/homebrew/bin/pagefind",
            "/usr/local/bin/pagefind",
            "/usr/bin/pagefind",
            (NSHomeDirectory() as NSString).appendingPathComponent(".cargo/bin/pagefind"),
        ]
        for extra in extras where seen.insert(extra).inserted {
            paths.append(extra)
        }
        return paths
    }

    // MARK: Process plumbing

    private func execute(
        executable: String,
        arguments: [String]
    ) async -> Outcome {
        await withCheckedContinuation { (cont: CheckedContinuation<Outcome, Never>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            // launchd hands children a minimal PATH (just /usr/bin:/bin),
            // which is fatal for npm-installed pagefind because its
            // shebang resolves `node` via PATH. Augment with the common
            // Homebrew + Node prefixes so the subprocess can locate its
            // own interpreter.
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? ""
            let extraPrefixes = [
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
            ]
            let pathEntries = (existingPath.split(separator: ":").map(String.init)
                + extraPrefixes)
                .reduce(into: [String]()) { acc, entry in
                    if !acc.contains(entry) { acc.append(entry) }
                }
            env["PATH"] = pathEntries.joined(separator: ":")
            task.environment = env
            let outPipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = errPipe
            task.terminationHandler = { proc in
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    cont.resume(returning: .indexed)
                } else {
                    cont.resume(returning: .failed(
                        status: proc.terminationStatus,
                        stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }
            do {
                try task.run()
            } catch {
                cont.resume(returning: .failed(
                    status: -1,
                    stderr: "Could not launch \(executable): \(error)"
                ))
            }
        }
    }
}
