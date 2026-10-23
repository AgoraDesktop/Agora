# Agora

*An installable desktop environment for Linux and the BSDs: the Cocoa stack, a Mac-like desktop, and its
applications — written in Objective-C, built from source.*

**Status: working, pre-release.** The components are implemented and run together: Foundation,
Core Graphics, Core Text and the Application Kit carry the Cocoa surface an application uses; the
window server is a Wayland compositor with client-side chrome, layers and input routing; the Workspace
shell draws the desktop, icons, menu bar and file windows; `demo/agora-session.sh` starts the default session — the
window server, the wallpaper client and Workspace — nested on an X11 desktop, and `demo/agora-demo.sh` adds the
controls application to that scene. There is also a Swift toolchain that compiles Swift against this stack (the standard
library, the Foundation overlay and the GNUstep class ABI). What is not there yet is an installable
image: the `release` repository pins and builds the components, but no release is tagged. This
document is the top-level record of what Agora is and how its repositories are organised; each
component carries its own detail in its own repository.

## What Agora is

Agora is a desktop environment for Linux and BSD. It is three things that compose into one whole:

1. **The Cocoa stack** — Core Foundation, Foundation, Core Graphics, Core Text and the Application
   Kit — implemented in Objective-C. The goal is behavioural and API compatibility: an Objective-C
   program written against the documented Cocoa surface builds and runs against Agora's stack.
2. **A Mac-like desktop** — a window server and shell whose behaviour matches Mac OS X's window
   management: client-side window chrome, a system-owned menu bar, a dock, a desktop with icons,
   sheets, and the drag-and-drop session.
3. **Applications** — a reference set (document, text, grid/formula, presentation, canvas,
   image) written against the stack, shipped as the desktop's content.

Everything is compiled from source, apart from the one piece of third-party *art* the desktop vendors — the
MIT-licensed Frost icon theme (see the Conventions below). A single **release** repository composes a whole
desktop by pinning, in a tagged release, one exact revision of every component.

## Repository model — one component, one repository

Agora is a federation of small repositories, not a monolith:

- **Each component lives in its own subdirectory, and that subdirectory is its own Git
  repository.**
- **A `release` repository aggregates them.** It is a separate repository, checked in here as a
  submodule. Its `main` follows the components' `main` branches; each release **tag** pins every
  component at a specific tagged revision and builds the entire desktop from those pins.

Two consequences this buys us:

- **Independent versioning.** A component moves on its own schedule; nothing else floats.
- **Reusable parts.** A component (the stack, the window server) can be consumed on its own, without
  pulling in the whole desktop.

**Layout.** This top-level directory is the *development workspace*: its working tree holds one
submodule directory per component, each tracking `main`, alongside this document. Its `release/`
subdirectory is a second submodule — the **`release` repository** — whose own working tree holds the
same components, its `main` also following theirs. Both float; a release **tag** on the `release`
repository is what pins an exact combination. Component remotes live under the `AgoraDesktop`
organisation, and `.gitmodules` records their URLs.

## The components

The component repositories named below exist and build. This list will grow; further components
(system preferences, more applications) are not yet specified.

### The Cocoa stack

| repository | what it is |
|---|---|
| `libagora-core` | Core Foundation — the C core: strings, collections, run loops |
| `libagora-text` | Core Text — text layout and fonts |
| `libagora-drawing` | Core Graphics — the 2D drawing and geometry model |
| `libagora-base` | Foundation — Objective-C collections, strings, dates, files, notifications |
| `libagora-app` | Application Kit (AppKit) — windows, views, controls, the menu model |

### Supporting libraries

| repository | what it is |
|---|---|
| `libagora-objc` | the Objective-C runtime (GNUstep libobjc2) — the runtime Foundation and the desktop are compiled against |
| `libagora-dispatch` | libdispatch — Grand Central Dispatch and the blocks runtime, which Core Foundation and the rest of the stack build on |
| `libagora-lcms2` | little CMS — the colour-management engine Core Graphics uses for colour spaces and colour conversion |

### The desktop

| repository | what it is |
|---|---|
| `window-server` | the Wayland compositor: Agora's implementation of the Mac window server — outputs, seats, input routing, surface roles, layers |
| `libagora-watch` | the change stream — a path changed, and here is which way |
| `libagora-iconservices` | Icon Services — the icon an item or a type is drawn with: the lookup, the representations, and the vendored Frost default theme |
| `libagora-launchservices` | Launch Services — the type model (Uniform Type Identifiers), and what opens what |
| `widget-zoo` | a demonstration application: the view and control classes and the menu system |
| `workspace` | Workspace — the desktop surface (wallpaper, icons, menu bar) and the file-manager windows; an application, consuming the AppKit |
| `dock` | the Dock — running applications as tiles, in a vertical strip on the right (or the left), at `NSDockWindowLevel` and reserving its edge; an application, a separate client of the window server |

