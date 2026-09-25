//
//  SidebarViewController.swift
//  md-preview
//

import Cocoa

final class SidebarViewController: NSViewController {

    enum Mode: Int {
        case outline = 0
        case files = 1
    }

    var onSelectHeading: ((Int) -> Void)?
    var onSelectFile: ((URL) -> Void)?
    var onModeChanged: ((Mode) -> Void)?
    /// Bubbled from the navigator's "Add Folder to Navigator" menu entries
    /// up to the window controller, which owns the folder picker.
    var onAddFolderRequested: (() -> Void)?

    private var contentContainer: NSView!
    private var scrollView: NSScrollView!
    private var outlineView: NSOutlineView!
    private var projectNavigator: ProjectNavigatorView!
    private var roots: [TOCNode] = []
    private var titleItem: TitleItem?
    private var lastRenderedMarkdown: String?
    private var lastRenderedFileName: String?
    private var lastRenderMode: MarkdownHTML.RenderMode = .markdown
    /// Shown over the outline when the document renders as plain text,
    /// which has no headings to list.
    private var plainTextOutlineLabel: NSTextField!
    /// The window's mounted navigator roots, explicit and implicit (D1: one
    /// set per window/tab).
    private var rootSet = NavigatorRootSet()
    /// The roots the navigator view has actually been handed; kept in step
    /// with `rootSet` so a lazy TOC-mode open doesn't walk the disk.
    private var loadedRootURLs: [URL] = []
    private var pendingFileURL: URL?

    private static let modeDefaultsKey = "Sidebar.Mode"

    private(set) var currentMode: Mode = {
        Mode(rawValue: UserDefaults.standard.integer(forKey: SidebarViewController.modeDefaultsKey)) ?? .outline
    }()

    private var titleOffset: Int { titleItem == nil ? 0 : 1 }

    override func loadView() {
        let container = NSView()

        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentContainer)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        contentContainer.addSubview(scrollView)

