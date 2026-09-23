# `.txt` file support: plan

Status: **Phase 1 implemented; Phase 2 not started** (deferred until Phase 1
has been used for a while, per §1). Written against `main` at `1e4f21e`
(0.0.59 + Unreleased).

Where the Phase 1 implementation departs from this plan:

- **Step 2: declared by extension, not by UTI.** Every source-code type
  (`public.python-script`, `public.swift-source`, …), `com.apple.log`, and
  `public.comma-separated-values-text` conforms to `public.plain-text`. With
  `LSItemContentTypes = public.plain-text`, Launch Services listed the app as
  an Open With handler for `.py`, `.swift`, `.log`, and `.csv`, which runs
  against D6. The Plain Text document type uses
  `CFBundleTypeExtensions = [txt, text]` instead. Verified with
  `NSWorkspace.urlsForApplications(toOpen:)`: the app is listed only for
  `.txt`/`.text` (and Markdown), and `.txt` opens through `NSDocumentController`.
- **Open panels** keep `public.plain-text` in `allowedContentTypes` but add a
  delegate (`SupportedDocumentOpenPanelFilter`) that disables files other than
  Markdown and `.txt`/`.text`, for the same conformance reason.
- **Step 5 (encoding)**: rather than tracking the encoding per window, the save
  path re-detects it from the bytes on disk right before writing (the conflict
  check already reads them). A non-UTF-8 file prompts "Convert to UTF-8?" on
  an explicit save; auto-save returns cancelled (shown as "Auto-save failed")
  until the user decides. A UTF-8 BOM is dropped on read and not rewritten.
- **Decoder cap**: data with a NUL byte and no UTF-16 BOM is rejected as
  binary, so the Latin-1 fallback never "decodes" images.
- **Not done**: the >20 MB size guard from §6, and `InfoPlist.strings`
  localization (no such file exists).

## 1. Summary

Plain-text files (`public.plain-text`, `.txt`) become first-class documents.
You can open them from Finder / "Open With", `mdp`, the `md-preview://`
scheme, the open panels, the Project Navigator, and in-document links. The
work comes in two phases:

- **Phase 1: open and render `.txt` as Markdown.** This makes today's
  README claim true.
- **Phase 2: add a "Plain text" render mode.** Plain prose and ASCII art in a
  `.txt` should not be reflowed or reinterpreted as Markdown syntax.

Phase 1 alone can ship. Phase 2 is recommended, but only after Phase 1 is
merged and has been used for a while.

No sandbox or entitlement changes. No signing changes. New Swift files under
`md-preview/` need no `project.pbxproj` edit, because `md-preview/` is a
`PBXFileSystemSynchronizedRootGroup`.

## 2. Current state (why this is a fix, not only a feature)

`README.md:93` lists `.txt` under "Supported file types", and
`CHANGELOG.md:1076` (0.0.1) says "Supports … `.txt`". Git history shows
`public.plain-text` was **never** in `CFBundleDocumentTypes`. It has only
appeared as a `UTTypeConformsTo` parent of the Markdown UTIs (`bf034ad`,
`e654810`). So the claim was never fully true.

Where `.txt` is handled today:

| Location | `.txt`? | Effect |
| --- | --- | --- |
| `Info.plist` `CFBundleDocumentTypes` → `LSItemContentTypes` (lines 25–48) | no | `NSDocumentController` can't map `public.plain-text` to `MarkdownDocument`. Finder "Open With", `mdp foo.txt`, `md-preview://file/…/foo.txt`, and the app-level open panel most likely fail with "cannot open files in the 'Plain Text' format" (**verify in Step 0**). |
| `md-preview/App/MarkdownDocumentController.swift:10` (app-level ⌘O panel filter) | yes | You can select a `.txt`, then (probably) hit the error above. |
| `md-preview/Document/DocumentWindowController+OpenTargets.swift:475` (`markdownFileExtensions`, used by the in-window open panel in `+DocumentOpening.swift:197`) | yes | The in-window open goes through `loadFile(at:)` → `String(contentsOf:encoding:.utf8)`, bypassing `NSDocumentController`, so it may already work. |
| `md-preview/Features/Sidebar/ProjectNavigatorView.swift:9` (`FileNode.markdownExtensions`) | no | `.txt` files are hidden in the navigator tree. |
| `md-preview/Rendering/MarkdownWebView.swift:1584` (`isMarkdownDocument`) | no | Clicking `[notes](notes.txt)` hands off to `NSWorkspace.open` (TextEdit) instead of opening in-app, and "Open Link in New Window" is missing from the context menu. |
| `md-preview/Features/OpenWith/OpenTargetCatalog.swift:125` (`markdownDocTypeExtensions`) | no | Only a heuristic for *other* apps' editor capability. **Leave as is.** |
| `quick-look/Info.plist` `QLSupportedContentTypes` | no | Quick Look for `.txt` stays with the system. **Intended; see D3.** |
| `DocumentWindowController.swift:561` `offerToBecomeDefaultHandlerIfNeeded` | Markdown UTI only | **Must stay Markdown-only.** Never offer to take over `.txt`. |

