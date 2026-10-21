# Workspace — a development plan

*Status: **plan.** This specifies the file manager the project README lists as an open question
("the file manager, system preferences, further applications … are not yet specified"). It is written in the
house style of `window-server/DESIGN.md` and `DEVELOPMENT-TOOLS.md`: every claim is tied to a file that
exists, every recommendation is marked as one, and the things that are refused are named rather than left to
be discovered. Nothing here is scheduled.*

**`Workspace` is the application's name** — Agora's file manager and desktop. It is not a
product name in the sense the project README warns about ("Apple's names are descriptive"); it is a role name,
like `Kestrel` is the window manager's and `Argentum` is the design language's.*

**Naming rule.** The application and every class, file, target, executable and user-visible string is named for
**Workspace**. A third-party product's name is never used, in whole or in part, for our software; an imported
Apple identifier survives only where the exact spelling is required for source compatibility.

---

## Verdict

**The premise buys less than it looks like, and that is the first thing this plan has to say.** "AppKit meets
10.6's standard" gives Workspace its *presentation* layer for free — the windows, views, cells, menus, controls,
scroll/tracking/text systems, `NSWorkspace`, `NSFileManager` — but **the 10.6 reference file manager was not primarily an
AppKit program.** It was a client of the **Core Services** band — and of the **Application Services** pieces
beside it: the CarbonCore File Manager (`FSRef`, `FSCatalogInfo`, aliases), **Launch Services** (types, default
applications, `Open With`), **Icon Services** (file and type icons),
**Metadata/Spotlight** (`NSMetadataQuery`, `Kind`, Smart Folders), **FSEvents** (live views), plus **Quick Look**,
**DiskArbitration**, and the network-share stack. Apple never exposed any of those as part of AppKit, and none of
them is in this tree's component list.

So the honest shape of the work is:

```
        assumed complete                     MISSING, and on the critical path
   ┌───────────────────────┐         ┌──────────────────────────────────────────────┐
   │  AppKit 10.6          │         │  system-services substrate                    │
   │  NSWorkspace          │  uses   │  launch services · icon services · file watch │
   │  NSFileManager        │ ──────► │  metadata store · trash · disk arbitration    │
   │  NSOutline/Table/Browser         └──────────────────────────────────────────────┘
   └───────────────────────┘                          ▲
              ▲                                       │
              │                          ┌────────────┴─────────────┐
              │                          │  Workspace.app            │
              │                          │  windows + DESKTOP window │
              └──────────────────────────┤  (a shell component, not  │
                                         │   one of the reference    │
                                         │   applications)           │
                                         └───────────────────────────┘
```

**Workspace is therefore not one component's worth of work; it is one application plus four to six small
libraries that 10.6 assumed the system already had.** The plan below separates those two piles, because
conflating them is how a file-manager project becomes a two-year detour into an indexer.

And one more thing the premise does *not* decide, which the prompt closes by fiat: **Workspace owns the
desktop.** On the Mac the system file manager is a single, never-quitting process that owns both the file windows and the
desktop window, and the desktop is not a separate program. Agora already splits the *Dock* out as its own client
(`window-server/DESIGN.md`: "the Dock is one of them"); this plan does **not** split the desktop out, because
desktop icons and file windows share one drag session, one icon-layout engine, one selection and one metadata
store, and separating them would make every one of those an IPC problem.

---

## 1. What the premise actually gives Workspace

Grounding each row in the tree, so the boundary is measured rather than asserted.

| Workspace needs | Owner at 10.6 | State in this tree |
|---|---|---|
| A window with client-side chrome, placement, levels | AppKit | **present** — `libagora-app/NSWindow.h`; `agora_shell` levels (`set_frame`, `set_level`, `work_area`) in `window-server/protocol/agora-shell.xml` |
| A work area to constrain a frame to | AppKit + server | **present** — `NSScreen.visibleFrame` is the server's `agora_output.work_area`; `window-server/src/shell.c:aws_shell_reserved` |
| Lists, outlines, columns, toolbars, split views | AppKit | **assumed** by the premise (`NSOutlineView`, `NSTableView`, `NSBrowser`, `NSToolbar`, `NSSplitView`) |
| Directory enumeration, copy/move/remove, attributes | Foundation | **present** — `libagora-base/NSFileManager.h` (including `trashItemAtURL:`, `mountedVolumeURLsIncludingResourceValuesForKeys:`, `URLForDirectory:`, display names) |
| File URLs and resource values (kind, size, dates, icon, label) | Foundation | **present in shape** — `libagora-base/NSURL.h` (resource-value doors) |
| Open / reveal / launch an item, default application, notifications | AppKit `NSWorkspace` | **assumed** by the premise; **its platform backing does not exist** (see §2) |
| Type identity (`Kind`, `Open With`, which app owns an extension) | Launch Services | **absent** |
| File and type icons, custom icons | Icon Services | **absent** |
| A directory that announces changes | FSEvents | **absent** (backing: `inotify` on Linux, `kqueue` on the BSDs) |
| Find by name / by content, Smart Folders | Spotlight | **absent** |
| Quick Look preview panel and generators | Quick Look framework | **absent** |
| Volumes, mount/eject, device notifications | DiskArbitration | **absent** |
| Network shares (AFP/SMB/NFS) | kernel + NetFS/Bonjour | **absent** |
| The desktop it draws itself | the system file manager | **Workspace's** — see §3 |
| The Trash the Dock shows | the system file manager (`~/.Trash`, per-volume `.Trash`) | **workspace's**, with a Dock contract |

**The two rows that matter for sequencing are Type identity and Icons.** Almost every view in a file manager — icon
view, list view's `Kind` column, `Get Info`, `Open With`, the sidebar's application list — is downstream of a
type registry and an icon lookup. They are the smallest substrate libraries and they unblock the most; they go
first (§6, stage F1/F2).

---

## 2. The system-services gap, named

**"Core Services" is Apple's band, not one framework, and the reference file manager reaches across the bands beside it too.**
Under AppKit sits **Core Services** — delivered as the `CoreServices.framework` umbrella, which bundles
CarbonCore, Launch Services, Metadata, FSEvents, SharedFileList, Search Kit and more — together with the
**Application Services** pieces the UI kits share (Icon Services, Quick Look) and the standalone **domain
frameworks** (DiskArbitration, Security). Core Foundation is *below* all of it: `libagora-core` is the
vocabulary (strings, arrays, run loops, URLs), while this layer is the system's *answers* about files,
applications, types, volumes and the machine. Per the project's one-component-one-repository rule each becomes
its own repository; per "third-party code is a component" each names its backing source. Names are proposed,
not binding, and follow the `libagora-<domain>` convention.

