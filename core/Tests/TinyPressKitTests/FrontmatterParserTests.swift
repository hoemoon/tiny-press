import Foundation
import Testing
@testable import TinyPressKit

@Suite("FrontmatterParser")
struct FrontmatterParserTests {
    private let parser = FrontmatterParser()

    @Test func parsesStandardFrontmatter() throws {
        let input = """
            ---
            title: Hello World
            tags: [intro, meta]
            draft: false
            ---

            Body line 1
            Body line 2
            """
        let (fm, body) = try parser.parse(input)
        #expect(fm.title == "Hello World")
        #expect(fm.tags == ["intro", "meta"])
        #expect(fm.draft == false)
        #expect(body.hasPrefix("\nBody line 1"))
    }

    @Test func returnsEmptyForFileWithoutFrontmatter() throws {
        let input = "# Just a heading\n\nNo metadata here."
        let (fm, body) = try parser.parse(input)
        #expect(fm == .empty)
        #expect(body == input)
    }

    @Test func parsesEmptyFrontmatterBlock() throws {
        let input = "---\n---\nbody"
        let (fm, body) = try parser.parse(input)
        #expect(fm == .empty)
        #expect(body == "body")
    }

    @Test func throwsOnInvalidYAML() {
        let input = """
            ---
            title: [oops
            ---
            body
            """
        #expect(throws: FrontmatterError.self) {
            _ = try parser.parse(input)
        }
    }

    @Test func handlesUTF8BOM() throws {
        let input = "\u{FEFF}---\ntitle: BOM Title\n---\nbody"
        let (fm, body) = try parser.parse(input)
        #expect(fm.title == "BOM Title")
        #expect(body == "body")
    }

    @Test func handlesWindowsLineEndings() throws {
        let input = "---\r\ntitle: CRLF\r\n---\r\nbody line"
        let (fm, body) = try parser.parse(input)
        #expect(fm.title == "CRLF")
        #expect(body == "body line")
    }

    @Test func bodyContainingTripleDashIsNotTreatedAsDelimiter() throws {
        let input = """
            ---
            title: Mixed
            ---

            Some body text

            ---

            More body
            """
        let (fm, body) = try parser.parse(input)
        #expect(fm.title == "Mixed")
        #expect(body.contains("More body"))
        #expect(body.contains("---"))
    }
}