The extension list is duplicated four times, and the copies already disagree
(`mkd`/`mkdn`/`mdwn` show up in some copies but not others). Merging them into
one list is part of Phase 1.

## 3. Decisions (recommended defaults in bold)

| # | Question | Options | Recommendation |
| --- | --- | --- | --- |
| D1 | How should a `.txt` render? | (a) Always Markdown, (b) always plain, (c) auto-detect + per-window toggle | **Phase 1: (a). Phase 2: (c).** (a) matches the README claim, and many `.txt` notes and LLM outputs are really Markdown. |
| D2 | Launch Services rank for `public.plain-text` | `Owner` / `Default` / **`Alternate`** / `None` | **`Alternate`**: listed under Finder "Open With" but never made the default. `Owner`/`Default` would compete with TextEdit and look like hijacking. |
| D3 | Quick Look for `.txt`? | yes / **no** | **No.** Adding `public.plain-text` to `QLSupportedContentTypes` replaces the system text preview for every `.txt`, `.log`, `.csv`-as-text, etc. system-wide. |
| D4 | Show `.txt` in the Project Navigator? | always / **setting, default on** / never | **Setting, default on.** It's useful for notes folders, but noisy in code repos (`requirements.txt`, `LICENSE.txt`, `CMakeLists.txt`). Add *Settings → General → "Show plain-text files in navigator"*. |
| D5 | Non-UTF-8 `.txt` | UTF-8 only (clear error) / **detect on read, UTF-8-only edit** | **Detect on read** (`String(contentsOf:usedEncoding:)` with a Latin-1/Windows-1252 fallback). In edit mode, refuse or convert with a prompt when the source wasn't UTF-8, so the file is never silently re-encoded. |
| D6 | Other plain-text extensions (`.text`, `.log`)? | yes / **no** | **No.** Declaring `public.plain-text` covers `.text` automatically (the system UTI owns both extensions). `.log` is `public.log`; keep it out of scope. |

## 4. Phase 1: open and render `.txt` as Markdown

### Step 0: confirm the baseline (no code)

Build the dev app (see `AGENTS.md`, "Build"), then record each path's
behaviour before any change:

```bash
printf '# Hello\n\nplain *text*\n' > /tmp/probe.txt
open -a "$APP" /tmp/probe.txt                         # Launch Services path
open "md-preview://file/tmp/probe.txt"                # URL scheme path
```

Also try: ⌘O with no window (app-level panel), ⌘O inside a window
(in-window panel), a navigator folder that contains a `.txt`, and a link to a
`.txt` inside a `.md`. This fixes the "before" column for the PR notes and
confirms the diagnosis in §2.

### Step 1: one source of truth for supported types

Create `md-preview/Helpers/SupportedDocumentTypes.swift` (a plain
`Foundation` + `UniformTypeIdentifiers` enum, `nonisolated`, with no AppKit so
the test package can compile it):

```swift
enum SupportedDocumentTypes {
    /// Markdown extensions, matching Info.plist's exported/imported UTIs.
    static let markdownExtensions: Set<String> =
        ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "mdx"]
    static let plainTextExtensions: Set<String> = ["txt", "text"]

    enum Kind { case markdown, plainText }

    static func kind(of url: URL) -> Kind?          // by extension, case-insensitive
    static func isOpenable(_ url: URL) -> Bool      // kind(of:) != nil
    static var openPanelContentTypes: [UTType]      // markdown UTIs + .plainText
}
```

Replace the four duplicated lists:

- `MarkdownDocumentController.markdownFileExtensions` → `openPanelContentTypes`
- `DocumentWindowController.markdownFileExtensions` (`+OpenTargets.swift:475`)
  → `openPanelContentTypes` in `+DocumentOpening.swift:197`
- `FileNode.markdownExtensions` → `isOpenable(_:)` (plus the D4 setting)
- `MarkdownWebView.isMarkdownDocument` → `isOpenable(_:)`. This file is also
  compiled into the Quick Look extension (`QUICK_LOOK_EXTENSION`), so either
  add the new file to the quick-look target's membership or keep a local
  helper there. **Check the quick-look target's source list first.** If adding
  membership means editing `project.pbxproj`, check the diff for
  `DEVELOPMENT_TEAM` changes (AGENTS.md).

