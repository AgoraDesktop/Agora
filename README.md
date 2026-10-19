# Agora

*An installable desktop environment for Linux and the BSDs: the Cocoa stack, a Mac-like desktop, and its
applications — written in Objective-C, built from source.*

**Status: working, pre-release.** The components are implemented and run together: Foundation,
Core Graphics, Core Text and the Application Kit carry the Cocoa surface an application uses; the
window server is a Wayland compositor with client-side chrome, layers and input routing; the Workspace
shell draws the desktop, icons and menu bar; and `demo/agora-demo.sh` starts all of them nested on an
X11 desktop. There is also a Swift toolchain that compiles Swift against this stack (the standard
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

Everything is compiled from source. A single **release** repository composes a whole desktop by
pinning, in a tagged release, one exact revision of every component.

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
| `libagora-iconservices` | Icon Services — the icon an item or a type is drawn with: the lookup and the representations |
| `libagora-launchservices` | Launch Services — the type model (Uniform Type Identifiers), and what opens what |
| `widget-zoo` | a demonstration application: the view and control classes and the menu system |
| `workspace` | Workspace — the desktop surface (wallpaper, icons, menu bar) and the file-manager windows; an application, consuming the AppKit |

### Tooling

| repository | what it is |
|---|---|
| `swift-toolchain` | the Swift-on-Agora toolchain: build scripts, the Swift-fork patch set, and the ObjectiveC and Foundation overlays, with the gates that verify the ABI |
| `swift-interop-probe` | the two runnable probes (Swift importing Agora's Foundation; Objective-C calling a Swift subclass) and the C-side class-ABI probes |

### Assembly

| repository | what it is |
|---|---|
| `release` | the `release` repository (a submodule of this workspace): the same components, `main` following them and tags pinning them, plus the build that produces a desktop and an installable image |

## Where to start

- **Run the demo.** `demo/agora-demo.sh` starts the window server, Workspace and the controls
  application nested on an X11 desktop (`demo/README.md`).
- **Build a component.** Each repository's `README.md` carries its build (CMake, into `build/`,
  installing into a shared SDK prefix). The dependency order is the one `release/components.conf`
  records, which the release driver checks.
- **Read the design record.** `WORKSPACE-PLAN.md` (the shell's stages), `SWIFT-PORT-HANDOFF.md`
  (where the Swift port stands), `DEVELOPMENT-TOOLS.md` (the interface-format/build-tool/IDE
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
- **System ICU.** Text, locale and formatting support uses the platform's **ICU** directly; Agora
  neither vendors ICU nor pins a copy of it.
- **System OpenSSL.** Cryptography uses the platform's **OpenSSL** directly, on the same terms as
  ICU: Agora does not vendor a TLS library or pin a copy of one.
- **No systemd.** No component depends on any systemd component — `libsystemd`, `sd-bus`, logind or its fork
  `elogind`, the `systemd` daemon, or `libudev`/`udev` — because the desktop targets **Linux, FreeBSD, NetBSD
  and OpenBSD** alike. The bar holds even where a systemd component's licence would be permissive.
- **Permissive licences first; linking-safe copyleft only by dynamic link, where unavoidable.** The
  shipped desktop is permissively licensed and takes permissive third-party code — MIT, BSD, Apache-2.0,
  zlib, public domain — wherever it can. Where no permissive option exists, an **LGPL-2.1/3.0** library, or
  a linking-safe equivalent such as **MPL-2.0**, may be used **dynamically linked only — never static,
  never vendored** (the *Every library is shared* rule above already builds our own libraries this way), so
  that the library's terms stay on the library and never reach Agora's code; its notice, source and
  replaceability conditions are the library's to meet. **GPL and AGPL are excluded** — they have no linking
  exception. *(Agora's own licence is MIT — see `LICENSE`.)*
- **Apple's names are descriptive.** Names like "Cocoa", "Core Graphics" and "AppKit" describe the
  surface being duplicated. They are not Agora's product names, and no Apple marks or assets ship.

## Assumptions to confirm

These are taken as given for now, but are not yet ratified:

- **Display target: Wayland.** Agora's window server is a Wayland compositor; X clients arrive via
  Xwayland. There is no X11-native target.
- **Licence: MIT, permissive-first** (stated above; `LICENSE`) — with a dynamic-link fallback for linking-safe
  copyleft where no permissive option exists.
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
