import Foundation
import WebKit
import XCTest
@testable import MarkdownHelpers

/// Plain-text render mode: the article, the page it sits in, and how WebKit
/// lays it out.
final class PlainTextRenderTests: XCTestCase {
    // MARK: - Article HTML

    func testArticleEscapesMarkupAndQuotes() {
        let html = MarkdownHTML.plainTextArticleHTML(
            "<script>alert(\"x\")</script> & <b>not bold</b>",
            font: .monospaced
        )
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<b>"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &lt;b&gt;"))
    }

    func testArticlePreservesLeadingSpacesTabsAndBlankLines() {
        let text = "  indented\n\tTabbed\n\n\nafter blanks\n    +--+\n    |  |"
        let html = MarkdownHTML.plainTextArticleHTML(text, font: .document)
        XCTAssertTrue(html.contains(">\(text)</div>"), html)
    }

    func testMarkdownSyntaxStaysLiteral() {
        let html = MarkdownHTML.plainTextArticleHTML("# Not a heading\n* not a list", font: .monospaced)
        XCTAssertFalse(html.contains("<h1"))
        XCTAssertFalse(html.contains("<li"))
        XCTAssertTrue(html.contains("# Not a heading\n* not a list"))
    }

    func testBlockSpansEverySourceLineWithoutOptingIntoSourceCopy() {
        let html = MarkdownHTML.plainTextArticleHTML("one\ntwo\nthree", font: .monospaced)
        XCTAssertTrue(html.contains("data-source-start=\"1\" data-source-end=\"3\""))
        XCTAssertFalse(html.contains("data-source-line"))
        XCTAssertTrue(MarkdownHTML.plainTextArticleHTML("", font: .monospaced)
            .contains("data-source-end=\"1\""))
    }

    func testFontChoiceSelectsClass() {
        XCTAssertTrue(MarkdownHTML.plainTextArticleHTML("x", font: .monospaced)
            .contains("class=\"\(MarkdownHTML.plainTextClass) \(MarkdownHTML.plainTextMonospacedClass)\""))
        XCTAssertTrue(MarkdownHTML.plainTextArticleHTML("x", font: .document)
            .contains("class=\"\(MarkdownHTML.plainTextClass)\""))
    }

    // MARK: - Page

    func testPlainTextPageLoadsNoVendorRenderers() {
        let text = """
        ```mermaid
        graph TD; A-->B
        ```
        $$x^2$$
        ```swift
        let x = 1
        ```
        """
        let rendered = MarkdownHTML.renderPlainText(text, vendorLoading: .inline)
        XCTAssertFalse(rendered.containsMath)
        XCTAssertFalse(rendered.containsMermaid)
        XCTAssertFalse(rendered.containsCode)
        // The same text as Markdown pulls in every vendor renderer…
        let markdown = MarkdownHTML.render(markdown: text, vendorLoading: .inline)
        let emissions = [
            MarkdownHTML.katexHead(mode: .inline),
            MarkdownHTML.mermaidScript(mode: .inline),
        ].flatMap { [$0.head, $0.body] }.filter { !$0.isEmpty }
        XCTAssertFalse(emissions.isEmpty)
        for emission in emissions {
            XCTAssertTrue(markdown.html.contains(emission))
            // …plain text loads none of them.
            XCTAssertFalse(rendered.html.contains(emission))
        }
        // Code is highlighted at render time in Markdown mode; plain text
        // never asks for the in-page highlighter either.
        for emission in [MarkdownHTML.highlightHead(mode: .inline)].flatMap({ [$0.head, $0.body] })
            where !emission.isEmpty {
            XCTAssertFalse(rendered.html.contains(emission))
        }
        XCTAssertFalse(rendered.articleHTML.contains("<pre"))
        XCTAssertEqual(rendered.markdown, text, "copy-as-source keeps the raw text")
    }

    func testPlainTextPageSharesThemeStylesheetAndShell() {
        let rendered = MarkdownHTML.renderPlainText("hello", allowsScroll: true)
        XCTAssertTrue(rendered.html.contains(MarkdownHTML.themeStyleElementID))
        XCTAssertTrue(rendered.html.contains(MarkdownHTML.readerLayoutStyleElementID))
        XCTAssertTrue(rendered.html.contains("white-space: pre-wrap"))
        XCTAssertTrue(rendered.html.contains("<article class=\"markdown-body\""))
    }

    func testFrontmatterIsNotExtractedInPlainMode() {
        let text = "---\ntitle: x\n---\nbody"
        let rendered = MarkdownHTML.renderPlainText(text)
        XCTAssertFalse(rendered.articleHTML.contains("<table"))
        XCTAssertTrue(rendered.articleHTML.contains("---\ntitle: x\n---\nbody"))
    }

    func testMarkdownModeIsTheDefault() {
        let rendered = MarkdownHTML.render(markdown: "# Title")
        XCTAssertTrue(rendered.articleHTML.contains("<h1"))
        XCTAssertFalse(rendered.articleHTML.contains(MarkdownHTML.plainTextClass))
    }

    // MARK: - WebKit layout

    @MainActor
    func testLongLineWrapsWithoutHorizontalScroll() async throws {
        let longLine = String(repeating: "abcdefghij", count: 50)   // 500 columns, no spaces
        let text = "\(longLine)\n  indented line\n\n\tafter a blank"
        let html = MarkdownHTML.renderPlainText(text, allowsScroll: true).html
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        webView.loadHTMLString(html, baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        while webView.isLoading && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(webView.isLoading)
        // The article is populated from its template after load.
        var metrics: [String: Any] = [:]
        while Date() < deadline {
            metrics = try await webView.evaluateJavaScript("""
                (() => {
                    const block = document.querySelector('article .\(MarkdownHTML.plainTextClass)');
                    if (!block) return {};
                    const root = document.scrollingElement;
                    return {
                        text: block.innerText,
                        blockOverflow: block.scrollWidth - block.clientWidth,
                        pageOverflow: root.scrollWidth - root.clientWidth,
                        height: block.getBoundingClientRect().height,
                        lineHeight: parseFloat(getComputedStyle(block).lineHeight),
                        whiteSpace: getComputedStyle(block).whiteSpace,
                    };
                })()
                """) as? [String: Any] ?? [:]
            if metrics["text"] != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(metrics["text"] as? String, text, "whitespace survives rendering")
        XCTAssertEqual(metrics["whiteSpace"] as? String, "pre-wrap")
        XCTAssertLessThanOrEqual(try XCTUnwrap(metrics["blockOverflow"] as? Double), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(metrics["pageOverflow"] as? Double), 0)
        // The 500-column line wrapped onto several lines.
        let height = try XCTUnwrap(metrics["height"] as? Double)
        let lineHeight = try XCTUnwrap(metrics["lineHeight"] as? Double)
        XCTAssertGreaterThan(height, lineHeight * 6)
    }
}

final class PlainTextHeuristicTests: XCTestCase {
    private func mode(_ text: String) -> MarkdownHTML.RenderMode {
        PlainTextHeuristic.suggestedMode(for: text)
    }

    func testProseIsPlainText() {
        XCTAssertEqual(mode("""
        Meeting notes, Tuesday.

        We agreed to ship on Friday. Bob will
        check the numbers again before then.
        """), .plainText)
    }

    func testLiteralBulletsQuotesAndIndentedArtStayPlain() {
        XCTAssertEqual(mode("""
        TODO
        * buy milk
        - call Alice
        > quoted reply
            +-----+
            | box |
            +-----+
        Title
        =====
        """), .plainText)
    }

    func testEmptyAndWhitespaceArePlain() {
        XCTAssertEqual(mode(""), .plainText)
        XCTAssertEqual(mode("  \n\t\n"), .plainText)
    }

    func testShebangAndHashCommentsAreNotHeadings() {
        XCTAssertEqual(mode("#!/bin/sh\necho hi\n#comment"), .plainText)
    }

    func testATXHeadingIsMarkdown() {
        XCTAssertEqual(mode("intro\n\n## Section\ntext"), .markdown)
    }

    func testFencedBlocksAreMarkdown() {
        XCTAssertEqual(mode("see:\n\n```\ncode\n```"), .markdown)
        XCTAssertEqual(mode("see:\n\n~~~python\ncode\n~~~"), .markdown)
    }

    func testInlineLinkAndImageAreMarkdown() {
        XCTAssertEqual(mode("See [the docs](https://example.com) for more."), .markdown)
        XCTAssertEqual(mode("![diagram](arch.png)"), .markdown)
    }

    func testBareAndAngleURLsStayPlain() {
        XCTAssertEqual(mode("See https://example.com and <https://example.org>."), .plainText)
    }

    func testTableIsMarkdown() {
        XCTAssertEqual(mode("| a | b |\n|---|---|\n| 1 | 2 |"), .markdown)
    }

    func testFrontmatterIsMarkdown() {
        XCTAssertEqual(mode("---\ntitle: Notes\n---\nplain body"), .markdown)
    }

    func testOnlyTheHeadOfLargeFilesIsInspected() {
        let filler = String(repeating: "log line without markup\n",
                            count: PlainTextHeuristic.inspectedCharacterLimit / 20)
        XCTAssertEqual(mode(filler + "# Heading past the limit\n"), .plainText)
        XCTAssertEqual(mode("# Heading up front\n" + filler), .markdown)
    }

    /// samples/*.txt describe which mode they render in; keep that true.
    func testSampleFilesRenderInTheModeTheyDescribe() throws {
        let samples = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("samples")
        let markdown = try String(contentsOf: samples.appendingPathComponent("plain-text.txt"), encoding: .utf8)
        let prose = try String(contentsOf: samples.appendingPathComponent("plain-prose.txt"), encoding: .utf8)
        XCTAssertEqual(mode(markdown), .markdown)
        XCTAssertEqual(mode(prose), .plainText)
    }

    func testSampleEndsOnALineBoundary() {
        let text = String(repeating: "a", count: 10) + "\n"
            + String(repeating: "b", count: PlainTextHeuristic.inspectedCharacterLimit)
        XCTAssertEqual(PlainTextHeuristic.inspectedSample(of: text), String(repeating: "a", count: 10))
    }
}

final class RenderModeMemoryTests: XCTestCase {
    func testUnsetFileHasNoRememberedMode() throws {
        XCTAssertNil(RenderModeMemory.mode(for: URL(fileURLWithPath: "/tmp/a.txt"), in: try makeDefaults()))
    }

    func testRememberAndOverwrite() throws {
        let defaults = try makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        RenderModeMemory.remember(.plainText, for: url, in: defaults)
        XCTAssertEqual(RenderModeMemory.mode(for: url, in: defaults), .plainText)
        RenderModeMemory.remember(.markdown, for: URL(fileURLWithPath: "/tmp/./a.txt"), in: defaults)
        XCTAssertEqual(RenderModeMemory.mode(for: url, in: defaults), .markdown)
        XCTAssertEqual(RenderModeMemory.entries(in: defaults).count, 1, "standardized path, one entry")
    }

    func testForget() throws {
        let defaults = try makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        RenderModeMemory.remember(.markdown, for: url, in: defaults)
        RenderModeMemory.forget(url, in: defaults)
        XCTAssertNil(RenderModeMemory.mode(for: url, in: defaults))
    }

    func testEvictsLeastRecentlyChosenBeyondCapacity() throws {
        let defaults = try makeDefaults()
        let urls = (0...RenderModeMemory.capacity).map { URL(fileURLWithPath: "/tmp/\($0).txt") }
        for url in urls { RenderModeMemory.remember(.plainText, for: url, in: defaults) }
        XCTAssertEqual(RenderModeMemory.entries(in: defaults).count, RenderModeMemory.capacity)
        XCTAssertNil(RenderModeMemory.mode(for: urls[0], in: defaults))
        XCTAssertEqual(RenderModeMemory.mode(for: urls[1], in: defaults), .plainText)

        // Re-choosing refreshes recency: urls[1] survives the next eviction.
        RenderModeMemory.remember(.markdown, for: urls[1], in: defaults)
        RenderModeMemory.remember(.plainText, for: URL(fileURLWithPath: "/tmp/new.txt"), in: defaults)
        XCTAssertEqual(RenderModeMemory.mode(for: urls[1], in: defaults), .markdown)
        XCTAssertNil(RenderModeMemory.mode(for: urls[2], in: defaults))
    }

    func testMalformedEntriesAreIgnored() throws {
        let defaults = try makeDefaults()
        defaults.set([["path": "/tmp/a.txt", "mode": "bogus"], ["mode": "markdown"]],
                     forKey: RenderModeMemory.defaultsKey)
        XCTAssertTrue(RenderModeMemory.entries(in: defaults).isEmpty)
    }

    func testPlainTextFontDefaultsToMonospaced() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(PlainTextFontSetting.read(from: defaults), .monospaced)
        PlainTextFontSetting.write(.document, to: defaults)
        XCTAssertEqual(PlainTextFontSetting.read(from: defaults), .document)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "RenderModeMemoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