### Tooling

| repository | what it is |
|---|---|
| `swift-toolchain` | the Swift-on-Agora toolchain: build scripts, the Swift-fork patch set, and the ObjectiveC and Foundation overlays, with the gates that verify the ABI |
| `swift-interop-probe` | the two runnable probes (Swift importing Agora's Foundation; Objective-C calling a Swift subclass) and the C-side class-ABI probes |

### Assembly

| repository | what it is |
|---|---|
| `release` | the `release` repository (a submodule of this workspace): the same components, `main` following them and tags pinning them, plus the build that produces a desktop and an installable image |

## The installation

**A complete Agora installation carries the usual Mac OS X directories**, because the Cocoa surface it
implements NAMES its directories rather than searching for them: `/Applications`, `/Library`, `/System`,
`/Users` and `/Volumes` at the root, and `~/Applications`, `~/Desktop`, `~/Library` and the folders beside
them in every home. "As much as is needed for supporting Cocoa applications" is a checkable rule rather than
a licence to copy a Mac's tree: the table below is the whole set, and every row names the code that reads
it.

| directory | who names it |
|---|---|
| `/Applications`, `/Applications/Utilities`, `~/Applications` | Launch Services scans them (`libagora-launchservices/LaunchServices.c`), `-[NSWorkspace fullPathForApplication:]` searches them, Workspace's PLACES points at `/Applications`; a bundled application installed for all users belongs in `/Applications`, for one user in `~/Applications` |
| `/Library/Preferences`, `~/Library/Preferences` | CFPreferences' store on every host Agora builds for (`libagora-core/CFKnownLocations.c`, `CFPreferences.c`) — where `AppleLanguages` lives, which bundle localization asks for — and where a ported application expects its plist; Agora's own defaults store is the `Configuration/` scopes below (`NSUserDefaults`) |
| `/Library/Colors`, `~/Library/Colors` | `NSColorList` — the standard directory is `~/Library/Colors`, and `+availableColorLists` scans both |
| `/Library/Fonts`, `/System/Library/Fonts` | Core Graphics' font search (`libagora-drawing/CGFont.c`), with `~/Library/Fonts` beside them |
| `/System/Library/CoreServices` | `CFCopySystemVersion*` reads the version bundles there |
| `/System/Temporary Files` | `NSTemporaryDirectory()` answers it; the autosave path writes under it |
| `/System/Configuration`, `/Shared/Configuration`, `~/Configuration` | `NSUserDefaults`' system, shared and user scopes (created on demand) |
| `~/Library/Autosave` | `NSDocumentController`'s autosave directory |
| `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Movies`, `~/Music`, `~/Pictures`, `~/Public`, `~/Library/{Application Support,Caches,…}` | the search-path types `NSSearchPathForDirectoriesInDomains()` answers (`libagora-base/NSFileManager.m`) |
| `~/.Trash` | the Dock draws it as the can; `-trashItemAtURL:` does not move anything yet |
| `/Users`, `/Volumes` | the file-system hierarchy's own root set (`NSUserDirectory`; `fsh-notes.txt` in the FNX tree) |

`/Users` and `/Volumes` are the hierarchy's own rather than a program's: the first is where the FSH keeps
accounts — a hosted installation's accounts may live elsewhere, which is why the home half above is written
`~/` — and the second is the mount root.

**Two doors create it, and neither assumes the other ran.** The root half is part of the image:
`release/scripts/install-layout.sh` writes it, and the release runs it against the image root, so
`make install` and the Debian package both carry it (`dh_installdirs` is what keeps the empty ones in a
package). The home half belongs to an account and is created at login — the session script does it the way
it already creates `~/Desktop` — with `--user` for an installer preparing an existing account. Account
creation, when Agora has one, copies the same list.

**A program asks for the table instead of hard-coding a path.** `NSSearchPathForDirectoriesInDomains()`
answers it by directory type and domain, and `-URLForDirectory:inDomain:appropriateForURL:create:error:`
creates one that is missing. What it does not answer is named: the network domain (there is no `/Network`),
and `NSItemReplacementDirectory`, whose answer on a Mac is a new temporary directory per call rather than a
location.

## Where to start

- **Run the default session.** `demo/agora-session.sh` starts the window server, the wallpaper client and
  Workspace nested on an X11 desktop.
- **Run the demo.** `demo/agora-demo.sh` adds the controls application to that scene to show two applications
  sharing one menu bar (`demo/README.md`).
- **Build a component.** Each repository's `README.md` carries its build (CMake, into `build/`,
  installing into a shared SDK prefix). The dependency order is the one `release/components.conf`
  records, which the release driver checks.
