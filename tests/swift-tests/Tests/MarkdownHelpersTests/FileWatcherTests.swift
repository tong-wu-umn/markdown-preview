import Foundation
import XCTest
@testable import MarkdownHelpers

/// Regression tests for the open document's file watcher: a cancelled
/// watcher must release its file descriptor even when the owner drops it
/// right away (`DocumentWindowController.startWatching` cancels the old
/// watcher and replaces it on every file switch and save). The leak slowly
/// exhausted the process's descriptors, after which every Project Navigator
/// root rendered as an empty folder.
final class FileWatcherTests: XCTestCase {
    private var directory: URL!
    private var file: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("doc.md")
        try Data("# doc\n".utf8).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCancelledAndReplacedWatchersReleaseDescriptors() throws {
        let queue = DispatchQueue(label: "FileWatcherTests")
        let baseline = try openDescriptorCount()

        // Hold the queue like the busy main thread does in the app, so every
        // cancel handler runs only after its watcher has been replaced.
        queue.suspend()
        var watcher: FileWatcher?
        for _ in 0..<200 {
            // startWatching's pattern: cancel, then replace immediately.
            watcher?.cancel()
            watcher = FileWatcher(url: file, queue: queue) {}
        }
        watcher?.cancel()
        watcher = nil
        _ = watcher
        queue.resume()
        queue.sync {}  // drain the cancel handlers

        XCTAssertLessThanOrEqual(try openDescriptorCount(), baseline + 2)
    }

    func testDeallocatedWatcherWithoutCancelReleasesDescriptor() throws {
        let queue = DispatchQueue(label: "FileWatcherTests")
        let baseline = try openDescriptorCount()

        for _ in 0..<200 {
            _ = FileWatcher(url: file, queue: queue) {}
        }
        queue.sync {}

        XCTAssertLessThanOrEqual(try openDescriptorCount(), baseline + 2)
    }

    func testReportsInPlaceWrite() throws {
        let changed = expectation(description: "change reported")
        changed.assertForOverFulfill = false
        let watcher = FileWatcher(url: file, queue: .main) { changed.fulfill() }

        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data("more\n".utf8))
        try handle.close()

        wait(for: [changed], timeout: 5)
        watcher.cancel()
    }

    /// An atomic save replaces the inode; the watcher re-opens on the path,
    /// keeps reporting, and does not leak the replaced file's descriptor.
    func testAtomicSavesKeepWatchingWithoutLeaking() throws {
        let baseline = try openDescriptorCount()
        var changes = 0
        let watcher = FileWatcher(url: file, queue: .main) { changes += 1 }

        for index in 0..<20 {
            try Data("# save \(index)\n".utf8).write(to: file, options: .atomic)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        }
        XCTAssertGreaterThan(changes, 0)

        // Still watching the path after the inode was replaced 20 times.
        let before = changes
        try Data("# final\n".utf8).write(to: file, options: .atomic)
        let deadline = Date().addingTimeInterval(5)
        while changes == before, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(changes, before)

        // Only the live watcher's descriptor remains open.
        XCTAssertLessThanOrEqual(try openDescriptorCount(), baseline + 2)
        watcher.cancel()
    }

    private func openDescriptorCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }
}
