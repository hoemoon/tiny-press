/// `TinyPressKit` is the shared static-site-generator core used by the
/// `tinypress` CLI and by the macOS / iOS apps.
///
/// The kit has no dependency on AppKit, UIKit, or SwiftUI — it operates
/// purely on `URL`s and `String`s so it can run inside a sandboxed app or
/// from the command line.

public enum TinyPressKit {
    /// Semantic version of the kit. Bumped on every public-API change.
    public static let version = "0.0.1"
}
