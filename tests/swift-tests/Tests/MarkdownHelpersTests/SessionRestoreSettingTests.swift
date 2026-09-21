import Foundation
import XCTest
@testable import MarkdownHelpers

final class SessionRestoreSettingTests: XCTestCase {
    func testEnabledDefaultsToOnWhenUnset() throws {
        let defaults = try makeDefaults()
        XCTAssertTrue(SessionRestoreSetting.readIsEnabled(from: defaults))
    }

    func testDisabledValueIsRememberedNotClearedToDefault() throws {
        let defaults = try makeDefaults()

        SessionRestoreSetting.writeIsEnabled(false, to: defaults)
        XCTAssertFalse(SessionRestoreSetting.readIsEnabled(from: defaults))

        SessionRestoreSetting.writeIsEnabled(true, to: defaults)
        XCTAssertTrue(SessionRestoreSetting.readIsEnabled(from: defaults))
    }

    func testSaveNormalizesAndDeduplicatesFolders() throws {
        let defaults = try makeDefaults()
        let a = URL(fileURLWithPath: "/tmp/one")
        let dup = URL(fileURLWithPath: "/tmp/./one")
        let b = URL(fileURLWithPath: "/tmp/two")

        SessionRestoreSetting.saveFolders([a, dup, b], to: defaults)

        XCTAssertEqual(
            SessionRestoreSetting.savedFolderPaths(from: defaults),
            ["/tmp/one", "/tmp/two"]
        )
    }

    func testSavingEmptyClearsStoredFolders() throws {
        let defaults = try makeDefaults()

        SessionRestoreSetting.saveFolders([URL(fileURLWithPath: "/tmp/one")], to: defaults)
        SessionRestoreSetting.saveFolders([], to: defaults)

        XCTAssertTrue(SessionRestoreSetting.savedFolderPaths(from: defaults).isEmpty)
    }

    func testRestorableFoldersDropsMissingAndNonDirectoryPaths() throws {
        let defaults = try makeDefaults()
        let existingDir = try makeTempDirectory()
        let regularFile = existingDir.appendingPathComponent("note.md")
        try Data("x".utf8).write(to: regularFile)
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/gone")

        SessionRestoreSetting.saveFolders([existingDir, regularFile, missing], to: defaults)

        let restored = SessionRestoreSetting.restorableFolders(from: defaults)
        XCTAssertEqual(restored.map(\.standardizedFileURL.path),
                       [existingDir.standardizedFileURL.path])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SessionRestoreSettingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRestoreSettingTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