Side effect to note in the CHANGELOG: the navigator and link handling pick up
`mkdn`/`mdtxt`/`mdtext`, which the plist already claims but those lists
missed.

Symlink the new file into `tests/swift-tests/Sources/MarkdownHelpers/` (same
pattern as `FileURLHelpers.swift`).

### Step 2: register the document type (`Info.plist`)

Add a **second** `CFBundleDocumentTypes` entry instead of adding
`public.plain-text` to the existing Markdown one, so each has its own rank:

```xml
<dict>
    <key>CFBundleTypeName</key>
    <string>Plain Text Document</string>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>          <!-- edit mode writes back -->
    <key>LSHandlerRank</key>
    <string>Alternate</string>       <!-- D2 -->
    <key>LSItemContentTypes</key>
    <array>
        <string>public.plain-text</string>
    </array>
    <key>NSDocumentClass</key>
    <string>$(PRODUCT_MODULE_NAME).MarkdownDocument</string>
</dict>
```

Notes:

- Don't list `public.text` or `public.utf8-plain-text`. `public.text` also
  covers source code, HTML, etc. Every Markdown UTI conforms to
  `public.plain-text`, so the more specific Markdown entry still wins for
  `.md` (verify with `typeForContents(of:)` in Step 7).
- Leave `UTExportedTypeDeclarations` / `UTImportedTypeDeclarations`
  untouched. `public.plain-text` is a system type.
- Don't touch `SUFeedURL`, `SUPublicEDKey`, or `CFBundleURLTypes`.
- Add a `CFBundleTypeName` localization if `InfoPlist.strings` exists for
  `en`/`zh-Hans` (check `md-preview/*.lproj`).

### Step 3: `MarkdownDocument` reading

`md-preview/Document/MarkdownDocument.swift:65`, `read(from:ofType:)`:

- Store the document kind (`typeName` → `.markdown` / `.plainText`) in a
  `Mutex`, like `markdownStorage`. Phase 2 needs it, and Phase 1 uses it for
  the default-handler guard below.
- D5: replace the strict `String(data:encoding:.utf8)` with a decoder that
  tries UTF-8 → BOM-detected UTF-16 → Windows-1252. Record the encoding that
  was used.

The same UTF-8-only read appears in `DocumentWindowController+DocumentOpening.swift:204`
(`loadFile`). Move the decoding into a shared helper
(`SupportedDocumentTypes.decode(_ data: Data) -> (String, String.Encoding)?`)
and call it from both places.

### Step 4: default-handler offer stays Markdown-only

`DocumentWindowController.display(markdown:fileURL:)` calls
`offerToBecomeDefaultHandlerIfNeeded()` for every file. It only targets
`net.daringfireball.markdown`, so it's safe. Still, skip the call when
`kind(of:) == .plainText`: a first-ever launch on a `.txt` shouldn't offer
to take over `.md` either. Add a code comment explaining why `.txt` must
never reach `setDefaultApplication`.

### Step 5: edit mode and saving

- Autosave / ⌘S write back to the same URL, so the `.txt` extension is kept.
  Confirm that `write(_:to:)` in `+EditSession.swift` preserves the extension
  and uses the encoding recorded in Step 3. If the file was read as
  non-UTF-8, the first save asks: "Convert to UTF-8?" / Cancel.
- `saveUntitledMarkdown` (`+EditSession.swift:88`) stays `.md`-only. Untitled
  documents are Markdown by definition.
- The formatting bar inserts Markdown syntax. That's fine in Phase 1, since
  `.txt` renders as Markdown.

### Step 6: navigator setting (D4)

- Add `NavigatorPlainTextSetting` in `md-preview/Preferences/`, following the
  existing `static func read(from defaults: UserDefaults?) -> Bool` pattern
  (e.g. `TabOpeningPolicy`). Default `true`.
- Add a checkbox in *Settings → General* (find the Windows / navigator group
  in `md-preview/Features/Settings/`). Localize the strings in `en.lproj` and
  `zh-Hans.lproj`.
- On change, post a notification. `ProjectNavigatorView` invalidates every
  `FileNode` cache and reloads the outline **without collapsing the expanded
  state** (the same technique the directory watcher uses).
- `FileNode.children()` filter: `kind == .markdown || (kind == .plainText && setting)`.

### Step 7: tests (`swift test --package-path tests/swift-tests`)

New file `SupportedDocumentTypesTests.swift`:

