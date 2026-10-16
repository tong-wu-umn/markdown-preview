//
//  RecentDocumentsList.swift
//  md-preview
//
//  The app's own File ▸ Open Recent list. AppKit's built-in recents
//  (`NSDocumentController.noteNewRecentDocumentURL` and the `recentDocuments`
//  system menu) queue an update on a background "Document Recents" queue that
//  calls into LaunchServices' shared file list, and on macOS 26 that call can
//  dereference null and kill the process — the window title changes, then the
//  app dies before the preview draws (docs/bugs/recent-documents-crash.md).
//  `MarkdownDocumentController` routes every recent-document note here instead
//  and never calls `super`, so nothing reaches LaunchServices.
//
//  Plain paths, like `SessionRestoreSetting`: the app holds a read-only
//  exception for the whole filesystem (see md-preview.entitlements), so a
//  recent file reopens by path without a security-scoped bookmark and the
//  notarization-sensitive entitlements stay untouched. Kept free of AppKit so
//  the SPM helper tests can exercise it without a GUI host.
//

import Foundation

enum RecentDocumentsList {
    static let defaultsKey = "MarkdownPreview.recentDocumentPaths"
    /// Same as AppKit's default Open Recent length.
    static let maximumCount = 10

    /// The stored paths, most recent first.
    static func paths(from defaults: UserDefaults? = .standard) -> [String] {
        (defaults?.array(forKey: defaultsKey) as? [String]) ?? []
    }

    /// Moves `url` to the front of the list, dropping any older entry for the
    /// same file and anything past `maximumCount`. Non-file URLs are ignored.
    static func note(_ url: URL, in defaults: UserDefaults? = .standard) {
        guard url.isFileURL else { return }
        let path = normalizedPath(url)
        guard !path.isEmpty else { return }
        var paths = paths(from: defaults).filter { $0 != path }
        paths.insert(path, at: 0)
        defaults?.set(Array(paths.prefix(maximumCount)), forKey: defaultsKey)
    }

    static func remove(_ url: URL, from defaults: UserDefaults? = .standard) {
        let path = normalizedPath(url)
        let paths = paths(from: defaults)
        let remaining = paths.filter { $0 != path }
        guard remaining.count != paths.count else { return }
        store(remaining, in: defaults)
    }

    static func clear(in defaults: UserDefaults? = .standard) {
        defaults?.removeObject(forKey: defaultsKey)
    }

    /// The recent files that still exist, most recent first. A file that was
    /// deleted, or sits on a volume that is not mounted right now, is hidden
    /// but kept, so it comes back when the volume does.
    static func existingURLs(from defaults: UserDefaults? = .standard,
                             fileManager: FileManager = .default) -> [URL] {
        paths(from: defaults).compactMap { path in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return nil }
            return URL(fileURLWithPath: path, isDirectory: false)
        }
    }

    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func store(_ paths: [String], in defaults: UserDefaults?) {
        if paths.isEmpty {
            defaults?.removeObject(forKey: defaultsKey)
        } else {
            defaults?.set(paths, forKey: defaultsKey)
        }
    }
}
