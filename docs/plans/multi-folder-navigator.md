# Multiple folders in one window — feasibility and implementation plan

Status: **plan only, nothing implemented.** Written against `main` at
`719f2dd` (post-0.0.59).

## 1. Verdict

**Feasible, moderate effort, no sandbox or entitlement changes.** The Project
Navigator is already per-window, lazily enumerated, and watched per directory
with a `[URL: DirectoryWatcher]` dictionary. The "one root" assumption lives in
exactly three places, all internal:

| Where | What is single-rooted today |
| --- | --- |
| `md-preview/Features/Sidebar/ProjectNavigatorView.swift` | `private var rootNode: FileNode?` (line 58); `setRoot(_ url: URL?)` (118); data source returns `rootNode == nil ? 0 : 1` top-level rows (452–461); `setCurrentFile` / `collectPath` walk one root (226–277). |
| `md-preview/Features/Sidebar/SidebarViewController.swift` | `loadedFolderURL` / `pendingFolderURL: URL?` (27–28); `openFolder(_:selectedFileURL:)` (162–173); `setOpenFileURL` replaces the root whenever the displayed file is outside it (179–190). |
| `md-preview/Document/MarkdownDocument.swift` | `folderStorage: Mutex<URL?>` (12) for the NSDocument-restoration path into a folder window (40–62). |

Everything above the sidebar (`MainSplitViewController.openFolder`,
`DocumentWindowController.openFolder`, `AppDelegate.openFolder`,
`MarkdownDocumentController.openDocument(withContentsOf:)`) just forwards a
single URL, so the change is a widening of one code path, not a redesign.

Why it is cheap:

- **Sandbox is a non-issue.** `md-preview.entitlements` already carries the
  read-only `temporary-exception.files.absolute-path` for `/` (lines 23–27),
  which is what lets the navigator enumerate sibling folders without Powerbox
  prompts today. Additional roots need no bookmarks and no entitlement edits
  (AGENTS.md forbids broadening them anyway).
- **Watching already scales.** `syncWatchers()` diffs a `Set<URL>` of loaded
  directories against `watchers`; it only needs to be fed nodes from N roots
  instead of one. Overlapping roots (`/proj` and `/proj/docs`) collapse to one
  watcher per directory because the dictionary is keyed by URL.
- **New Swift files need no `project.pbxproj` edit** — `md-preview/` is a
  `PBXFileSystemSynchronizedRootGroup`, so no signing-hunk risk.
- **A latent bug gets fixed for free.** `AppDelegate.application(_:open:)`
  (lines 150–187) loops over URLs and calls `openFolder(url)` per directory,
  and `DocumentWindowController.openFolder` replaces the root each time. So
  `mdp docs guides` (→ `open -b doc.md-preview docs guides`) shows only the
  last folder today. With multiple roots, the batch mounts every folder.

Why it is not trivial:

- **A behaviour policy must be chosen** for "the open file is outside every
  root" (today: silently swap the root to the file's parent). Section 3
  recommends a rule and calls out the alternatives.
- **NSOutlineView identity.** Adding/removing a root must not collapse the
  other trees; use `insertItems(at:inParent:withAnimation:)` /
  `removeItems(...)` with `inParent: nil` rather than `reloadData()`.
- **Two open panels** (`MarkdownDocumentController.beginOpenPanel` and
  `DocumentWindowController.makeOpenPanel`) both set
  `allowsMultipleSelection = false`; multi-select is a natural companion but
  widens scope to multi-file opens too (Phase 2).

### Coordination risks — check before starting

1. **Issue #335 "Should I build obsidian style folder management?"** — the
   maintainer (@mfauzaan) posted on 2026‑09‑21: *"Im still working on it, will
   be part of the app when its done."* That work almost certainly touches the
   same navigator surface. Confirm scope split (or hand this plan over) before
   writing code, or the PR risks being superseded.
2. **PR #408 "Search for Document" (open)** introduces `ProjectFileIndex`
   scoped to "the folder the sidebar has mounted" and moves
   `markdownExtensions` out of `FileNode`. Whichever lands second must adopt
   the other's model: this plan exposes `mountedFolderURLs: [URL]` from the
   sidebar so the palette indexes every root.

## 2. Current flow (for reference)

