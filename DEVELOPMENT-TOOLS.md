# Building Agora apps — an options exploration for the interface format, the project, and the IDE

*Status: **blue-sky wishlist.** This is not a plan, a commitment, or a milestone. It is an options
exploration, written the way `SWIFT-INTEROP-INVESTIGATION.md` and `RUST-BINDINGS.md` are: every claim
is tied to a file that exists, and the thing each option needs is named at the file that already
carries it or the header that already refuses it. Nothing here is scheduled.*

*Nothing here is a product name. Per the project README ("Apple's names are descriptive"), **Interface
Builder**, **Project Builder** and **Xcode** are used below as the names of *roles* — a visual
interface editor, a project/build tool, an integrated development environment — and not as Agora
products. Candidate Agora names are sketched at the end and are deliberately non-binding.*

---

## Verdict

**Agora does not need to invent much. The hard, load-bearing substrate for all three roles is already in
the stack — the one thing genuinely missing is named, in writing, by the class that refuses it.**

- **The interface format is the gate.** `libagora-app/NSNib.h` refuses to decode a nib *by name* and
  states the closure in the same paragraph: *"a first-party interface format for THIS AppKit — an emitter
  and a reader this tree owns, the way the interface side of the retired C++ kit owned one — and that is
  a unit of its own rather than something to infer from Apple's bytes."* Everything an archive needs to
  *be* already exists: `NSCoding`, a documented `NSKeyedArchiver` schema with object identity, binary
  plists, `NSClassFromString`, KVC, and `NSBundle`'s `dlopen`/`-classNamed:`. What is missing is a
  *connection model*, a *reader*, and a *tool*.
- **The project/build tool is a thin layer over what already builds.** Agora already builds itself with
  per-component CMake that installs CMake packages into an SDK prefix (`build-prefix/`). A "project file"
  is most cheaply a **manifest that generates** that build, not a new build engine.
- **The IDE is the replaceable part.** Source editing, completion and debugging are the expensive,
  low-differentiation halves, and open, permissively-licensed equivalents already exist
  (`clangd`/LSP, `lldb-dap`/DAP). **The visual canvas is the one part that cannot be borrowed**, because
  it renders AppKit — an IB canvas is necessarily an Agora process. That asymmetry decides the whole
  build-vs-borrow question, and it is taken up in §5.

The single most valuable move, if one is forced, is also the cheapest and it unblocks the most: **define
a first-party, text-source interface format and ship its reader in `NSNib` plus a CLI compiler.** That
closes a gap the tree has already recorded, and it is a prerequisite for the canvas and the IDE alike.

---

## 1. What the three roles actually are

The names bundle things that were historically separate and became one over twenty years. Separating
them is what makes the options tractable.

| Role | What it *is* | What it is *not* | Apple's history |
|---|---|---|---|
| **Interface Builder** | An editor for a **serialised object graph** — class names, property values, and *connections* — plus a reader that rebuilds the graph at launch. | A code generator, or a runtime framework. | 1988 standalone; acquired 1996; merged into Xcode 4. |
| **Project Builder** | A **project description** and a **build** that turns it into a product. | A language server, or a debugger. | NeXTSTEP; became Xcode 1. |
| **Xcode (the IDE)** | An **editor shell** over a project, a build, a debugger, and an interface canvas. | The sum of the other two — it is the *shell* plus those two. | PB + IB merged; LLDB, Instruments, SPM added after. |

Two consequences fall straight out of that table:

1. **IB and PB are clients, not stacks.** IB is a client of AppKit (it *is* an AppKit app that renders a
   designed view hierarchy). PB is a client of the toolchain (it drives clang and a linker). Neither is
   the place to put new runtime machinery — which is why §2 matters: the runtime machinery has to exist
   underneath, and most of it does.
2. **The IDE is emergent, not foundational.** It is what you get once IB and PB exist and are worth
   hosting. Building the shell *first* is the trap; building it *last* is the order Apple actually took
   (PB in 1988, IB in 1988, one shell in 2003+).

---

## 2. What the stack already has — measured, at the file

This is the section that changes the size of the problem. An IB needs to: instantiate a class by name,
set properties it was never compiled to know about, wire target/action, load code and resources from a
bundle, and run the result. Every one of those is already here.

