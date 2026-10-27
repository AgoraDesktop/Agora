# Third-party components and assets

This file records everything in the Agora tree that is **not** original to Agora, and
therefore everything the project-wide relicense did **not** touch.

The rule is simple: a component that arrived from upstream keeps the licence it arrived
with. Relabelling it, or applying Agora's licence to it, would remove the very grant
that makes it usable here. Each such tree carries its upstream licence file in place.

## Vendored code

| Component | Upstream | Pinned at | Licence |
|---|---|---|---|
| `libagora-objc` | [gnustep/libobjc2](https://github.com/gnustep/libobjc2) | `v2.3` — `e877e782fb965c4e870d2ecf6aff58dddc6290ae` | **MIT**, © 2009 David Chisnall |
| `libagora-core` | [swiftlang/swift-corelibs-foundation](https://github.com/swiftlang/swift-corelibs-foundation), `Sources/CoreFoundation/` | see its `PROVENANCE.md` | **Apache-2.0 with the Runtime Library Exception** |
| `libagora-dispatch` | [swiftlang/swift-corelibs-libdispatch](https://github.com/swiftlang/swift-corelibs-libdispatch) | `swift-6.4.0-RELEASE` — `024805abec6daa9cdda569fd736b9c7686dfd735` | **Apache-2.0** |
| `libagora-lcms2` | [lcms2](https://github.com/mm2/Little-CMS) | see its `PROVENANCE.md` | **MIT**, © 2023 Marti Maria Saguer |

Each has a `PROVENANCE.md` recording exactly what was copied, what was dropped, and
what Agora changed. `libagora-objc` is the only place in the tree where the change is a
source edit (`arc.mm`, a small-object retain-count crash fix).

> **On GNUstep.** libobjc2 is GNUstep's Objective-C runtime, and it is **MIT**, not
> LGPL. It is the only GNUstep code in the tree. GNUstep Base and the Application Kit
> are LGPL-2.1-or-later; no part of either is present here. Where Agora's sources name
> GNUstep — in `NSObject.h`, `NSObjCRuntime.h`, `NSFileManager.h` and others — they
> cite GNUstep's *published reference documentation* as a specification, which is a
> reading of method, not a copy of source.

## Vendored assets

| Asset | Where | Licence |
|---|---|---|
| **Frost** icon theme v0.3.1 (`84e3f873`), by Sayantan | `libagora-iconservices/themes/Frost/` | **MIT**, upstream `LICENSE` beside the art |
| **Vimix** cursor theme, by vinceliuice | `window-server/assets/cursors/Vimix/` | **GPL-3.0**, upstream `COPYING` beside the art |
| **Bootstrap Icons** v1.13.2, © 2019-2024 The Bootstrap Authors — restyled source for the platform's named images | `libagora-app/art/system-images/` → `SystemImageMasks.{c,h}` | **MIT**; notice must travel with the generated table |
| **OS marks** — path data from **Simple Icons**; hamburger is original | `window-server/assets/system-menu-icons/` → `systemicon-data.c` | **CC0 1.0** path data; the marks remain their owners' trademarks |
| Default font set — 28 families | `libagora-drawing/fonts/` | **SIL OFL 1.1**, except Source Serif 4 (**Apache-2.0**); each family carries its own licence file |

All four art sets are **data**, not linked code, and each has a `PROVENANCE` record beside it.

> **Vimix is the one art set whose licence is not permissive, and its placement is the licence decision.** The cursor
> theme is GPL-3.0 (version 3, not "or later"), so it lives in `window-server`, the tree's GPL-3.0-or-later program,
> and nowhere else: the `libagora-*` libraries are LGPL and a GPL-3.0 asset must not add a term to them. The compositor
> is also the only component that can use a cursor theme today — it composites the theme's pointer on a DRM output and
> hands it to the host as the X cursor in the nested backend. A downstream that cannot ship GPL-3.0 artwork deletes
> `assets/cursors/Vimix` and the compositor draws its own arrow.

> **Generated files carry a compound identifier.** The two generated icon tables are
> Agora code *combined with* this art, so their SPDX line is not the plain tree licence:
> `libagora-app`'s table is `LGPL-3.0-or-later AND MIT`, and `window-server`'s is
> `GPL-3.0-or-later AND CC0-1.0`. The generators emit that line themselves, so regenerating
> a table preserves it — this is verified, not assumed: regenerating all six generators now
> reproduces the tracked files byte for byte.

## Not vendored, taken from the system

**ICU** and **OpenSSL** are used from the platform directly — neither is vendored nor
pinned. Their licences stay on the host.

## Why the whole tree is not simply GPL

`libagora-core` and `libagora-dispatch` are Apache-2.0. Apache-2.0 is compatible with
**GPL-3.0/LGPL-3.0 only** — it is incompatible with GPL-2.0 and with LGPL-2.1. Because
every Agora binary links them, version 3 is the only copyleft the combined work can
resolve as. This is why the tree is LGPL-3.0-or-later / GPL-3.0-or-later and not
LGPL-2.1 / GPL-2.0, which is what GNUstep itself uses.

## GNUstep

**libobjc2 is the only GNUstep code in the tree, and it is MIT, not LGPL.** GNUstep
Base and the Application Kit are LGPL-2.1-or-later; **no part of either is present**.
Where Agora's sources name GNUstep — in `NSObject.h`, `NSObjCRuntime.h`,
`NSFileManager.h` and others — they cite GNUstep's *published reference
documentation* as a specification. Reading a specification is not copying source.

That claim was **tested rather than asserted** on 2026-10-22: the first-party tree was
fingerprinted against `gnustep/libs-base`, `gnustep/libs-gui`,
`swift-corelibs-foundation` and `swift-corelibs-libdispatch`, on both code tokens and
comment prose. **No copied code and no copied prose were found.** The corpus was
extended with **Cocotron** (`cjwl/cocotron`, MIT, dormant since 2015 — the only other
independent implementation of this API) and the audit re-run on 2026-10-23 with the
same result. The procedure and both recorded results are in [`audit/`](audit/).

Until that audit was run, every first-party file carried the line *"Portions of this
file may derive from GNUstep"*. It was a hedge stated in advance, and it is now gone:
with the audit in hand the sentence asserted something untrue of ~1,100 files, and an
unfounded notice is worse than none — it makes a real match harder to spot later and
dilutes the record it points at.

**None of that comparison material is committed, here or in any repository of this project.** The trees the
audit reads — `gnustep/libs-base`, `gnustep/libs-gui`, `cjwl/cocotron` and the two swift-corelibs — are
cloned by `audit.py setup` at the revisions pinned in `audit/audit.py`'s `CORPUS` table, into `audit/corpus/`,
which `audit/.gitignore` excludes. A checkout is 255 MB on a developer's disk and zero bytes in git. The audit's
reproducibility comes from the pins, not from a vendored copy, which is also why a tree can be added by naming
a URL and a SHA rather than by importing anything.

**The one piece of GNUstep source this project does carry is `libagora-objc`, and the fork is kept.** It is
the tree at upstream `v2.3` (`e877e78`) plus seven Agora patches — 227 added lines across eleven files, the ten
source and build files (`objc/runtime.h`, `dtable.c`, `class_table.c`, `arc.mm`, `protocol.c`, `ivar.c`,
`class.h`, `CMakeLists.txt`, `objc/objc-config.h.in`, `.gitignore`) and `PROVENANCE.md` — which is what makes
the runtime answer Apple's `BOOL` encoding, survive a late-bound superclass, and support the class ABI the Swift
toolchain needs.

**Why a fork and not a pinned upstream plus a patch series** — considered, and decided against on three
grounds, in this order:

1. **The delta is load-bearing, not cosmetic.** Three of the seven patches change what the runtime *does*
   (`dtable.c` building a missing superclass dtable instead of aborting, `arc.mm`'s small-object
   `-retainCount`, `class_table.c`'s late-bound size). A patch applied at build time moves those failures out
   of a commit and into whoever runs `cmake` next; a fork puts them where the rest of the runtime's history is,
   next to the upstream code they must be read with.
2. **Pinning is already exact, so "vendored" does not mean "floating".** `Agora` records this submodule at a
   commit (`a589c38`), and `release` pins every component the same way. The audit's reproducibility rule — a
   result is only meaningful against a stated revision — is satisfied by the gitlink, which is why the corpus
   needs pins in `audit/audit.py` and this tree does not.
3. **The drift stays measurable.** The delta is exactly `git log e877e78..HEAD` in `libagora-objc`, and
   `PROVENANCE.md` there is the record of it. A fork that says what it changed is more honest than a patch
   series that has to be applied successfully to be read.

**What the decision does NOT license.** The fork is of the **MIT** runtime only. `gnustep/libs-base` and
`gnustep/libs-gui` are LGPL-2.1-or-later and no part of either is present — that is the claim the audit tested,
and keeping this fork does not change it. And the licence obligation travels with the copy: upstream's
`COPYING` and `ANNOUNCE*` files are in the fork, and `PROVENANCE.md` names the revision the copy came from.

## If copied code is ever found

The audit is a control against a specific mistake, not a one-time ritual. Re-run it
whenever code is added that was produced with model assistance, and when a new
upstream is proposed as a source. If a file is found to contain code or prose taken
from GNUstep or any other project:

1. **Rewrite the span.** This is almost always cheap, it is always preferred, and it
   is the only outcome that keeps the file's provenance clean.
2. **If it cannot be rewritten**, keep it and mark it honestly: reproduce the upstream
   copyright notice on that file, leave the file under the upstream terms GNUstep
   already uses (LGPL-2.1-or-later upgrades cleanly into this tree's
   LGPL-3.0-or-later), and add a row to the table above.
3. **Record it.** `release/debian/copyright` gains a stanza for the path, and the next
   audit run should show the file as known — not as a surprise.

What must *not* happen is the blanket notice returning. A permission-shaped sentence on
every file covers nothing and hides everything.
