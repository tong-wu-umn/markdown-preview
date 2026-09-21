# Markdown Preview — agent guide

A macOS app for previewing Markdown files. AppKit, sandboxed, ships with a Quick Look extension. Updates via Sparkle, distributed via Amore.

## Project facts

| Thing             | Value                                                       |
| ----------------- | ----------------------------------------------------------- |
| Bundle id         | `doc.md-preview`                                            |
| Product name      | `Markdown Preview`                                          |
| Scheme            | `md-preview`                                                |
| Quick Look target | `quick-look` (embedded extension)                           |
| Min macOS         | 15.0                                                        |
| Sandboxed         | yes — uses Sparkle XPC services for updates                 |
| Auto-updater      | Sparkle 2.x (Swift package)                                 |
| Distribution      | Amore (managed); appcast at `release.md-preview.app` |

Version is managed centrally in `Version.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). Both the app and the quick-look extension inherit from it.

## Codex development workflow

- `.codex/config.toml` pins `gpt-6-astra` with `medium` reasoning for trusted project sessions. Explicit session overrides can take precedence. This config controls the coding agent; the app's Open in LLM action delegates to external apps.
- This is a **personal fork** of `pluk-inc/markdown-preview`. Work is committed directly to the local branch — there are no upstream pull requests, so PR/branch-naming conventions do not apply. Branches exist only to organize local work or to merge upstream changes.
- The owner uses Nushell and has `gh` authentication available. Match shell syntax to the actual execution shell.
- Complete work authorized by the user's request, making reasonable routine implementation choices. A request for a plan authorizes planning only.
- Apply skills within their stated scope. If an instruction blocks authorized work, identify the exact file and instruction rather than inferring an extra approval requirement.
- Keep verification proportional: config and documentation changes need validation and diff review; Swift changes need relevant tests and an app build; visible behavior changes need runtime verification.

## Documentation that describes behaviour is part of the behaviour

**If a change makes a documented claim false, updating that claim is part of the
change — same commit, not a follow-up.** This applies to `README.md`, sample and
fixture files, and any comment that tells a reader what to expect on screen.

The reason is not tidiness. A stale claim asserts the *opposite* of what the
code does, and people trust it, so it is worse than saying nothing at all. It
produces two specific failures:

- A correct result gets reported as a bug, because the documentation says
  something else should happen.
- A real regression gets waved through as a known limitation, because the
  documentation says it never worked.

The second one is not hypothetical here. `README.md` said Mermaid diagrams
render in both the app and Quick Look previews. They had stopped rendering in
Quick Look, and the mismatch was read as documentation drift rather than as the
bug it was — which is part of why it survived several releases before anyone
chased it (#338, fixed in #343).

So when you change what the reader sees, grep for what says otherwise:

```bash
grep -rn "<the behaviour you changed>" README.md samples/ tests/fixtures/ docs/
```

## Signing & secrets — do not touch without asking

- `DEVELOPMENT_TEAM = 5P3TSMNV42` (`project.pbxproj`, both targets) is the
  maintainer's Apple Developer Team ID, hardcoded in the shared Xcode project.
  Never change it, regenerate signing, or let Xcode "fix" it automatically —
  building locally without the team's certificates can make Xcode silently
  rewrite `DEVELOPMENT_TEAM` to your own personal team on save. Check
  `git diff` on `project.pbxproj` before committing anything and revert that
  hunk if it shows up.
- `CODE_SIGN_IDENTITY` / `CODE_SIGN_STYLE = Automatic` — same story, leave as-is.
- Secrets (currently `POSTHOG_PROJECT_TOKEN`) live in `Secrets.xcconfig`,
  gitignored — copy `Secrets.xcconfig.example` to `Secrets.xcconfig` locally.
  Never hardcode a real token into a tracked file, Info.plist, or a commit.
- The Sparkle/Amore signing material (EdDSA key, notary keychain profile) is
  documented in the `release-process` skill. Don't touch `SUPublicEDKey` in
  `Info.plist` or the entitlements' `mach-lookup` names without reading that
  skill first — they're paired with private material outside the repo (login
  Keychain / Amore), so an unmatched change breaks Sparkle updates silently.
- `md-preview.entitlements` / `quick-look.entitlements` — the sandbox
  `temporary-exception` entries (Sparkle XPC mach-lookup names, the read-only
  filesystem exception) are narrowly scoped, notarization-review-sensitive
  capabilities. Don't broaden or "clean up" them without understanding why
  they're there (see the inline comments in each file).
- When bumping the version, update **both** `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` in `Version.xcconfig`, together with the matching
  `CHANGELOG.md` entry. `scripts/release.sh` builds and publishes through the
  upstream Amore/Sparkle channel and needs the maintainer's signing material
  (Team ID, EdDSA key, notary/Amore profile) — this fork generally cannot run
  it; build a local copy instead (see "Running & updating a local build").

## Releasing (upstream only)

The `release-process` skill documents branch naming, exactly what `scripts/release.sh` and `scripts/rollback-release.sh` do, and the Amore config wired for the upstream project. This fork lacks the upstream signing material (Team ID `5P3TSMNV42`, EdDSA key, notary keychain / Amore profile), so it can publish neither notarized builds nor Sparkle updates. Kept here for reference and for merging upstream changes; day-to-day use is the local build below.

## Release references

- `Info.plist` currently sets `SUFeedURL` to `https://release.md-preview.app/v1/apps/doc.md-preview/appcast.xml`. Check the current plist and Amore configuration before releasing; do not assume an old hostname or mismatch still applies.
- The canonical GitHub repository is `pluk-inc/markdown-preview`. Older remotes may redirect from `pluk-inc/md-preview.app`; check `git remote -v` and `gh repo view` before publishing.

