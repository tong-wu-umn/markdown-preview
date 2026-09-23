//
//  ProjectNavigatorView.swift
//  md-preview
//

import Cocoa

private final class FileNode {
    let url: URL
    let isDirectory: Bool
    private var loadedChildren: [FileNode]?

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var displayName: String { url.lastPathComponent }

    /// Children if `children()` has populated the cache; nil otherwise.
    var cachedChildren: [FileNode]? { loadedChildren }

    func invalidateCache() { loadedChildren = nil }

    func children() -> [FileNode] {
        if let cached = loadedChildren { return cached }
        guard isDirectory else {
            loadedChildren = []
            return []
        }
        let showsPlainText = NavigatorPlainTextSetting.isEnabled
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        let nodes: [FileNode] = entries.compactMap { entry in
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { return FileNode(url: entry, isDirectory: true) }
            guard NavigatorPlainTextSetting.shouldList(entry, showsPlainText: showsPlainText) else { return nil }
            return FileNode(url: entry, isDirectory: false)
        }
        let sorted = nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        loadedChildren = sorted
        return sorted
    }
}

final class ProjectNavigatorView: NSView {

    var onSelectFile: ((URL) -> Void)?
    /// Fired by the "Add Folder to Navigator…" menu entries so the window
    /// controller can present the folder picker.
    var onAddFolderRequested: (() -> Void)?
    /// Fired by "Remove from Navigator" on an explicit root row.
    var onRemoveRoot: ((URL) -> Void)?
    /// Fired when folders are dropped onto the navigator (mounted additively).
    var onAddFolders: (([URL]) -> Void)?
    /// Asks the owner whether a root row was mounted by the user (only
    /// explicit roots offer "Remove from Navigator").
    var isExplicitRoot: ((URL) -> Bool)?

    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private var rootNodes: [FileNode] = []
    /// Disambiguated labels for root rows (shared with the Window menu).
    private var rootLabels: [URL: String] = [:]
    /// The file whose document is actually open. Keep this separate from the
    /// outline's transient click selection so a pending Save/Don't Save/Cancel
    /// decision cannot make the navigator disagree with the editor.
    private var currentFileURL: URL?
    // One watcher per loaded directory; kept in sync with which FileNodes
    // currently have a populated children cache.
    private var watchers: [URL: DirectoryWatcher] = [:]
    /// Shown in `.files` mode when no folder is mounted (D7 / Phase 2).
    private let emptyStateView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        addSubview(scrollView)

        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.indentationPerLevel = 14
        outlineView.refusesFirstResponder = true

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outlineView.menu = contextMenu

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView

        // Accept directory drops onto the navigator to mount them (Phase 2).
        outlineView.registerForDraggedTypes([.fileURL])

        setUpEmptyState()

