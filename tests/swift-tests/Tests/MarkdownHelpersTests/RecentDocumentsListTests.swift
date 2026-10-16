import Foundation
import XCTest
@testable import MarkdownHelpers

final class RecentDocumentsListTests: XCTestCase {
    func testEmptyWhenNothingNoted() throws {
        let defaults = try makeDefaults()
        XCTAssertTrue(RecentDocumentsList.paths(from: defaults).isEmpty)
    }

    func testNoteMovesFileToFrontWithoutDuplicates() throws {
        let defaults = try makeDefaults()

        RecentDocumentsList.note(URL(fileURLWithPath: "/tmp/a.md"), in: defaults)
        RecentDocumentsList.note(URL(fileURLWithPath: "/tmp/b.md"), in: defaults)
        RecentDocumentsList.note(URL(fileURLWithPath: "/tmp/./a.md"), in: defaults)

        XCTAssertEqual(RecentDocumentsList.paths(from: defaults), ["/tmp/a.md", "/tmp/b.md"])
    }

    func testNoteCapsListAtMaximumCount() throws {
        let defaults = try makeDefaults()
        let total = RecentDocumentsList.maximumCount + 3

        for index in 0..<total {
            RecentDocumentsList.note(URL(fileURLWithPath: "/tmp/\(index).md"), in: defaults)
        }

        let paths = RecentDocumentsList.paths(from: defaults)
        XCTAssertEqual(paths.count, RecentDocumentsList.maximumCount)
        XCTAssertEqual(paths.first, "/tmp/\(total - 1).md")
        XCTAssertFalse(paths.contains("/tmp/0.md"))
    }

    func testNoteIgnoresNonFileURLs() throws {
        let defaults = try makeDefaults()

        RecentDocumentsList.note(try XCTUnwrap(URL(string: "https://example.com/a.md")), in: defaults)

        XCTAssertTrue(RecentDocumentsList.paths(from: defaults).isEmpty)
    }

    func testRemoveAndClear() throws {
        let defaults = try makeDefaults()
        RecentDocumentsList.note(URL(fileURLWithPath: "/tmp/a.md"), in: defaults)
        RecentDocumentsList.note(URL(fileURLWithPath: "/tmp/b.md"), in: defaults)

        RecentDocumentsList.remove(URL(fileURLWithPath: "/tmp/b.md"), from: defaults)
        XCTAssertEqual(RecentDocumentsList.paths(from: defaults), ["/tmp/a.md"])

        RecentDocumentsList.remove(URL(fileURLWithPath: "/tmp/a.md"), from: defaults)
        XCTAssertNil(defaults.object(forKey: RecentDocumentsList.defaultsKey))

        RecentDocumentsList.note(URL(fileURLWithPath: "/tmp/c.md"), in: defaults)
        RecentDocumentsList.clear(in: defaults)
        XCTAssertTrue(RecentDocumentsList.paths(from: defaults).isEmpty)
    }

    func testExistingURLsHidesMissingFilesAndDirectoriesButKeepsThem() throws {
        let defaults = try makeDefaults()
        let directory = try makeTempDirectory()
        let older = directory.appendingPathComponent("older.md")
        let newer = directory.appendingPathComponent("newer.md")
        try Data("x".utf8).write(to: older)
        try Data("y".utf8).write(to: newer)
        let missing = directory.appendingPathComponent("gone.md")

        RecentDocumentsList.note(older, in: defaults)
        RecentDocumentsList.note(missing, in: defaults)
        RecentDocumentsList.note(directory, in: defaults)
        RecentDocumentsList.note(newer, in: defaults)

        XCTAssertEqual(
            RecentDocumentsList.existingURLs(from: defaults).map(\.standardizedFileURL.path),
            [newer.standardizedFileURL.path, older.standardizedFileURL.path]
        )
        XCTAssertEqual(RecentDocumentsList.paths(from: defaults).count, 4)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "RecentDocumentsListTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentDocumentsListTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
