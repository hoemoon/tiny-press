import Foundation
import Markdown

/// `MarkupWalker` that emits HTML into an internal buffer.
///
/// `swift-markdown` does not ship an HTML emitter, so we walk the AST and
/// translate each node by hand. The output mirrors common CommonMark
/// expectations: paragraphs in `<p>`, code blocks in `<pre><code>`, etc.
struct HTMLEmittingWalker: MarkupWalker {
    private(set) var html: String = ""

    mutating func defaultVisit(_ markup: any Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    // MARK: Block-level

    mutating func visitDocument(_ document: Document) -> Void {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> Void {
        html += "<p>"
        for child in paragraph.children { visit(child) }
        html += "</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> Void {
        let level = max(1, min(heading.level, 6))
        html += "<h\(level)>"
        for child in heading.children { visit(child) }
        html += "</h\(level)>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> Void {
        html += "<blockquote>\n"
        for child in blockQuote.children { visit(child) }
        html += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Void {
        if let lang = codeBlock.language, !lang.isEmpty {
            html += "<pre><code class=\"language-\(escape(lang))\">"
        } else {
            html += "<pre><code>"
        }
        html += escape(codeBlock.code)
        html += "</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) -> Void {
        html += htmlBlock.rawHTML
        if !htmlBlock.rawHTML.hasSuffix("\n") {
            html += "\n"
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> Void {
        html += "<hr />\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> Void {
        if orderedList.startIndex == 1 {
            html += "<ol>\n"
        } else {
            html += "<ol start=\"\(orderedList.startIndex)\">\n"
        }
        for child in orderedList.children { visit(child) }
        html += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> Void {
        html += "<ul>\n"
        for child in unorderedList.children { visit(child) }
        html += "</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> Void {
        html += "<li>"
        // Tight-list rendering: when every child is a Paragraph we emit the
        // inline content directly, matching what most CommonMark renderers
        // produce for `- foo\n- bar` style lists.
        let children = Array(listItem.children)
        let allParagraphs = !children.isEmpty && children.allSatisfy { $0 is Paragraph }
        if allParagraphs {
            for (offset, child) in children.enumerated() {
                if let paragraph = child as? Paragraph {
                    if offset > 0 { html += "\n" }
                    for grandchild in paragraph.children { visit(grandchild) }
                }
            }
        } else {
            for child in children { visit(child) }
        }
        html += "</li>\n"
    }

    mutating func visitTable(_ table: Markdown.Table) -> Void {
        html += "<table>\n"
        for child in table.children { visit(child) }
        html += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Markdown.Table.Head) -> Void {
        html += "<thead><tr>"
        for cell in tableHead.cells {
            html += "<th>"
            for child in cell.children { visit(child) }
            html += "</th>"
        }
        html += "</tr></thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Markdown.Table.Body) -> Void {
        html += "<tbody>\n"
        for child in tableBody.children { visit(child) }
        html += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Markdown.Table.Row) -> Void {
        html += "<tr>"
        for cell in tableRow.cells {
            html += "<td>"
            for child in cell.children { visit(child) }
            html += "</td>"
        }
        html += "</tr>\n"
    }

    // MARK: Inline

    mutating func visitText(_ text: Text) -> Void {
        html += escape(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> Void {
        html += "<em>"
        for child in emphasis.children { visit(child) }
        html += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> Void {
        html += "<strong>"
        for child in strong.children { visit(child) }
        html += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> Void {
        html += "<del>"
        for child in strikethrough.children { visit(child) }
        html += "</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Void {
        html += "<code>"
        html += escape(inlineCode.code)
        html += "</code>"
    }

    mutating func visitLink(_ link: Link) -> Void {
        let dest = link.destination ?? ""
        html += "<a href=\"\(escapeAttribute(dest))\">"
        for child in link.children { visit(child) }
        html += "</a>"
    }

    mutating func visitImage(_ image: Image) -> Void {
        let src = image.source ?? ""
        let alt = image.plainText
        if let title = image.title, !title.isEmpty {
            html +=
                "<img src=\"\(escapeAttribute(src))\" alt=\"\(escape(alt))\" title=\"\(escape(title))\" />"
        } else {
            html += "<img src=\"\(escapeAttribute(src))\" alt=\"\(escape(alt))\" />"
        }
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> Void {
        html += inlineHTML.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> Void {
        html += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> Void {
        html += "\n"
    }

    // MARK: Escaping

    private func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for char in value {
            switch char {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            case "'": result.append("&#39;")
            default: result.append(char)
            }
        }
        return result
    }

    private func escapeAttribute(_ value: String) -> String {
        escape(value)
    }
}