| Proposed component | What it provides | Apple's home — the face it answers | Candidate backing (licence) | Backing on Linux/BSD | Criticality |
|---|---|---|---|---|---|
| `libagora-launchservices` | Apple's type model: a **UTI** registry (conformance hierarchy + tag declarations), an application registry of **Agora bundles only**, and the handler bindings the default application and `Open With` are read from | **Core Services** → `LaunchServices.framework` (`LSGetApplicationForURL`, `LSCopyApplicationURLsForURL`, `LSCopyKindStringForURL`, `UTType*`) | **in-tree only** — Apple's UTI + LS model, fed solely by Agora bundles' `Info.plist`; no FreeDesktop and no external type database | Agora bundles in the app directories; **no foreign applications** are run or registered | **critical path** — blocks stages F1, W3, W9 |
| `libagora-iconservices` | icon lookup for a file/type/application; raster at the sizes a view asks; compositing of a badge over a base icon; custom icons | **Application Services** → `IconServices.framework` (`IconRef`, `GetIconRef`, `ReadIconFile`; wrapped by `NSWorkspace -iconForFile:`) | **no third-party library** — PNG via `libagora-drawing`'s `CGImageCreateWithPNGDataProvider`, generics drawn with Core Graphics, `.icns` (PNG entries) in-tree; SVG deferred (nanosvg Zlib) | in-tree `.icns` reader + bundle scan; no foreign data | **critical path** — blocks W1, W3, W9 |
| `libagora-watch` | a per-directory change stream with coalescing and a startup rescan; the "something changed under this path" event | **Core Services** → `FSEvents.framework` (`FSEventStreamCreate`; newer code also uses a `DISPATCH_SOURCE_TYPE_VNODE` source) | none — raw `inotify` / `kqueue` | `inotify` (Linux); `kqueue` `EVFILT_VNODE` (FreeBSD, NetBSD, OpenBSD) | **critical path** — blocks live views, W1 onward |
| `libagora-quicklook` | a preview-panel host and a generator-plugin ABI; built-in generators for text, images, PDF, media | **Application Services** → `QuickLook.framework` (`QLPreviewPanel`; generator bundles) | **libpng / libjpeg-turbo / libwebp** (permissive ✓), **pdfium** (BSD-3 ✓), **ogg/vorbis/opus/flac** (BSD-3 ✓), **minimp3** (CC0 ✓); video: **FFmpeg (LGPL, dyn)** — fallback only | in-tree; reuses `libagora-text`, `libagora-drawing` | high — blocks cover-flow, Spacebar preview, W10 |
| `libagora-metadata` | a content/attribute index with an importer-plugin ABI and a query language | **Core Services** → `Metadata.framework` (`MDItem`, `MDQuery`; wrapped by `NSMetadataQuery`) | **SQLite + FTS5** (Public Domain ✓) | in-tree schema, importers and query over SQLite (**candidate**, §5.5) | medium — blocks full search, W11 |
| `libagora-sharedfilelist` | the user-editable system lists a sidebar and a login are made of | **Core Services** → `SharedFileList.framework` (`LSSharedFileList`) | in-tree store (no candidate needed) | in-tree store; the session consumes the same list | medium — blocks the W2 sidebar and login items |
| `libagora-disk` | volume enumeration, mount/eject, mount/unmount notifications | **Domain framework** → `DiskArbitration.framework` (`DADiskRef`) | **in-tree**; no udev, no udisks2, no libmount | Linux: `/sys` + `mount(2)`; FreeBSD: `libgeom` + `devctl`; NetBSD & OpenBSD: `getmntinfo` + `mount(2)` | medium — blocks Devices sidebar, W12 |
| `libagora-netfs` | remote share browsing and mounting | `NetFS.framework`; discovery via Bonjour (`NSNetService`), transport via CFNetwork | discovery: **mDNSResponder** (Apache-2.0 ✓); SMB: **libsmb2** (LGPL-2.1, dyn); NFS: **libnfs** (LGPL-2.1, dyn); Samba ✗ (GPL-3.0) | SMB/NFS via the kernel or libsmb2/libnfs (dynamic); discovery via mDNS | low — defer to W12 |
| `session` (name TBD) | login/session start, launching the shell's components at login, app lifetime | **Darwin** → `launchd` + loginwindow (not a Core Services framework) | in-tree; **libdbus** (AFL-2.1) if a bus is used; **no systemd, logind, elogind or sd-bus** | in-tree session manager; no logind | medium — blocks "Workspace at login", Force Quit |
| `Dock` (name TBD) | the Dock as its own client; the Trash icon; running-app list | Apple's `Dock.app` (a desktop client, not a framework) | in-tree | in-tree; an `agora_shell` client at `NSDockWindowLevel` | medium — blocks Trash drop, but not desktop |

**Three parts of the band deliberately get no repository of their own.** The **CarbonCore File Manager**
(`FSRef`, `FSCatalogInfo`, `FSGetCatalogInfo`) and **Alias Manager** (`AliasHandle`, `FSResolveAlias`) are the
largest thing inside `CoreServices.framework`, but their job is already answered by
`libagora-base/NSFileManager.h` and by `NSURL` bookmarks respectively — so `WSAlias` (§5.2) is the
bookmark-shaped answer where the Alias Manager would have been. **CFNetwork** is likewise answered by
Foundation's `NSURL` doors. **Search Kit** (an app-level inverted index) and **DictionaryServices** (the
"Look Up in Dictionary" service) are named and not built: neither is required for parity with the reference, and the latter
arrives with the Services menu in W13.

**Several of these are runtime *services*, not merely libraries, and that is a decision to make:** the Spotlight
answer is normally a daemon (`mds`) with importer bundles, and Launch Services/Icon Services maintain databases
that must be rebuilt when applications are installed. Agora can start each as a library with an in-process
database and only split out a daemon if a second consumer appears. **Recommendation: library first, daemon only
when forced**, matching the window server's own "a file rather than a change" test for new backends
(`window-server/src/server.h`).

### The licence gate

**The rule is permissive-first, with a dynamic-link fallback — and the fallback is the ruling.** The project
prefers permissive code, and every candidate above is taken through one of four patterns, in order. *This
replaces the README's former blanket "No GPL/LGPL in the shipped desktop" line, which the ruling has amended
to match.*

1. **A permissive third-party library extracted as its own pinned component** — the `libagora-lcms2` pattern
   (`libagora-core` and `libagora-dispatch` are the same shape): a component of its own, pinned, never vendored
   into a consumer. SQLite, libarchive, pdfium and nanosvg belong here.
2. **A permissive *system* library used directly** — the **ICU** and **OpenSSL** pattern the README already
   states. Where every target ships the library there is no component to add and possibly no wrapper to write:
   libpng, libjpeg-turbo, libwebp, zlib and freetype (under the FTL) belong here.
3. **A linking-safe copyleft library, dynamically linked, only where no permissive alternative exists** — **the
   ruling: LGPL-2.1/3.0, and linking-safe equivalents such as MPL-2.0, may be linked DYNAMICALLY, and doing so
   does not taint our shipping code.** The licence text is explicit: LGPL-2.1 §5 makes our program a "work that
   uses the Library", *"not a derivative work"*, and §6 (or LGPL-3.0 §4) lets the combined work be distributed
   *"under terms of your choice"* — MIT — provided the **Library's** conditions are met. Those conditions bind
   the library, not us, and they are: a suitable **shared**-library mechanism (§6(b) / §4d1 — *never* static,
   never vendored); notice and a copy of the LGPL (and of the GPL for LGPL-3); the library's source or a written
   offer; the user's ability to replace it with an interface-compatible modified build; and, for **LGPL-3 on a
   User Product** (a shipped image), Installation Information. **Our components remain MIT.**
4. **The service as a *process*, not a linked library** — an IPC call or a CLI invocation is not linking at
   all, and is the answer for a **GPL** daemon (e.g. `udisks2`). It makes the daemon a **runtime** dependency,
   which is its own decision, but it taints nothing.

