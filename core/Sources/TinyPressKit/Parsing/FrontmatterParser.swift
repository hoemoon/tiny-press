import Foundation
import Yams

/// Splits a markdown source string into a `(Frontmatter, body)` pair.
public struct FrontmatterParser: Sendable {
    public init() {}

    /// Parses the YAML frontmatter block (delimited by `---`) at the start of
    /// `text`. If no block is present `Frontmatter.empty` is returned and the
    /// original text becomes the body.
    public func parse(_ text: String) throws -> (Frontmatter, String) {
        let normalized = normalize(text)

        guard let (yamlBlock, body) = extractBlock(from: normalized) else {
            return (.empty, normalized)
        }

        let trimmedYAML = yamlBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedYAML.isEmpty {
            return (.empty, body)
        }

        let decoder = YAMLDecoder()
        do {
            let frontmatter = try decoder.decode(Frontmatter.self, from: yamlBlock)
            return (frontmatter, body)
        } catch {
            throw FrontmatterError.invalidYAML(underlying: error)
        }
    }

    // MARK: Helpers

    /// Strip BOM and convert CRLF to LF so downstream code only sees one
    /// newline style.
    private func normalize(_ text: String) -> String {
        var stripped = text
        if stripped.hasPrefix("\u{FEFF}") {
            stripped.removeFirst()
        }
        return stripped.replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// Locate the leading `---\n...\n---` delimiter pair. The opening fence
    /// must sit on the first line; otherwise we treat the document as
    /// frontmatter-less so a stray `---` inside body content cannot be
    /// misread as the closing delimiter.
    private func extractBlock(from text: String) -> (yaml: String, body: String)? {
        let openingFence = "---\n"
        guard text.hasPrefix(openingFence) else {
            return nil
        }
        let afterOpening = text.index(text.startIndex, offsetBy: openingFence.count)
        let remainder = text[afterOpening...]

        // Special case: empty frontmatter — opening immediately followed by
        // the closing `---` line.
        if remainder.hasPrefix("---\n") {
            let bodyStart = remainder.index(remainder.startIndex, offsetBy: 4)
            return ("", String(remainder[bodyStart...]))
        }
        if remainder == "---" {
            return ("", "")
        }

        // Look for a `\n---\n` or `\n---<EOF>` closing fence on its own line.
        var searchStart = remainder.startIndex
        while let lineRange = remainder.range(of: "\n---", range: searchStart..<remainder.endIndex) {
            let after = lineRange.upperBound
            if after == remainder.endIndex || remainder[after] == "\n" {
                let yaml = String(remainder[remainder.startIndex..<lineRange.lowerBound])
                let bodyStart =
                    after == remainder.endIndex
                    ? remainder.endIndex
                    : remainder.index(after: after)
                let body = String(remainder[bodyStart..<remainder.endIndex])
                return (yaml, body)
            }
            searchStart = lineRange.upperBound
        }
        return nil
    }
}

/// Errors raised while parsing the frontmatter block.
public enum FrontmatterError: Error, Sendable {
    /// The YAML block could not be decoded — see the underlying error for
    /// details.
    case invalidYAML(underlying: Error)
}
