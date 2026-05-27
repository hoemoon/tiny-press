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

    @Test func fallsBackToPublishedAtWhenDateMissing() throws {
        let input = """
            ---
            title: Naverp Article
            published_at: "2026-03-03"
            fetched_at: 2026-05-27T06:00:17Z
            channel: growthpapa/wave
            ---
            body
            """
        let (fm, _) = try parser.parse(input)
        #expect(fm.date != nil)
        let components = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: fm.date!)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 3)
        #expect(fm.extra["channel"] == .string("growthpapa/wave"))
        #expect(fm.extra["published_at"] == .string("2026-03-03"))
    }

    @Test func explicitDateBeatsPublishedAt() throws {
        let input = """
            ---
            date: 2026-01-01
            published_at: "2026-12-31"
            ---
            body
            """
        let (fm, _) = try parser.parse(input)
        let components = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: fm.date!)
        #expect(components.year == 2026)
        #expect(components.month == 1)
        #expect(components.day == 1)
    }

    @Test func capturesUnknownTopLevelKeysIntoExtra() throws {
        let input = """
            ---
            title: T
            naver_id: 260303233251216jo
            image_count: 3
            ---
            body
            """
        let (fm, _) = try parser.parse(input)
        #expect(fm.extra["naver_id"] == .string("260303233251216jo"))
        #expect(fm.extra["image_count"] == .int(3))
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
