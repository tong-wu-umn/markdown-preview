# Bug: preview stays blank after clicking a file in the navigator (crash in Open Recent)

Status: **fixed** 2026-10-16 (see "Fix" below). Investigated 2026-10-16 on
macOS 26.7.1 (25G241), build at commit `d014e30` (installed as
`/Applications/Markdown Preview (dev).app`).

## Symptom

After the app is relaunched, it restores the last folders ("Reopen last folders
at launch"). Clicking a Markdown file in the Project Navigator changes the window
title to the file name, but the preview stays blank. It looked like a rendering
bug.

## What is actually happening

The app **crashes**. The title changes first, then the process dies before the
preview is drawn. For a moment the window stays on screen, so it looks like a
blank preview. macOS then shows "Markdown Preview quit unexpectedly".

Every crash report has the same faulting thread:

```
Thread "Document Recents"   EXC_BAD_ACCESS (SIGSEGV) at 0x0
  LaunchServices  initkLSSharedFileListRecentDocumentItems()
  LaunchServices  _LSGetRecentItemsSharedList(short, unsigned int**)
  LaunchServices  _LSGetRecentItemCount
  AppKit          -[_NSRecentItemsMenuController _preferredRecentsLimit]
  AppKit          -[_NSDocumentRecentItemsMenuController maximumRecentDocumentCount]
  AppKit          -[_NSRecentItemsMenuController _notePendingRecentDocumentURLsForKey:documentsSnapshot:]
  Foundation      NSBlockOperation main
  libdispatch     …
```

The trigger is
`NSDocumentController.shared.noteNewRecentDocumentURL(url)`. When a file is
opened, AppKit updates the Open Recent list later, on a background queue. That
update reaches LaunchServices, which dereferences a null pointer.

Where the app calls `noteNewRecentDocumentURL`:

| File | Line | Path |
| --- | --- | --- |
| `md-preview/Document/DocumentWindowController.swift` | 393 | `display(markdown:fileURL:)` |
| `md-preview/Document/DocumentWindowController.swift` | 451 | `present(url:…)`, the navigator click path |
| `md-preview/Document/DocumentWindowController.swift` | 550 | rename / move of the open file |
| `md-preview/Document/DocumentWindowController+EditSession.swift` | 125 | save from the editor |

Crash reports (`~/Library/Logs/DiagnosticReports/`):

- `Markdown Preview-2026-10-09-144032.ips`, `…-144043.ips`: right after the Oct 9 install
- `Markdown Preview-2026-10-16-110306.ips`: during quit (AppleScript `quit`)
- `Markdown Preview-2026-10-16-111225.ips`: after clicking `AGENTS.md` in the navigator
- `Markdown Preview-2026-10-16-111542.ips`: same, after re-signing the app (see below)

All five have the same stack.

## Reproduction

1. Mount a folder in the navigator, for example `~/Downloads/projects`, and quit.
2. Launch the app with `open "/Applications/Markdown Preview (dev).app"`.
   It restores the folder in a folder-only window.
3. Click any `.md` file in the navigator.
4. The title changes, the preview stays blank, and a new crash report appears.

Reproduced 3 out of 3 times when the app was launched through LaunchServices
(`open` / Finder / Dock).

## Checks done and results

| Check | Result |
| --- | --- |
| The file itself (`drug_cold_start_foundation_system/AGENTS.md`, 14.5 KB, UTF-8) | Fine. It renders when opened with `open -a … AGENTS.md`. |
| Descriptor exhaustion, the earlier navigator bug (fa2ec30 / 0cf4bde) | Ruled out. The running process had about 60 open fds and the main thread was idle (`sample`). |
| Installed copy older than the source | Ruled out. `Markdown Preview.debug.dylib` in `/Applications` is byte-identical to a fresh Debug build of `d014e30`. Only `DTXcode*` in Info.plist differs. |
| Fresh Debug build started directly from the shell (`…/Contents/MacOS/Markdown Preview`, with `OS_ACTIVITY_DT_MODE=YES`) | **No crash.** Clicking `CONTRIBUTING.md` then `AGENTS.md` rendered both. That is only two clicks, so not conclusive. |
| Minimal test app (`/tmp/rt/RT.app`) calling `noteNewRecentDocumentURL`, started from the shell and with `open -W` | No crash either way. So this is **not** a general macOS 26.7.1 problem. Something specific to Markdown Preview triggers it. |
| Is the dev app sandboxed? | No. It is built with `CODE_SIGNING_ALLOWED=NO`, so it is only linker-signed (`Identifier=Markdown Preview`, `Info.plist=not bound`) and has no container. Its recents go to `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/doc.md-preview.dev.sfl4`, which was written successfully at 11:09 by the shell-launched run. |
| Proper ad-hoc re-sign (`codesign --force --deep --sign -`, giving `Identifier=doc.md-preview.dev`) | **Still crashes.** Signing is not the cause. |
| Launch with a minimal environment (`env -i …`) to see whether the inherited shell environment explains the shell-vs-LaunchServices difference | **Not run.** The tool harness blocked the command. Still open. |

### Side observation (separate issue, maybe a symptom)

Twice, right after a LaunchServices launch, the restored window showed the
navigator root with **no children drawn**, and the preview was empty.
Accessibility queries showed the outline rows did exist. Resizing the window
made them draw. So it is a missing redraw, not a failed folder read: no
`Folder read failed` log was emitted. This was not investigated further. It may
come from restoring the window frame (`NSWindow Frame MainWindow` holds a
macOS tiling state) during session restore.

## Underlying cause: running out of file descriptors

This explains why only Markdown Preview was affected, and only when
LaunchServices launched it.

After the Open Recent fix, mounting `~/Downloads/projects` and clicking a file
showed "The operation couldn\U2019t be completed. (NSCocoaErrorDomain error
256.)". The literal `\U2019` means Foundation could not load its own
localized strings. At that point the process held **250 directory
descriptors**.