**Excluded outright — no linking exception, so even a dynamic link reaches us**: `poppler` (GPL-2.0),
`samba`/`libsmbclient` (GPL-3.0), `shared-mime-info` (GPL-2.0+), `mupdf` (AGPL-3.0). A GPL tool may still be
*run* as a process under rule 4; it may not be linked.

**Permissible under rule 3, and only while no permissive answer exists** — each is a last resort, not a
default: `avahi`, `libnfs`, `libsmb2`, `libicns`, `libexif`, `librsvg`, `glib`/`gio`, `gvfs` (LGPL); an LGPL
build of `FFmpeg`. The condition does real work: nanosvg already beats librsvg, and mDNSResponder already beats
Avahi. **`libudev`, the `systemd` libraries and `sd-bus` are not on this list at all — they are barred by the
no-systemd rule (Portability below), not weighed by licence; `libmount`/util-linux is barred by being Linux-only.**

**The two former "no permissive option" cases now have a rule-3 fallback**: the **network clients** (SMB via
`libsmb2`, NFS via `libnfs` — both LGPL-2.1, dynamically linked; Samba's `libsmbclient` is GPL-3.0 and stays
out) and **video decoding** (an LGPL build of FFmpeg).

**`libdbus` is not a rule-3 case — it is permissive.** The D-Bus reference implementation is dual-licensed
**AFL-2.1 or GPL-2.0+**; taken under **AFL-2.1 it is non-copyleft**, so the IPC transport itself adds no
obligation and needs no dynamic-link discipline — and it is portable, so it stands on every target. **Using
D-Bus under its permissive terms is acceptable.** `sd-bus` is barred (systemd), and the `udisks2` daemon is
Linux/udev-bound and so is not a portable backend.

**A ✓ above is a one-file check made while writing this plan, not a per-file audit, and the ruling is a
*policy* reading of the licence text — there is no case law.** `libjpeg-turbo`, `libarchive`, `pdfium`, `flac`
and `util-linux` are multi-licence projects, and the library that matters can differ from the project — the
`libmount`-inside-`util-linux` distinction is the one that bites. Each component still owes a `PROVENANCE.md`
in the `libagora-text` pattern, pinning the revision, the licence **per file**, and — for any rule-3
dependency — the dynamic-link decision and its compliance obligations.

### Portability — Linux and the BSDs, and no systemd

**Workspace targets Linux, FreeBSD, NetBSD and OpenBSD — Wayland support permitting** (`README.md`). Two rules
follow, and the first outranks the licence gate:

1. **No systemd component, on any target, at any price.** `libsystemd`, `sd-bus`, logind and its fork
   `elogind`, the `systemd` daemon, and `libudev`/`udev` are **barred** — barred even where a licence would
   permit them. Appearing in a "permissible under rule 3" list is not a way in.
2. **A Linux-only backend is not a backend.** `libinput`, `udisks2`, `libmount`/util-linux and `/sys` are
   Linux's, not the desktop's; each platform uses its own kernel's interface.

| Concern | Linux | FreeBSD | NetBSD / OpenBSD |
|---|---|---|---|
| file watching (F3) | `inotify` | `kqueue` (`EVFILT_VNODE`) | `kqueue` |
| volumes (`libagora-disk`) | `/sys` + `mount(2)` | `libgeom` + `devctl` | `getmntinfo` + `mount(2)` |
| seat / input | direct DRM + evdev, or a non-systemd seat manager (`seatd`, MIT) | direct device access | direct device access |
| session / IPC | in-tree; `libdbus` (AFL-2.1) if a bus is used | same | same |

**This reaches outside Workspace.** The window server's `libinput` path reads devices "through udev and logind"
(`window-server/README.md`) — both barred — so that backend must be revisited in its own repository (direct
device handling, or a non-systemd seat manager). Workspace's own substrate keeps to the table above; nothing it
names needs systemd.

---

## 3. Ownership, levels and the desktop

This is where Agora's architecture and the Mac's agree, and the seam must be stated before code is written.

- **The desktop is TWO LEVELS, and Workspace owns only the upper one.**
  * `kCGDesktopWindowLevel` — the **WALLPAPER**, a window of its own below every ordinary window, and **the
    Dock's to draw** (a stub in the tests until the Dock exists). The reference file manager drew it at 10.6; Agora gives that
    layer to the Dock so the desktop is a *shell* surface and not a file manager's private background.
  * `kCGDesktopIconWindowLevel` — the **ICONS**, and **Workspace's**: one borderless, **TRANSPARENT** window
    covering `[NSScreen frame]`, drawing ONLY the items of the desktop directory. The compositor blends it over
    the wallpaper (source-over), so the wallpaper shows through wherever there is no icon.
  The Dock (`NSDockWindowLevel`) and ordinary windows (`NSNormalWindowLevel`) sit above both, and **BOTH ARE UNDER
  THE SERVER'S MENU BAR**: the bar is composited at its own level (`AWS_MENU_BAR_LEVEL`, 24 — Apple's main-menu
  level), so the desktop is the furniture's background and not its coverer.
- **The desktop level is CoreGraphics vocabulary, and this tree's AppKit enumeration starts too high.**
  `libagora-app/NSWindow.h` defines `NSNormalWindowLevel = 0` and up; the desktop sits *below* it, in
  `CGWindowLevel.h`'s names (`kCGDesktopWindowLevel`, and `kCGDesktopIconWindowLevel` — see the same argument in
  `window-server/DESIGN.md`: the levels are named `kCG…` because ordering is the *server's* business).
  `libagora-drawing` now publishes those level names (`CGWindowLevel.h`, F4) — and F4 found the real blocker was
  not the header but the SERVER: `output.c` and `seat.c` walked the numeric range `lowest..highest`, so a
  desktop-level window spun ~2 billion passes per frame and hung the compositor. Both now walk the levels PRESENT.
