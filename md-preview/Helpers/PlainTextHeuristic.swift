//
//  PlainTextHeuristic.swift
//  md-preview
//
//  Picks the default render mode for a `.txt` file that the user hasn't
//  explicitly set with View → Render as Markdown. Plenty of `.txt` notes and
//  LLM outputs are Markdown, so the heuristic looks for syntax that plain
//  prose rarely produces by accident:
//
//  - frontmatter
//  - an ATX heading (`# Title`; a `#!/bin/sh` shebang or a `#comment` is not
//    one, because an ATX heading needs a space after the hashes)
//  - a fenced code block (``` or ~~~)
//  - an inline Markdown link or image (`[text](url)`, `![alt](src)`)
//  - a GFM table
//
//  Lists, block quotes, emphasis, indented code, and setext underlines don't
//  count. They show up in hand-written plain text too (`* bullets meant
//  literally`, ASCII art indented four spaces, `Title` over `=====`), so on
//  their own they leave the file in plain-text mode.
//
//  Pure and AppKit-free so the SPM helper tests can exercise it.
//

import Foundation
import Markdown

nonisolated enum PlainTextHeuristic {
    /// Only the head of the file is parsed, which keeps a multi-megabyte log
    /// from stalling the main thread. Markdown shows its hand early.
    static let inspectedCharacterLimit = 64 * 1024

    static func suggestedMode(for text: String) -> MarkdownHTML.RenderMode {
        guard text.contains(where: { !$0.isWhitespace }) else { return .plainText }
        if MarkdownFrontmatter.split(text).raw != nil { return .markdown }
        let sample = inspectedSample(of: text)
        var detector = MarkdownSignalDetector(source: sample)
        detector.visit(Document(parsing: sample))
        return detector.found ? .markdown : .plainText
    }

    /// The first `inspectedCharacterLimit` characters, trimmed back to a line
    /// boundary so a construct cut in half can't count.
    static func inspectedSample(of text: String) -> String {
        guard text.count > inspectedCharacterLimit else { return text }
        let head = text.prefix(inspectedCharacterLimit)
        guard let lastNewline = head.lastIndex(of: "\n") else { return String(head) }
        return String(head[..<lastNewline])
    }
}

private nonisolated struct MarkdownSignalDetector: MarkupWalker {
    private let lines: [Substring]
    private(set) var found = false

    init(source: String) {
        lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    }

    mutating func defaultVisit(_ markup: any Markup) {
        guard !found else { return }
        descendInto(markup)
    }

    mutating func visitHeading(_ heading: Heading) {
        if startsLine(of: heading, with: "#") { found = true }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if startsLine(of: codeBlock, with: "```") || startsLine(of: codeBlock, with: "~~~") {
            found = true
        }
    }

    mutating func visitTable(_ table: Table) {
        found = true
    }

    mutating func visitLink(_ link: Link) {
        // `<https://…>` autolinks parse as links too; only `[text](…)` counts.
        if sourceText(at: link).hasPrefix("[") { found = true }
    }

    mutating func visitImage(_ image: Image) {
        if sourceText(at: image).hasPrefix("![") { found = true }
    }

    /// Whether the node's first source line, leading blanks aside, starts
    /// with `prefix`. Distinguishes ATX from setext headings and fenced from
    /// indented code, which the AST itself doesn't.
    private func startsLine(of markup: any Markup, with prefix: String) -> Bool {
        guard let line = markup.range?.lowerBound.line,
              lines.indices.contains(line - 1) else { return false }
        return lines[line - 1].drop(while: { $0 == " " || $0 == "\t" }).hasPrefix(prefix)
    }

    /// Source from the node's first character to the end of that line.
    private func sourceText(at markup: any Markup) -> Substring {
        guard let location = markup.range?.lowerBound,
              lines.indices.contains(location.line - 1) else { return "" }
        let utf8 = lines[location.line - 1].utf8
        // Columns are 1-based UTF-8 offsets.
        guard let start = utf8.index(utf8.startIndex,
                                     offsetBy: location.column - 1,
                                     limitedBy: utf8.endIndex) else { return "" }
        return Substring(utf8[start...])
    }
}
