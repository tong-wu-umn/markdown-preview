//
//  MarkdownDocumentController.swift
//  md-preview
//

import Cocoa
import UniformTypeIdentifiers

final class MarkdownDocumentController: NSDocumentController {
    override func beginOpenPanel(
        _ openPanel: NSOpenPanel,
        forTypes inTypes: [String]?
    ) async -> Int {
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.message = NSLocalizedString(
            "Choose a Markdown file or folder",
            comment: "Open panel prompt"
        )
        SupportedDocumentOpenPanelFilter.configure(openPanel)
        return await super.beginOpenPanel(openPanel, forTypes: inTypes)
    }

    /// The app-level Open command (Command-O with no document window key).
    /// `NSDocumentController`'s default opens each selected URL through
    /// `openDocument(withContentsOf:)` independently, so two selected folders
    /// would each replace the root and the second would win. Run the panel
    /// and dispatch the whole selection through one batch instead, so every
    /// folder mounts and files still open per the tab policy.
    @IBAction override func openDocument(_ sender: Any?) {
        Task { @MainActor in
            let panel = NSOpenPanel()
            let response = await beginOpenPanel(panel, forTypes: nil)
            guard response == NSApplication.ModalResponse.OK.rawValue,
                  !panel.urls.isEmpty,
                  let appDelegate = NSApp.delegate as? AppDelegate else { return }
            appDelegate.openResolvedURLs(panel.urls)
        }
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        if url.isExistingDirectory,
           let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openFolder(url)
            completionHandler(nil, false, nil)
            return
        }

        super.openDocument(
            withContentsOf: url,
            display: displayDocument,
            completionHandler: completionHandler
        )
    }

    override func openUntitledDocumentAndDisplay(_ displayDocument: Bool) throws -> NSDocument {
        let document = try super.openUntitledDocumentAndDisplay(displayDocument)
        if displayDocument {
            (document.windowControllers.first as? DocumentWindowController)?
                .enterEditMode(autofocus: true)
        }
        return document
    }

    // MARK: - Recent documents
    //
    // AppKit's recents queue an update on a background "Document Recents"
    // queue that calls into LaunchServices, which can crash the app with a
    // null dereference (docs/bugs/recent-documents-crash.md). Every
    // recent-document entry point is overridden to use `RecentDocumentsList`
    // and never calls `super`; the Open Recent menu in MainMenu.xib is a plain
    // menu (no `recentDocuments` system menu) that this controller fills.
    // `noteNewRecentDocument(_:)`, which NSDocument uses after opening and
    // saving, funnels into `noteNewRecentDocumentURL(_:)`.

    override func noteNewRecentDocumentURL(_ url: URL) {
        RecentDocumentsList.note(url)
    }

    override var recentDocumentURLs: [URL] {
        RecentDocumentsList.existingURLs()
    }

    override var maximumRecentDocumentCount: Int {
        RecentDocumentsList.maximumCount
    }

    override func clearRecentDocuments(_ sender: Any?) {
        RecentDocumentsList.clear()
    }

    /// File ▸ Open Recent ▸ Clear Menu. A custom selector rather than
    /// `clearRecentDocuments:` so AppKit doesn't adopt the menu as its own
    /// recent-documents menu.
    @IBAction func clearRecentDocumentList(_ sender: Any?) {
        RecentDocumentsList.clear()
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            RecentDocumentsList.remove(url)
            NSSound.beep()
            return
        }
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openResolvedURLs([url])
        } else {
            openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    fileprivate static let recentItemIdentifier =
        NSUserInterfaceItemIdentifier("MarkdownPreview.recentDocumentItem")

    /// Menu items for `urls`: display name, file icon, and the parent folder
    /// appended when two recents share a name (as AppKit's menu does).
    fileprivate func recentDocumentItems(for urls: [URL]) -> [NSMenuItem] {
        let names = urls.map { FileManager.default.displayName(atPath: $0.path) }
        var nameCounts: [String: Int] = [:]
        for name in names { nameCounts[name, default: 0] += 1 }

        return zip(urls, names).map { url, name in
            var title = name
            if nameCounts[name, default: 0] > 1 {
                let parent = FileManager.default.displayName(
                    atPath: url.deletingLastPathComponent().path)
                title = "\(name) \u{2014} \(parent)"
            }
            let item = NSMenuItem(title: title,
                                  action: #selector(openRecentDocument(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.identifier = Self.recentItemIdentifier
            item.toolTip = (url.path as NSString).abbreviatingWithTildeInPath
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            return item
        }
    }
}

extension MarkdownDocumentController: NSMenuDelegate {
    /// Rebuilds File ▸ Open Recent each time it opens, keeping the xib's
    /// (localized) Clear Menu item at the bottom.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items.reversed()
        where item.identifier == Self.recentItemIdentifier {
            menu.removeItem(item)
        }

        let urls = RecentDocumentsList.existingURLs()
        let items = recentDocumentItems(for: urls)
        for (index, item) in items.enumerated() {
            menu.insertItem(item, at: index)
        }
        if !items.isEmpty {
            let separator = NSMenuItem.separator()
            separator.identifier = Self.recentItemIdentifier
            menu.insertItem(separator, at: items.count)
        }

        menu.autoenablesItems = false
        for item in menu.items where item.action == #selector(clearRecentDocumentList(_:)) {
            item.isEnabled = !RecentDocumentsList.paths().isEmpty
        }
    }
}
