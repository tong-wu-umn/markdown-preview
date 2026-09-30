//
//  FileWatcher.swift
//  md-preview
//
//  Watches an open document's file for changes, renames, and deletion.
//  Kept free of AppKit so the SPM helper tests can verify that watchers
//  release their file descriptors.
//

import Foundation

/// Not main-actor isolated: its `deinit` must be able to cancel the source,
/// and every handler runs on the `queue` it is given (`.main` in the app).
nonisolated final class FileWatcher {
    private static let moveResolutionDelay: TimeInterval = 0.20

    private let url: URL
    private let queue: DispatchQueue
    private let onChange: () -> Void
    /// Fired when the watched file is renamed or moved (in Finder, by an
    /// editor, etc.). Detected via `F_GETPATH` on the still-open FD —
    /// the inode follows the file, so the descriptor resolves to the
    /// new path. Plain deletes don't fire this (path unchanged).
    var onRename: ((URL) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    /// The live source's descriptor, for `F_GETPATH` only; -1 once the
    /// source is cancelled. Closing is the cancel handler's job.
    private var fileDescriptor: Int32 = -1
    private var debounce: DispatchWorkItem?
    private var moveResolution: DispatchWorkItem?

    init(url: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
        open()
    }

    deinit {
        cancel()
    }

    private func open() {
        stopSource()
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let event = source.data
            // Atomic-rename saves (Vim, VS Code, etc.) replace the inode;
            // re-open the watcher against the path so we keep tracking.
            // For an actual user-visible rename, the FD's resolved path
            // differs from the watcher's URL — surface that to the host.
            if !event.intersection([.delete, .rename, .revoke]).isEmpty {
                self.resolveMove(afterSettlingAt: self.currentPath())
                return
            }
            self.scheduleChange()
        }
        // Capture the descriptor by value, never through `self`: the cancel
        // handler runs asynchronously on `queue`, usually after the owner has
        // already dropped (and deallocated) this watcher. Routing the close
        // through a weak `self` skipped it, leaking a descriptor on every
        // file switch, save, and window close until the process could no
        // longer open anything — the Project Navigator then went blank.
        source.setCancelHandler { Darwin.close(fd) }
        fileDescriptor = fd
        self.source = source
        source.resume()
    }

    /// Cancels the live source (its cancel handler closes the descriptor).
    private func stopSource() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func resolveMove(afterSettlingAt movedURL: URL?) {
        moveResolution?.cancel()
        debounce?.cancel()
        stopSource()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.moveResolution = nil
            let resolution = FileWatcherMoveResolution.resolve(
                originalURL: self.url,
                movedURL: movedURL,
                fileExists: { FileManager.default.fileExists(atPath: $0.path) }
            )
            switch resolution {
            case .reloadOriginal:
                self.open()
                self.scheduleChange()
            case .followRename(let newURL):
                self.onRename?(newURL)
            case .unavailable:
                self.reopen()
            }
        }
        moveResolution = work
        queue.asyncAfter(deadline: .now() + Self.moveResolutionDelay, execute: work)
    }

    private func reopen() {
        stopSource()
        let work = DispatchWorkItem { [weak self] in self?.open() }
        queue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func currentPath() -> URL? {
        guard fileDescriptor >= 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fileDescriptor, F_GETPATH, &buffer) == 0 else { return nil }
        return URL(fileURLWithFileSystemRepresentation: buffer,
                   isDirectory: false,
                   relativeTo: nil)
    }

    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Stops watching and releases the file descriptor (asynchronously, on
    /// the watcher's queue). Safe to call more than once.
    func cancel() {
        debounce?.cancel()
        debounce = nil
        moveResolution?.cancel()
        moveResolution = nil
        stopSource()
    }
}
