import XCTest
@testable import Peridot

/// The same cases as the Android app's MarkdownTest, so both parsers stay in step.
final class MarkdownTests: XCTestCase {
    func testBlocks() {
        let md = """
        # Title
        Some text
        on two lines

        - one
        - two
          continued
        1. first

        > quoted
        ---
        ```swift
        let x = 1
        ```
        """
        XCTAssertEqual(Markdown.blocks(md), [
            .heading(level: 1, text: "Title"),
            .paragraph("Some text\non two lines"),
            .listItem(marker: "•", text: "one", depth: 0),
            .listItem(marker: "•", text: "two continued", depth: 0),
            .listItem(marker: "1.", text: "first", depth: 0),
            .quote("quoted"),
            .rule,
            .code(language: "swift", code: "let x = 1"),
        ])
    }

    func testUnclosedFenceRunsToTheEnd() {
        XCTAssertEqual(Markdown.blocks("Look:\n```\na\nb"), [.paragraph("Look:"), .code(language: "", code: "a\nb")])
    }

    func testTable() {
        let md = "| A | B |\n|---|:-:|\n| 1 | 2 \\| 3 |\n| x |"
        XCTAssertEqual(Markdown.blocks(md), [.table(header: ["A", "B"], rows: [["1", "2 | 3"], ["x"]])])
    }

    func testNestedListDepth() {
        XCTAssertEqual(Markdown.blocks("- a\n  - b"), [
            .listItem(marker: "•", text: "a", depth: 0),
            .listItem(marker: "•", text: "b", depth: 1),
        ])
    }

    func testInlineStyles() {
        XCTAssertEqual(Markdown.spans("a **bold** *it* `code` ~~gone~~"), [
            MDSpan(text: "a "),
            MDSpan(text: "bold", bold: true),
            MDSpan(text: " "),
            MDSpan(text: "it", italic: true),
            MDSpan(text: " "),
            MDSpan(text: "code", code: true),
            MDSpan(text: " "),
            MDSpan(text: "gone", strike: true),
        ])
    }

    func testItalicInsideBold() {
        XCTAssertEqual(Markdown.spans("**x *y***"), [
            MDSpan(text: "x ", bold: true),
            MDSpan(text: "y", bold: true, italic: true),
        ])
    }

    func testUnclosedDelimitersStayText() {
        XCTAssertEqual(Markdown.spans("2 * 3 and **open"), [MDSpan(text: "2 * 3 and **open")])
    }

    func testSnakeCaseIsNotItalic() {
        XCTAssertEqual(Markdown.spans("my_var_name"), [MDSpan(text: "my_var_name")])
    }

    func testLinks() {
        XCTAssertEqual(Markdown.spans("see [docs](https://tryperidot.io/docs) or https://x.dev/a."), [
            MDSpan(text: "see "),
            MDSpan(text: "docs", url: "https://tryperidot.io/docs"),
            MDSpan(text: " or "),
            MDSpan(text: "https://x.dev/a", url: "https://x.dev/a"),
            MDSpan(text: "."),
        ])
    }

    func testEscapes() {
        XCTAssertEqual(Markdown.spans("\\*not italic\\*"), [MDSpan(text: "*not italic*")])
    }
}
