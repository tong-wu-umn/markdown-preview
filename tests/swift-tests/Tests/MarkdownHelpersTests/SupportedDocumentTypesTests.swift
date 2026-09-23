import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import MarkdownHelpers

final class SupportedDocumentTypesTests: XCTestCase {
    // MARK: - kind(of:)

    func testEveryMarkdownExtensionIsMarkdown() {
        for ext in ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "mdx"] {
            XCTAssertEqual(kind("notes.\(ext)"), .markdown, ext)
            XCTAssertEqual(kind("notes.\(ext.uppercased())"), .markdown, ext.uppercased())
        }
    }

    func testTxtAndTextArePlainTextCaseInsensitively() {
        XCTAssertEqual(kind("notes.txt"), .plainText)
        XCTAssertEqual(kind("NOTES.TXT"), .plainText)
        XCTAssertEqual(kind("notes.text"), .plainText)
    }

    func testOtherPlainTextConformingFilesAreNotDocuments() {
        // All conform to public.plain-text, yet stay out of scope.
        for name in ["app.log", "data.csv", "doc.rtf", "script.py", "main.swift", "README", "archive.md.zip"] {
            XCTAssertNil(kind(name), name)
            XCTAssertFalse(SupportedDocumentTypes.isOpenable(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
    }

    func testDirectoryWithoutDocumentExtensionIsNotOpenable() {
        let directory = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
        XCTAssertNil(SupportedDocumentTypes.kind(of: directory))
        XCTAssertFalse(SupportedDocumentTypes.isOpenable(directory))
    }

    func testOpenPanelContentTypesIncludeMarkdownAndPlainTextOnce() {
        let identifiers = SupportedDocumentTypes.openPanelContentTypes.map(\.identifier)
        XCTAssertTrue(identifiers.contains(UTType.plainText.identifier))
        XCTAssertTrue(identifiers.contains("net.daringfireball.markdown"))
        XCTAssertEqual(identifiers.count, Set(identifiers).count, "no duplicates")
    }

    // MARK: - decode

    func testDecodesUTF8() {
        let decoded = SupportedDocumentTypes.decode(Data("# Héllo ✓".utf8))
        XCTAssertEqual(decoded?.text, "# Héllo ✓")
        XCTAssertEqual(decoded?.encoding, .utf8)
        XCTAssertEqual(decoded?.needsConversionToUTF8, false)
    }

    func testDecodesUTF8WithBOMAndDropsIt() {
        let decoded = SupportedDocumentTypes.decode(Data([0xEF, 0xBB, 0xBF]) + Data("# Hi".utf8))
        XCTAssertEqual(decoded?.text, "# Hi")
        XCTAssertEqual(decoded?.encoding, .utf8)
    }

    func testDecodesUTF16LittleEndianWithBOM() {
        let data = Data([0xFF, 0xFE]) + "é#".data(using: .utf16LittleEndian)!
        let decoded = SupportedDocumentTypes.decode(data)
        XCTAssertEqual(decoded?.text, "é#")
        XCTAssertEqual(decoded?.encoding, .utf16)
        XCTAssertEqual(decoded?.needsConversionToUTF8, true)
    }

    func testDecodesUTF16BigEndianWithBOM() {
        let data = Data([0xFE, 0xFF]) + "é#".data(using: .utf16BigEndian)!
        let decoded = SupportedDocumentTypes.decode(data)
        XCTAssertEqual(decoded?.text, "é#")
        XCTAssertEqual(decoded?.encoding, .utf16)
    }

    func testFallsBackToWindows1252() {
        // "café – ok" in Windows-1252: 0xE9 = é, 0x96 = en dash.
        let data = Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x96, 0x20, 0x6F, 0x6B])
        let decoded = SupportedDocumentTypes.decode(data)
        XCTAssertEqual(decoded?.text, "café – ok")
        XCTAssertEqual(decoded?.encoding, .windowsCP1252)
        XCTAssertEqual(decoded?.needsConversionToUTF8, true)
    }

    func testBytesUndefinedInWindows1252StillDecodeViaLatin1() throws {
        // 0x81 is undefined in CP1252; Latin-1 maps every byte.
        let decoded = try XCTUnwrap(SupportedDocumentTypes.decode(Data([0x61, 0x81, 0xE9])))
        XCTAssertEqual(decoded.text.unicodeScalars.count, 3)
        XCTAssertTrue(decoded.needsConversionToUTF8)
    }

    func testEmptyDataIsEmptyUTF8Text() {
        let decoded = SupportedDocumentTypes.decode(Data())
        XCTAssertEqual(decoded?.text, "")
        XCTAssertEqual(decoded?.encoding, .utf8)
    }

    func testBinaryDataIsRejected() {
        // PNG signature: not UTF-8, contains NUL — refuse rather than show garbage.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
        XCTAssertNil(SupportedDocumentTypes.decode(png))
    }

    func testReadTextThrowsForBinaryFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SupportedDocumentTypesTests-\(UUID().uuidString).txt")
        try Data([0xFF, 0x00, 0xC3, 0x28]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try SupportedDocumentTypes.readText(at: url))
    }

    func testReadTextRoundTripsLatin1File() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SupportedDocumentTypesTests-\(UUID().uuidString).txt")
        try Data([0x72, 0xE9, 0x73, 0x75, 0x6D, 0xE9]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try SupportedDocumentTypes.readText(at: url)
        XCTAssertEqual(decoded.text, "résumé")
        XCTAssertTrue(decoded.needsConversionToUTF8)
    }

    // MARK: - Helpers

    private func kind(_ name: String) -> SupportedDocumentTypes.Kind? {
        SupportedDocumentTypes.kind(of: URL(fileURLWithPath: "/tmp/\(name)"))
    }
}

final class NavigatorPlainTextSettingTests: XCTestCase {
    func testDefaultsToOnWhenUnset() throws {
        XCTAssertTrue(NavigatorPlainTextSetting.read(from: try makeDefaults()))
    }

    func testDisabledValueIsRemembered() throws {
        let defaults = try makeDefaults()
        NavigatorPlainTextSetting.write(false, to: defaults)
        XCTAssertFalse(NavigatorPlainTextSetting.read(from: defaults))
        NavigatorPlainTextSetting.write(true, to: defaults)
        XCTAssertTrue(NavigatorPlainTextSetting.read(from: defaults))
    }

    func testNilDefaultsFallBackToOn() {
        XCTAssertTrue(NavigatorPlainTextSetting.read(from: nil))
    }

    func testShouldListFiltersByKindAndSetting() {
        let md = URL(fileURLWithPath: "/tmp/a.md")
        let txt = URL(fileURLWithPath: "/tmp/requirements.txt")
        let py = URL(fileURLWithPath: "/tmp/setup.py")

        XCTAssertTrue(NavigatorPlainTextSetting.shouldList(md, showsPlainText: false))
        XCTAssertTrue(NavigatorPlainTextSetting.shouldList(md, showsPlainText: true))
        XCTAssertTrue(NavigatorPlainTextSetting.shouldList(txt, showsPlainText: true))
        XCTAssertFalse(NavigatorPlainTextSetting.shouldList(txt, showsPlainText: false))
        XCTAssertFalse(NavigatorPlainTextSetting.shouldList(py, showsPlainText: true))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "NavigatorPlainTextSettingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