## Common Xcode tasks
```bash
xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Debug build
xcodebuild -resolvePackageDependencies -project md-preview.xcodeproj
```
Sparkle helper tools (sign_update / generate_keys / generate_appcast) live at:
`~/Library/Developer/Xcode/DerivedData/md-preview-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`

## Running & updating a local build

This fork runs as an **unsigned Debug app** built locally. It receives no
Sparkle auto-updates (those need the upstream appcast + EdDSA key), so
"updating the app" means rebuilding and re-copying — there is no in-app update.

### One-time toolchain setup

A full **Xcode** install is required (not just Command Line Tools): `xcodebuild`
and the app-target build need it, and a mismatched Command Line Tools toolchain
fails to compile even `import Foundation`. Point the toolchain at Xcode once:

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version   # verify
```

### Build

```bash
xcodebuild -project md-preview.xcodeproj -scheme md-preview \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The product lands in **DerivedData**, a disposable hashed cache that a clean
build wipes and that changes if the repo moves — never treat its path as
permanent:
`~/Library/Developer/Xcode/DerivedData/md-preview-*/Build/Products/Debug/Markdown Preview.app`

### Run

```bash
APP="$(xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/Markdown Preview.app"
open -a "$APP" README.md
open -a "$APP" docs guides      # several folders -> one window
```

### Install a stable copy

Copy it out of DerivedData so the path survives clean builds and repo moves.
The dev build's bundle id is `doc.md-preview.dev`, so it coexists with any
released `doc.md-preview` install and appears as "Markdown Preview (dev)":

```bash
ditto "$APP" "/Applications/Markdown Preview (dev).app"
open "/Applications/Markdown Preview (dev).app"
```

### Update the installed copy after code changes

The `/Applications` copy is a snapshot; it does not track DerivedData. Rebuild,
then re-copy:

```bash
xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
ditto "$APP" "/Applications/Markdown Preview (dev).app"
```

### Notes

- Unsigned/ad-hoc: if Gatekeeper blocks first launch, right-click -> Open once.
- **Quick Look** from Finder uses whichever registered app LaunchServices
  picks; a DerivedData or dev build can shadow a released one. Reset the
  database with `lsregister -kill -r -domain local -domain user` (the tool is
  under `.../CoreServices/.../LaunchServices.framework/Support/`).
- The `mdp` / `md-preview` CLI (installed from a released app) runs
  `open -b "doc.md-preview"`, i.e. it targets the **released** bundle id, not
  the `.dev` build. Test the local build with `open -a "$APP"` instead.
- To keep current with upstream: `git fetch` the upstream remote, merge, then
  rebuild. Watch `Version.xcconfig`, `Info.plist` (`SUFeedURL`, `SUPublicEDKey`),
  and `project.pbxproj` (`DEVELOPMENT_TEAM`) in the merge — those carry the
  upstream signing identity this fork does not own.
