# Bug: preview stays blank after clicking a file in the navigator (crash in Open Recent)

Status: **open, not fixed**. Investigated 2026-10-16 on macOS 26.7.1 (25G241),
build at commit `d014e30` (installed as `/Applications/Markdown Preview (dev).app`).

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

## Still unknown

- Why only Markdown Preview, and seemingly only when launched by LaunchServices.
  Candidates: the inherited environment, something the app loads at launch
  (Sentry `CrashReporter.start()`, Sparkle, the Debug `__preview.dylib` /
  `.debug.dylib` split), or timing alongside session restore.
- Whether a signed Release build is affected too.

## Proposed fix (not implemented)

Keep AppKit's background Open Recent update from reaching the crashing
LaunchServices call. Do this in
`md-preview/App/MarkdownDocumentController.swift` (already a
`NSDocumentController` subclass):

- **Preferred:** override `noteNewRecentDocumentURL(_:)` and the Open Recent
  menu so the app keeps its own recent-files list (e.g. in `UserDefaults`),
  never calling `super`. Open Recent keeps working, and the crash on quit should
  go away too.
- **Minimal:** override `noteNewRecentDocumentURL(_:)` as a no-op. This stops
  the crash, but Open Recent stops updating.

After either change, reproduce with the steps above. Expect no new `.ips` and
the preview rendering, for both the navigator click and quit.

## Workaround until fixed

Open files with `open -a "Markdown Preview (dev)" file.md` or `mdp file.md`.
Avoid clicking them in the navigator of a restored window.

## Machine state left by the investigation

- `/Applications/Markdown Preview (dev).app` was **re-signed ad hoc** during
  testing (this triggered a "Quick Look extension added" notice). The original
  linker-signed copy is backed up at `/tmp/mdp-backup.app`. Restoring it
  required deleting the app folder, which the harness blocked. Rebuilding and
  re-copying (see AGENTS.md, "Update the installed copy") gives the same result.
- Temporary helpers in `/tmp`: `clk/click` (synthetic mouse click),
  `relaunch.sh`, `runclick.sh`, `rt/RT.app`.