- **The 256 limit.** An app launched by LaunchServices starts with a soft
  limit of **256** open files (`launchctl limit maxfiles`). A shell launch
  inherits the shell's limit, here about 1 million. That is why the
  shell-launched runs never failed.
- **Where the descriptors went.** The Project Navigator opens one
  `DirectoryWatcher` (one `O_EVTONLY` descriptor) per watched folder. It
  watched every folder that appeared in any loaded listing, not only folders
  whose own listing was loaded. Checking whether a row can expand loads that
  folder's listing, so every visible folder and each of its subfolders got a
  watcher. In the leaked set, 67 were top-level folders of `projects` and 171
  were their unopened subfolders. A second window on the same tree doubles
  the count.
- **What fails at the limit.** Once the process is out of descriptors,
  opening the clicked document fails with error 256. LaunchServices'
  recent-documents code is very likely the same failure: it fails to open its
  list and then dereferences null. This explains why the crash needed a
  restored large tree.

The crash-to-limit link was not reproduced directly. An old build at
soft limit 256, pushed to exactly 256 descriptors, did not crash on click
before testing was stopped.

Two changes address this:

- `md-preview/Helpers/FileDescriptorLimit.swift` raises the soft limit to
  10,240 (`OPEN_MAX`, capped by the hard limit). `AppDelegate` calls it in
  `applicationWillFinishLaunching`, before session restore mounts folders.
- `ProjectNavigatorView.collectLoadedDirectories` now watches only folders
  whose listing is loaded. When layout loads a listing outside a refresh, a
  watcher sync is scheduled for it. With the same expanded folders, the count
  fell from 256 to 188.

Verified with a LaunchServices launch: two windows on `~/Downloads/projects`
with most folders expanded, pushed to **350 open descriptors**. Opening
`README.md` rendered it (108 accessibility elements in the preview). Quit
exited cleanly, and no `.ips` was written.

Still open: whether a signed Release build behaves the same. It should,
because the limit comes from LaunchServices, not from signing.

## Fix: Open Recent

The preferred option from the investigation: the app keeps its own recent-files
list and never hands a recent document to AppKit or LaunchServices. With the
descriptor fix in place this is defense in depth rather than the cure.

- `md-preview/Preferences/RecentDocumentsList.swift` stores the list as plain
  paths in `UserDefaults` (`MarkdownPreview.recentDocumentPaths`): most recent
  first, no duplicates, at most 10. Missing files are hidden but kept. It uses
  paths rather than bookmarks for the same reason `SessionRestoreSetting` does:
  the app already has read-only access to the whole filesystem.
- `MarkdownDocumentController` overrides `noteNewRecentDocumentURL(_:)`,
  `recentDocumentURLs`, `maximumRecentDocumentCount` and
  `clearRecentDocuments(_:)`, and none of them call `super`. The four call sites
  in the table above, and AppKit's own `noteNewRecentDocument(_:)`, all go
  through `noteNewRecentDocumentURL(_:)`.
- In `MainMenu.xib`, *Open Recent* is a plain menu, no longer
  `systemMenu="recentDocuments"`. Its delegate is the document controller, which
  rebuilds the menu each time it opens. *Clear Menu* sends
  `clearRecentDocumentList:` instead of `clearRecentDocuments:`, so AppKit does
  not take the menu over and run its own menu controller. That controller calls
  `_LSGetRecentItemCount`, the function that crashed.

Trade-offs: the old system list is not migrated, so Open Recent starts empty.
Recent files no longer appear in the Dock icon's menu.

Verified with the reproduction steps above, using a LaunchServices launch
(`open`) of the rebuilt dev app:

- Clicking `AGENTS.md` in the restored navigator rendered the preview, and the
  process stayed alive.
- *Open Recent* listed the files that had been opened, and choosing one opened
  it.
- Quitting through AppleScript exited cleanly.
- No new `.ips` was written.
- `doc.md-preview.dev.sfl4` (LaunchServices' recents file) was not modified.

The first render after launch can take 5–10 s. Wait that long before deciding
the preview is blank.

## Machine state left by the investigation

- `/Applications/Markdown Preview (dev).app` was **re-signed ad hoc** during
  testing (this triggered a "Quick Look extension added" notice). The original
  linker-signed copy is backed up at `/tmp/mdp-backup.app`. Restoring it
  required deleting the app folder, which the harness blocked. Rebuilding and
  re-copying (see AGENTS.md, "Update the installed copy") gives the same result.
- Temporary helpers in `/tmp`: `clk/click` (synthetic mouse click),
  `relaunch.sh`, `runclick.sh`, `rt/RT.app`.