        outlineView = NSOutlineView()
        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.floatsGroupRows = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))
        // Don't grab keyboard focus — leave first responder on the document so
        // arrow / Page keys scroll the preview instead of moving the sidebar
        // selection. Click selects rows via target/action, not via focus.
        outlineView.refusesFirstResponder = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView

        plainTextOutlineLabel = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "No outline for plain text",
            comment: "Sidebar outline empty state for a document rendered as plain text"
        ))
        plainTextOutlineLabel.translatesAutoresizingMaskIntoConstraints = false
        plainTextOutlineLabel.alignment = .center
        plainTextOutlineLabel.textColor = .secondaryLabelColor
        plainTextOutlineLabel.font = .preferredFont(forTextStyle: .callout)
        plainTextOutlineLabel.isHidden = true
        contentContainer.addSubview(plainTextOutlineLabel)

        projectNavigator = ProjectNavigatorView()
        projectNavigator.translatesAutoresizingMaskIntoConstraints = false
        projectNavigator.onSelectFile = { [weak self] url in
            self?.onSelectFile?(url)
        }
        projectNavigator.onAddFolderRequested = { [weak self] in
            self?.onAddFolderRequested?()
        }
        projectNavigator.onRemoveRoot = { [weak self] url in
            self?.removeFolder(url)
        }
        projectNavigator.onAddFolders = { [weak self] urls in
            // Adding folders must not change which document is open, so keep
            // the current file as the selection candidate.
            self?.openFolders(urls, selectedFileURL: self?.pendingFileURL, mode: .add)
        }
        projectNavigator.isExplicitRoot = { [weak self] url in
            let target = url.standardizedFileURL
            return self?.rootSet.roots.first { $0.url == target }?.isExplicit ?? false
        }
        contentContainer.addSubview(projectNavigator)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: container.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            projectNavigator.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            projectNavigator.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            projectNavigator.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            projectNavigator.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            plainTextOutlineLabel.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            plainTextOutlineLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 16),
            plainTextOutlineLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -16)
        ])

        view = container
        applyMode()
    }

    func setMode(_ newMode: Mode) {
        guard newMode != currentMode else { return }
        currentMode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeDefaultsKey)
        if isViewLoaded {
            applyMode()
            if newMode == .files {
                refreshNavigatorIfNeeded()
            }
        }
        onModeChanged?(newMode)
    }

    private func refreshNavigatorIfNeeded() {
        if rootSet.urls != loadedRootURLs {
            loadedRootURLs = rootSet.urls
            projectNavigator.setRoots(rootSet.urls)
        }
        projectNavigator.setCurrentFile(pendingFileURL)
    }

    /// Every folder currently mounted as a root — exposed so a document
    /// search index (PR #408) can index all of them, not just the first.
    var mountedFolderURLs: [URL] { rootSet.urls }

    /// Expanded navigator folders to save for the next launch; `nil` when
    /// the navigator was never built (state unknown).
    var navigatorExpandedFolderPaths: [String]? {
        guard isViewLoaded else { return nil }
        return projectNavigator.expandedFolderPaths
    }

    /// Restores the navigator's expanded folders saved at last quit.
    func restoreNavigatorExpandedFolders(_ paths: Set<String>) {
        loadViewIfNeeded()
        projectNavigator.restoreExpandedFolders(paths)
    }

    private func applyMode() {
        switch currentMode {
        case .outline:
            scrollView.isHidden = false
            projectNavigator.isHidden = true
        case .files:
            scrollView.isHidden = true
            projectNavigator.isHidden = false
        }
        plainTextOutlineLabel.isHidden = currentMode != .outline || lastRenderMode != .plainText
    }

    func display(markdown: String,
                 fileName: String,
                 fileURL: URL?,
                 renderMode: MarkdownHTML.RenderMode = .markdown) {
        loadViewIfNeeded()
        setOpenFileURL(fileURL)

        guard markdown != lastRenderedMarkdown
                || fileName != lastRenderedFileName
                || renderMode != lastRenderMode else { return }
        lastRenderedMarkdown = markdown
        lastRenderedFileName = fileName
        lastRenderMode = renderMode
        applyMode()
        if renderMode == .plainText {
            // Plain text has no headings; the empty state says why.
            titleItem = nil
            roots = []
        } else {
            titleItem = fileName.isEmpty ? nil : TitleItem(title: fileName)
            roots = MarkdownTOC.parse(markdown).map(TOCNode.init)
        }
        outlineView.reloadData()
        for root in roots {
            outlineView.expandItem(root, expandChildren: true)
        }
        outlineView.deselectAll(nil)
    }

    /// Update the tracked file URL after a rename — keeps the navigator
    /// selection on the open file without rebuilding the TOC.
    func openFileURLDidChange(_ newURL: URL) {
        loadViewIfNeeded()
        setOpenFileURL(newURL)
    }

    /// Mounts an explicitly chosen folder as the Project Navigator root,
    /// replacing whatever was there. Kept for callers that open a single
    /// folder; delegates to `openFolders`.
    func openFolder(_ folderURL: URL, selectedFileURL: URL?) {
        openFolders([folderURL], selectedFileURL: selectedFileURL, mode: .replace)
    }

    /// Mounts one or more folders as navigator roots. `.replace` swaps the
    /// whole set (⌘O, Finder, `mdp`, URL scheme); `.add` appends (Add Folder
    /// to Navigator…). If the current document is inside one of the
    /// resulting roots, keep it selected.
    func openFolders(_ folderURLs: [URL], selectedFileURL: URL?, mode: FolderMountMode) {
        loadViewIfNeeded()
        rootSet.mount(folderURLs, mode: mode)
        if let selectedFileURL, rootSet.containingRoot(for: selectedFileURL) != nil {
            pendingFileURL = selectedFileURL.standardizedFileURL
        } else {
            pendingFileURL = nil
        }
        if currentMode == .files {
            refreshNavigatorIfNeeded()
        }
    }

    /// Removes a root (D7). Leaves the open document untouched; only drops
    /// the navigator selection if the file is no longer under any root.
    func removeFolder(_ folderURL: URL) {
        loadViewIfNeeded()
        guard rootSet.remove(folderURL) else { return }
        if let file = pendingFileURL, rootSet.containingRoot(for: file) == nil {
            pendingFileURL = nil
        }
        if currentMode == .files {
            refreshNavigatorIfNeeded()
        }
    }

    /// Defers folder enumeration until the user is actually in the
    /// navigator (saves disk walks on every TOC-mode open). Keeps the
    /// existing root when the new file is a descendant; otherwise follows
    /// the file's parent so an unrelated File → Open updates the tree. A set
    /// with explicit roots is left alone (D3).
    private func setOpenFileURL(_ fileURL: URL?) {
        rootSet.accommodate(openFileURL: fileURL)
        pendingFileURL = fileURL?.standardizedFileURL
        if currentMode == .files {
            refreshNavigatorIfNeeded()
        }
    }

    /// Highlights the matching TOC row. Selecting via the API doesn't
    /// dispatch the outline's action, so this won't loop back into
    /// `onSelectHeading`. We don't `scrollRowToVisible` — yanking the
    /// sidebar while the user scrolls the doc feels jumpy.
    func setActiveHeading(_ headingID: Int?) {
        loadViewIfNeeded()
        guard let headingID,
              let node = findNode(withID: headingID, in: roots) else {
            outlineView.deselectAll(nil)
            return
        }
        for ancestor in ancestors(of: node, in: roots) {
            outlineView.expandItem(ancestor)
        }
        let row = outlineView.row(forItem: node)
        guard row >= 0, outlineView.selectedRow != row else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row),
                                     byExtendingSelection: false)
        refreshRowTextColors()
    }

    /// Rows keep concrete colors for the scheme they were styled under;
    /// re-style them when the effective appearance flips (explicit switch
    /// or an Automatic system transition).
    override func viewDidLayout() {
        super.viewDidLayout()
        let appearanceName = view.effectiveAppearance.name
        if appearanceName != lastRowColorAppearance {
            lastRowColorAppearance = appearanceName
            refreshRowTextColors()
        }
    }

    private var lastRowColorAppearance: NSAppearance.Name?

    /// Theme accent for the active TOC row — the link color, so the
    /// sidebar's highlight matches the page's primary color. Nil without a
    /// link override; the system accent then applies.
    private var themeAccent: NSColor? {
        let isDark = view.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return ThemeColorsSetting.current.color(.linkColor, isDark ? .dark : .light)
    }

    /// Re-applies text colors to visible rows: the selected heading gets
    /// the theme accent (or the system accent), everything else the plain
    /// label colors.
    func refreshRowTextColors() {
        guard isViewLoaded else { return }
        view.needsDisplay = true
        projectNavigator?.refreshRowTextColors()
        let accent = themeAccent ?? .controlAccentColor
        let selected = outlineView.selectedRow
        for row in 0..<outlineView.numberOfRows {
            guard let cell = outlineView.view(
                atColumn: 0, row: row, makeIfNecessary: false
            ) as? NSTableCellView, let textField = cell.textField else { continue }
            if cell.identifier?.rawValue == "TitleCell" {
                textField.textColor = .secondaryLabelColor
                continue
            }
            textField.textColor = row == selected ? accent : .labelColor
        }
    }

    private func findNode(withID id: Int, in nodes: [TOCNode]) -> TOCNode? {
        for node in nodes {
            if node.headingID == id { return node }
            if let hit = findNode(withID: id, in: node.children) { return hit }
        }
        return nil
    }

    private func ancestors(of target: TOCNode, in nodes: [TOCNode]) -> [TOCNode] {
        var path: [TOCNode] = []
        func walk(_ node: TOCNode) -> Bool {
            if node === target { return true }
            for child in node.children {
                path.append(node)
                if walk(child) { return true }
                path.removeLast()
            }
            return false
        }
        for root in nodes {
            path = []
            if walk(root) { return path }
        }
        return []
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? TOCNode else { return }
        onSelectHeading?(node.headingID)
    }
}

