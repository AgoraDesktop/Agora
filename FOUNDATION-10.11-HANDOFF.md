# Foundation 10.11 — handoff

*State at the end of the session that wrote `FOUNDATION-10.11-PLAN.md` and implemented W0, W1a/W1b and most of W2.
Everything below was measured, not remembered; the commands that reproduce it are in §5.*

---

## 1. Where the tree is

`libagora-base`, gate by gate (all green, 29 tests):

| Gate | Reads |
|---|---|
| `foundation-api-census` | 10.6: 173/173 classes, 2,840/2,840 selectors, 23/23 protocols, 180/180 functions — **unmoved all session except when a declaration landed** |
| `foundation-api-10.11-census` | 10.11: **197 of 219 classes, 3,408 of 3,513 selectors (105 missing), 31 of 40 protocols, 182 of 182 functions** |
| `api-ledger-selftest` | 18 fixture cases for the extractor's own faults |
| `foundation-api-availability` | 792 of 792 annotated declarations, 0 wrong, 0 extra; designated-init 137 candidates / 2 present / 135 missing |
| `foundation-header-compile` | 196 headers **alone** in ObjC, ObjC++, ARC, plus the umbrella per mode (591 compilations) |

`methods-declared-not-implemented` is 0 in both censuses. The whole remaining 10.11 gap is **10.8–10.11**: 0 owed
from 10.6.

## 2. What landed, and the five things it taught

### W0 — the denominator (`b43ab04`, tool `98240f3`)
`api/10.11/foundation-manifest.txt` (4,218 lines: 220 classes, 40 protocols, 185 functions, 3,763 selectors, 1
`ios-class`, 9 `unavailable-selector`, 74 `class-era`, 860 `selector-era`), `api/10.11/README.md` (recipe), and
`tests/api-10.11-census.txt`, registered as a second `add_test` over the same `api_census.cmake`.

**Three extractor faults were inflating and deflating the gap at the same time**, each now a selftest case:

1. A property's trailing annotation was read as its name, or made the property vanish — **299 accessors were never in
   the manifest**, so the gap read 25 selectors too small. The gap *grew* when the instrument was fixed.
2. String literals were parsed as syntax, so `NS_DEPRECATED(…, "Use [NSURLSession dataTaskWithRequest:…]")` produced
   selector names that exist nowhere (2 doors).
3. Availability was not a fact — `NS_UNAVAILABLE` and `NA` were indistinguishable from absent (1 phantom class, 2
   phantom selectors).

