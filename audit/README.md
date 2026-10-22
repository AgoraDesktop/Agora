# Provenance audit — is any first-party code copied?

Agora reimplements an Apple API. Both Agora and GNUstep implement the *same*
specification, so their code converges in places without anyone copying
anything. This directory exists to tell those two situations apart, and to make
the answer reproducible instead of a claim.

`audit.py` compares the first-party tree against four pinned upstreams on two
independent channels.

## Setup

```sh
./audit.py setup
```

Clones (or checks out) the pinned comparison trees into `audit/corpus/`:

| Tree | Revision | Why it is here |
|---|---|---|
| `gnustep/libs-base` | `cb9b67d` | Foundation — the closest structural match to `libagora-base` |
| `gnustep/libs-gui` | `cacd5cb` | AppKit — the closest structural match to `libagora-app` |
| `swift-corelibs-foundation` | `28249ce` | Apple's own open source; the highest-duplication corpus |
| `swift-corelibs-libdispatch` | `ce1b4d3` | as above |

`corpus/` is not tracked. A clean result is only meaningful against stated
revisions, so the pins live in `CORPUS` in `audit.py` — bump them deliberately
and record the new run below.

## Running

```sh
./audit.py code  --control     # code tokens
./audit.py prose --control     # comment prose  <- the one that matters
./audit.py explain LIBAGORA-FILE CORPUS-FILE   # longest shared token run
```

`--control` runs the same comparison against `libagora-core` and
`libagora-dispatch`. Those are **known verbatim extractions** of swift-corelibs,
so the control must light up. **If the control is quiet, the tool is broken and
a clean audit result means nothing.** Always run with `--control`.

### What each channel means

**`prose` is the probative one.** Code can coincide because the specification
forces it; comment prose cannot. Any shared 12-word run needs an explanation.

**`code` produces candidates, not findings.** A hit is a file to inspect with
`explain`. The expected shape of a benign hit is a declaration
(`- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c;`) or a thin
delegating body — text that any implementation of that API must produce.

Resolution: `code` finds shared runs of roughly `k + w - 1` = 47 tokens
(defaults `k=40`, `w=8`); `prose` finds runs of 12 words. Shorter lifts are below
resolution by construction.

## Recorded run — 2026-10-22

Corpus at the pins above. Run before the per-file derivation notice was removed,
so the result decided that question.

```
prose   control   345 of 377 files share prose   (tool is sensitive)
        first-party   1 of 1063 files, 2 phrases  -> both Apple doc prose
                       inherited via swift-corelibs CFURL.h; reworded since
                       -> current result: NO SHARED COMMENT PROSE

code    control   matches at ~99% of fingerprints (known copies, as expected)
        first-party  68 of 1063 files with any collision
                       36 headers, 32 sources; 58 of them under 5% of the file
                       highest implementation match: NSLayoutAnchor.m at 11.7%
                       every inspected run was API-forced declaration or
                       delegation text
```

**Conclusion: no copied code and no copied comment prose.** The residual overlap
is specification convergence, which is the expected result for two independent
implementations of one API.

Two artefacts were produced by the tool itself and fixed before this run was
trusted — recorded because they are the failure modes a future reader will hit:

1. Mapping identifiers to per-file ids destroyed identifier identity, so
   structurally similar but textually different code collided (a generated bitmap
   table "matched" 377,169 shingles).
2. Erasing string-literal contents made any list of quoted strings match any
   other (`NSURL.m` showed a 369-token "match" against an unrelated nib decoder;
   it falls to 0 once literal text is kept).

Both were only visible because the control was lighting up while first-party
results claimed implausibilities.

## If a real match is found

Triage per [`THIRD-PARTY.md`](../THIRD-PARTY.md), in this order:

1. **Rewrite the span.** Cheap, preferred, keeps provenance clean.
2. **If it cannot be rewritten**, keep it and mark it honestly: reproduce the
   upstream copyright notice on that file, leave it under GNUstep's terms
   (LGPL-2.1-or-later, which upgrades into this tree's LGPL-3.0-or-later), and add
   a row to `THIRD-PARTY.md`.
3. **Record it** in `release/debian/copyright` and below, so the next run sees a
   known file rather than a surprise.

Do not restore a blanket per-file notice. It covered nothing and obscured this.

## Limits

- Four upstreams only. GNUstep *applications* are not compared, and Apple's SDK
  headers cannot be (not redistributable).
- Detects verbatim runs, not paraphrases. A paraphrase is not a licence problem.
- `.c/.h/.m/.mm/.cc/.cpp` only; build glue (shell, Python, CMake) is not
  fingerprinted.
- This is detection with a stated resolution, not proof of absence.
