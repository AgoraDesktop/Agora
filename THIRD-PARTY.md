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
| **Bootstrap Icons** v1.13.2, © 2019-2024 The Bootstrap Authors — restyled source for the platform's named images | `libagora-app/art/system-images/` → `SystemImageMasks.{c,h}` | **MIT**; notice must travel with the generated table |
| **OS marks** — path data from **Simple Icons**; hamburger is original | `window-server/assets/system-menu-icons/` → `systemicon-data.c` | **CC0 1.0** path data; the marks remain their owners' trademarks |
| Default font set — 28 families | `libagora-drawing/fonts/` | **SIL OFL 1.1**, except Source Serif 4 (**Apache-2.0**); each family carries its own licence file |

All three art sets are **data**, not linked code, and each has a `PROVENANCE` record beside it.

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

## The GNUstep derivation notice

Every first-party source file carries the line:

```
Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
```

This is a **hedge, stated in advance**, not a claim that each file contains GNUstep
code. It exists because language models can reproduce training data, and a portion of
this tree was written with model assistance; the notice ensures that if any span is
found to match GNUstep source, the licensing position is already correct and nothing
has been distributed under terms that could not cover it.

If an audit identifies an actual match, the correct remedy is unchanged and still the
preferred one: rewrite the span, or mark that file with the real upstream notice, and
record it in the table above.
