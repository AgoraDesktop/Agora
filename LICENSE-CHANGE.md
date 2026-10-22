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
`SPDX-License-Identifier`, plus the derivation notice described in `THIRD-PARTY.md`.

## What did not change

`libagora-objc` (MIT, David Chisnall), `libagora-core` and `libagora-dispatch`
(Apache-2.0), `libagora-lcms2` (MIT), the Frost icon theme (MIT) and the default font set
(SIL OFL 1.1 / Apache-2.0) keep their upstream licences and their upstream notices. They
are **not** covered by this change and must not be relabelled.

## Why

Two reasons, in order of weight:

1. **Compatibility with GNUstep.** The project intends to import GNUstep library and
   application code where it is useful. Adopting GNUstep's own scheme — LGPL for
   libraries, GPL for programs — removes all licence friction from doing that.
2. **A forward-looking hedge** against the possibility that model-assisted code in the
   tree reproduces a span of GNUstep source. With the project already under compatible
   terms, no portion is distributed under a licence that could not cover it.

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
