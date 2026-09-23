//
//  SupportedDocumentTypes.swift
//  md-preview
//
//  One source of truth for which files the app opens, shows in the Project
//  Navigator, and follows as in-document links, plus the tolerant text
//  decoder shared by every document read path.
//
//  Kept free of AppKit so the SPM helper tests can compile it, and compiled
//  into the Quick Look extension (MarkdownWebView uses `isOpenable`).
//

import Foundation
import UniformTypeIdentifiers

nonisolated enum SupportedDocumentTypes {
    /// Markdown extensions, matching the UTIs Info.plist exports/imports.
    static let markdownExtensions: Set<String> =
        ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "mdx"]

    /// Plain-text extensions opened (and rendered) as Markdown. Deliberately
    /// narrow: `public.plain-text` is also the parent of source code, `.log`,
    /// and `.csv`, none of which the app lists or follows as links.
    static let plainTextExtensions: Set<String> = ["txt", "text"]

    enum Kind: Sendable, Equatable {
        case markdown
        case plainText
    }

    /// Classifies by path extension, case-insensitively. Nil for anything
    /// the app does not treat as a document (including extensionless paths).
    static func kind(of url: URL) -> Kind? {
        kind(ofExtension: url.pathExtension)
    }

    static func kind(ofExtension pathExtension: String) -> Kind? {
        let ext = pathExtension.lowercased()
        if markdownExtensions.contains(ext) { return .markdown }
        if plainTextExtensions.contains(ext) { return .plainText }
        return nil
    }

    /// True for files the app opens in-app. Directories are never "openable"
    /// documents here; callers handle folders separately.
    static func isOpenable(_ url: URL) -> Bool {
        kind(of: url) != nil
    }

    /// Content types for open panels: every Markdown UTI plus plain text.
    /// `public.plain-text` admits conforming types (source code, logs) in a
    /// panel, so panels pair this with an `isOpenable` delegate filter.
    static var openPanelContentTypes: [UTType] {
        var types: [UTType] = []
        var seen: Set<String> = []
        let candidates = [UTType("net.daringfireball.markdown")]
            + markdownExtensions.sorted().map { UTType(filenameExtension: $0) }
            + [UTType.plainText]
        for case let type? in candidates where seen.insert(type.identifier).inserted {
            types.append(type)
        }
        return types
    }

    // MARK: - Decoding

    struct DecodedText: Sendable, Equatable {
        let text: String
        let encoding: String.Encoding

        /// Whether writing `text` back as UTF-8 would change the file's
        /// encoding. Saving must ask first (never silently re-encode).
        var needsConversionToUTF8: Bool { encoding != .utf8 }
    }

    /// Decodes document bytes: UTF-8 (a leading BOM is dropped), then UTF-16
    /// with a BOM, then Windows-1252 / ISO Latin-1 for legacy text.
    ///
    /// Returns nil for data that looks binary (a NUL byte without a UTF-16
    /// BOM). Without that cap the Latin-1 fallback would "decode" anything,
    /// images included, into garbage.
    static func decode(_ data: Data) -> DecodedText? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = String(data: data.dropFirst(3), encoding: .utf8) else { return nil }
            return DecodedText(text: text, encoding: .utf8)
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            // `.utf16` reads the BOM to pick the byte order and strips it.
            guard let text = String(data: data, encoding: .utf16) else { return nil }
            return DecodedText(text: text, encoding: .utf16)
        }
        if let text = String(data: data, encoding: .utf8) {
            return DecodedText(text: text, encoding: .utf8)
        }
        guard !data.contains(0) else { return nil }
        if let text = String(data: data, encoding: .windowsCP1252) {
            return DecodedText(text: text, encoding: .windowsCP1252)
        }
        // CP1252 leaves five bytes (0x81, 0x8D, 0x8F, 0x90, 0x9D) undefined;
        // Latin-1 maps every byte, so this is the last resort.
        return String(data: data, encoding: .isoLatin1)
            .map { DecodedText(text: $0, encoding: .isoLatin1) }
    }

    /// Reads and decodes a file, throwing `fileReadCorruptFile` (or the
    /// underlying read error) when it isn't decodable text.
    static func readText(at url: URL) throws -> DecodedText {
        let data = try Data(contentsOf: url)
        guard let decoded = decode(data) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
        }
        return decoded
    }
}