        // Re-filter in place when "Show plain-text files" flips, keeping
        // expansion and selection — the same path a folder change takes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigatorFilterDidChange),
            name: NavigatorPlainTextSetting.didChangeNotification,
            object: nil
        )

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Centered placeholder shown when `.files` mode has no folder mounted.
    private func setUpEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true

        let label = NSTextField(labelWithString:
            NSLocalizedString("No folder in the navigator", comment: "Empty project navigator"))
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2

        let button = NSButton(
            title: NSLocalizedString("Add Folder to Navigator\u{2026}", comment: "Empty project navigator"),
            target: self,
            action: #selector(addFolderButtonClicked))
        button.bezelStyle = .rounded
        button.controlSize = .small

        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(stack)
        addSubview(emptyStateView, positioned: .above, relativeTo: scrollView)

        NSLayoutConstraint.activate([
            emptyStateView.topAnchor.constraint(equalTo: topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyStateView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyStateView.trailingAnchor, constant: -16)
        ])
        updateEmptyState()
    }

    private func updateEmptyState() {
        emptyStateView.isHidden = !rootNodes.isEmpty
    }

    @objc private func addFolderButtonClicked() {
        onAddFolderRequested?()
    }

    /// Mounts `urls` as the navigator's roots. Existing `FileNode`s are
    /// reused for URLs that were already mounted, so their child caches and
    /// expansion survive; only added/removed roots are animated in and out,
    /// which keeps the other trees from collapsing.
    func setRoots(_ urls: [URL]) {
        let standardized = urls.map(\.standardizedFileURL)
        var existing: [URL: FileNode] = [:]
        for node in rootNodes { existing[node.url] = node }
        let oldURLs = rootNodes.map(\.url)
        let newNodes = standardized.map { existing[$0] ?? FileNode(url: $0, isDirectory: true) }
        rootNodes = newNodes
        rootLabels = PathDisambiguation.labels(for: standardized)
        updateEmptyState()

        if oldURLs == standardized {
            // Same roots, possibly restyled labels — nothing structural.
            reloadRootLabels()
            syncWatchers()
            return
        }

        // Incremental only while the surviving roots keep their order
        // (add-at-end / remove); otherwise a full reload preserving expansion.
        let survivingOld = oldURLs.filter { standardized.contains($0) }
        let survivingNew = standardized.filter { oldURLs.contains($0) }
        guard survivingOld == survivingNew else {
            let expanded = collectExpandedURLs()
            outlineView.reloadData()
            for node in newNodes {
                outlineView.expandItem(node)
                reExpand(node, expanded: expanded)
            }
            syncWatchers()
            return
        }

        outlineView.beginUpdates()
        for index in oldURLs.indices.reversed() where !standardized.contains(oldURLs[index]) {
            outlineView.removeItems(at: IndexSet(integer: index),
                                    inParent: nil,
                                    withAnimation: .effectFade)
        }
        for index in standardized.indices where !oldURLs.contains(standardized[index]) {
            outlineView.insertItems(at: IndexSet(integer: index),
                                    inParent: nil,
                                    withAnimation: .slideDown)
        }
        outlineView.endUpdates()
        for node in newNodes where !oldURLs.contains(node.url) {
            outlineView.expandItem(node)
        }
        syncWatchers()
    }

    /// Refreshes the visible text of root rows without touching the tree —
    /// used when only the disambiguated labels changed.
    private func reloadRootLabels() {
        for node in rootNodes {
            let row = outlineView.row(forItem: node)
            guard row >= 0,
                  let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                    as? NSTableCellView else { continue }
            cell.textField?.stringValue = rootLabels[node.url] ?? node.displayName
            cell.toolTip = node.url.path
        }
    }

    private func isRootNode(_ node: FileNode) -> Bool {
        rootNodes.contains { $0 === node }
    }

    // MARK: - Folder watching

    private func syncWatchers() {
        var live: Set<URL> = []
        for node in rootNodes { collectLoadedDirectories(node, into: &live) }
        for url in live where watchers[url] == nil {
            watchers[url] = DirectoryWatcher(url: url) { [weak self] in
                self?.handleFolderChange()
            }
        }
        for (url, watcher) in watchers where !live.contains(url) {
            watcher.cancel()
            watchers.removeValue(forKey: url)
        }
    }

    private func collectLoadedDirectories(_ node: FileNode, into set: inout Set<URL>) {
        guard node.isDirectory else { return }
        set.insert(node.url.standardizedFileURL)
        guard let kids = node.cachedChildren else { return }
        for child in kids where child.isDirectory {
            collectLoadedDirectories(child, into: &set)
        }
    }

    @objc private func navigatorFilterDidChange() {
        refreshTree()
        // Re-select the open document; a now-hidden `.txt` simply ends up
        // with no selected row.
        if let currentFileURL, selectPath(to: currentFileURL) { return }
        outlineView.deselectAll(nil)
    }

    private func handleFolderChange() {
        let selectedURL = currentlySelectedURL()
        refreshTree()
        if let selectedURL { setCurrentFile(selectedURL) }
    }

    /// Reloads the outline from disk while preserving expansion state.
    /// Selection is left to the caller.
    private func refreshTree() {
        let expandedURLs = collectExpandedURLs()
        for node in rootNodes { invalidateCaches(node) }
        outlineView.reloadData()
        for node in rootNodes {
            outlineView.expandItem(node)
            reExpand(node, expanded: expandedURLs)
        }
        syncWatchers()
    }

    private func invalidateCaches(_ node: FileNode) {
        guard node.isDirectory, let kids = node.cachedChildren else { return }
        for child in kids where child.isDirectory {
            invalidateCaches(child)
        }
        node.invalidateCache()
    }

    private func collectExpandedURLs() -> Set<URL> {
        var result: Set<URL> = []
        func walk(_ item: Any?) {
            let count = outlineView.numberOfChildren(ofItem: item)
            for i in 0..<count {
                let child = outlineView.child(i, ofItem: item)
                if let node = child as? FileNode, outlineView.isItemExpanded(node) {
                    result.insert(node.url.standardizedFileURL)
                    walk(child)
                }
            }
        }
        walk(nil)
        return result
    }

    private func currentlySelectedURL() -> URL? {
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FileNode else { return nil }
        return node.url.standardizedFileURL
    }

    private func reExpand(_ node: FileNode, expanded: Set<URL>) {
        guard node.isDirectory else { return }
        for child in node.children() where child.isDirectory {
            if expanded.contains(child.url.standardizedFileURL) {
                outlineView.expandItem(child)
                reExpand(child, expanded: expanded)
            }
        }
    }

    func setCurrentFile(_ url: URL?) {
        currentFileURL = url?.standardizedFileURL
        guard let target = currentFileURL, !rootNodes.isEmpty else {
            outlineView.deselectAll(nil)
            return
        }
        if selectPath(to: target) { return }
        // Cache might be stale (file was just renamed and our
        // DirectoryWatcher hasn't fired yet). Refresh from disk once
        // and retry before giving up.
        refreshTree()
        if selectPath(to: target) { return }
        outlineView.deselectAll(nil)
    }

    /// Selects `target` under the first root that contains it (D4). Returns
    /// false when no mounted root holds the file.
    private func selectPath(to target: URL) -> Bool {
        for root in rootNodes where target.isDescendantOrSame(of: root.url) {
            var path: [FileNode] = []
            guard collectPath(to: target, from: root, into: &path) else { continue }
            outlineView.expandItem(root)
            for ancestor in path.dropLast() {
                outlineView.expandItem(ancestor)
            }
            if let leaf = path.last {
                let row = outlineView.row(forItem: leaf)
                if row >= 0 {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                    refreshRowTextColors()
                    return true
                }
            }
        }
        return false
    }

    private func collectPath(to targetURL: URL,
                             from root: FileNode,
                             into path: inout [FileNode]) -> Bool {
        // Skip subtrees that can't contain the target.
        guard targetURL.isDescendantOrSame(of: root.url) else { return false }

        for child in root.children() {
            if child.url.standardizedFileURL == targetURL {
                path.append(child)
                return true
            }
            if child.isDirectory {
                path.append(child)
                if collectPath(to: targetURL, from: child, into: &path) { return true }
                path.removeLast()
            }
        }
        return false
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            // Disclosure buttons handle their own clicks in AppKit; this
            // action covers the folder's name, icon, and remaining row area.
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else {
            let requestedURL = node.url.standardizedFileURL
            guard requestedURL != currentFileURL else { return }
            // `shouldSelectItem` keeps the highlight on the committed file,
            // so there's no AppKit selection to undo here — display(markdown:)
            // selects the requested file only after navigation succeeds.
            onSelectFile?(node.url)
        }
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let controller = documentWindowController else { return }
        controller.openInNewTab(url)
    }

    @objc private func openInNewWindow(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let controller = documentWindowController else { return }
        controller.openInNewWindow(url)
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    @objc private func copyContents(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Task { @concurrent in
            guard let text = try? SupportedDocumentTypes.readText(at: url).text else { return }
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    @objc private func addFolderToNavigator(_ sender: NSMenuItem) {
        onAddFolderRequested?()
    }

    @objc private func removeRootFromNavigator(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onRemoveRoot?(url)
    }
}

extension ProjectNavigatorView: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else {
            // Empty area: the one action that makes sense with no row is
            // mounting another folder.
            menu.addItem(makeAddFolderItem())
            return
        }
        let url = node.url

        menu.addItem(makeMenuItem(title: NSLocalizedString("Show in Finder", comment: "Project navigator context menu"),
                                  symbol: "folder",
                                  action: #selector(showInFinder(_:)),
                                  url: url))

        if isRootNode(node) {
            if isExplicitRoot?(url) ?? false {
                menu.addItem(makeMenuItem(title: NSLocalizedString("Remove from Navigator", comment: "Project navigator context menu"),
                                          symbol: "minus.circle",
                                          action: #selector(removeRootFromNavigator(_:)),
                                          url: url))
            }
            menu.addItem(.separator())
            menu.addItem(makeAddFolderItem())
            menu.addItem(makeMenuItem(title: NSLocalizedString("Copy Path", comment: "Project navigator context menu"),
                                      symbol: "document.on.document",
                                      action: #selector(copyPath(_:)),
                                      url: url))
            return
        }

        if !node.isDirectory {
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: NSLocalizedString("Open in New Tab", comment: "Project navigator context menu"),
                                      symbol: "macwindow",
                                      action: #selector(openInNewTab(_:)),
                                      url: url))
            menu.addItem(makeMenuItem(title: NSLocalizedString("Open in New Window", comment: "Project navigator context menu"),
                                      symbol: "macwindow.badge.plus",
                                      action: #selector(openInNewWindow(_:)),
                                      url: url))
            if let controller = documentWindowController {
                for item in controller.contextMenuEditorItems(for: url) {
                    menu.addItem(item)
                }
            }
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: NSLocalizedString("Copy", comment: "Project navigator context menu"),
                                      symbol: "document.on.clipboard",
                                      action: #selector(copyContents(_:)),
                                      url: url))
        } else {
            menu.addItem(.separator())
        }

        menu.addItem(makeMenuItem(title: NSLocalizedString("Copy Path", comment: "Project navigator context menu"),
                                  symbol: "document.on.document",
                                  action: #selector(copyPath(_:)),
                                  url: url))
    }

    private func makeMenuItem(title: String,
                              symbol: String,
                              action: Selector,
                              url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = url
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private func makeAddFolderItem() -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString("Add Folder to Navigator\u{2026}", comment: "Project navigator context menu"),
                              action: #selector(addFolderToNavigator(_:)),
                              keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
        return item
    }

    private var documentWindowController: DocumentWindowController? {
        outlineView.window?.windowController as? DocumentWindowController
    }

    /// Theme accent for the selected file row — the link color, matching
    /// the TOC outline's treatment. Nil without a link override.
    fileprivate var themeAccent: NSColor? {
        let isDark = effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return ThemeColorsSetting.current.color(.linkColor, isDark ? .dark : .light)
    }

    func refreshRowTextColors() {
        let accent = themeAccent ?? .controlAccentColor
        let selected = outlineView.selectedRow
        for row in 0..<outlineView.numberOfRows {
            guard let cell = outlineView.view(
                atColumn: 0, row: row, makeIfNecessary: false
            ) as? NSTableCellView, let textField = cell.textField else { continue }
            textField.textColor = row == selected ? accent : .labelColor
        }
    }
}

