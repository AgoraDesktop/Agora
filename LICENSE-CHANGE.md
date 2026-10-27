# Licence change — MIT to LGPL-3.0-or-later / GPL-3.0-or-later

**Effective 2026-10-22.** This file is the record of the change and of what it does and
does not affect.

## What changed

| | Before | After |
|---|---|---|
| Libraries (`libagora-base`, `-app`, `-drawing`, `-text`, `-iconservices`, `-launchservices`, `-watch`) | MIT | **LGPL-3.0-or-later** |
| Programs (`window-server`, `workspace`, `tests/` in the library repos, `demo/*.sh`) | MIT | **GPL-3.0-or-later** |
| Root / umbrella | MIT | **GPL-3.0-or-later with per-tree carve-outs** |
| `libagora-objc`, `-core`, `-dispatch`, `-lcms2`, Frost, fonts | unchanged | **unchanged** — see `THIRD-PARTY.md` |

Every first-party source file now carries `SPDX-FileCopyrightText` and
`SPDX-License-Identifier`.

## What did not change

`libagora-objc` (MIT, David Chisnall), `libagora-core` and `libagora-dispatch`
(Apache-2.0), `libagora-lcms2` (MIT), the Frost icon theme (MIT) and the default font set
(SIL OFL 1.1 / Apache-2.0) keep their upstream licences and their upstream notices. They
are **not** covered by this change and must not be relabelled.

The **Vimix** cursor theme (GPL-3.0, `window-server/assets/cursors/Vimix`) is the same
kind of asset and arrived after the change; it is likewise covered by neither the old MIT
grant nor this one, and keeps its upstream licence. It lives in `window-server` — the
GPL-3.0-or-later program — rather than in an LGPL library, so it adds no term to anything
else in the tree.

## Why

Two reasons, in order of weight:

1. **Compatibility with GNUstep.** The project intends to import GNUstep library and
   application code where it is useful. Adopting GNUstep's own scheme — LGPL for
   libraries, GPL for programs — removes all licence friction from doing that.
2. **A hedge against model-assisted code reproducing a GNUstep span.** A portion of
   this tree was written with model assistance, and language models can reproduce
   training data verbatim. With the project already under compatible terms, no portion
   would be distributed under a licence that could not cover it.

   **That hedge has since been retired, on evidence.** The tree was audited on
   2026-10-22 against GNUstep Base, GNUstep GUI and Apple's swift-corelibs, on both
   code tokens and comment prose, and no copied code or prose was found — see `audit/`.
   The audit was re-run on 2026-10-23 with Cocotron added to the corpus and reached the
   same conclusion. The blanket per-file derivation notice was therefore removed: a
   claim that every file may derive from GNUstep is false for all of them, and an
   unfounded notice is worse than none.

## Why version 3, specifically

Apache-2.0 is compatible with GPL-3.0 and LGPL-3.0 only, and is incompatible with
GPL-2.0 and LGPL-2.1. `libagora-core` and `libagora-dispatch` are Apache-2.0 and are
linked by every binary, so version 3 is the only copyleft the combination can resolve
as. GNUstep's LGPL-2.1-or-later upgrades into it cleanly.

## History

**Commits before 2026-10-22 remain available under MIT.** The licence on a given
revision is the licence that revision was published under; this change is forward-only
and does not revoke any grant already made.

**No release was ever tagged**, so there are no published MIT releases and no downstream
expectation is broken by this change.

## Standing consequence

This is a one-way door in practice. LGPL-3.0-or-later and GPL-3.0-or-later cannot be
narrowed back to a permissive licence without the consent of every copyright holder in
the tree. While the project has a single copyright holder this is reversible by that
holder's decision; the first outside contribution removes that freedom unless a
contributor grant is in place.

**Outstanding:** a contributor licence agreement or a DCO with an express right to
relicense has been deferred. It should be added before the first external contribution
is merged.