- **The desktop window is not a normal window.** Borderless; `NSWindowCollectionBehaviorStationary |
  IgnoresCycle` (it must not appear in the Window menu or Cmd-\` cycling); never key and never in the window
  menu; its controller is deliberately not in the app's window list.
- **The server's background remains the fallback.** `window-server/ARGENTUM.md` records that the server fills
  `#A8DED9` by request; once Workspace runs, that fill is only seen before the desktop window maps or if
  Workspace dies. That is the correct priority order and should be written at the fill.
- **The Dock is a separate client and the Trash is a contract, not a file.** Workspace performs the recycle
  operation and owns `Put Back` and per-volume trash semantics; the Dock owns the Trash *icon* and receives the
  drop. The contract — a small service (a Wayland protocol, an in-tree IPC, or a shared library) — is
  **undecided** and is named in §5.
- **Workspace is launched by the session and does not quit.** With no session component yet, it is launched by
  hand and tested directly; the "never quits, relaunches at login, reopens windows" behaviour arrives with the
  `session` component (stage W13).

---

## 4. Product scope — the 10.6 reference

The 10.6 reference is the target. Measured against it, feature by feature:

**In scope (the standard)**
- Three window views: **Icon**, **List** (hierarchical, sortable columns), **Column** (`NSBrowser`).
- A window shell: toolbar (Back/Forward, the three-view switcher, Action, Quick Look, Labels, New Folder, Delete,
  Connect, Eject, Search), a **source list sidebar** (Devices / Shared / Places / Search For), a **path bar**,
  a **status bar**, and a proxy icon in the title.
- Navigation history (Back/Forward) per window.
- Selection, inline rename (with extension preserved), keyboard navigation, type-select.
- Drag and drop: move/copy/alias by modifier and volume, spring-loaded folders, drag to the Dock's Trash, drag
  out to other applications, drag in from other applications.
- File operations: New Folder, Duplicate, Move to Trash, Put Back, Empty Trash, Compress, Make Alias, Get Info
  (single and multiple / inspector), Move To, Copy To.
- The desktop: wallpaper, icons, selection, rubber band, double-click open, drag, Clean Up / Arrange By,
  Show View Options, the desktop's contextual menu, icon positions persisted.
- Get Info: kind, size, dates, permissions, `Open With`, preview, custom icon.
- Quick Look (Spacebar / panel / slideshow).
- Search: the search field, `This Mac` vs the current folder scope, saved **Smart Folders** in the sidebar.
- Volumes: the Devices section, eject, disk images.
- Services menu integration and `Open With` via Launch Services.

**Out of scope, and why** (each named rather than silently dropped)
- **iDisk / MobileMe** — dead; no answer to copy.
- **AppleScript / Automator / the scripting bridge** — needs an OSA this tree does not have; already refused by
  name in `libagora-app/NSApplication.h`.
- **Burn folders / optical media** — `libagora-disk` could carry it; deferred indefinitely.
- **Network browsing (AFP/SMB/NFS)** — real, but its own component and its own risk; stage W12.
- **Tabs** — tabs arrive in 10.7, after the pin. Correctly absent.
- **Tags (10.9+)** — the pin has **colour labels**, not tags. Do not build tags.

---

## 5. Decisions this plan must force

Each is a real fork; the plan states a recommendation and the file that would carry the answer.

1. **The per-directory metadata store (the `.DS_Store` question).** The Mac's answer is a hidden per-folder
   file, and the project rule is "where the Mac has an answer, Agora takes it" — but the **format is ours to
   choose**, exactly as `window-server/DESIGN.md` argues for the wire format. **Recommendation:** a per-folder
   sidecar in Agora's own property-list format, holding icon positions, view options (icon size, grid spacing,
   label position, sort/arrange), and per-item labels; filename Agora-owned (`.agora` is the placeholder).
   Per-item data that must survive a move (labels, custom-icon reference, `Quarantine`) goes in an **extended
   attribute** where the filesystem supports one, with the sidecar as fallback. `WSMetadataStore` is the only
   reader/writer. **Owner of the format: Workspace.**
2. **The alias format.** 10.6 aliases are Carbon Alias records; Agora has no Carbon and will not grow one.
   **Recommendation:** adopt `NSURL` bookmarks (10.6's own answer for the same problem) as the in-memory
   representation, and store an alias as a tiny Agora-owned record file carrying a bookmark plus a magic.
   Resolve-on-open, with the same "original moved" walk the Mac does. `WSAlias`.
3. **The Trash contract with the Dock.** Who performs the recycle when a drop lands on the Dock's Trash icon.
   **Recommendation:** Workspace owns the operation (per-volume trash directories, `Put Back` records,
   secure-empty), and exposes it as a small service the Dock calls; the Dock never touches the filesystem. The
   transport (a Wayland protocol extension, an in-tree IPC, or `libagora-netfs`-style shared library) is
   **open** and must be decided with whoever writes the Dock. `WSTrash`.
4. **Custom icons.** The Mac stores a folder's custom icon in an `Icon\r` file and flags it in the classic info record.
   **Recommendation:** Agora's own convention — a custom-icon reference in the sidecar, the image bytes in an
   sidecar blob or an xattr — because it needs no magic filename and no classic info record. **Owner: Workspace +
   `libagora-iconservices`.**
5. **Search architecture.** Live filename filtering needs no index; system-wide content search needs
   `libagora-metadata` and an importer ABI. **Recommendation:** three slices — W11a filters names in the
   current directory over `libagora-watch`; W11b adds a system-wide filename/attribute index; W11c adds content
   importers. Only W11a is required for 10.6 parity of the *search field*; Smart Folders require W11b+.
6. **The "Kind" string.** At 10.6, `Kind` comes from Launch Services' type database. Until
   `libagora-launchservices` exists, `Kind` is a fallback derived from the extension + `stat` mode.
   **Recommendation:** build the fallback first, swap it behind one door when F1 lands.
7. **The sidebar's Shared section and `Connect to Server`.** These require `libagora-netfs`. Named in scope but
   sequenced last; the sidebar renders the section empty rather than faking it.
8. **The type model is Apple's, and the application universe is closed.** Launch Services is keyed by **UTI**
   and fed by `Info.plist` declarations from **Agora bundles only** (F1). Agora does not run other desktops'
   applications, so no FreeDesktop input is imported — no `.desktop`, no MIME database, no `mimeapps.list`, no
   `xdg-open` — and no MIME-shaped API is exposed. The *model* and the *ingest* are both Apple's. **The closure
   is about *applications*, not system services**: D-Bus is used under its permissive AFL-2.1 option, and a GPL
   daemon such as `udisks2` is reached as a process (§2, rule 4).

---

## 6. Workspace's own structure

Workspace is an application **bundle** (`libagora-base/NSBundle.h` documents the `Contents/` layout), with one
`Info.plist` declaring its document/type roles once `libagora-launchservices` can read them. Proposed layout:

```
workspace/
  src/
    WSApplication.{h,m}            NSApplication subclass; owns the desktop and the window list
    WSDesktopWindow.{h,m}          the borderless desktop window at the CG desktop level
    WSDesktopView.{h,m}            wallpaper + icon grid + rubber band (reuses WSIconLayout)
    WSFileWindowController.{h,m} one file window; its own history, view mode, sort
    WSItemModel.{h,m}              THE shared model: one directory's items + change stream
    WSIconView.{h,m}               icon view (NSCollectionView-backed)
    WSListView.{h,m}               list view (NSOutlineView-backed)
    WSColumnView.{h,m}             column view (NSBrowser-backed)
    WSSidebarController.{h,m}      the source list
    WSToolbarController.{h,m}      the toolbar and its items
    WSPathBar.{h,m}  WSStatusBar.{h,m}
    WSIconLayout.{h,m}             grid arithmetic shared by desktop and icon view
    WSHistory.{h,m}                back/forward stacks
    WSFileOperations.{h,m}         copy/move/duplicate/rename/compress + undo + progress
    WSTrash.{h,m}                  recycle, Put Back, per-volume trash
    WSAlias.{h,m}                  alias/bookmark records
    WSMetadataStore.{h,m}          the sidecar format (§5.1)
    WSGetInfoWindowController.{h,m}
    WSSearchController.{h,m}
    WSServicesProvider.{h,m}       the Services menu provider
  Info.plist  README.md  DESIGN.md  tests/
```

**`WSItemModel` is the load-bearing class.** Every view is a rendering of the same model — a directory, its
items, the current sort and filter, and a change stream from `libagora-watch`. If the three views each own their
own enumeration, the project will produce four subtly different file managers; making the model one object is
the single decision that prevents that, and it is the same discipline `libagora-app` used when it made
`NSTextStorage`/`NSLayoutManager`/`NSTextContainer` one web rather than three ad-hoc stores
(`libagora-app/README.md`).

---

## 7. The staged plan

Stages are ordered by **dependency and by "what can be shown and measured"**, not by the reference file manager's menu order. Each
stage names the smallest honest deliverable, what it proves, and the test that holds it up. The F-stages are the
substrate; the W-stages are Workspace.

### F1 — Launch Services: the type registry

**THE MODEL IS APPLE'S, AND THE APPLICATION UNIVERSE IS CLOSED.** The registry is keyed by **UTI**, built from
**`UTExportedTypeDeclarations` / `UTImportedTypeDeclarations` / `CFBundleDocumentTypes`** in a bundle's
`Info.plist`, and answered through Apple's doors (`UTTypeCreatePreferredIdentifierForTag`,
`UTTypeCopyPreferredTagWithClass`, `UTTypeConformsTo`, `LSGetApplicationForURL`,
`LSCopyApplicationURLsForURL`, `LSCopyKindStringForURL`). Its inputs are **Agora bundles only**: Agora does not
run other desktops' applications, so there is **no `.desktop` importer, no MIME database, no `mimeapps.list`,
no `xdg-open`** — nothing FreeDesktop enters the model or the registry. Type identification follows Apple's LS,
**by declared tag** (filename extension, MIME, OSType) and not by an external magic database. The model *and*
the ingest are Apple's.