extension ProjectNavigatorView: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? FileNode { return node.children().count }
        return rootNodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? FileNode { return node.children()[index] }
        return rootNodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.isDirectory && !node.children().isEmpty
    }

    // MARK: - Directory drops

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard !droppedFolderURLs(from: info).isEmpty else { return [] }
        // Retarget any folder drop to the navigator as a whole, so dropping
        // onto a row still mounts the folder as a new root.
        outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .copy
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        let urls = droppedFolderURLs(from: info)
        guard !urls.isEmpty else { return false }
        onAddFolders?(urls)
        return true
    }

    private func droppedFolderURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let objects = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options) as? [URL] else { return [] }
        return objects.filter { $0.isExistingDirectory }
    }
}

extension ProjectNavigatorView: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cell: NSTableCellView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.cell?.usesSingleLineMode = true
            textField.maximumNumberOfLines = 1
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        if isRootNode(node) {
            cell.textField?.stringValue = rootLabels[node.url] ?? node.displayName
            cell.toolTip = node.url.path
        } else {
            cell.textField?.stringValue = node.displayName
            cell.toolTip = nil
        }
        let icon = NSWorkspace.shared.icon(forFile: node.url.path)
        icon.size = NSSize(width: 16, height: 16)
        cell.imageView?.image = icon
        let row = outlineView.row(forItem: node)
        cell.textField?.textColor = row >= 0 && row == outlineView.selectedRow
            ? (themeAccent ?? .controlAccentColor)
            : .labelColor
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        QuietSelectionRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 24
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        refreshRowTextColors()
    }

    /// A click must not move the selection away from the committed file:
    /// the highlight only follows after navigation actually succeeds
    /// (`setCurrentFile`). Preventing the native selection here is what
    /// stops the O → X → O bounce on file switches. Directories stay
    /// selectable — they have no navigation side effect.
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        if node.isDirectory { return true }
        return node.url.standardizedFileURL == currentFileURL?.standardizedFileURL
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        // Newly-loaded subtree needs its own watcher.
        syncWatchers()
    }
}

private final class DirectoryWatcher {
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                Darwin.close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.source = source
        source.resume()
    }

    /// FS events arrive in bursts (Finder rewrites + xattr updates). Coalesce.
    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func cancel() {
        debounce?.cancel()
        source?.cancel()
        source = nil
    }
}
