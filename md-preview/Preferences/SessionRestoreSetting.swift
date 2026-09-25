//
//  SessionRestoreSetting.swift
//  md-preview
//
//  Remembers the folders mounted in the navigator so a relaunch can pick up
//  the last working folders instead of showing the Open panel, with the same
//  folders expanded. Folders only (not the open file), gated behind a
//  preference that defaults on.
//
//  The app holds a read-only exception for the whole filesystem (see
//  md-preview.entitlements — the navigator enumerates sibling folders that
//  way), so re-mounting a folder by path needs no security-scoped bookmark:
//  plain paths round-trip fine and the notarization-sensitive entitlements
//  stay untouched. Kept free of AppKit so the SPM helper tests can exercise
//  the round-trip without a GUI host.
//

import Foundation

enum SessionRestoreSetting {
    static let enabledDefaultsKey = "MarkdownPreview.restoresLastFoldersAtLaunch"
    static let foldersDefaultsKey = "MarkdownPreview.lastSessionFolderPaths"
    static let expandedFoldersDefaultsKey = "MarkdownPreview.lastSessionExpandedFolderPaths"

    // MARK: - Preference toggle (defaults ON)

    static var isEnabled: Bool {
        get { readIsEnabled(from: .standard) }
        set { writeIsEnabled(newValue, to: .standard) }
    }

    /// Defaults on, so a fresh install resumes. Stored explicitly (not cleared
    /// when off, unlike the additive preferences) so an intentional `false`
    /// is remembered across launches rather than reverting to the default.
    static func readIsEnabled(from defaults: UserDefaults?) -> Bool {
        guard let value = defaults?.object(forKey: enabledDefaultsKey) as? Bool else {
            return true
        }
        return value
    }

    static func writeIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults?) {
        defaults?.set(isEnabled, forKey: enabledDefaultsKey)
    }

    // MARK: - Saved folders

    /// Records the folders mounted in the window being remembered. An empty
    /// list clears the key so a folderless quit doesn't resurrect stale roots.
    static func saveFolders(_ urls: [URL], to defaults: UserDefaults? = .standard) {
        let paths = normalizedPaths(urls)
        if paths.isEmpty {
            defaults?.removeObject(forKey: foldersDefaultsKey)
        } else {
            defaults?.set(paths, forKey: foldersDefaultsKey)
        }
    }

    /// The stored folder paths, order preserved and de-duplicated. A pure
    /// string round-trip so it is testable without touching the filesystem.
    static func savedFolderPaths(from defaults: UserDefaults? = .standard) -> [String] {
        (defaults?.array(forKey: foldersDefaultsKey) as? [String]) ?? []
    }

    /// The saved folders that still exist as directories, as file URLs.
    /// Callers mount these; a folder deleted or renamed since last quit is
    /// silently dropped rather than mounted as a dead root.
    static func restorableFolders(from defaults: UserDefaults? = .standard,
                                  fileManager: FileManager = .default) -> [URL] {
        savedFolderPaths(from: defaults).compactMap { path in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    // MARK: - Saved navigator expansion

    /// Records which navigator folders (roots included) were expanded. `nil`
    /// means "unknown" (e.g. the navigator was never shown) and clears the
    /// key so a relaunch falls back to the default (roots expanded). An empty
    /// array is kept: it means everything was collapsed.
    static func saveExpandedFolders(_ urls: [URL]?, to defaults: UserDefaults? = .standard) {
        guard let urls else {
            defaults?.removeObject(forKey: expandedFoldersDefaultsKey)
            return
        }
        defaults?.set(normalizedPaths(urls), forKey: expandedFoldersDefaultsKey)
    }

    /// The expanded folder paths saved at last quit, or `nil` when none were
    /// recorded (use the default expansion).
    static func savedExpandedFolderPaths(from defaults: UserDefaults? = .standard) -> Set<String>? {
        guard let paths = defaults?.array(forKey: expandedFoldersDefaultsKey) as? [String] else {
            return nil
        }
        return Set(paths)
    }

    /// Standardized, de-duplicated folder paths in order.
    static func normalizedPaths(_ urls: [URL]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            result.append(path)
        }
        return result
    }
}
