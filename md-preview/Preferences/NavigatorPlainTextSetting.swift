//
//  NavigatorPlainTextSetting.swift
//  md-preview
//
//  Whether the Project Navigator lists `.txt` / `.text` files alongside
//  Markdown. Useful for notes folders, noisy in code repos
//  (`requirements.txt`, `LICENSE.txt`), so it's a preference that defaults
//  on. Kept free of AppKit so the SPM helper tests can exercise it.
//

import Foundation

enum NavigatorPlainTextSetting {
    static let defaultsKey = "MarkdownPreview.navigatorShowsPlainTextFiles"

    /// Posted after the value changes so open navigators re-filter their
    /// trees in place (expansion kept).
    static let didChangeNotification =
        Notification.Name("MarkdownPreview.navigatorPlainTextSettingDidChange")

    static var isEnabled: Bool {
        get { read(from: .standard) }
        set {
            write(newValue, to: .standard)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Defaults on. Stored explicitly so an intentional `false` survives.
    static func read(from defaults: UserDefaults?) -> Bool {
        guard let value = defaults?.object(forKey: defaultsKey) as? Bool else { return true }
        return value
    }

    static func write(_ isEnabled: Bool, to defaults: UserDefaults?) {
        defaults?.set(isEnabled, forKey: defaultsKey)
    }

    /// Whether a file (not a directory) belongs in the navigator tree.
    static func shouldList(_ url: URL, showsPlainText: Bool) -> Bool {
        switch SupportedDocumentTypes.kind(of: url) {
        case .markdown: true
        case .plainText: showsPlainText
        case nil: false
        }
    }
}