| What IB/PB/IDE needs | Where it already lives | Status |
|---|---|---|
| Instantiate a class by name | `NSClassFromString`, `NSSelectorFromString` — `libagora-base/NSObject.h:259–273` | **present** |
| Set properties reflected at design time | `-setValue:forKey:`, `-setValue:forKeyPath:` — `libagora-base/NSKeyValueCoding.h:67,69`; KVO in `NSKeyValueObserving.h` | **present** |
| Target/action wiring | `NSControl -target`/`-action`/`-sendAction:to:` — `libagora-app/NSControl.h:67–114`; `NSActionCell`, `NSCell` | **present** |
| An archived object graph with identity | `NSCoding` (`libagora-base/NSCoding.h`) + `NSKeyedArchiver`/`NSKeyedUnarchiver` with a **documented** schema and preserved identity (`NSKeyedArchiver.h`, header note) | **present** |
| A sequential-archive fallback | `NSArchiver`/`NSUnarchiver` (`libagora-base/NSArchiver.h`) | **present** |
| A compact binary encoding | `CFBinaryPList` — `libagora-core/CFBinaryPList.c` | **present** |
| Load code and resources from a bundle | `NSBundle -load` (dlopen), `-principalClass`, `-classNamed:`, `Contents/MacOS` + `Contents/Resources` + `Info.plist` — `libagora-base/NSBundle.h:46–170,262` | **present** |
| Run the designed hierarchy | `NSWindow`/`NSView`, `NSViewController`, `NSWindowController` — `libagora-app/` | **present** |
| A document controller | `NSWindowController`, `NSViewController` (`libagora-app/`) | **present**; `NSDocument` is **absent** and named |
| A window server to preview against | `window-server` `--backend x11` (nested, grabs nothing) and `--backend headless`; the `agora-shell` protocol (`set_frame`, levels, `work_area`) | **present** |
| **Read a nib's object graph** | `NSNib -instantiateNibWithOwner:topLevelObjects:` | **refused by name** — the gate |
| **A connection/outlet model** | — | **absent** (the concept, not the primitives) |
| **A source format for a project** | — | **absent** |
| **An SDK/profile an app builds against** | `build-prefix/` + each component's installed CMake package | **present as a build artifact**, not yet a product |

**So the gap is narrow and it is exactly where `NSNib.h` says it is.** The archive machinery, the
reflection, the KVC, the bundle loading and the preview server are all built. What does not exist is
(a) a *schema* Agora owns, (b) a *reader* for it, (c) the *connection* vocabulary, (d) a *tool* around
it, and (e) everything above that (project manifest, canvas, shell).

### One real risk that is already recorded, and it lands on the interface format

`NSCoding.h` states plainly that **secure decoding is not enforced**: *"THE ENFORCEMENT IS STILL
MISSING AND IS NAMED RATHER THAN IMPLIED… `+supportsSecureCoding` answers, and the unarchiver does not
yet ask."* An interface format is *precisely* an archive of arbitrary class names that a tool decodes
and instantiates — which is the classic remote-code-execution shape. **Any first-party format must
decide an allow-list policy and the unarchiver must grow the `-decodeObjectOfClass:forKey:` enforcement
before a design file from outside the project is ever loaded.** This is not a reason to skip the format;
it is a reason the format is a *unit of its own* and not a weekend `NSNib` patch.

---

## 3. The interface format — the gating decision

Five families, each with a real precedent, scored against Agora's constraints: text-in-git (Agora is a
federation of submodules — a binary blob is a merge conflict by construction), permissive licence only
(README), clang/ObjC, and "the Mac's answer is the answer" where it reaches.