### W1a/W1b — the availability layer (`7632dfb`, `1aee79d`, tool `ff613cd`/`7b75a34`)
The macros were inert by decision (D12) and now alias `CF_AVAILABLE`/`CF_DEPRECATED` as Apple's own header does.
**761 declarations in 108 headers** carry Apple's version, written by `api-ledger annotate` (idempotent, dry-run by
default, inserts only at a terminator). Two more instrument faults fell out — and both had already put false facts in
the manifest: **a category's availability was recorded as its class's** (NSArray is not a 10.6 class), and **a forward
`@protocol X;` was read as a block** (NSXMLParser's doors were attributed to its delegate).

Lessons: `CF_AVAILABLE` was never in scope (W1a compiled only because nothing used the macros); the sweep's spelling is
`NS_AVAILABLE_MAC`/`NS_DEPRECATED_MAC`, never the two-argument form, because only the macOS token is a committed fact.

### W1's other half — headers and ownership (`e3734d9`) and the designated facts (`8101a28`)
`foundation-header-compile` found **five headers that had never been asked to stand alone**: two importing nothing at
all, a category whose host class was forward-declared, an ivar type nobody declared, a protocol conformance with no
protocol. `NS_RETURNS_INNER_POINTER` on the seven doors Apple marks; `__kindof` on the two generics the tree has.

**`NS_DESIGNATED_INITIALIZER` did not exist in this tree at all.** The facts are now committed and pinned, but the
marks are **not** placed: with all 135 in place the library builds and clang emits **208 distinct
`-Wobjc-designated-initializers` warnings, every one of them true**. Marking the headers first would state a contract
the constructors break 208 times. The constructor pass is its own slice, gated on that warning count.

### W2 — the spine (five slices, all verified by a probe)
`9af40bb` unit style + the enum fix · `399cb69` `NSURLQueryItem` · `53f152d` `NSURLComponents` · `87940c1`
`NSProgress` · `6c36835` `NSByteCountFormatter` · `0e078c0` evaluation sandbox (5 doors) · `19ab8e9` the eight
`rangeOf…` properties.

Three findings worth keeping:

- **`NSFormattingUnitStyle` counted from zero** where 10.11 declares 1/2/3 — found by the first code to read it. A
  zeroed ivar also looked like a valid style, which is why every formatter now sets it in `-init`.
- **`FNURLComponents`' plain setters take RAW text** (correct for a parser) where Apple's take DECODED text, and one
  percent-encoder encoded the **path separator** (`/a b` → `%2Fa%20b`). Each component now has its own RFC 3986
  allow-list; `queryItems`' pair encoder keeps nothing beyond unreserved, because `&`/`=` inside a value must survive.
- **A manual KVO pair double-announces a key that KVO already wraps.** `NSProgress`' first version bracketed
  `completedUnitCount` and `cancelled` and announced each twice; the manual pair is only for the DERIVED keys
  (`fractionCompleted`, `indeterminate`), which have no setter to wrap.

## 3. What is left

### W2 — 14 doors
| Group | Doors | Blocker |
|---|---|---|
| `+expressionWithFormat:` family | 3 | **the parser** — see §4 |
| `trueExpression`, `falseExpression`, `+expressionForConditional:trueExpression:falseExpression:` | 3 | needs an `NSExpressionType` for conditional expressions |
| `NSPersonNameComponentsFormatter` | 8 | needs a **policy** decision (below) |

### W1 residue
`AGORA_EXTENSION` for post-10.11 classes; the **411 `-Wnullability-completeness` warnings across 194 of 196 headers**
(measured, objc mode); the designated-initializer constructor pass (208 warnings → 0, then place the marks and move
`annotations`/`designated` pins in one commit).

### W3 onward
`URLSession`: 7 classes, 5 protocols, ~103 class-owned selectors — the largest single item in the plan, and it gates
W4 structurally. Then notifications/extensions, XPC refusals + the refusal census, the 70-door tail, and the 26 header
names.

## 4. The one open design question, and one bug with a known cause

**`+expressionWithFormat:` is blocked by a deliberate refusal, not a defect.** `FNPredicateFormat.m:271`:

```c
case '(':
    /* A PARENTHESIS IN OPERAND POSITION IS A PREDICATE GROUP… (a) == b is not Cocoa, and this tree refuses it */
    FNFail(p, @"a parenthesised expression is not supported in operand position; use a key path");
```

That is right for the predicate grammar and wrong for Apple's expression grammar, which allows grouped operands. The
fix is a parser mode flag (expression accepts `(`, predicate keeps the refusal **and its message**), not a rewrite.
A probe of eight cases was run: `1 + 1`, `%@`, `1 < 2` → nil, `nil` format → nil all pass today; `2 * (3 + 4)` and
`%d + 1` (varargs and `argumentArray:`) fail. `%d` substitution **is** handled at primary level, so its failure is
downstream and should be probed separately before any code moves.

**A variadic declaration must not be preceded by a fixed one with the same selector.** The first attempt declared both
`+expressionWithFormat:` forms; clang took the first and reported *"too many arguments to method call, expected 1, have
2"* — which cost one session to misdiagnose as a header disagreement. Apple declares it **once, variadically**.

`NSPersonNameComponentsFormatter`'s open question: Apple orders names by locale and this tree has no CLDR. The shape
the plan's §4.3 discipline supports is a small documented table (family-given where it knows, given-family otherwise)
plus a **refusal by name** outside it — but how much locale data this tree carries is a decision to write down before
the code, not during it.

## 5. Reproducing everything

```sh
cd libagora-base
python3 ../libagora-app/tools/api-ledger check api/10.11/foundation-manifest.txt . \
        tests/api-10.11-census.txt --library build/libagora-base.so --include ../libagora-core/include
python3 ../libagora-app/tools/api-ledger availability api/10.11/foundation-manifest.txt . \
        --pin tests/api-10.11-annotations.txt
python3 ../libagora-app/tools/api-ledger annotate api/10.11/foundation-manifest.txt .     # dry run: must say 0
python3 ../libagora-app/tools/api-ledger selftest
cd build && ctest
```

The reference SDK is **not** in the repository. `api/10.11/README.md` has the fetch recipe (156 headers of
`MacOSX10.11.sdk`, `Versions/C/Headers`); the manifest is names, relationships and version tokens only.

## 6. Working-tree caveats for whoever continues

- **`libagora-app` was being edited concurrently** during this session (`NSWindow.h`, `NSCell.h`, …). Only
  `tools/api-ledger` was staged from that tree, in four commits (`98240f3`, `ff613cd`, `7b75a34`, `acfbd16`).
- The AppKit census reported `methods-declared 5,408 → 5,409` mid-session from those concurrent edits. **Its pin was
  left alone** — pinning someone else's in-flight work would hide it.
- One workspace commit (`e7feeec`) bumped the `libagora-app` pointer without its submodule change; `acfbd16` in the
  submodule and `bbc73e0` in the workspace corrected it. Check `git submodule status` before trusting a pointer.
- Two attempts at the expression slice were **reverted**, not committed. The tree at `19ab8e9` is the last green state
  of `libagora-base`; nothing half-applied is waiting.

## 7. Order I would take next

1. **`%d + 1` probe** — one small test, no code, to find whether the substitution failure is in the operator tokeniser
   or in the test's varargs. Cheap, and it may be a one-line fix.
2. **Parser mode flag for `(`** — expression mode accepts a group, predicate mode keeps its refusal and message. Then
   declare the three doors with the variadic form alone.
3. **The conditional expression type** (3 doors) — a new `NSExpressionType`, its two accessors, and the class method.
4. **`NSPersonNameComponentsFormatter`** — write the locale policy into the plan first, then the table, then the
   refusal, then the class.
5. **The constructor pass** — 135 designated initializers, 208 warnings as the gate, then the marks and both pins.
6. **W3 (`URLSession`)** — the largest item; start with the task state machine over the existing libcurl engine, since
   `NSURLConnection`/`NSURLDownload` already drive it.