```
Finder / CLI / md-preview:// ──▶ AppDelegate.application(_:open:)
        │  isExistingDirectory                       │ file
        ▼                                            ▼
AppDelegate.openFolder(url)              NSDocumentController.openDocument(withContentsOf:)
        │ active window? else new MarkdownDocument       (MarkdownDocumentController intercepts
        ▼                                                 directories → AppDelegate.openFolder)
DocumentWindowController.openFolder(url)      ← also from ⌘O sheet (promptForDocument)
        │ title = folder name if no file          and present(url:) when a link targets a directory
        ▼
MainSplitViewController.openFolder(url, selectedFileURL:)   → setSidebarMode(.files), showSidebar()
        ▼
SidebarViewController.openFolder(url, selectedFileURL:)     → pendingFolderURL = url
        ▼ (only when mode == .files)                          refreshNavigatorIfNeeded()
ProjectNavigatorView.setRoot(url)                          → rootNode, reloadData, expand, syncWatchers
```

Per-file display (`MainSplitViewController.display` →
`SidebarViewController.display` → `setOpenFileURL`) re-derives the root from
the file's parent unless the file is already inside `loadedFolderURL`.

## 3. Design decisions (recommended defaults)

| # | Decision | Recommendation | Alternatives considered |
| --- | --- | --- | --- |
| D1 | Scope of roots | **Per window/tab**, matching today's per-window sidebar. Tabs in a group do not share roots. | App-wide workspace — larger change, conflicts with per-document windows. |
| D2 | How folders are added | **Explicit "Add Folder to Navigator…"** (File menu, navigator context menu, empty-area context menu) with *add* semantics; existing folder-open entry points (⌘O single folder, Finder, `mdp dir`, URL scheme) keep **replace** semantics for backward compatibility. A single `application(_:open:)` batch with several folders mounts them all (replace current roots with the batch). | Make every folder open additive (surprising accumulation); modifier keys (undiscoverable). |
| D3 | File displayed outside every root | Roots are tagged **explicit** (user mounted) or **implicit** (derived from the open file's parent). If every root is implicit (i.e. the single auto-root), keep today's behaviour and swap it to the new parent. If any explicit root exists, **keep the roots and deselect** — do not silently destroy a deliberately assembled set, do not auto-add. | Always add the parent as another root (clutter on every cross-folder link); always replace (destroys the workspace). |
| D4 | Duplicate / overlapping roots | Same standardized path twice → no-op. Ancestor/descendant overlap → allowed (Xcode allows it); watchers dedupe by URL; `setCurrentFile` selects the first containing root in order. | Reject overlap (more logic, less useful). |
| D5 | Root row labels | `lastPathComponent`; when two roots share a name, append the shortest distinguishing parent suffix — extract the algorithm already in `AppDelegate.menuNeedsUpdate` (lines 1253–1281, PR #356) into a shared pure helper. Tooltip = full path. | Always show full path (noisy). |
| D6 | Root row styling | Regular folder rows (same cell, click toggles expand/collapse as #393). Roots are auto-expanded when mounted. | Source-list group rows (`isGroupItem`) — changes the click behaviour and the current look; revisit later if the maintainer wants Xcode-style headers. |
| D7 | Removing a root | Context menu **"Remove from Navigator"** on root rows (explicit roots only). Removing the last root leaves an empty navigator with an "Add Folder…" placeholder (Phase 2). Does not close the open document. | Hide when only one root — inconsistent. |
| D8 | Window title for folder-only windows | 1 root → folder name (today). >1 → first root's name (keep simple; window titles are for documents, and any open file overrides the title anyway). | "%d Folders" localized string — adds two strings for little value; can be added later. |
| D9 | Persistence across relaunch | **Out of scope** for this plan (nothing about roots persists today; folder windows are `MarkdownDocument`s without a `fileURL`, so `NSDocument` restoration does not carry them). Listed as a follow-up. | `encodeRestorableState` on the window (viable later). |
| D10 | Model location | Pure-Foundation `NavigatorRootSet` in `md-preview/Features/Sidebar/`, symlinked into `tests/swift-tests/Sources/MarkdownHelpers/` like `TabOpeningPolicy.swift`, so policy is unit-tested without AppKit. | Keep the logic inside the view controller (untestable in the SPM package). |

## 4. Implementation plan

### Phase 0 — Model + tests (no UI change)

**New file** `md-preview/Features/Sidebar/NavigatorRootSet.swift` (Foundation only):

```swift
struct NavigatorRoot: Equatable {
    let url: URL            // standardizedFileURL
    let isExplicit: Bool    // mounted by the user (folder open / Add Folder)
}

enum FolderMountMode { case replace, add }

struct NavigatorRootSet: Equatable {
    private(set) var roots: [NavigatorRoot] = []
    var urls: [URL] { roots.map(\.url) }
    var hasExplicitRoots: Bool

    /// Dedupes by standardized path; `.replace` drops every existing root
    /// (explicit and implicit). Returns true when anything changed.
    @discardableResult mutating func mount(_ folderURLs: [URL], mode: FolderMountMode) -> Bool
    @discardableResult mutating func remove(_ folderURL: URL) -> Bool

    /// D3: called on every display(file:). Implicit-only sets follow the
    /// file's parent; sets with explicit roots are left alone.
    @discardableResult mutating func accommodate(openFileURL: URL?) -> Bool

    func containingRoot(for fileURL: URL) -> NavigatorRoot?
}

enum PathDisambiguation {
    /// Moved from AppDelegate.menuNeedsUpdate (PR #356) so root labels and
    /// the Window menu share one algorithm.
    static func labels(for urls: [URL]) -> [URL: String]
}
```

Symlink: `tests/swift-tests/Sources/MarkdownHelpers/NavigatorRootSet.swift ->
../../../../md-preview/Features/Sidebar/NavigatorRootSet.swift`.

**New test** `tests/swift-tests/Tests/MarkdownHelpersTests/NavigatorRootSetTests.swift`:

- mount replace vs add; duplicate path is a no-op; order preserved.
- overlapping ancestor/descendant roots both retained.
- `accommodate`: implicit-only set follows an unrelated file; file inside a
  root leaves the set untouched; explicit set stays put for an outside file
  (returns `false`); `nil` file (untitled) leaves explicit roots alone.
- `containingRoot` picks the first containing root in order.
- `PathDisambiguation.labels` reproduces the #356 cases (`README.md (proj)`,
  `README.md (proj/child)`), plus identical folder names in different parents.

Refactor `AppDelegate.menuNeedsUpdate` to call `PathDisambiguation.labels`
(behaviour-preserving; existing Window-menu behaviour is the regression check).

### Phase 1 — Multi-root navigator + Add/Remove (the feature)

**`ProjectNavigatorView.swift`**

- `rootNode: FileNode?` → `rootNodes: [FileNode]`; `rootLabels: [URL: String]`.
- `setRoot(_:)` → `setRoots(_ urls: [URL])`: reuse the existing `FileNode`
  for URLs that were already mounted (preserves child caches and expansion),
  create nodes for new URLs, then apply the diff with
  `insertItems(at:inParent:nil)` / `removeItems(at:inParent:nil)` (animated
  `.slideDown` / `.effectFade`), expand new roots, `syncWatchers()`. Fall back
  to `reloadData()` + `reExpand` only if ordering changes.
- Data source: `numberOfChildrenOfItem(nil)` → `rootNodes.count`;
  `child(index, ofItem: nil)` → `rootNodes[index]`.
- `collectLoadedDirectories`, `refreshTree`, `invalidateCaches`, `reExpand`:
  iterate `rootNodes`.
- `setCurrentFile`: iterate roots that contain the target (`isDescendantOrSame`),
  first hit wins (D4). Keep the stale-cache retry.
- `viewFor`: for root nodes use `rootLabels[url] ?? displayName` and set
  `cell.toolTip = node.url.path`.
- `menuNeedsUpdate`:
  - `clickedRow < 0` (empty area): **Add Folder…** only.
  - root row: Show in Finder, **Remove from Navigator** (explicit roots only —
    navigator asks `isExplicitRoot: (URL) -> Bool` callback), separator,
    **Add Folder…**, Copy Path.
  - non-root rows unchanged.
- New callbacks alongside `onSelectFile`: `onAddFolderRequested: (() -> Void)?`,
  `onRemoveRoot: ((URL) -> Void)?`, `isExplicitRoot: ((URL) -> Bool)?`.
- Keep `shouldSelectItem` as is (directories selectable, files only when current).

**`SidebarViewController.swift`**

- Replace `loadedFolderURL` / `pendingFolderURL` with
  `private var rootSet = NavigatorRootSet()` and `private var loadedRootURLs: [URL] = []`.
- `openFolder(_:selectedFileURL:)` → `openFolders(_ urls: [URL], selectedFileURL: URL?, mode: FolderMountMode)`
  (keep the old signature as a one-liner for callers). Mount with the mode,
  select the file if any root contains it.
- `setOpenFileURL` → `rootSet.accommodate(openFileURL:)` (D3), then
  `refreshNavigatorIfNeeded()` when in `.files` mode.
- `refreshNavigatorIfNeeded()`: `if rootSet.urls != loadedRootURLs { projectNavigator.setRoots(rootSet.urls) }` then `setCurrentFile`.
- New: `func removeFolder(_ url: URL)`, `var mountedFolderURLs: [URL]`
  (for PR #408), wire the three navigator callbacks.

**`MainSplitViewController.swift`**

- `openFolder(_:selectedFileURL:)` → `openFolders(_:selectedFileURL:mode:)`
  (still switches to `.files` and shows the sidebar), plus
  `removeFolder(_:)`, `mountedFolderURLs`, and an `onAddFolderRequested`
  passthrough to the window controller.

**`DocumentWindowController+DocumentOpening.swift`**

- `openFolder(_ url:)` → `openFolders(_ urls: [URL], mode: FolderMountMode = .replace)`;
  title rule per D8 (only when `currentFileURL == nil`).
- New `@objc func addFolderToNavigator(_ sender: Any?)`: `NSOpenPanel` with
  `canChooseFiles = false`, `canChooseDirectories = true`,
  `allowsMultipleSelection = true`, message *"Choose folders to add to the
  Project Navigator"*, `beginSheetModal` → `openFolders(panel.urls, mode: .add)`.
- New `func removeFolderFromNavigator(_ url: URL)` → split → sidebar.
- `promptForDocument` keeps single selection in Phase 1 (folder → `.replace`).

**`DocumentWindowController.swift`** — `present(url:preservingEditMode:intent:fragment:)`
directory branch (409–415) keeps calling the replace-mode convenience; a link
to a directory behaves exactly as today.

**`AppDelegate.swift`**

- `application(_:open:)`: collect directories from the batch first, then call
  `openFolders(directories)` **once** (fixes `mdp a b`), then open files as
  today.
- `openFolder(_:)` → `openFolders(_ urls: [URL])` (same active-window-or-new-
  document logic; `MarkdownDocument.makeWindowControllers` still mounts its
  single `folderURL` — leave `folderStorage` alone, it is a restoration safety
  net that never sees a batch).
- Install **File ▸ Add Folder to Navigator…** next to *Open…* using the
  `installNewTabMenuItem` pattern (nil target → responder chain →
  `DocumentWindowController.addFolderToNavigator(_:)`, auto-disabled with no
  document window). No key equivalent (⌥⌘O is free but undiscoverable; leave
  unassigned unless the maintainer wants one).
- `MarkdownDocumentController.openDocument(withContentsOf:)` keeps
  intercepting a single directory → `appDelegate.openFolders([url])`.

**Strings** (`en.lproj` + `zh-Hans.lproj/Localizable.strings`):

| Key | zh-Hans draft (needs native review, cf. #351) |
| --- | --- |
| `Add Folder to Navigator…` | `将文件夹添加到项目导航器…` |
| `Remove from Navigator` | `从项目导航器中移除` |
| `Choose folders to add to the Project Navigator` | `选择要添加到项目导航器的文件夹` |

**Docs (same PR — AGENTS.md rule):**

- `README.md` line 70 *File navigator* bullet: add that several folders can be
  shown in one window via *File ▸ Add Folder to Navigator…* or by passing
  several folders to `mdp` / the open panel, and that root rows can be removed.
- `README.md` line 79 *Command line tools*: mention `mdp docs guides` opens
  both folders in one window.
- `CHANGELOG.md` `[Unreleased]` → *Added* entry per the
  `changelog-maintenance` skill; credit issue reporters if an issue is filed.

### Phase 2 — Open-panel multi-select and polish

- `allowsMultipleSelection = true` in both panels. Partition `panel.urls`:
  directories → one `openFolders(dirs, mode: .replace)` in the sheet's window;
  files → existing per-file path (`openInNewTab` / `openDocumentWindow`),
  which already honours `TabOpeningPolicy`. For the app-level ⌘O
  (`MainMenu.xib` targets `AppDelegate.openDocument` → `NSDocumentController.openDocument(_:)`,
  which calls `openDocument(withContentsOf:)` **per URL**), override
  `MarkdownDocumentController.openDocument(_ sender:)` to run the configured
  panel via `beginOpenPanel(_:forTypes:)` and dispatch the batch through one
  `AppDelegate.open(urls:)` — otherwise two selected folders arrive as two
  replace calls and the second wins again.
- Empty state in `.files` mode with no roots: centered secondary label
  *"No folder in the navigator"* + *Add Folder…* button (currently a blank
  outline).
- Drag & drop: register `outlineView.registerForDraggedTypes([.fileURL])`,
  accept directory drops on the empty area/top level → `openFolders(_, mode: .add)`.
- Optional D8 refinement: localized `"%d Folders"` title when more than one
  root and no file is open.

### Phase 3 — Follow-ups (separate PRs)

- Persist roots per window across relaunch (`encodeRestorableState` /
  `restoreState` on `DocumentWindowController`; `applicationSupportsSecureRestorableState`
  is already `true`).
- Folder entries in *Open Recent* (`noteNewRecentDocumentURL` is file-only today).
- Root-header styling (group rows / "Show|Hide"), keyboard removal
  (`refusesFirstResponder = true` currently keeps focus off the outline, so
  Delete would need a design decision).
- Hook PR #408's `ProjectFileIndex` to `mountedFolderURLs`.

## 5. Verification

Per AGENTS.md (Swift changes → tests + build; visible behaviour → runtime check):

```bash
swift test --package-path tests/swift-tests          # NavigatorRootSetTests + existing suites
xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Debug build CODE_SIGNING_ALLOWED=NO
git diff -- md-preview.xcodeproj/project.pbxproj     # must be empty (DEVELOPMENT_TEAM guard)
grep -rn "navigator\|Project Navigator\|mdp \." README.md samples/ tests/fixtures/ docs/   # stale-claim sweep
```

Runtime checklist (Debug build, two fixture folders `A/` and `B/`, each with
`README.md` and a subfolder):

1. ⌘O → `A` → navigator shows `A` expanded (unchanged behaviour).
2. File ▸ Add Folder to Navigator… → `B` → `A` keeps its expansion; `B`
   appears expanded below it; both watched (create `B/new.md` in Finder → row
   appears).
3. Click `B/README.md` → opens, row highlighted under `B`; `A` untouched.
4. Follow a link from `B/README.md` to a file outside `A` and `B` → document
   opens, navigator keeps `A`+`B`, no row selected (D3).
5. Fresh window, open `~/x/README.md` (implicit root `x`) → then open
   `~/y/notes.md` in the same window → root swaps to `y` (today's behaviour
   preserved).
6. Right-click `B` root → Remove from Navigator → only `A` remains; the open
   document stays open. Remove `A` → empty navigator (Phase 2: placeholder).
7. Add `A` again → no duplicate; add `A/sub` → both `A` and `A/sub` rows
   exist; editing a file under `A/sub` refreshes both.
8. Quit app; `mdp A B` from a shell → one window with both roots (fixes the
   last-folder-wins behaviour).
9. Two roots named `docs` in different parents → labels disambiguate
   (`docs (projA)`, `docs (projB)`), tooltips show full paths; Window menu
   duplicate-name labels unchanged after the helper extraction.
10. Untitled document (File ▸ New) with explicit roots present → roots remain;
    saving the untitled file inside a root selects it.
11. Tabs: roots added in one tab do not appear in another tab (D1).
12. zh-Hans run (`-AppleLanguages '(zh-Hans)'`) shows the new strings.

## 6. Effort

| Phase | Estimate |
| --- | --- |
| 0 — model, helper extraction, tests | ~half a day |
| 1 — multi-root view, add/remove, menu, batch open, docs | ~1–1.5 days incl. runtime verification |
| 2 — multi-select panels, empty state, drag & drop | ~1 day |

## 7. Open questions for the maintainer

1. Does this collide with the #335 folder-management work in progress? If so,
   should this plan be folded into that effort instead of a standalone PR?
2. D2: should ⌘O with a folder ever *add* rather than replace (e.g. when the
   window already has explicit roots)?
3. D6: plain rows (recommended) or Xcode-style group headers for roots?
4. Any key equivalent for *Add Folder to Navigator…*?
