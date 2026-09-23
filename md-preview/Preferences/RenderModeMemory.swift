//
//  RenderModeMemory.swift
//  md-preview
//
//  Remembers the render mode chosen with View → Render as Markdown for each
//  `.txt` file, so the choice survives reloads and relaunches and overrides
//  `PlainTextHeuristic`. Keyed by standardized path and bounded to the
//  `capacity` most recently chosen files, so the defaults entry can't grow
//  without limit. Kept free of AppKit so the SPM helper tests can exercise it.
//

import Foundation

enum RenderModeMemory {
    static let defaultsKey = "MarkdownPreview.plainTextRenderModes"
    static let capacity = 200

    private static let pathKey = "path"
    private static let modeKey = "mode"

    /// The mode the user chose for this file, or nil to fall back to the
    /// heuristic.
    static func mode(for url: URL,
                     in defaults: UserDefaults? = .standard) -> MarkdownHTML.RenderMode? {
        let path = key(for: url)
        return entries(in: defaults)
            .last { $0.path == path }
            .map(\.mode)
    }

    /// Stores `mode` as the most recent choice, evicting the oldest entries
    /// beyond `capacity`.
    static func remember(_ mode: MarkdownHTML.RenderMode,
                         for url: URL,
                         in defaults: UserDefaults? = .standard) {
        let path = key(for: url)
        var list = entries(in: defaults).filter { $0.path != path }
        list.append((path, mode))
        if list.count > capacity {
            list.removeFirst(list.count - capacity)
        }
        store(list, in: defaults)
    }

    static func forget(_ url: URL, in defaults: UserDefaults? = .standard) {
        let path = key(for: url)
        let list = entries(in: defaults)
        let kept = list.filter { $0.path != path }
        guard kept.count != list.count else { return }
        store(kept, in: defaults)
    }

    /// Oldest first. Malformed entries (from a hand-edited plist) are skipped.
    static func entries(in defaults: UserDefaults?) -> [(path: String, mode: MarkdownHTML.RenderMode)] {
        let raw = defaults?.array(forKey: defaultsKey) as? [[String: String]] ?? []
        return raw.compactMap { entry in
            guard let path = entry[pathKey], !path.isEmpty,
                  let mode = entry[modeKey].flatMap(MarkdownHTML.RenderMode.init(rawValue:))
            else { return nil }
            return (path, mode)
        }
    }

    private static func store(_ list: [(path: String, mode: MarkdownHTML.RenderMode)],
                              in defaults: UserDefaults?) {
        if list.isEmpty {
            defaults?.removeObject(forKey: defaultsKey)
        } else {
            defaults?.set(list.map { [pathKey: $0.path, modeKey: $0.mode.rawValue] },
                          forKey: defaultsKey)
        }
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