- `kind(of:)` for every Markdown extension, `txt`/`TXT`/`text`, and negatives
  (`log`, `csv`, `rtf`, no extension, a directory URL).
- `openPanelContentTypes` includes `UTType.plainText` and
  `net.daringfireball.markdown`.
- Decoder: UTF-8, UTF-8 with BOM, UTF-16 LE/BE with BOM, Windows-1252 bytes
  (`0xE9` → "é"), empty data, and invalid data that's still decodable by
  1252 (document the "never fails" behaviour, or cap it deliberately).
- The navigator-setting read/default, following `TabOpeningPolicyTests`.

Add `samples/plain-text.txt`: a Markdown-ish `.txt` (headings, list,
link to `full.md`) for manual testing and for the README screenshot.

### Step 8: build and runtime verification

```bash
swift test --package-path tests/swift-tests
xcodebuild -project md-preview.xcodeproj -scheme md-preview \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
git diff -- md-preview.xcodeproj/project.pbxproj   # must show no DEVELOPMENT_TEAM hunk
```

Re-register with Launch Services so the new plist is seen
(`lsregister -f "$APP"`), then repeat the Step 0 matrix. Each path must open
the `.txt` in-app:

| Path | Expected |
| --- | --- |
| Finder → right-click `.txt` → Open With | "Markdown Preview (dev)" listed; **not** the default (TextEdit still is) |
| `open -a "$APP" /tmp/probe.txt` | Opens, renders heading + italics |
| `md-preview://file/tmp/probe.txt` | Opens |
| ⌘O, no window / in window | `.txt` selectable, opens |
| Navigator folder containing `.txt` | Listed; hidden when the setting is off, and expansion is kept on toggle |
| Link `[x](probe.txt)` in a `.md`, plus its context menu | Opens in-app; "Open Link in New Window" offered |
| Edit a `.txt`, autosave | File stays `.txt`, content saved, watcher doesn't loop |
| Latin-1 `.txt` | Renders correctly; the first save prompts for UTF-8 conversion |
| `.md` file after the change | Still opens as a Markdown document type (no regression in the type mapping) |
| Finder spacebar on `.txt` | **System** Quick Look, unchanged (D3) |
| `duti -x txt` / Finder "Get Info" | Default for `.txt` unchanged |

### Step 9: documentation (same commit, per AGENTS.md)

```bash
grep -rn "\.txt\|plain.text\|Supported file types" README.md samples/ tests/fixtures/ docs/ CHANGELOG.md
```

- `README.md` "Supported file types": list the full Markdown set plus `.txt`,
  and say that `.txt` renders as Markdown, isn't claimed as default, and
  isn't handled by Quick Look. Update the UTI line to include
  `public.plain-text (Alternate)`.
- `README.md` Quick Look bullet already says `.md` only. Keep it that way.
- `CHANGELOG.md` → `[Unreleased]`:
  - *Fixed*: "Plain-text `.txt` files open in Markdown Preview." They were
    advertised as supported, but Finder, `mdp`, and `md-preview://` opens
    failed.
  - *Added*: the navigator setting, and the navigator/link support for
    `.mkdn`, `.mdtxt`, `.mdtext`.

## 5. Phase 2: plain-text render mode

The goal is that a prose `.txt` (hard-wrapped lines, `#` comments, `*` bullets
meant literally, ASCII tables and art) looks the way it would in a text editor.

### Rendering