- **Deliverable:** `libagora-launchservices` — the UTI registry (conformance hierarchy + tag declarations), the
  application registry read from Agora bundles' `Info.plist`, the handler bindings, and the doors above. No
  third-party library and no foreign application source.
- **Proves:** an item has an identity independent of its extension; the default application and `Open With` can
  be answered from Agora's own applications; `UTTypeConformsTo` walks the hierarchy.
- **Test:** a fixture bundle tree of Agora apps — the declaring app is found for an extension, a moved bundle is
  re-found after a rescan, and `UTTypeConformsTo` walks the hierarchy. Nothing foreign is on the fixture.
- **Done (2026-10-16):** `libagora-launchservices` — C throughout over Core Foundation alone (`readelf`:
  `libagora-core.so` and libc, nothing else), **19 checks** in its own suite. See the component `README.md`.
- **And the OPENING DOOR landed with it:** `LSOpenCFURLRef` / `LSOpenURLsWithRole` spawn an application's
  process — a bundle, or a document in the application that owns its type — with activation, single-instance and
  lifetime left to the session; the `launch` suite is **9 checks**. **AND IT FOUND A CORE FOUNDATION BUG, NOW
  FIXED THERE:** `CFBundleCopyExecutableURL` answered NULL for a modern `.app` because the executables
  subdirectory name was the host's (`Linux`), not `Contents/MacOS`; fixed in `libagora-core`.

### F2 — Icon Services: the icon lookup
- **Deliverable:** `libagora-iconservices` returning a rasterised icon for a URL (via the type registry), an
  application, or a generic type, at requested sizes; a badge compositor.
- **Proves:** the icon view and `Get Info` have their images.
- **Test:** offscreen raster; assert an app's declared icon is found and that a `.txt` gets the generic document
  icon, at two sizes.
- **Done (2026-10-16):** `libagora-iconservices` — C over Core Graphics and Launch Services, **no third-party
  library** (PNG rides `libagora-drawing`), the generics drawn rather than shipped, **16 checks**. See the
  component `README.md`.
- **Interim default art (2026-10-19):** **Frost v0.3.1** (MIT) is vendored at
  `libagora-iconservices/themes/Frost`. A type's preferred MIME name is looked up there before the drawn
  generic (`image/png` → `image-png`, a folder → `folder`), both scales are representations, and
  `AGORA_ICON_THEME` overrides the installed default. It is data and not a linked dependency; the suite is
  **24 checks**. The choice and its pin are in `libagora-iconservices/themes/PROVENANCE.md`.

### F3 — Watch: the change stream
- **Deliverable:** `libagora-watch`, `inotify`/`kqueue`-backed, coalescing bursts, with a startup rescan so a change during
  subscription is not lost.
- **Proves:** a view can be live.
- **Test:** mutate a temp directory from a helper process; assert the stream reports create/remove/rename and
  coalesces a burst into one event.
- **Done (2026-10-16):** `libagora-watch` — FSEvents over `inotify` (measured on Linux) and `kqueue` (written,
  awaiting a BSD run), Core Foundation alone and nothing linked for the watching, **12 checks**. See the
  component `README.md`.

### F4 — The desktop level in CoreGraphics
- **Deliverable:** `kCGDesktopWindowLevel` / `kCGDesktopIconWindowLevel` published by `libagora-drawing`, and
  `window-server`'s level ordering made to walk the levels PRESENT rather than the numeric range between them —
  which is what "honours arbitrary levels" actually required.
- **Proves:** the desktop can be placed below everything.
- **Test:** a two-window seam test — a desktop-level window and a normal window — asserting the normal window
  composites above regardless of map order.
- **Done (2026-10-16):** `CGWindowLevel.h`/`.c` in `libagora-drawing` (Apple's key-plus-function shape; values
  agreeing with `NSWindow.h`), its order test, and the server fix. **MEASURED:** a desktop-level window HUNG the
  compositor — `output.c`/`seat.c` walked `lowest..highest`, ~2 billion passes per frame at `INT32_MIN + 20` vs 0
  — and both now walk the distinct levels; `window-server-headless` passes with the desktop-level client.

### W0 — Workspace exists and owns a desktop window
- **Deliverable:** `Workspace.app` launches against `agora_shell`, opens **one** borderless window at the desktop
  level covering `[NSScreen frame]`, and fills it with the Argentum wallpaper.
- **Proves:** the app/bundle/launch path, the desktop level, and the fact that the desktop is Workspace's.
- **Test:** `seam-desktop.sh` — headless `window-server` + Workspace for N frames + screenshot; assert the
  desktop fill covers the screen and that a normal window opened above it is composited on top.
- **Done (2026-10-16):** `workspace/` — `Workspace.app` (a real bundle) whose desktop window is borderless, at
  `kCGDesktopWindowLevel` (`-2147483628`, measured), the size of `[NSScreen frame]`, drawing the Argentum
  wallpaper as a vertical ramp. The suite is `workspace-desktop` (`tests/run-desktop.sh` + `check.py`),
  **9 checks**: coverage at every corner, the ramp the right way up, and a NORMAL window created *after* the
  desktop composited *over* it. **AND ONE THING FOUND, THEN FIXED:** the server's menu-bar strip was painted
  before the windows ("until the strip has a LEVEL of its own such a window covers it"), so the full-screen
  desktop used to cover it. The strip now has `AWS_MENU_BAR_LEVEL` (24) and is composited in the level walk, so
  the suite measures the fix — the MENU BAR is in the top rows, OVER the desktop — and the desktop's icons are
  padded below it by the bar's height plus ten points.

### W1 — Desktop icons
- **Deliverable:** `WSIconLayout` + `WSDesktopView`, backed by `WSItemModel`, showing `~/Desktop`; single/multi
  selection, rubber band, double-click open (via F1), drag to reposition, icon positions in `WSMetadataStore`.
- **Proves:** the desktop is a real file manager surface, not wallpaper.
- **Test:** `desktop_layout.m` (offscreen) for grid arithmetic, collision and arrange modes; `metadata_store.m`
  for a sidecar round-trip; a pixel test for icon presence at a stored position.
