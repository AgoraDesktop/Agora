# Provenance audit — is any first-party code copied?

Agora, GNUstep and Cocotron implement the *same* specification, so their code
converges in places without anyone copying anything. This directory exists to tell
those two situations apart, and to make the answer reproducible instead of a claim.

`audit.py` compares the first-party tree against five pinned upstreams on two
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
| `cocotron` | `9cda7d7` | the only other independent implementation of this API — Foundation, AppKit and the `Onyx2D` Core Graphics clone |

`corpus/` is not tracked. A clean result is only meaningful against stated
revisions, so the pins live in `CORPUS` in `audit.py` — bump them deliberately
and record the new run below.

**Why Cocotron.** The corpus held one *independent* implementation (GNUstep) plus
Apple's own source. Cocotron is the second independent reimplementation — MIT, ~2,070
source files, dormant since 2015, and therefore old, fork-heavy, widely mirrored code
of exactly the kind a language model reproduces verbatim. It also reaches where GNUstep
is thin here: `Onyx2D` and AppKit's drawing classes cover `libagora-drawing`'s subject
matter, and its `Foundation/NSURL` cluster is where the strongest `libagora-base`
candidate in the whole audit comes from (31.6% on `NSURLError.h`).

`setup` checks out each pin and **fails** if a pin cannot be reached, rather than
leaving the tree on whatever HEAD it found. `code`/`prose` print a file count for every
tree and refuse to run when one is missing or empty: a clean result against an absent
corpus is not a result.

**Adding a tree.** Add it to `CORPUS` with the repository URL and the revision you
mean to read, run `setup`, then `prose --control` and `code --control`. Record the run
below with the per-corpus line from both channels — that line is the evidence the new
tree was actually compared, and it is what a reviewer should check first. A tree that
contributes nothing to either channel is worth stating explicitly, because it usually
means it does not implement the surface rather than that agreement is total.

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

Both channels also print hits **per corpus tree**, so coverage of each upstream is
visible in the output rather than implied by it.

## Recorded run — 2026-10-23 (five trees)

Corpus at the pins above; `setup` verified each. The first-party tree held 1,098
fingerprintable files at the time (libagora-app had uncommitted slider work, so the
file count moves between runs; the result did not).

```
prose   control   345 of 377 files share prose   (tool is sensitive)
                   by corpus: swift-corelibs-foundation 767 runs,
                   swift-corelibs-libdispatch 433, cocotron 55, libs-base 10
        first-party   1,098 files -> NO SHARED COMMENT PROSE

code    control   360 of 377 files match (known copies, as expected)
        first-party  101 of 1,098 files with any collision
                       52 headers, 49 sources
                       pairs by corpus: cocotron 54, libs-gui 45, libs-base 38,
                       swift-corelibs-foundation 11
                       highest implementation match: NSLayoutAnchor.m at 14.9%
```

Cocotron behaves like the other upstreams: 54 code pairs, no prose. Sitting in the
middle of the distribution is what a genuine second independent implementation should
do — quiet on the probative channel, comparable to GNUstep on the candidate channel.

Every Cocotron candidate was inspected with `explain`. The longest shared runs are
declaration and enumeration bodies whose contents are Apple's:

| Agora file | Cocotron file | Longest run |
|---|---|---|
| `libagora-app/NSEvent.h` | `AppKit/NSEvent.subproj/NSEvent.h` | 356 tokens: one `enum` of key masks and function-key codes, 170 distinct tokens, no comment |
| `libagora-base/NSURLError.h` | `Foundation/NSURL/NSURLError.h` | 102: the `NSURLError*` codes and their values |
| `libagora-base/NSNumber.h` | `Foundation/NSNumber/NSNumber.h` | 93: `+numberWith…` declarations |
| `libagora-app/NSGradient.h` | `AppKit/NSGradient.h` | 74: `-drawFromPoint:toPoint:options:` declarations |
| `libagora-base/NSTextCheckingResult.h` | `Foundation/NSTextCheckingResult.h` | 71: the `NSTextCheckingType` options enum |
| `libagora-base/NSURLAuthenticationChallenge.m` | `Foundation/NSURL/NSURLAuthenticationChallenge.m` | 63: a `-dealloc` releasing three ivars |
| `libagora-base/NSURLCredential.m` | `Foundation/NSURL/NSURLCredential.m` | 54: ivar accessors |

The 356-token `NSEvent.h` run is the longest any Cocotron file produces, and it is
worth stating why it is not a finding: it is a run of enumerators, `=` and integer
literals, with no sentence of explanation anywhere in it. The order and the values
are fixed by the header both trees implement against; there is no discretionary text
in the span to copy.

**Conclusion: no copied code and no copied comment prose**, now against both
independent implementations of this API rather than GNUstep alone.

### False-positive class this corpus introduced

Cocotron transcribes `unicode.org`'s mapping tables into
`Foundation/NSString/Encoding/*.h`, and Apple's `CFBuiltinConverters.c` transcribes
the same tables. The comments are Unicode character names (`//START OF HEADING`), so
the two files share 55 twelve-word runs of what the prose channel calls prose. That
pair is the control, where shared text is expected — but the same shape in a
first-party file would be a false positive, and it is the one to check first if a
future Cocotron prose hit appears.

### Two tool defects found while adding the fifth tree

Both would have let a clean result mean less than it appeared to, which is why they
are recorded rather than quietly fixed.

1. **Fingerprints were not reproducible.** `hash()` is randomised per process, so
   winnowing kept different minima on every run: the same corpus reported 98 and then
   104 colliding files. Tokens now hash through blake2b with a per-token cache, and
   consecutive runs are identical wherever the tree is.
2. **An absent corpus tree was indistinguishable from a clean one.** `os.walk` over a
   missing directory yields nothing, and the audit printed `NO COLLISIONS`. Five trees
   made that silent pass much easier to achieve. `setup` now fails on an unreachable
   pin, and the audit refuses to run unless every pinned tree is present and
   non-empty.

## Recorded run — 2026-10-22 (four trees)

Corpus at the four original pins. Run before the per-file derivation notice was
removed, so the result decided that question. Not directly comparable to the run
above: the fingerprint hash and therefore the winnowing, and the `NSLayoutAnchor.m`
fraction, changed in between.

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
   upstream copyright notice on that file, leave it under the upstream's own terms,
   and add a row to `THIRD-PARTY.md`. GNUstep is LGPL-2.1-or-later, which upgrades
   into this tree's LGPL-3.0-or-later; Cocotron is MIT, which composes with either
   and constrains nothing — but a silent copy is still a false provenance claim, so
   the notice goes on the file either way.
3. **Record it** in `release/debian/copyright` and below, so the next run sees a
   known file rather than a surprise.

Do not restore a blanket per-file notice. It covered nothing and obscured this.

## Limits

- Five upstreams only. GNUstep *applications* are not compared, and Apple's SDK
  headers cannot be (not redistributable).
- **Cocotron carries two ports that are not its own:** GIFLIB in
  `Onyx2D/gif_lib.{h,m}` and a pthreads-win32 port in `pthread/`. A hit against those
  files is a hit on the ported library — check the file's own header before reading it
  as Cocotron, and check whether the counterpart in this tree is likewise a port of the
  same original.
- Detects verbatim runs, not paraphrases. A paraphrase is not a licence problem.
- `.c/.h/.m/.mm/.cc/.cpp` only; build glue (shell, Python, CMake) is not
  fingerprinted.
- This is detection with a stated resolution, not proof of absence.