| # | Option | Precedent | Licence | Git/diff | Fit |
|---|---|---|---|---|---|
| **A** | **First-party binary keyed archive**, read by `NSNib`, written by a tool | Apple `.nib` | Agora's | ✗ binary | Closes the recorded gap; the archive exists |
| **B** | **Text source → compiled archive** (the `.xib`→`.nib` split) | Apple `.xib`/`.storyboard`; Godot `.tscn` | Agora's | ✓ text source | **Strongest fit** — human-mergeable source, binary is a build artifact |
| **C** | **Code as the UI** — generator emits ObjC | SwiftUI, Compose, Flutter | Agora's | ✓ code | No format to own, but no visual round-trip either; the canvas becomes a code generator |
| **D** | **Adopt an external format** | GNUstep Gorm (GPL), GTK Builder `.ui` (LGPL), Qt `.ui` (LGPL), Glade (GPL), Lazarus `.lfm` | mixed | varies | Licence-disqualified as *shipped* deps; useful as **ideas**, and Gorm's GPL is exactly the trap the README names |
| **E** | **HTML/CSS-like markup** | WebObjects `.wod`/`.html` | — | ✓ text | Historical, no live canvas story worth the cost; noted and not recommended |

**Recommendation (non-binding): B over A — the source is text, the product is an archive.** This is the
`.xib`/`.nib` split, and it is the only family that satisfies both the runtime (an archived object graph,
which `NSNib` already expects to hold) and Agora's git culture (a text source that merges). The compiled
archive is a **build artifact**, per the README's *"build into `build/`"* convention, and is therefore
*not committed* — the source is. Concretely, the format needs five things the primitives do not supply:

1. **A schema Agora owns and versions.** `NSKeyedArchiver` already writes a `$version` and a
   `$archiver` key; a format is a *profile* of that, with a `$classes` allow-list and a forward-compat
   rule. Own it in one place (a header and a spec file), not implied across the tool and the reader.
2. **A connection model.** `IBOutlet` and `IBAction` are historically *macros that erase to `id` and
   `void(^)(id)`* — zero runtime cost, zero ABI. The connection itself is a triple
   `(source, key, destination)` applied through `-setValue:forKey:` (already present) or a
   `(target, selector)` pair applied through `NSControl`'s target/action (already present). This is the
   whole vocabulary, and it is small.
3. **Design-time metadata.** An `IBInspectable`-equivalent is a declared property plus a type hint the
   *editor* reads; it has no runtime meaning. It can live in the source text and never reach the archive.
4. **A live-render ("designable") path.** The editor instantiates the edited class and calls its
   drawing. That requires the edited code be **loadable** — which is what `NSBundle -load`/`-classNamed:`
   already does. The designable mechanism is therefore *a bundle build plus a child process*, not new
   runtime code. Isolation is the point: run the user's `-drawRect:` in a child, against a nested
   `window-server`, so a crash in a custom control does not take the editor with it.
5. **A round-trip tool.** Read source → emit archive → read archive → re-emit source, and prove the two
   ends agree. This is the testable core, and it is where the tree's "measured, not assumed" habit pays
   off: the format's test is a census of what survives the round trip.

