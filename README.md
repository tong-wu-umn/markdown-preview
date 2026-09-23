<h1 align="center">Markdown Preview</h1>

<p align="center">
  <img src="docs/markdown-logo.svg" width="128" alt="Markdown Preview logo" />
</p>

<p align="center">
  A fast, native macOS app for reading Markdown files.
</p>

<p align="center"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" />&nbsp;<img alt="Swift" src="https://img.shields.io/badge/swift-6.0-orange" />&nbsp;<img alt="License" src="https://img.shields.io/badge/license-MIT-green" /></p>

---

> **Personal fork.** This is my own build of [`pluk-inc/markdown-preview`](https://github.com/pluk-inc/markdown-preview), maintained for personal use with local changes (for example, showing several folders in one Project Navigator window). It is built and run locally rather than distributed. For the official signed, notarized, auto-updating app, use upstream. Build/run/update steps live in [`AGENTS.md`](AGENTS.md).

> Drop a `.md` on the icon (or set Markdown Preview as your default handler) and get a clean, scrollable preview with a real document outline — no Electron, no browser tab.

## Installation

This fork is not distributed — build it locally (full Xcode required):

```sh
git clone https://github.com/tong-wu-umn/markdown-preview.git
cd markdown-preview
xcodebuild -project md-preview.xcodeproj -scheme md-preview \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Then copy the built `Markdown Preview.app` out of DerivedData into
`/Applications` (it installs as **Markdown Preview (dev)**, bundle id
`doc.md-preview.dev`, so it never clashes with the upstream app). The full
build/run/update workflow is in [`AGENTS.md`](AGENTS.md).

For the official signed, notarized, auto-updating app, install upstream:

```sh
brew install --cask markdown-preview
```

## Screenshots

<p align="center">
  <img src="docs/screenshot-main.png" width="820" alt="Main window with document outline sidebar" />
</p>

<p align="center">
  <em>Edit Markdown directly with a native formatting toolbar:</em>
</p>

<p align="center">
  <img src="docs/screenshot-edit-mode.png" width="820" alt="Edit Mode with document outline and Markdown formatting toolbar" />
</p>

<p align="center">
  <em>Quick Look preview — spacebar a <code>.md</code> in Finder:</em>
</p>

<p align="center">
  <img src="docs/screenshot-quicklook.png" width="640" alt="Quick Look preview from Finder" />
</p>

<p align="center">
  <em>Customize the toolbar — drag in Print, Copy, Zoom and the rest from <em>View → Customize Toolbar…</em></em>
</p>

<p align="center">
  <img src="docs/screenshot-toolbar-customize.png" width="820" alt="Native macOS toolbar customization sheet showing draggable items" />
</p>

## Features

- **Native rendering** — `WKWebView` pipeline backed by [swift-markdown](https://github.com/swiftlang/swift-markdown), with heading anchors and link handling. Bare `http://` and `https://` URLs are clickable in the app and Quick Look previews.
- **Edit Mode** — edit Markdown in place with a formatting toolbar for headings, emphasis, lists, quotes, code, and links. Toggle it from the toolbar or with <kbd>⌘E</kbd>, then save with <kbd>⌘S</kbd>.
- **Mermaid diagrams** — fenced `mermaid` code blocks render as diagrams in both the app and Quick Look previews, using a bundled renderer so previews work offline without a CDN request.
- **Math equations** — LaTeX inline (`$x_1 + x_2$`), display (`$$\int_0^1 x^2\,dx$$`), and fenced `math` blocks render with a bundled KaTeX. Selecting a rendered formula and copying yields the original LaTeX source (via the official `copy-tex` extension).
- **Document outline** — sidebar TOC that mirrors your headings; click to jump.
- **File navigator** — browse Markdown files (and `.txt` files, unless you turn off *Settings → General → Show plain-text files in navigator*) in the sidebar. Click a folder's name, icon, or empty row space to expand or collapse it, or use its disclosure triangle. Click a file to open its preview. Show several folders in one window with *File → Add Folder to Navigator…*, by dropping folders onto the navigator, or by passing several folders to `mdp` or the open panel; right-click a top-level folder to *Remove from Navigator*.
- **Inspector panel** — toggleable side panel with file metadata.
- **In-document search** — toolbar search field plus standard <kbd>⌘F</kbd> / <kbd>⌘G</kbd> / <kbd>⌘⇧G</kbd> for next/previous match.
- **Open With** — switch to your real editor (VS Code, Cursor, Zed, Sublime, BBEdit, Nova, CotEditor, TextMate, MacVim, Xcode, TextEdit) without leaving the preview. The list filters to apps that actually declare an editor role for Markdown, and remembers your pick.
- **Open in LLM** — send the current Markdown file to Codex, Claude, or ChatGPT from the toolbar. Supported apps open with file or folder context where possible, with a copy-and-open fallback for longer prompts.
- **Text zoom** — bump preview text up or down with trackpad pinch, the toolbar's <kbd>A A</kbd> control, or <kbd>⌘+</kbd> / <kbd>⌘−</kbd> / <kbd>⌘0</kbd>. Discrete Safari-style stops from 50% to 300%.
- **Customizable toolbar** — drag in the items you actually use (Print, Copy, Zoom, Sidebar, Open With, Inspector, Share, Search) via *View → Customize Toolbar…* Standard AppKit affordance, your layout sticks across launches.
- **Share = copy the source** — the share toolbar feeds the picker the Markdown text itself, so **Copy** writes the raw source to the clipboard (great for pasting into ChatGPT / Claude), and Mail, Messages, and Notes get the content in the body instead of a file URL.
- **Quick Look extension** — system-wide `.md` previews from Finder spacebar, Spotlight, and Mail attachments without launching the app.
- **Command line tools** — install `mdp`, `md-preview`, and `markdown-preview` from the app menu, then open files or folders from any shell with commands like `mdp README.md` or `mdp .`. Pass several folders at once (`mdp docs guides`) to show them all in one window.
- **URL scheme** — open a file or folder from a browser link or another app with `md-preview://file/<absolute path>` (e.g. `md-preview://file/Users/me/project/README.md`), the same shape as `cursor://file/…`. Percent-encode special characters in the path (a space becomes `%20`).
- **Default handler** — offers to register itself as the default `.md` opener on first launch.

## Supported file types

Markdown: `.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`, `.mdwn`, `.mdtxt`, `.mdtext`, `.mdx`
UTI: `net.daringfireball.markdown` (plus the app's exported Markdown UTIs), rank `Owner`

Plain text: `.txt`, `.text` — declared by extension at rank `Alternate`
(`public.plain-text` itself also covers source code, `.log`, and `.csv`, which
the app deliberately doesn't claim).

- A `.txt` renders either as Markdown or as plain text. Plain text keeps the
  file exactly as written: hard-wrapped lines, `#` comments, literal `*`
  bullets, and ASCII tables and art. It uses a monospaced font by default
  (*Settings → General → Monospaced font for plain text*), and a long line
  wraps rather than scrolling sideways.
- The mode is detected per file. Frontmatter, a `# Heading`, a fenced code
  block, a `[link](url)` or image, or a table means Markdown; anything else is
  plain text. Only the first 64 KB are checked. *View → Render as Markdown*
  switches a `.txt` between the two, and the choice is remembered for that file
  across reloads and relaunches.
- In plain text the outline is empty, the inspector drops Markdown-only counts
  and frontmatter, and edit mode opens a plain editor with no formatting bar.
  HTML/PDF export, Find, and Open in LLM use the plain text too.
- Links to a `.txt`, its navigator row, and its Open panel entry work like a
  `.md` file's.
- The app appears under Finder's *Open With* for `.txt` but never makes itself
  the default `.txt` app, and the first-launch default-handler offer only covers
  `.md`.
- Quick Look for `.txt` stays with the system preview; the extension handles
  Markdown only.
- Non-UTF-8 text (UTF-16 with a BOM, Windows-1252 / Latin-1) opens too. Saving
  an edit asks before converting such a file to UTF-8, and auto-save leaves it
  unsaved until you do.

## Requirements

- macOS 15 or later
- Apple Silicon or Intel

## Building from source

```sh
git clone https://github.com/tong-wu-umn/markdown-preview.git
cd markdown-preview
open md-preview.xcodeproj
```

Build and run the `md-preview` scheme (requires full Xcode, not just the Command Line Tools). Swift Package Manager will resolve [Sparkle](https://github.com/sparkle-project/Sparkle), [Sentry](https://github.com/getsentry/sentry-cocoa), and [swift-markdown](https://github.com/swiftlang/swift-markdown) on first build.

> Local Debug builds — this fork's default — send **nothing**: the crash reporter and usage analytics below are both release-build only, and the release channel belongs to upstream. The two subsections describe upstream release builds and are kept for reference.

### Crash reporting

Release builds submit native crash reports to the `pluk-inc/markdown-preview` Sentry project. The integration does not collect performance traces, session data, breadcrumbs, network requests, user information, document contents, or file paths. Users can turn reporting off in Markdown Preview > Settings > Privacy; on later launches, the Sentry SDK will not initialize at all.

The committed DSN is a public client key. Release archives upload the app dSYM with `sentry-cli`; authenticate locally with `sentry-cli login` and keep that authentication token outside the repository.

### Anonymous usage analytics

Release builds can submit at most one anonymous `app became active` event per installation per UTC day when Markdown Preview becomes active. The event contains a random installation identifier, app version, macOS major version, processor architecture, locale country or region, and the flag that prevents PostHog from creating a person profile. It is used to count daily and monthly active installations and understand basic platform compatibility. It does not contain document contents, file names or paths, actions, screens, precise location, personal information, or advertising identifiers. Users can disable it from Settings > Privacy.

The PostHog project token is injected from the gitignored `Secrets.xcconfig`. Copy `Secrets.xcconfig.example` to `Secrets.xcconfig` and set `POSTHOG_PROJECT_TOKEN` before making a release build. If the token is absent, or for a Debug build, analytics remains disabled. Every event disables GeoIP enrichment, and the PostHog project must also be configured to discard IP data in Project Settings > General.

## Project layout

```
md-preview/         Main app target (AppKit, WKWebView)
quick-look/         Quick Look extension (.appex)
scripts/            Release & rollback automation
Version.xcconfig    Marketing & build version (single source of truth)
appcast.xml         Sparkle update feed
```

## Releasing (upstream only)

The upstream project is released with [Amore](http://amore.computer/) — building, code signing, notarization, DMG creation, S3 upload, and Sparkle appcast publishing in one shot via `./scripts/release.sh` (rollback with `./scripts/rollback-release.sh`). This fork does not hold the upstream signing material (Apple Team ID, EdDSA key, notary/Amore profile), so it cannot publish notarized builds or Sparkle updates. The scripts and the [release-process skill](.agents/skills/release-process/SKILL.md) are kept for reference and for merging upstream changes.

## Acknowledgments

This is a personal fork of [`pluk-inc/markdown-preview`](https://github.com/pluk-inc/markdown-preview) by [Pluk](https://pluk.sh) — all credit for the app itself goes to the upstream authors.

- [Amore](http://amore.computer/) — MacOS release automation (signing, notarization, DMG, hosting, appcast)
- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parser (Apple, cmark-gfm-backed)
- [Mermaid](https://mermaid.js.org/) — Bundled diagram renderer for `mermaid` fenced code blocks
- [KaTeX](https://katex.org/) — Bundled math typesetter for inline `$…$`, display `$$…$$`, and ` ```math ` blocks
- [Sparkle](https://sparkle-project.org) — Auto-update framework
- [Sentry](https://sentry.io) — Privacy-filtered native crash reporting
- [LottieFiles](https://lottiefiles.com/) — Animated README logo

## License

[MIT](LICENSE)