- **Read the design record.** `WORKSPACE-PLAN.md` (the shell's stages), `COCOA-10.11-SURFACE-PLAN.md`
  (the four frameworks' 10.11 API surface and the plan to reach it), `SWIFT-PORT-HANDOFF.md`
  (where the Swift port stands), `SWIFT-FOUNDATION-PARITY-PLAN.md` (how the Swift Foundation surface
  reaches parity with Apple's), `DEVELOPMENT-TOOLS.md` (the interface-format/build-tool/IDE
  exploration), `RUST-BINDINGS.md`.
- **Build the Swift toolchain.** `swift-toolchain/README.md` — it needs the bootstrap Swift release
  and this stack's `build-prefix`, and installs under `~/.agora-swift`.

## Conventions

- **Language: Objective-C.** The stack and the desktop are written in Objective-C (Objective-C 2.0,
  ARC). The system-facing layer drops to C where the platform demands it (Wayland, KMS, and
  friends); Core Foundation is C by design.
- **Compiler: clang only.** The whole project builds with clang (and clang++ for Objective-C), on
  Linux and BSD. GCC is not a supported compiler.
- **Naming.** Reusable libraries are `libagora-<domain>` (`libagora-core`, `libagora-base`, …);
  programs take a plain kebab-case name (`window-server`, `widget-zoo`).
- **Bundle identity.** Every first-party application bundle declares
  **`io.github.agoradesktop.NAME`** — the component's name in lower case, because an identifier is reverse-DNS
  and Apple's own are (`com.apple.finder`, `com.apple.dock`), while `CFBundleName` keeps the product's spelling
  (`Workspace`). The identifier is what a window's `set_app_id` carries, what a shell groups windows by, and what
  Launch Services keys its registry on, so it is a source-compatibility fact and not a caption: renaming a
  bundle renames the window's application. Libraries carry no identity of their own (their `Info.plist`s, where
  they have one, record what they *are*, not what they would be called in a Dock).
- **One repo per component.** Each repository is self-contained: its own build, its own tests, its
  own `README`.
- **Build into `build/`.** Each repository builds into its own top-level `build/` directory, which
  git ignores. A component consumes another only as that component's *built* output (a package or a
  library) — never by building a sibling inside the consumer's own build tree.
- **Every library is shared.** Components build `<name>.so`, never a static archive: there is no
  static configuration. A consumer loads the whole library, so an Objective-C category in it is
  registered whether or not anything references its symbols — a static archive drops such members and
  their categories silently stop answering — and the Objective-C runtime and Core Foundation state are
  shared rather than duplicated per binary.
- **Pins, not floating versions.** Components never depend on each other by a moving version. The
  `release` repository records the exact combination that was built and tested.
- **Third-party code is a component.** Libraries taken from elsewhere become pinned Agora components
  of their own — `libagora-core` and `libagora-dispatch` are both extracted from upstream at a pinned
  revision, not vendored inside a consumer.
- **Third-party *art* that is data may be vendored, pinned and attributed.** The interim default icon
  set is **Frost** (MIT, v0.3.1), committed as its built PNGs in `libagora-iconservices/themes/Frost`
  with a provenance record and its own licence. It is data, not linked code, and the rule above still
  governs code. `AGORA_ICON_THEME` can replace it at run time, and Icon Services' drawn generics remain
  the fallback. **The default font set is the same kind of asset**: `libagora-drawing/fonts/` carries
  open-licensed faces (SIL OFL 1.1 and Apache 2.0, each with its licence beside it) that fill the roles
  macOS fills with its non-redistributable catalogue, plus a provenance record with upstream revisions
  and checksums. `FN_FONT_PATH` replaces the search path, `AGORA_UI_FONT`/`AGORA_MONO_FONT` replace the
  role preferences, and a host font of the same name still wins an exact match.
- **System ICU.** Text, locale and formatting support uses the platform's **ICU** directly; Agora
  neither vendors ICU nor pins a copy of it.
- **System OpenSSL.** Cryptography uses the platform's **OpenSSL** directly, on the same terms as
  ICU: Agora does not vendor a TLS library or pin a copy of one.
- **No systemd.** No component depends on any systemd component — `libsystemd`, `sd-bus`, logind or its fork
  `elogind`, the `systemd` daemon, or `libudev`/`udev` — because the desktop targets **Linux, FreeBSD, NetBSD
  and OpenBSD** alike. The bar holds even where a systemd component's licence would be permissive.