- **Done (2026-10-16):** `workspace/` shows `~/Desktop` (or `AGORA_DESKTOP`) as icons — **`WSIconLayout`**
  (column-major grid, nearest-free snap, arrange, hit test), **`WSMetadataStore`** (the per-folder `.agora`
  sidecar), and **`WSItemModel`** (the one directory model every view will read). The view draws an icon per item
  (`libagora-iconservices`), single/multi-selects, rubber-bands, drags to reposition (snapping to the nearest
  free cell and SAVING the sidecar) and double-click OPENS (F1's `LSOpenCFURLRef`; a folder is W2's window).
  **MEASURED:** `workspace-desktop-layout` and `workspace-metadata-store` offscreen, and the desktop pixel test
  is now **11 checks** — the icon appears at the stored position (900,300). **AND THE SIDECAR IS XML:** the plan
  said binary, this tree's serializer REFUSES binary, and a sidecar that diffs is the better answer anyway.
  **AND THE ICONS CLEAR THE MENU BAR:** the grid's ORIGIN is now the top of the AREA it fills rather than an
  inset it adds, and `WSDesktopView` pads that area by the menu bar's height (`NSStatusBar -thickness`) plus ten
  points — MEASURED: the first icon's box begins at y = 34.

### W1b — The application menu
- **Deliverable:** `WSMainMenu` (the bar's seven titles and the application menu's rows), `WSAboutPanel`,
  `WSPreferencesWindow`, and `WSApplication` as the two app-menu rows' target.
- **Proves:** the application is a Mac application rather than a full-screen picture — it has a menu bar, an About,
  and a Preferences that changes something real.
- **Test:** `main_menu.m` (offscreen: the bar's shape, each row's target and shortcut mask, and what `-update`'s
  enabling walk makes of every row); the desktop suite's SECOND SCENE, which reads the strip's ink with Workspace as
  the active application and confirms the bar is only as wide as its menus.
- **Done (2026-10-16):** seven menus — the application's own (About, Preferences…, Services, Hide, Hide Others,
  Show All, Quit) plus File, Edit, View, Go, Window, Help — installed through `-[NSApplication setMainMenu:]`, which
  inserts the application menu and moves Help last. **About and Preferences are real:** the first reads the bundle's
  own `Info.plist` through `NSBundle` and draws the icon, the name, the version and the identifier; the second
  changes the desktop icons' size through `WSMetadataStore` and SAVES it, so the `.agora` sidecar carries the
  preference. **AND THE MENUS BESIDE IT ARE A SKELETON, MEASURED RATHER THAN ASSUMED:** every File, View and Go row
  has no target and is greyed by `-update`'s walk; `workspace-main-menu` checks that, and pins the two rows that do
  NOT behave that way — the Edit menu's five chain-routed rows, which this tier's base `NSResponder` implements as
  forwarders, so the walk enables them where Apple's would not. **THREE FINDINGS, TWO OF THEM THE APPKIT'S**, are in
  `workspace/PROVENANCE.md`: the key-equivalent mask is ZERO by default here where Apple's is Command (so every row
  names its own); the bar's window was a RACE, now fixed at `-nextEventMatchingMask:` in `libagora-app`; and
  clicking the first title opens the application menu (MEASURED: a window at level 101) which a flood of spurious
  `NSLeftMouseDragged` events then dismisses. **THAT THIRD ONE IS NOW DIAGNOSED AND FIXED IN TWO COMPONENTS:** the
  session was begun and never driven, because this application pumped its own events and `NSMenuView`'s bar loop
  fetches only while `-[NSApplication isRunning]` — so `-runForSeconds:` now calls the ORDINARY LOOP, with the
  deadline riding `-applicationDidUpdate:`; and a RELEASE was ending the session, a rule written for a menu that
  owns its own loop where a bar's loop drains every window's queue instead (see `libagora-app/PROVENANCE.md` § 8).

### W2 — The file window shell
- **READY (2026-10-18): THE APPKIT PREREQUISITES ARE COMPLETE.** A file window is a toolbar, a sidebar, a path bar
  and a view switcher, and the AppKit now has all four: `NSToolbar` with `NSToolbarItemGroup`, the cell-based table
  and `NSOutlineView` in an `NSSplitView`, `NSSegmentedControl` for the switcher and `NSPathControl` for the bar.
  `NSBrowser` is here now (W5, table-backed); `NSSearchField` and `NSProgressIndicator` remain W10's and W6's. The W2 shell can be built now; **W2p** records the inventory that unblocked it. W4's list
  view also has its table foundation: editing, type-select, variable heights, column reordering, autosave and a local
  row drag are in; only the cross-process drag session waits for W7.
- **Deliverable:** `WSFileWindowController` with toolbar, sidebar, path bar, status bar, the three-view
  switcher (only Icon works), Back/Forward history, and the Places list; a second window shows a second folder.
- **Proves:** the window is a shell over `WSItemModel`, not a view.
- **Test:** `history.m` (back/forward semantics, including that a new navigation truncates the forward stack);
  a seam test that a window's status bar reports the item count of the model.
- **Done (2026-10-19):** `workspace/src/WSFileWindowController` assembles the shell from `NSToolbar` (Back,
  Forward, view switcher), `NSOutlineView` in an `NSSplitView` (PLACES and DEVICES from `WSPlaces`),
  `NSPathControl` and a status bar — all reading ONE `WSItemModel`. `WSHistory` is the Back/Forward stack and its
  truncation rule; `WSIconView` is the icon mode (W3); a desktop folder double-click
  posts `WSDesktopViewOpenFolderNotification` and the application opens a second window with its own model and
  history. Column is W5's now; List is W4's. **AND THE SHELL'S STRIPS ARE AUTO LAYOUT NOW:** the path bar is pinned
  to the content's top, the status bar to its bottom and the split view fills the band; the split's delegate keeps
  the sidebar's width and gives the content pane the rest, so a window resize moves the boundary instead of scaling
  both panes. **AND THE SIDEBAR'S DIVIDER IS A GUTTER:** the split view is in `NSSplitViewDividerStylePaneSplitter`, an
  eighteen-point three-ring grip a person can drag, and the sidebar's bar autohides when its rows fit.
  **MEASURED:** `workspace-history` (15 checks) and `workspace-file-window` (57 checks, including two
  window resizes and both panes), and the live `--file-window` scene (the first one found that a flipped ROOT content
  view is drawn with the wrong strip order in this tier's live path — the window keeps an unflipped content view,
  recorded in `workspace/PROVENANCE.md`).

### W2p — The AppKit prerequisites for the file window
- **Why it exists:** W2's shell is assembled from controls, and the inventory below is what the AppKit actually has.
  Ordered by what each class unlocks, because two of them carry more than one stage.
