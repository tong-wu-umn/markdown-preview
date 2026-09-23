//
//  MarkdownHTML+PlainText.swift
//  md-preview
//
//  The plain-text render mode for `.txt` files: the text is shown as written
//  (hard wraps, `#` comments, literal `*` bullets, ASCII tables and art)
//  instead of being reinterpreted as Markdown. It shares the page shell,
//  theme, reader width, and color scheme with the Markdown renderer. Only the
//  article body differs, and no vendor renderer (Mermaid, KaTeX, highlight.js)
//  is loaded.
//
//  The body is a `<div>` with `white-space: pre-wrap`, not a fenced code
//  block. A code block brings its chrome (background, border, copy button,
//  horizontal scrolling), and fencing arbitrary text breaks on text that
//  contains long backtick runs.
//

import Foundation

nonisolated extension MarkdownHTML {
    /// How a document's text becomes the article.
    enum RenderMode: String, Sendable, CaseIterable {
        case markdown
        case plainText
    }

    /// Face used by the plain-text render mode.
    enum PlainTextFont: String, Sendable, CaseIterable {
        /// The code face, like a text editor. Keeps ASCII tables and art aligned.
        case monospaced
        /// The reader's document font (Settings → Appearance).
        case document
    }

    static let plainTextClass = "mdp-plain-text"
    static let plainTextMonospacedClass = "mdp-plain-text-mono"

    /// The article body for plain-text mode: the whole text, HTML-escaped,
    /// in one pre-wrapped block. `dir="auto"` lets an RTL document lay out
    /// right to left without the per-block inference the Markdown path runs.
    ///
    /// The block spans every source line, so the edit-mode scroll hand-off
    /// (which maps between editor lines and `data-source-start/end`) lands
    /// proportionally inside it. `data-source-line` is deliberately absent:
    /// it opts a block into copy-as-Markdown-source, and plain text copies
    /// exactly what is selected.
    static func plainTextArticleHTML(_ text: String, font: PlainTextFont) -> String {
        let classes = font == .monospaced
            ? "\(plainTextClass) \(plainTextMonospacedClass)"
            : plainTextClass
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return "<div class=\"\(classes)\" dir=\"auto\" data-source-start=\"1\" "
            + "data-source-end=\"\(max(1, lineCount))\">\(htmlEscape(text))</div>"
    }

    /// Plain-text mode's page: `render(markdown:…, renderMode: .plainText)`.
    static func renderPlainText(_ text: String,
                                font: PlainTextFont = .monospaced,
                                allowsScroll: Bool = false,
                                assetBaseHref: String? = nil,
                                vendorLoading: VendorLoading = .inline,
                                contentWidth: ContentWidth = .centered,
                                colorScheme: ColorScheme? = nil,
                                themeOverrides: ThemeOverrides? = nil,
                                documentFont: DocumentFontSetting = .current,
                                readerLayout: ReaderLayoutSetting = .current) -> RenderedHTML {
        render(markdown: text,
               allowsScroll: allowsScroll,
               assetBaseHref: assetBaseHref,
               vendorLoading: vendorLoading,
               contentWidth: contentWidth,
               colorScheme: colorScheme,
               themeOverrides: themeOverrides,
               documentFont: documentFont,
               readerLayout: readerLayout,
               renderMode: .plainText,
               plainTextFont: font)
    }

    /// Part of the shared stylesheet (not emitted per mode) so a page loaded
    /// for Markdown can swap in a plain-text article on the fast path.
    ///
    /// `overflow-wrap: anywhere` breaks a 500-column line inside the column
    /// instead of scrolling horizontally. Reader letter/word spacing stops
    /// here, as it does at code: whitespace fidelity wins.
    static let plainTextCSS = """
    article.markdown-body .\(plainTextClass) {
        margin: 0;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        tab-size: 4;
        letter-spacing: normal;
        word-spacing: normal;
    }
    article.markdown-body .\(plainTextMonospacedClass) {
        font-family: \(codeFontFamily);
        font-size: var(--mdp-code-font-size, 0.9em);
        line-height: 1.45;
    }
    """
}