**What the format must *not* do** — and each is already a written rule in the tree: do not infer Apple's
`.nib` byte schema (`NSNib.h` refuses it for exactly this reason — *"a guessed nib schema would be a
WRONG VALUE rather than an unfinished feature"*); do not commit a binary; do not adopt a GPL format.

---

## 4. The project/build layer — the Project Builder role

Agora already builds itself: each component is CMake, each installs a CMake package, and `release/` (this
directory) composes them into a desktop. A "Project Builder" is therefore **not** a new build engine; it
is a **project description** plus a **driver**. Four options:

| # | Option | Precedent | Cost | Fit |
|---|---|---|---|---|
| **A** | **Manifest → CMake generator.** A declarative project file generates the per-target CMake that already works. | XcodeGen, Tuist | low | **Best first move** — reuses everything, invents only the manifest |
| **B** | **A native Agora build engine.** Own graph, own rules, own caching. | Xcode's build system, Bazel, Buck2 | very high | Sky-blue only; no payoff until the manifest is proven |
| **C** | **Adopt a generic engine outright** and make the project file its input. | Meson, Bazel | medium | Reasonable, but imports a dependency and a worldview the README's "clang only / pinned components" ethos does not obviously want |
| **D** | **No project file — CMake *is* the project file**, plus a bundle packager. | plain CMake | lowest | Honest for internal components; weakest for third-party app authors |

**Recommendation: A now, B only if a real need appears.** The manifest should describe: targets, sources,
resources, the SDK/profile to build against, dependencies (by component pin), and build settings. The
generator emits the CMake the tree already knows how to build. This keeps the "one repo per component,
each self-contained" rule intact — an app project is a *consumer* of the release, not a sibling
rebuilt inside it.

**Two things the project layer must add that the manifest does not cover, and both have a home already:**

- **An app bundle.** Cocoa's product *is* a `.app`: `Contents/MacOS`, `Contents/Resources`, `Info.plist`.
  `NSBundle.h` already models exactly this layout and already reads it, so the packager is a *writer* for
  a layout the runtime *reader* already understands. That symmetry is the design.
- **An SDK/profile.** Applications build against the installed stack, which `build-prefix/` already
  is. Turning that into a *named, versioned SDK* an app project can pin is packaging work, not runtime
  work — and it is the same "pins, not floating versions" rule the README states for components.

---

## 5. The IDE — the integrated role, and the one asymmetry that decides it

The IDE is editor + build + debug + canvas. The asymmetry that decides build-vs-borrow:

> **The canvas must be an Agora process, because it renders AppKit. The source editor need not be, because
> it renders text.**

So the three halves have three different answers:

| Half | Build or borrow | Why |
|---|---|---|
| **Interface canvas** | **Build** (on Agora's AppKit) | It *is* a view hierarchy; hosting it anywhere else means reimplementing AppKit. |
| **Build/run/debug** | **Drive existing tools** | `clang`, the generated CMake/Ninja, and `lldb` already exist; the IDE is a front-end. |
| **Source editing / completion / diagnostics** | **Borrow via LSP** | `clangd` (Apache-2.0 w/ LLVM exception) already understands Objective-C/C and Agora's headers. `lldb-dap` (same licence) already speaks DAP. Both specs are open. |

That yields three architectures, cheapest first:

| # | Architecture | What it is | Cost | Fit |
|---|---|---|---|---|
| **A** | **Thin IDE / no GUI of its own** | `clangd` + `lldb-dap` + a CLI build wrapper; any LSP editor works; ship a config, not an app | lowest | **Best leverage**; exercises the project layer and the format's CLI |
| **B** | **Borrow a shell** | Code-OSS (MIT) or another editor hosts Agora LSP/DAP/IB plugins | low | Fast, but the product is somebody else's shell; the IB pane is still an Agora process bolted on |
| **C** | **Native Agora IDE** | An Agora app: project pane, source editor, canvas, console | highest | **Most on-brand**, and the hardest AppKit client — it is the stack's own acceptance test |

**Recommendation: A is the ramp, C is the destination, B is optional and skippable.** The reason C is
not merely vanity: **an IDE is the most demanding known client of an AppKit** — multi-document, many
windows, text editing at speed, a dockable layout, a live canvas — so *building it is how the stack
proves itself*, and it is exactly the "dogfood the stack" logic that made the window server's own tests
point the AppKit at Agora's compositor instead of mutter. The corollary is a sequencing rule: **do not
start C until the format (the canvas's data model) and the manifest (the project pane's data model)
exist**, because otherwise the IDE invents both badly.

### The canvas, mechanically

The canvas is smaller than it looks, because the primitives are all present:

- **Document model** = the source format's AST (option B). The canvas edits the AST and writes text.
- **Canvas** = a live `NSView` hierarchy (the real designed views) with an *adornment overlay* — selection
  handles, alignment guides — drawn by the editor, not by AppKit. The overlay is a second window at a
  high window level, which `agora-shell`'s level model already supports.
- **Inspector** = KVC over the selected object (`-setValue:forKey:`; present). No code generation.
- **Connection dragging** = target/action on controls (`NSControl -sendAction:to:`; present) and KVC for
  outlets. The connection is recorded in the AST, not compiled.
- **Live preview** = instantiate in-process for speed, or in a child process against a nested
  `window-server` for safety; the "designable" custom control is a bundle loaded with `NSBundle -load`.
- **The CLI is the real unit.** `ibtool`-equivalent: `compile` (source→archive), `validate`, `dump`,
  `roundtrip`. It is testable without any GUI, it is what C depends on, and it is what makes the format's
  tests possible at all. **It should exist before the canvas does.**

---

## 6. Blue-sky tiers (the wishlist itself)

Ordered so that each tier's prerequisite is the tier below it. "Cost" is a rough order of magnitude, not
a schedule.

| Tier | What lands | Unlocks | Cost |
|---|---|---|---|
| **0** | First-party format spec + `NSNib` reader/writer + `IBOutlet`/`IBAction` vocabulary + nib loading in `NSViewController`/`NSWindowController` | Closes the gap `NSNib.h` records; UI becomes data | **S–M** |
| **1** | `ibtool` CLI: compile / validate / dump / round-trip, with round-trip and pixel tests | Testable format; format is safe to build on | **M** |
| **2** | Project manifest → CMake generator + `.app` packager + a pinned SDK profile | A third party can build an Agora app end to end | **M** |
| **3** | Live canvas editor (an Agora app) with inspector, connections, designable child-process preview | The Interface Builder role, for real | **L** |
| **4** | Shell decision: LSP/DAP wiring (A) or borrowed shell (B) | Edit/build/run/debug loop | **S** (A) / **M** (B) |
| **5** | Native Agora IDE: project pane, source editor, canvas, console, debugger | The Xcode role; the stack's acceptance test | **XL** |
| **6** | Package manager / dependency resolution + distribution/signing | Ecosystem; not required for the desktop | **XL** |

**Tiers 0–2 are the whole critical path.** Everything after them is hostable; everything before them is
invention. If nothing else in this document is acted on, tier 0 is the one with a written gap and a
written closure already in the tree.

---

## 7. Cross-cutting decisions and open questions

These are the questions that will be answered *implicitly and badly* by whoever writes tier 0, unless
they are answered explicitly here first.

1. **Which new component repositories?** The README's rule is *one component, one repository*. This work
   is at least three: the **format/schema** (linkable, and a spec — a `libagora-…` if it ships readers),
   the **tools** (a program: `ibtool`, the project driver), and the **IDE** (a program). Where the
   *schema* lives — inside the AppKit repo (as `NSNib`'s implementation) or as its own unit — is the
   first decision, and `NSNib.h` already leans toward *"a unit of its own"*.
2. **Text vs binary in git.** Resolved by the source/artifact split (§3), but the *rule* needs stating:
   the compiled archive is a `build/` artifact and is never committed. A binary design file in a submodule
   federation is a merge conflict waiting to happen.
3. **Format versioning and forward compatibility.** `NSKeyedArchiver` already writes `$version`. A design
   format needs a policy: what does an old reader do with a new file? Naming the answer now is cheaper
   than discovering it in a shipped desktop.
4. **The secure-decoding gate.** §2. This is the one item that is a *safety* prerequisite rather than a
   feature: the unarchiver must enforce an allow-list before a design file crosses a trust boundary.
5. **Language of the tools.** AppKit-linked pieces are Objective-C by the README's rule. CLI tools that
   touch no AppKit could be C. If the Swift toolchain (`SWIFT-TOOLCHAIN-INTEGRATION.md`) or the Rust
   bindings (`RUST-BINDINGS.md`) land, an IDE's language-services story changes — and the **project
   format must not be Objective-C-only**, or it becomes an obstacle to exactly the languages Agora is
   evaluating.
6. **Design-time vs run-time execution.** Custom controls run *in the editor's world* for preview. The
   isolation boundary (child process, nested window server) is a design decision with a security and a
   stability face, and `window-server`'s nested backend makes it cheap.
7. **Naming.** Per the README, "Interface Builder" and "Project Builder" describe roles and are not
   Agora products. The products need names that are not Apple's marks. (Non-binding sketch, for
   atmosphere only: a session/format built around the existing **Argentum** design language could carry
   names in that family — but no name is proposed here as anything but a placeholder.)
8. **Licence hygiene for anything borrowed.** The permissive-only rule (README) disqualifies GNUstep's
   Gorm (GPL) as a shipped dependency, and makes GTK/Qt/Glade formats *ideas*, not code. The safe
   borrowables are `clangd`/LLDB (Apache-2.0 w/ LLVM exception) and Code-OSS (MIT); the safest path for
   the *format* is to own it, which is what `NSNib.h` already argues.

---

## 8. Evidence index

- The recorded gap and its closure: `libagora-app/NSNib.h` (header note), `libagora-app/NSNib.m`
  (`fn_refuse`), `libagora-app/NSViewController.h` (nib loading refused), `libagora-app/NSWindowController.h`.
- Archive substrate and its schema: `libagora-base/NSCoding.h`, `libagora-base/NSKeyedArchiver.h`
  (documented `$version`/`$objects`/`$top` shape, identity preservation), `libagora-base/NSArchiver.h`,
  `libagora-core/CFBinaryPList.c`.
- Reflection and KVC: `libagora-base/NSObject.h:259–273` (`NSClassFromString`/`NSSelectorFromString`),
  `libagora-base/NSKeyValueCoding.h:67,69`, `libagora-base/NSKeyValueObserving.h`.
- Controls and target/action: `libagora-app/NSControl.h:67–114`, `libagora-app/NSActionCell.h`.
- Bundle loading and layout: `libagora-base/NSBundle.h:46–170,262` (`-load`/dlopen, `-principalClass`,
  `-classNamed:`, `Contents/MacOS` + `Contents/Resources` + `Info.plist`).
- The security gate: `libagora-base/NSCoding.h` header note ("THE ENFORCEMENT IS STILL MISSING").
- Preview infrastructure: `window-server/README.md` (§2 nested backend, §4/§5 input and DRM),
  `window-server/DESIGN.md` and `window-server/protocol/agora-shell.xml` (`set_frame`, levels, `work_area`).
- The build model to reuse: the project README (one repo per component; build into `build/`; pins not
  floating versions), each component's `CMakeLists.txt` and installed `*Config.cmake`, `build-prefix/`.
- The design language a canvas would be drawn in: `window-server/ARGENTUM.md`.
- Sibling explorations this document is a companion to: `SWIFT-INTEROP-INVESTIGATION.md`,
  `SWIFT-TOOLCHAIN-INTEGRATION.md`, `RUST-BINDINGS.md`.

---

## 9. Practicality — an honest sizing

The question that matters is not *"is it possible?"* (it plainly is — there is no research problem,
no unpublished schema to reverse, no compiler or protocol to invent) but *"how big, and where does the
size actually sit?"* Those have different answers for each of the three roles, and the difference is the
whole result.

### Feasibility: high. No unknowns.

Every load-bearing assumption is either already built (§2) or is a **documented AppKit class** — buildable
by the same slice-by-slice method the tree already uses. There is nothing here of the kind
`SWIFT-INTEROP-INVESTIGATION.md` had to weigh (an ABI mismatch, an uncharted frontend fork). The risk is
**volume of a known kind**, not feasibility.

### Size: the four deliverables have very different cost profiles

| Deliverable | Prereqs already present | What is missing | Practicality |
|---|---|---|---|
| **Interface format + reader + `IBOutlet`/`IBAction`** | archive, KVC, reflection, bundle loading | a schema, a connection model, the `NSNib` decode | **High** — small, self-contained, closes a gap the tree already wrote down |
| **`ibtool` CLI** (compile/validate/dump/roundtrip) | plist/XML, `NSKeyedArchiver` | the tool itself | **High** — pure CLI, no GUI, fully testable |
| **Project manifest + `.app` packager** | CMake packages in `build-prefix/`, `NSBundle`'s layout | the manifest format, the generator, the packager | **High–Medium** — plumbing, not invention |
| **Visual canvas (IB's editor half)** | `NSView`/`NSWindow` drawing, hit-testing, KVC, **`NSUndoManager`**, sheets, menus | editor furniture (below) | **Medium** — the canvas *itself* is small; the surrounding chrome is not |
| **Integrated IDE (Xcode)** | LSP/DAP borrowable | ~20–30 AppKit classes + a performant source editor + a document model | **Low** built from scratch; **High** if the editor shell is borrowed |

### The real cost driver is missing editor *furniture*, and it is measurable

A census of the AppKit classes an editor shell leans on, checked against the tree:

- **Present (the fundamentals are here):** `NSWindow`, `NSView`, `NSResponder`, `NSEvent`, `NSMenu`,
  `NSMenuItem`, `NSPasteboard`, `NSClipView`, `NSScrollView`, `NSScroller`, `NSTrackingArea`,
  `NSText`/`NSTextView`/`NSTextStorage`/`NSLayoutManager`/`NSTextContainer`, `NSImage`/`NSImageRep`,
  `NSFont`, `NSColor`, `NSBezierPath`, `NSGraphicsContext`, `NSViewController`, `NSWindowController`,
  `NSButton`, `NSSlider`, `NSTextField`, `NSPopUpButton`, `NSComboBox`, `NSTableView`, `NSOutlineView`,
  `NSSplitView`, `NSSegmentedControl`, `NSToolbar`, `NSToolbarItemGroup`, `NSPathControl`,
  `NSTextAttachment` — **and `NSUndoManager`**, which is the one most likely to be assumed missing and is not: Foundation ships it and
  `NSResponder.h:157` walks the chain to it.
- **Absent (the furniture):** `NSTabView`, `NSPanel`, `NSAlert`, `NSDrawer`, `NSBox`, `NSProgressIndicator`,
  `NSPopover`, `NSColorPanel`, `NSFontPanel`, `NSRulerView`, `NSCollectionView`, `NSTextFinder`,
  `NSBrowser`, `NSDraggingSession`, `NSTreeController`, `NSArrayController`, `NSDictionaryController`,
  `NSDocument`.

That list is the honest cost: an IDE needs an **outline** for the navigator and the view hierarchy, a
**split view** for panes, **panels/alerts** for dialogs, a **drag session** for reordering and for
connection-dragging, **temporary attributes** for syntax highlighting (`NSLayoutManager` names its
background/underline doors as owed), and a **document model**. Each is a documented class → buildable,
but each is a slice like the ones already in the tree, and there are ~20–30 of them.

Two corrections that keep the cost from being overstated: the negative one first.

- **`NSDocument` missing is the biggest single item, and it is bypassable.** Both IB and an IDE are
  *document-based* on the Mac, but an application can own its windows directly; an IDE-lite can too. It is
  a moderate build, not a blocker.
- **Cocoa Bindings are *not* on the critical path.** The three controller classes
  (`NSArrayController`, `NSTreeController`, `NSDictionaryController`) drive bindings, and an inspector and
  a navigator do not need bindings — direct KVC over the selected object (already present, §2) is enough
  and simpler. Their absence does not have to be paid for.
- **The hardest single piece is the source editor, not the canvas.** An IDE lives or dies on typing
  latency and highlighting over a large file, plus find/replace. The current `NSTextView` slice is a line
  model with wrapping and scrolling and **no rich text, no attachments, no find** — and its own header
  names rich text and paragraphs as owed. **This is the strongest argument for borrowing the editor shell
  (LSP/DAP into an existing editor) and building only the canvas natively**, exactly as §5 concluded from
  the other direction.

### Where the practicality is genuinely high

1. **The format + reader + CLI.** Small, self-contained, testable without a GUI, and it closes a gap the
   tree already recorded (`NSNib.h`). **Everything else depends on it; almost nothing depends on the rest.**
2. **The project manifest + packager.** It reuses a build that already works.
3. **The canvas** — *after* (1), and with a handful of new classes (an overlay window, selection handles,
   an inspector panel).
4. **The IDE** — last, and with the editor half borrowed rather than written.

### The failure modes worth naming now

- **The canvas drags in furniture.** A usable IB almost certainly wants an outline of the view hierarchy,
  which pulls in `NSOutlineView`; that is fine, but it is 3–5 classes, not one.
- **The source editor is the hidden largest cost**, and it is avoidable only by borrowing.
- **The secure-decoding gate** (§2) is a safety prerequisite, not a feature; unresolved, the format is a
  liability.
- **The format's text↔archive round trip must be lossless.** If it is not, the whole model breaks, and it
  breaks late and quietly. It must be measured early — a census of what survives.

### The cheapest way to test the notion: one vertical slice

The practical question — *is this worth doing?* — is answerable by **one end-to-end probe**, in the shape
of `swift-interop-probe/`: hand-write a small text description of a window with a button and a connection,
run `ibtool` to compile it to an archive, load it through `NSNib`, and show the window with the button's
action firing. **That single slice exercises every load-bearing assumption** — the format, the reader, the
connection model, bundle loading, and "the designed graph runs" — with **no editor furniture at all**. If
that slice is cheap, the notion is practical and the cost is the furniture; if it is expensive, the editor
certainly is. It is also the smallest thing that *closes the recorded gap* (`NSNib.h`) rather than merely
planning to.