- **Agora's own licence is copyleft; third-party code is taken permissively where it costs nothing.**
  The libraries are **LGPL-3.0-or-later** and the programs **GPL-3.0-or-later** (`LICENSE`,
  `LICENSE-CHANGE.md`). That is not a preference: `libagora-core` and `libagora-dispatch` are
  Apache-2.0 and every binary links them, and Apache-2.0 is compatible with GPL-3.0/LGPL-3.0 only — it
  is incompatible with GPL-2.0 and LGPL-2.1. Version 3 is the only copyleft the combination resolves as.
  Beyond that, third-party code is still taken **permissively wherever a permissive option exists** —
  MIT, BSD, Apache-2.0, zlib, public domain — because that keeps the widest room to move; **LGPL-2.1/3.0**
  and **MPL-2.0** are accepted. **GPL-2.0 is excluded** (incompatible with the Apache-2.0 foundation) and
  **AGPL-3.0 is excluded** (it would make every component AGPL). **GPL-3.0-or-later is accepted**, since
  Agora already is. Third-party trees keep their own terms and their own notices — `THIRD-PARTY.md` is
  the register — and a library taken from elsewhere becomes a pinned component of its own rather than
  being vendored inside a consumer.
- **Apple's names are descriptive.** Names like "Cocoa", "Core Graphics" and "AppKit" describe the
  surface being duplicated. They are not Agora's product names, and no Apple marks or assets ship.

## Provenance: auditing for copied code

Agora reimplements an API that GNUstep also reimplements, so the two trees converge in places without
anyone copying anything. Telling those cases apart is a measurement, not an opinion, and it is kept
runnable in `audit/`.

**Run it** whenever code is added that was produced with model assistance, and whenever a new upstream
is proposed as a source:

```sh
cd audit && ./audit.py setup          # clone the pinned comparison trees
./audit.py prose --control            # comment prose - the probative channel
./audit.py code  --control            # code tokens - produces candidates
./audit.py explain LIBAGORA-FILE CORPUS-FILE   # inspect one candidate
```

The corpus is `gnustep/libs-base`, `gnustep/libs-gui`, Apple's
`swift-corelibs-foundation`/`-libdispatch`, and Cocotron (`cjwl/cocotron`) — both
independent implementations of this API plus Apple's own — pinned in
`audit/audit.py`. **`--control` is not optional:**
it runs the same comparison against `libagora-core` and `libagora-dispatch`, which are known verbatim
extractions, so the control must light up — if it does not, the tool is broken and a clean result means
nothing.

The two channels answer different questions. **Comment prose is the probative one**: code can coincide
because the specification forces it, but a shared 12-word run of comment text cannot be explained that
way. A code collision is a candidate to inspect, not a finding; the expected benign shape is a
declaration or a thin delegating body, which any implementation of that API must produce. The recorded
run, its numbers and the tool's own failure modes are in `audit/README.md`.

**If a file is found to contain copied code or prose**, in this order:

1. **Rewrite the span.** Cheap, always preferred, and the only outcome that leaves the file's
   provenance clean.
2. **If it cannot be rewritten**, keep it and mark it honestly — reproduce the upstream copyright
   notice on that file, leave it under that upstream's own terms (GNUstep's LGPL-2.1-or-later
   upgrades cleanly into this tree's LGPL-3.0-or-later; Cocotron's MIT composes with either),
   and add a row to `THIRD-PARTY.md`.
3. **Record it** in `release/debian/copyright` and in `audit/README.md`, so the next run sees a known
   file rather than a surprise.

What must not happen is a blanket per-file "may derive from" notice returning. One was carried on every
file until the 2026-10-22 audit; it covered nothing, was false for all ~1,100 files, and made a real
match harder to spot.

## Assumptions to confirm

These are taken as given for now, but are not yet ratified:

- **Display target: Wayland.** Agora's window server is a Wayland compositor; X clients arrive via
  Xwayland. There is no X11-native target.
- **Licence: LGPL-3.0-or-later** for libraries and **GPL-3.0-or-later** for programs (`LICENSE`) —
  version 3 rather than 2.1 because Apache-2.0 is incompatible with GPL-2.0/LGPL-2.1; see
  `LICENSE-CHANGE.md` for the reasoning and for what is deliberately not relicensed.
- **Objective-C runtime: libobjc2** (portable, ARC, blocks) rather than Apple's runtime.

## Open questions

- **The component split.** The first thirteen components are named; the rest — the file manager, system
  preferences, further applications, and any protocol or session repositories — are still to be
  decided.
- **Remote hosting and naming** for every component repository — *resolved*: repositories live under
  the `AgoraDesktop` organisation, and `.gitmodules` records their URLs.
- **The `release` repository itself** — *resolved*: it is a separate repository, checked in here as the
  `release/` submodule; its `main` follows the components and its **tags** pin them. Its **build
  system** is still open: distribution packages, a bootable/installable image, or both.
- **The session model and the reference application set's order** — deferred until the split above
  is settled.
