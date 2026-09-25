//
//  DirectoryWatcher.swift
//  md-preview
//
//  Watches one directory for entry changes (create / delete / rename) and
//  reports them, debounced. Used by the Project Navigator — one watcher per
//  loaded directory. Kept free of AppKit so the SPM helper tests can verify
//  that watchers release their file descriptors.
//

import Foundation

/// Not main-actor isolated: its `deinit` must be able to cancel the source,
/// and every handler runs on the `queue` it is given (`.main` in the app).
nonisolated final class DirectoryWatcher {
    private let onChange: () -> Void
    private let queue: DispatchQueue
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?

    init(url: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.queue = queue
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        // Capture the descriptor by value, never through `self`: the cancel
        // handler runs asynchronously on `queue`, usually after the owner has
        // already dropped (and deallocated) this watcher. Routing the close
        // through a weak `self` skipped it, leaking one descriptor per
        // cancelled watcher until the process could no longer open any
        // directory — every navigator root then rendered as an empty folder.
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
    }

    deinit {
        cancel()
    }

    /// FS events arrive in bursts (Finder rewrites + xattr updates). Coalesce.
    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Stops watching and releases the file descriptor (asynchronously, on
    /// the watcher's queue). Safe to call more than once.
    func cancel() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
    }
}