- Add `MarkdownHTML.renderPlainText(_ text: String, …) -> String`, sharing
  the page shell, theme, font, reader-width, and color-scheme code with
  `render(markdown:…)` in `md-preview/Rendering/MarkdownHTML.swift:276`.
  The body is `<pre class="plain-text">` with the text HTML-escaped (reuse
  `EscapingHTMLFormatter`'s escaping helper), styled
  `white-space: pre-wrap; overflow-wrap: anywhere; tab-size: 4` in the
  document font, or monospace if the user chooses.
- Optional: autolink bare `http(s)://` URLs. Keep it off in the first cut.
- Skip Mermaid, KaTeX, highlight.js, and footnotes in this mode, which also
  makes it faster for large logs.
- Don't implement it as "wrap in a fenced code block". That gets you the
  code-block chrome, horizontal scrolling, and a copy button, and breaks on
  text that contains long backtick runs.

### Mode selection (D1 → c)

- `enum RenderMode { case markdown, plainText }`. `.md` is always `markdown`.
  A `.txt` gets a heuristic default:
  - `markdown` if the text has frontmatter (`MarkdownFrontmatter`), an ATX
    heading, a fenced block, a Markdown link/image, or a GFM table. Parse with
    swift-markdown and check for block kinds other than `Paragraph`.
  - otherwise `plainText`.
- Put the heuristic in a pure, testable `PlainTextHeuristic.suggestedMode(for:)`.
- Add a toolbar/View-menu toggle, *View → Render as Markdown* (⌥⌘M or
  unbound), enabled only for `.txt` documents. Remember the choice per file
  path in `UserDefaults` (a bounded LRU, e.g. 200 entries), and re-check it on
  reload.
- The toggle flows through `DocumentWindowController.renderCurrentDocument` →
  `MainSplitViewController.display` → `ContentViewController.display` →
  `MarkdownWebView.display(markdown:assetBaseURL:)`. Add a `renderMode`
  parameter along the way. Keep scroll position across a toggle, the same way
  a reload does.

### Features affected in plain mode

| Feature | Plain mode behaviour |
| --- | --- |
| Outline / TOC (`SidebarViewController.display`, `MarkdownTOC.parse`) | Empty-state message "No outline for plain text" |
| Inspector (`DocumentMetadata.make`) | Word/line counts still shown; frontmatter panel hidden |
| Find (⌘F) | Works (web view text) |
| PDF / HTML export (`MarkdownWebView+PDFExport.swift`) | Exports the plain rendering. `ExportSource` needs `renderMode` |
| Share / Copy source / Open in LLM | Unchanged (raw text). The LLM prompt wrapper in `+OpenTargets.swift` (```` ```markdown ```` fence) should say `text` for plain mode |
| Edit mode | CodeMirror editor still works; **hide the formatting bar** and turn off Markdown-specific live preview decorations if possible (check `EditorHTML.render`) |
| Task checkboxes / table editing | Not applicable (no rendered elements) |
| Scrollspy / heading offsets | Skip (no headings) |

### Phase 2 tests

- `PlainTextHeuristicTests`: prose → plain; heading/fence/link/table/frontmatter
  → markdown; empty → plain; a `#!/bin/sh` shebang → plain (a `#` with no space
  isn't an ATX heading).
- `MarkdownHTMLRenderTests` additions: `renderPlainText` escapes `<script>`,
  `&`, and quotes; preserves leading spaces, tabs, and blank lines; includes
  the theme stylesheet; loads no vendor scripts.
- A WebKit layout test via `WebViewLayoutHarness`: a 500-column line wraps
  with no horizontal scroll.
- Runtime: toggle on a `.txt` keeps scroll position; the per-file choice
  survives an app relaunch; `.md` has no toggle.

### Phase 2 docs

README: describe auto-detection and the *View → Render as Markdown* toggle.
CHANGELOG *Added* entry.

## 6. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Launch Services picks the app for `.txt` by default on some machines | `Alternate` rank. Verify on a clean user with `lsregister -dump \| grep -A3 plain-text`. Never call `setDefaultApplication` for `.plainText` (Step 4) |
| `.md` suddenly resolves to the plain-text document type | `typeForContents` returns the most specific UTI, and Markdown UTIs are listed first. Covered by Step 8 (last matrix rows) |
| A large `.txt` log (100 MB) freezes rendering | Phase 1: add a size guard (e.g. over 20 MB → alert "File too large to preview" with "Open Anyway"). Phase 2 plain mode is cheaper but still limited by WebKit |
| Re-encoding user files on save | D5: record the encoding, and prompt before converting to UTF-8 |
| Navigator noise in code repos | D4 setting |
| Merge conflicts with upstream (plist, navigator, maintainer's folder-management work in #335) | Keep changes small and local, with the plist entry as its own `<dict>`. Rebase before starting; see the coordination note in `multi-folder-navigator.md` |
| `project.pbxproj` signing drift if target membership changes | Check `git diff` for `DEVELOPMENT_TEAM` / `CODE_SIGN_*` hunks and revert them |

## 7. Work breakdown and rough size

| Step | Size |
| --- | --- |
| 0 Baseline check | S |
| 1 `SupportedDocumentTypes` + dedupe lists | S |
| 2 `Info.plist` document type | XS |
| 3 Decoder + document kind | S |
| 4 Default-handler guard | XS |
| 5 Edit/save encoding handling | S–M |
| 6 Navigator setting | M |
| 7–9 Tests, verification, docs | M |
| **Phase 1 total** | **~1–1.5 days** |
| Phase 2 (renderer, heuristic, toggle, feature gating, tests, docs) | **~2–3 days** |

A minimal Phase 1 that removes the README mismatch is Steps 1, 2, 7 (partial),
8, and 9: about half a day. Steps 3, 5, and 6 can follow separately.