/// Row view whose selection never draws emphasized. While the mouse is
/// down, AppKit emphasizes the pressed row and fills the selection pill
/// with the system accent color — which fights the theme. Suppressing the
/// emphasized state keeps the quiet source-list fill in every state; the
/// theme accent lives in the row's text color instead. Stateless, so it
/// is created directly rather than recycled. Shared with ProjectNavigatorView.
final class QuietSelectionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

private final class TitleItem {
    let title: String
    init(title: String) { self.title = title }
}

final class TOCNode {
    let headingID: Int
    let level: Int
    let title: String
    let children: [TOCNode]

    init(_ item: TOCItem) {
        self.headingID = item.id
        self.level = item.level
        self.title = item.title
        self.children = item.children.map(TOCNode.init)
    }
}

extension SidebarViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? TOCNode { return node.children.count }
        return roots.count + titleOffset
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? TOCNode { return node.children[index] }
        if let titleItem, index == 0 { return titleItem }
        return roots[index - titleOffset]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? TOCNode else { return false }
        return !node.children.isEmpty
    }
}

extension SidebarViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        if let titleItem = item as? TitleItem {
            return titleCell(for: titleItem, in: outlineView)
        }
        guard let node = item as? TOCNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("TOCCell")
        let cell: NSTableCellView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.cell?.usesSingleLineMode = true
            textField.cell?.truncatesLastVisibleLine = true
            textField.maximumNumberOfLines = 1
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = node.title
        let row = outlineView.row(forItem: node)
        cell.textField?.textColor = row >= 0 && row == outlineView.selectedRow
            ? (themeAccent ?? .controlAccentColor)
            : .labelColor
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        QuietSelectionRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return item is TOCNode
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        refreshRowTextColors()
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 30
    }

    private func titleCell(for titleItem: TitleItem, in outlineView: NSOutlineView) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("TitleCell")
        let cell: NSTableCellView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            textField.textColor = .secondaryLabelColor
            textField.lineBreakMode = .byTruncatingMiddle
            textField.cell?.usesSingleLineMode = true
            textField.maximumNumberOfLines = 1
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 8),
                textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4)
            ])
        }
        cell.textField?.stringValue = titleItem.title
        return cell
    }
}