- **Measured inventory (`libagora-app`'s headers):**

  | a file window needs | class | state |
  |---|---|---|
  | toolbar | `NSToolbar`, `NSToolbarItem`, `NSToolbarItemGroup` | **have** |
  | sidebar / source list | `NSTableView`, `NSOutlineView`, `NSSplitView` | **have (cell-based core)**; split view with drag, collapse and autosave |
  | path bar | `NSPathControl`, `NSPathCell`, `NSPathComponentCell` | **have** |
  | view switcher | `NSSegmentedControl`, `NSSegmentedCell` | **have** |
  | list view (W4) | `NSTableView`, `NSTableColumn`, `NSTableHeaderView`, `NSTableHeaderCell` | **have (cell-based)**; editing, type-select, variable heights, column reordering and autosave **have**; cross-process drag session **missing** |
  | column view (W5) | `NSBrowser` | **have** (table-backed; the `NSMatrix` form is absent) |
  | search (W10) | `NSSearchField`, `NSSearchFieldCell` | **missing** |
  | progress (W6) | `NSProgressIndicator` | **have** |
  | status bar | `NSTextField`, `NSTextFieldCell` | **have** |
  | scrolling | `NSScrollView`, `NSClipView`, `NSScroller` | **have** |
  | buttons, sliders, pop-ups | `NSButton`/`Cell`, `NSSlider`/`Cell`, `NSPopUpButton`/`Cell` | **have** |
  | the window itself | `NSWindow`, `NSWindowController`, `NSView`, `NSViewController` | **have** |
  | dialogs (W6) | `NSPanel`, `NSAlert` | **have** (the conflict sheet has not moved to them yet) |
  | resizing (W2) | `NSLayoutConstraint`, `NSLayoutAnchor` | **have** (post-10.6 slice; used by the shell's strips) |

- **Order, and why:** `NSTableView` first — it is the source list's engine (`NSOutlineView` is a subclass) AND the
  list view of W4. **Every file-shell prerequisite is now here**: the table/outline, `NSSplitView`,
  `NSSegmentedControl`, `NSToolbarItemGroup` and `NSPathControl`. W2 can return to its deliverable; W4's list view
  can start on the table core's missing editing/type-select/drag-drop half, and `NSProgressIndicator` and
  `NSSearchField` still wait for W6 and W10.
- **Proves:** the window shell is a real shell — its parts are the platform's, not painted pictures of them.

### W3 — Icon view
- **Deliverable:** `WSIconView` (the desktop's layout engine reused), inline rename, keyboard navigation,
  type-select, drag & drop within the view and between windows, spring-loaded folders.
- **Proves:** the shared engine is shared.
- **Test:** `icon_view.m` for selection/rename/keyboard; an `NSPasteboard`/`NSDragging` test for the drop
  policies (move within a volume, copy across, alias with the modifier).
- **Done (2026-10-19):** `workspace/src/WSIconView` is the desktop's layout engine in the file window's order
  (`WSIconOrderLeftToRightRows`), with keyboard navigation, a one-second prefix type-select, inline rename (the
  extension left unselected), the tier's `NSDraggingSession` as source and a registered destination (Move within a
  volume, Copy across, Option Copy, Command across Move, Command-Option Link), preflighted drops that refuse a
  conflict, and a 0.6-second hover that posts `WSIconViewRequestFolderWindowNotification` for the application to
  open. **THE LINK IS A SYMBOLIC LINK UNTIL `WSAlias` (W6)**, named where the operation is. **MEASURED:**
  `workspace-icon-view`, **54 checks**, including a real drag from one window's icon view into another's and the
  label cut to its cell in the middle rather than spilling into the next one; the
  cross-volume cases use a second root on `/dev/shm`.

### W4 — List view
- **Deliverable:** `WSListView` over `NSOutlineView`: Name, Date Modified, Size, Kind (F1), disclosure,
  column sorting, resize, inline rename, keyboard navigation.
- **Test:** `list_view.m` for sort ordering (including directories-first and natural-number name ordering) and
  for the outline's expansion surviving a model change.
- **Done (2026-10-19):** `workspace/src/WSListView` is an `NSOutlineView` over one `WSItemModel` per directory
  (children are child models made on first expansion), with Name, Date Modified, Size and Kind columns; `WSItemSort`
  keeps directories first and orders names naturally (`file2` before `file10`), dates, sizes and Kinds; expansion is
  remembered by PATH across a reload; the Name column's field editor performs one `NSFileManager` move. **MEASURED:**
  `workspace-list-view`, **33 checks** (four folders and five files, the column values, size/date/Kind orders, a
  folder open across a reload, a rename through the field editor, Return/Right/Left/Command-Down, and the Name
  column's 16-point icon), and the live `--list-view` scene. **AND THE FIELD EDITOR'S DOOR IS A FINDING:** an
  outline's editor ends through the TABLE data-source method with a row, not the outline's by-item method, so
  `WSListView` implements both; recorded in `workspace/PROVENANCE.md`. **AND `--list-view` ITSELF WAS ONE:** the
  two mode setters both assigned the mode unconditionally, so the list-then-column call order reset it to 0;
  a false flag now means "not this mode". Still absent: list drag/drop.

### W5 — Column view
- **Deliverable:** `WSColumnView` over `NSBrowser`, with the preview column.
- **Test:** `column_view.m` for the selection→next-column relationship and for the last column's preview.
- **Done (2026-10-19):** `libagora-app`'s `NSBrowser`/`NSBrowserCell` are here as a table-backed browser (one
  horizontal `NSScrollView` holding one vertical `NSScrollView` + `NSTableView` per column, the 10.6 delegate surface;
  the `NSMatrix` form is named absent), and `workspace/src/WSColumnView` puts it over the per-directory
  `WSItemModel`s with a fixed preview panel at the right (icon, name, Kind, size, date). A folder selection loads the
  next column and scrolls the browser to its end so the new column is against the right edge; a leaf adds none and
  previews. **MEASURED:** `appkit-browser` (37 checks) and `workspace-column-view` (**28 checks**), plus the live
  `--column-view` scene. **AND THE COLUMNS ARE INDIVIDUAL NOW:** each has its own vertical scroller, `-widthOfColumn:`/
  `-setWidth:ofColumn:` are per column, and `NSBrowserUserColumnResizing` makes the gap a drag handle (Workspace sets
  it) drawn as `NSSplitView`'s eighteen-point, three-ring pane-splitter gutter. A column's bar autohides when its
  rows fit. **AND THE COLUMNS ARE FINDER'S 256-SLOT POOL:** empty slots are visible columns and keep their widths,
  while only the visible/active slots size the horizontal document. **AND THE BROWSER FOUND A TABLE BUG:** `NSTableView` released the proposed selection set before copying it when
  a delegate returned that same set, so the selection became empty; fixed and recorded in
  `libagora-app/PROVENANCE.md` § 18. Still absent: a Quick Look preview inside the column (W9), column drag/drop and
  rename.

### W6 — File operations, undo and progress
- **Deliverable:** `WSFileOperations` + `WSTrash`: New Folder, Duplicate, Rename, Move/Copy To, Move to Trash,
  Put Back, Empty Trash, Compress; an undo manager; a progress window; a name-conflict sheet.
- **Proves:** the manager *does* things, and does them undoably.
- **Test:** `file_ops.m` against a temp tree, including undo of each op, a conflict, and a cross-volume copy;
  `trash.m` for recycle and Put Back.
- **Done (2026-10-19):** `workspace/src/WSFileOperations` and `WSTrash` implement New Folder, Duplicate, Rename,
  Move/Copy (including across volumes), Move to Trash, Put Back, Empty and Compress, with inverses registered in
  `NSUndoManager`; the inline renames in the icon and list views route through the manager. Conflicts are a
  handler answered by `WSConflictSheet` (a modal Replace/Skip/Keep Both/Cancel panel built before the tier had
  `NSPanel`/`NSAlert`; both classes are here now and the sheet has not moved to them), progress is a handler feeding
  `WSProgressWindow`, and Compress is a ZIP writer using
  zlib's raw deflate (no shell-out). `WSTrash` uses `~/.Trash` or a per-volume `.Trash-<uid>` and Put Back records.
  **MEASURED:** `workspace-file-ops` (**28 checks**) and `workspace-trash` (**19 checks**), plus
  `appkit-progress-indicator` (**11 checks**) in libagora-app. Named absences: no Trash window/Dock contract (W7/
  §5.3), no progress Cancel, no ZIP64, and a multi-item operation that fails halfway has no rollback.

### W7 — The drag session, system-wide
- **Deliverable:** Agora's pasteboard types for file URLs and for a promised file; drag images; drops
  to/from other applications; **drag to the Dock's Trash** over the §5.3 contract.
- **Test:** `drag_drop.m` for the pasteboard flavours and the promise handshake; a two-process seam test for a
  drop from an independent client into Workspace.

### W8 — Get Info, labels, custom icons
- **Deliverable:** `WSGetInfoWindowController` (single + multiple/inspector), permissions, `Open With` (F1),
  preview, custom icon (F2), colour labels in the metadata store.
- **Test:** `get_info.m` for the multiple-selection summing (size) and the mixed-value placeholder; custom-icon
  round-trip.

### W9 — Quick Look
- **Deliverable:** `libagora-quicklook` + Workspace's Spacebar preview, panel, and slideshow; built-in
  generators for text/image/PDF/media.
- **Test:** a generator ABI test (a plugin produces a view for a fixture) and a panel test (Spacebar opens,
  arrows move, Escape closes).

### W10 — Search and Smart Folders
- **Deliverable:** W11a/b/c from §5.5: filename filter, system index, content importers; the search field, the
  scope selector, and saved searches in the sidebar.
- **Test:** `search.m` for query semantics and for a Smart Folder surviving save/reload.

### W11 — Volumes
- **Deliverable:** `libagora-disk` + the sidebar Devices section, eject, disk images, per-volume Trash.
- **Test:** `volumes.m` with a loopback image mount/eject; a per-volume trash test.

### W12 — Network shares
- **Deliverable:** `libagora-netfs` + the Shared sidebar section and `Connect to Server`.
- **Test:** SMB against a fixture server (opt-in, like the nested compositor tests).

### W13 — The shell's integration
- **Deliverable:** the `session` component launches Workspace at login; Workspace never quits, reopens windows,
  and answers Force Quit; the Services menu (needs an `NSApplication` Services plumbing that
  `libagora-app/NSApplication.h` currently says is absent).
- **Test:** a session test that kills Workspace and asserts the session relaunches it and the desktop returns.

---

## 8. Tests and evidence

Workspace inherits the project's evidence discipline (`libagora-app/README.md` "What is measured, not
assumed"; `window-server/README.md`). Concretely:

- **Logic lives in offscreen probes.** `WSIconLayout`, `WSItemModel`'s sort/filter, `WSHistory`,
  `WSMetadataStore`, `WSFileOperations`, `WSAlias` and `WSTrash` are all testable with no compositor and no
  display, which is where the majority of the bugs will be.
- **The seam is tested against Agora's own server**, headless (`window-server --backend headless`), never
  against mutter, exactly as `libagora-app` does. The nested-X11 runners stay opt-in for the same reason
  recorded there (they take the host's pointer).
- **Pixel tests are opt-in and inspect.py-shaped.** A desktop test screenshots the server and asserts the
  wallpaper fill, icon pixels at stored positions, and the selection highlight — the same method the window
  server already uses.
- **The substrate components each carry their own tests in their own repositories**, per the one-repo rule;
  Workspace's tests consume the *built* libraries only.

---

## 9. Risks

1. **The substrate is the schedule.** If F1–F3 are treated as "part of Workspace", the file manager will not
   reach a first honest screen for a very long time. The stage split exists to prevent that. **F1, F2 and F3
   are the critical path and should be built as standalone components with their own tests before W1.**
2. **`WSItemModel` discipline.** Three views over three enumerations is the classic file-manager-clone failure. The
   model is one object and every view is a consumer; this is a review rule, not a suggestion.
3. **Search scope creep.** Spotlight is a multi-year subsystem; §5.5 chops it into three slices and only the
   first is required for parity of the search *field*. Guard against W10 becoming the project.
4. **The Trash/Dock contract is cross-team.** It needs the Dock, which does not exist. Until the contract is
   fixed, drag-to-Trash is untestable end to end; the *operation* can still be built and tested behind it.
5. **The level constant was a tiny blocker, and the blast radius turned out to be a SERVER BUG** (§3). F4's
   header and function in `libagora-drawing` were indeed small — but a desktop-level window **hung the
   compositor**, because `output.c` and `seat.c` walked the numeric range `lowest..highest` rather than the
   levels present, which is ~2 billion passes per frame between `INT32_MIN + 20` and 0. Both now walk the levels
   PRESENT. DONE in F4, and W0 can place its desktop window.
6. **Metadata-store format churn.** Once users (and the desktop) have positions stored, changing the sidecar
   format is a migration. The format should be versioned from the first write (`WSMetadataStore` carries a
   version field), even though 10.6's `.DS_Store` was not.
7. **`Kind`/type answers before F1.** If views ship with an extension-derived `Kind` baked in rather than behind
   one door, swapping in Launch Services later touches every view. The fallback is behind a door from W4.
8. **The LGPL fallback is one `-static` from a taint.** Rule 3 permits LGPL *dynamically*; the moment a component
   links one statically — a vendored copy, a `-static` flag, a bundled `.a` — the relink obligation of
   §6(a)/§4d0 reaches *our* object code. The build must refuse to statically link any rule-3 library, and each
   `PROVENANCE.md` must record that the link is dynamic and why.

---

## 10. Open questions

- **The application's Agora name.** The prompt fixes `Workspace`; the project's own convention for product names
  (Kestrel, Argentum) suggests confirming it, and confirming the Dock's and the session's names, before their
  repositories are created.
- **The Trash transport** (§5.3) — a protocol extension, a shared library, or an in-tree IPC. Decide with the
  Dock.
- **The metadata store's filename and format** (§5.1) — recommended, not ratified.
- **Daemon vs library for Launch Services, Icon Services and the metadata index** (§2) — recommended library
  first; the reverse may be right once a second consumer (a shell, a launcher) appears.
- **Whether the reference applications' document-type declarations populate the same type registry** as
  Workspace's `Open With` — they should, and this is the first cross-application contract the registry forces.
- **The `session` component's shape** — the desktop cannot be a login-time component before it exists, so
  Workspace's "never quits" behaviour is deferred to W13 and every earlier stage must be run by hand.

---

## 11. Summary of the critical path

```
F1 launch services ─┐
F2 icon services  ──┼─► W0 desktop window ─► W1 desktop icons ─► W2 window shell ─► W3 icon view
F3 watch          ──┤                     (F4 desktop level first)
F4 CG desktop lvl ──┘                                                              │
                                                                  W4 list ─► W5 column ─► W6 file ops
                                                                  │
                                                     W7 drag session ─► W8 info ─► W9 quick look
                                                                  │
                                                     W10 search ─► W11 volumes ─► W12 network ─► W13 shell
```

**The first shippable thing is a desktop** (W0+W1): wallpaper, icons, selection, open, drag, positions — a
useful, non-trivial, measurable surface that needs F1–F4 and nothing else. **The file-manager windows are the
second thing** (W2+W3+W4), and they reuse the desktop's icon engine and model rather than reimplementing them.
That ordering is the opposite of the reference file manager's menu layout, and it is the right one here because the prompt asks
for the desktop explicitly and because the desktop is where the shared machinery is proven first.
