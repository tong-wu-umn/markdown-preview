//
//  NavigatorRootSet.swift
//  md-preview
//
//  The set of folders mounted as Project Navigator roots for one window.
//  Kept free of AppKit so the SPM helper tests can exercise the mount /
//  remove / accommodate policy without a GUI host.
//
//  A root is either *explicit* (the user opened or added the folder) or
//  *implicit* (derived from the parent of the currently open file — the
//  single auto-root the navigator has always shown). The distinction drives
//  D3 below: an implicit-only set follows the open file the way it always
//  has, but a set the user has deliberately assembled is never silently
//  destroyed by opening a file outside it.
//

import Foundation

struct NavigatorRoot: Equatable {
    /// Always a `standardizedFileURL`.
    let url: URL
    /// Mounted by the user (folder open / Add Folder) rather than derived
    /// from the open file's parent.
    let isExplicit: Bool
}

enum FolderMountMode {
    /// Drop every existing root and show only the incoming folders. Used by
    /// the backward-compatible folder-open entry points (⌘O, Finder, `mdp`,
    /// the URL scheme).
    case replace
    /// Append the incoming folders, keeping the current roots. Used by
    /// "Add Folder to Navigator…".
    case add
}

struct NavigatorRootSet: Equatable {
    private(set) var roots: [NavigatorRoot] = []

    /// Mounted roots in display order.
    var urls: [URL] { roots.map(\.url) }

    /// Whether the user has deliberately mounted at least one folder.
    var hasExplicitRoots: Bool { roots.contains { $0.isExplicit } }

    /// Mounts `folderURLs` as explicit roots, deduping by standardized path
    /// (a duplicate path is a no-op — no second row). `.replace` drops every
    /// existing root, explicit and implicit alike.
    ///
    /// - Returns: `true` when the set changed.
    @discardableResult
    mutating func mount(_ folderURLs: [URL], mode: FolderMountMode) -> Bool {
        let incoming = folderURLs.map(\.standardizedFileURL)
        switch mode {
        case .replace:
            var newRoots: [NavigatorRoot] = []
            var seen: Set<String> = []
            for url in incoming where seen.insert(url.path).inserted {
                newRoots.append(NavigatorRoot(url: url, isExplicit: true))
            }
            guard newRoots != roots else { return false }
            roots = newRoots
            return true
        case .add:
            var changed = false
            var seen = Set(roots.map(\.url.path))
            for url in incoming where seen.insert(url.path).inserted {
                roots.append(NavigatorRoot(url: url, isExplicit: true))
                changed = true
            }
            return changed
        }
    }

    /// Removes the root at `folderURL`, if present.
    ///
    /// - Returns: `true` when a root was removed.
    @discardableResult
    mutating func remove(_ folderURL: URL) -> Bool {
        let target = folderURL.standardizedFileURL.path
        guard let index = roots.firstIndex(where: { $0.url.path == target }) else { return false }
        roots.remove(at: index)
        return true
    }

    /// D3: called on every `display(file:)`. An implicit-only set follows the
    /// file's parent (today's single auto-root behaviour); a set with any
    /// explicit root is left untouched so a cross-folder link cannot destroy
    /// a deliberately assembled workspace.
    ///
    /// - Returns: `true` when the set changed.
    @discardableResult
    mutating func accommodate(openFileURL: URL?) -> Bool {
        guard !hasExplicitRoots else { return false }

        // Already inside one of the implicit roots — keep it (matches the old
        // "keep the root if the file is a descendant" behaviour, including
        // deeply nested files).
        if let file = openFileURL?.standardizedFileURL,
           roots.contains(where: { file.isDescendantOrSame(of: $0.url) }) {
            return false
        }

        let newRoots: [NavigatorRoot]
        if let parent = openFileURL?.deletingLastPathComponent().standardizedFileURL {
            newRoots = [NavigatorRoot(url: parent, isExplicit: false)]
        } else {
            // Untitled document (no file): nothing to derive a root from.
            newRoots = []
        }
        guard newRoots != roots else { return false }
        roots = newRoots
        return true
    }

    /// The first mounted root that contains `fileURL`, in display order (D4).
    func containingRoot(for fileURL: URL) -> NavigatorRoot? {
        let target = fileURL.standardizedFileURL
        return roots.first { target.isDescendantOrSame(of: $0.url) }
    }
}

enum PathDisambiguation {
    /// Labels a list of URLs by `lastPathComponent`, appending the shortest
    /// distinguishing parent suffix — `README.md (proj)` vs
    /// `README.md (proj/child)` — when two share a name. Moved verbatim from
    /// `AppDelegate.menuNeedsUpdate` (PR #356) so root-row labels and the
    /// Window menu share one algorithm.
    static func labels(for urls: [URL]) -> [URL: String] {
        var result: [URL: String] = [:]
        for url in urls {
            let duplicates = urls.filter { $0.lastPathComponent == url.lastPathComponent }
            guard duplicates.count > 1 else {
                result[url] = url.lastPathComponent
                continue
            }
            let parents = url.deletingLastPathComponent().pathComponents.filter { $0 != "/" }
            var count = 1
            while count < parents.count {
                let suffix = parents.suffix(count).joined(separator: "/")
                let ambiguous = duplicates.contains { other in
                    other != url && other.deletingLastPathComponent().pathComponents
                        .suffix(count).joined(separator: "/") == suffix
                }
                if !ambiguous { break }
                count += 1
            }
            result[url] = "\(url.lastPathComponent) (\(parents.suffix(count).joined(separator: "/")))"
        }
        return result
    }
}
