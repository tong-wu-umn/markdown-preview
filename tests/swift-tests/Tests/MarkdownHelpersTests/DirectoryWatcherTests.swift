import Foundation
import XCTest
@testable import MarkdownHelpers

/// Regression tests for the Project Navigator's directory watchers: a
/// cancelled watcher must release its file descriptor even when the owner
/// drops it right away (the navigator's `syncWatchers` pattern). The leak
/// exhausted the process's descriptors under an agent editing files, after
/// which every navigator root rendered as an empty folder.
final class DirectoryWatcherTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCancelledAndDroppedWatchersReleaseDescriptors() throws {
        let queue = DispatchQueue(label: "DirectoryWatcherTests")
        let baseline = try openDescriptorCount()

        for _ in 0..<200 {
            var watcher: DirectoryWatcher? = DirectoryWatcher(url: directory, queue: queue) {}
            watcher?.cancel()
            watcher = nil  // dropped before the async cancel handler runs
            _ = watcher
        }
        queue.sync {}  // drain the cancel handlers

        XCTAssertLessThanOrEqual(try openDescriptorCount(), baseline + 2)
    }

    func testDeallocatedWatcherWithoutCancelReleasesDescriptor() throws {
        let queue = DispatchQueue(label: "DirectoryWatcherTests")
        let baseline = try openDescriptorCount()

        for _ in 0..<200 {
            _ = DirectoryWatcher(url: directory, queue: queue) {}
        }
        queue.sync {}

        XCTAssertLessThanOrEqual(try openDescriptorCount(), baseline + 2)
    }

    func testReportsEntryChanges() throws {
        let changed = expectation(description: "change reported")
        changed.assertForOverFulfill = false
        let watcher = DirectoryWatcher(url: directory, queue: .main) { changed.fulfill() }

        try Data("# hi\n".utf8).write(to: directory.appendingPathComponent("note.md"))

        wait(for: [changed], timeout: 5)
        watcher.cancel()
    }

    private func openDescriptorCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }
}
