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

## 8. Items 1–3, closed (the session after)

The first three are done, and two of the three guesses in §7 were wrong in a useful way:

1. **The `%d + 1` probe found no substitution fault at all.** `%d` was substituted correctly at primary level, as
   §4 suspected; what failed was the arithmetic that followed it, which did not exist. `%d + 1` and a two-argument
   `%d + %d` are now cases in the suite, so the next reader does not have to take that on trust.
2. **The mode flag was the smaller half of the slice.** Grouping was one case in `FNParsePrimary`; what the new door
   actually needed was a precedence-climbing arithmetic grammar (`**`, then `* /`, then `+ -`), Apple's function names
   behind it, and — the part no header diff would have caught — a RENDERER that writes arithmetic as arithmetic.
   `add:to:(a, b)` is text no grammar here can parse, so without that half the door would build trees that cannot
   survive their own `-predicateFormat`. The second unplanned piece was a trailing-colon rule: `modulus:by:` has no
   operator, so it is only round-trippable once a selector-shaped name is read as one symbol.
3. **The conditional** was as sized (3 doors), plus the `TERNARY` production, because it renders as `TERNARY(...)` and
   the predicate door must be able to read what the renderer writes. `TERNARY` also could not reuse the function
   argument loop: its first argument is a predicate, and that loop parses all arguments as expressions.

Two things are worth knowing before the next slice:

- `-Wobjc-designated-initializers` is still the constructor pass's gate, untouched. Nothing here moved it.
- The expression suite (`tests/expression_format.m`, 56 cases) is where a comparison refusal, the round trip and the
  `TERNARY` form meet; `1 < 2` raises naming `+predicateWithFormat:` on purpose, and that refusal is a test now.

State after the two commits (`ea2b053`, `12af1e2`): 10.11 census 3,414 of 3,513 selectors (99 missing), 197 of 219
classes, 31 of 40 protocols; 10.6 census unmoved except `methods-declared` 4,017 → 4,024; annotations 799 of 799;
30 of 30 tests green, including the header-compile gate over 196 headers in three modes.

## 9. Item 4, closed — and the policy it asked for

`NSPersonNameComponentsFormatter` landed all eight of its doors (`3b67dec`), and the decision §7 item 4 said had to be
written before the code is FOUNDATION-10.11-PLAN.md **§4.14**: this tree has no CLDR and does not get one in this slice,
so the order of a name comes from a **written table of five languages** (`hu`, `ja`, `ko`, `vi`, `zh` family-first) and a
**documented default** (given-first) for every other language, read from the locale's language subtag. The header states
the table, because a caller reads the header and not the plan.

Three things that were decisions and not mechanics:

- **The refusals are the two places a guess would have been invisible.** An unimplemented style raises naming the value
  (10.12's `Abbreviated` would otherwise have rendered *something*), and the parsing door answers NO with a nil object
  and **no invented error string** — Apple's class does not parse either, so that is the documented answer.
- **The annotated string is the same renderer, not a second one.** It records the range of every component and every
  separator as it appends, so `-stringFromPersonNameComponents:` and `-annotatedStringFromPersonNameComponents:` cannot
  disagree, and the separator is a marked run because a caller laying a name out needs to know where the spaces are.
- **`phonetic` is a total switch.** The representation is used only when it carries a component; a hollow one falls back
  to the components rather than rendering nothing.

The census fell by **one class and zero selectors** (198 of 219, 3,422 of 3,521, 99 missing): the eight doors arrived
with the class they belong to, which is what a slice that starts at the input type looks like when it finishes.

W2 is closed. What remains in the plan is the W1 residue (the constructor pass, `AGORA_EXTENSION`, the 411
nullability warnings) and W3 onward (`URLSession`, notifications/extensions, XPC refusals, the 70-door tail, the 26
header names).

## 10. Item 5, attempted and handed back — with the rule it needs

The constructor pass was started, measured and reverted. Nothing is half-applied; the tree is green at `3b67dec` plus
the documentation commits.

**What the attempt produced, which the plan did not have:**

- The accurate size: **202 distinct `-Wobjc-designated-initializers` sites across 35 files** (the 208 in §2 was a raw
  line count over an interleaved parallel build). The distribution is in the plan's §4.15 and it is the batch plan.
- **The rule clang actually enforces**, established by four minimal compilations rather than by reading the message
  text: a designated initializer may not chain to ANY initializer on `self` (not even another designated one); `[super
  init]` is legal when the superclass declares no designated initializers (so the unmarked `NSObject -init` is fine);
  it is illegal when the superclass declares one unless that callee is the designated one; and a class-extension mark
  does not rescue a self-chain.
- **The recipe that follows**: every class here funnels its constructors through one private initializer, and that is
  precisely what a designated door may not call. So the pass converts each funnel into a plain method and makes each
  marked door its own constructor — which also fixes the funnels' existing failure paths (a funnel returning nil from
  an init does not release `self`). The behaviour of every failure path is the part to review, not the marks.
- **One class cannot obey it at all**: `NSNumber`'s re-routing cluster. A concrete override must call a marked super
  init; calling one re-enters the front's re-router and recurses, so the only legal call is `[super init]`, which the
  rule forbids. Apple's marks describe a CF-backed cluster where no clang rule applies. Two dispositions are written
  down (leave 16 marks out, or mark `NSNumber -init` and record `designated-extra` 1); it is a decision, and it is why
  the number cluster (57 sites) is the LAST batch and not the first.

**Why not land it partially.** The marks are a binary statement per declaration and the sweep places them by class, so a
partial placement would be a sweep whose pin reads a number nobody chose. Landing them without the pass would state 135
contracts the bodies break 202 times — what §2 refused. The plan's §4.15 now carries the per-file work list and the
batch order (superclasses before subclasses: `NSURL` → the XML family → the collection family → … → the cluster last),
so the next session can take one batch per commit and each commit moves `designated-present` by the batch's count.

## 11. Item 5, first batch landed — and the rule is now a recipe

`NSURL` is done: 11 sites → 0, `designated-present` 2 → 10, `designated-missing` 135 → 127 (`0259d46`). The parse is
`-fn_takePartsFromString:` answering YES/NO, the eight marked doors are each their own constructor, and the two
nil-returning failure paths in the old funnel now release.

**The finding of the batch is a recursion, and it is written into §4.15 so the next batch looks for it first.** Routing
the non-resolving `-initWithString:` through the resolving designated door made `+URLWithString:` resolve — and
`FNURLResolveRelative` ended with `[components URL]`, whose `-URL` calls `+URLWithString:`. 174k frames deep and the
crash surfaced in an unrelated test. The resolver now finishes with `FNURLWithSpelling`, the parse alone, declared
beside `FNURLResolveRelative` in `NSURL.h`. **The rule for the next batch: when a funnel becomes a constructor, find
every caller of the public door the constructors route to — the resolver was such a caller.**

A second, smaller rule: a door whose whole body raises cannot be made to comply; it keeps its refusal and carries a
local `#pragma clang diagnostic` with the reason (`NSTinyString.m`'s precedent), rather than parsing something first to
satisfy the checker.

The next batch is the XML family (`NSXMLNode`/`NSXMLDocument`/`NSXMLDTD`, 26 sites, and the family shares a funnel the
way `NSURL` did), then the collections (39), then `NSString`/`NSFileWrapper`/`NSMachPort`/`NSSocketPort` (29), the
scripting six (14), the tail (26), and the number cluster (57) last — it still needs the (a)/(b) decision §4.15 records.

## 12. Item 5, batch 2 — the XML family, and three rules the batch cost

26 sites to 0 (`e19b252`): `NSXMLNode`, `NSXMLElement`, `NSXMLDocument`, `NSXMLDTD`, `NSXMLDTDNode`. The batch was
three times the work of `NSURL`'s because a *hierarchy* is not a single class, and what it taught is now in §4.15:

1. **A designated mark is rejected in a category**, so a private constructor's declaration has to live in the main
   `@interface`.
2. **A private constructor that is an initializer makes every subclass owe an override of it** (and of the newly
   declared `-init`) — a cascade of shadow doors. Convert it to a factory plus a storage *method*, which is `NSURL`'s
   recipe in the form a hierarchy needs.
3. **A subclass that marks any initializer must re-state the inherited designated doors it honours**, or clang reads
   its override as convenience. Two of those restatements are facts Apple does not state (`NSXMLElement`'s and
   `NSXMLDTD`'s kind doors), which is the census's first `designated-extra`, 0 → 2, recorded rather than hidden.

The batch also exposed a capability gap it did not create: `NSXMLElement -initWithXMLString:error:` had been chaining to
the inherited door that RAISES, so its error out-parameter was never written. It now refuses by name and releases.

State: `designated-present` 22, `missing` 120, `candidates` 142, `extra` 2; `methods-declared` 4,041; 31 of 31 suites
green, including the `NSXMLDocument` parser. Next in §4.15's order: the collection family (`NSDictionary`/`NSSet`/
`NSOrderedSet`/`NSCountedSet`/`NSArray`/`NSCharacterSet`, 39 sites) — one family, and by now the three rules above are
the checklist rather than the surprise.

## 13. Item 5, batch 3a — the pair is where the cascade shows

17 sites to 0 (`6cbe7d4`): `NSSet`, `NSMutableSet`, `NSCountedSet`, `NSCharacterSet`. Four lessons, all from the
mutable/immutable pair rather than from any single class:

- **One designated door per class means the FUNNEL becomes the convenience one.** `NSSet` had three copies of its
  construction rules (`-initWithObjects:count:`, `-initWithArray:`, `-initWithCoder:`); only the designated door may
  build, so the array and coder doors changed shape rather than gaining an override.
- **A mutable subclass owes an override of the immutable's designated constructor** as soon as it marks one of its
  own. Make it a CONVENIENCE override (route through its own designated door and add) and `designated-extra` stays put;
  make it a pass-through and it needs a second tree-local mark.
- **A coder override is where a subclass's extra storage has to be rebuilt.** `NSCountedSet`'s counts are aligned with
  the members it inherits, and the wire carries members only: the override rebuilds one count per member instead of
  leaving `_counts` nil for the first `-countForObject:`.
- **A behaviour change worth writing down**: an empty DECODED set is a plain instance now, not the shared empty one —
  the class-choosing rule belongs to the constructor, and a decoder has data rather than a constructor argument.

State: `designated-present` 28, `missing` 114, `candidates` 142, `extra` 2; 31 of 31 suites green. Remaining in the
family: `NSDictionary` 9, `NSOrderedSet` 6, `NSArray` 5, `NSPropertyListSerialization` 1 — 21 sites, marks not yet
placed, next commit.

## 14. Item 5, batch 3b — the coder as a designated door

10 sites to 0 (`5b16759`): `NSDictionary`, `NSMutableDictionary`, and the two `-initWithContentsOfURL:` doors that live
in `NSPropertyListSerialization.m`. The dictionary is the first class whose designated door is the **coder**, and it
behaved exactly like its siblings:

- convenience doors start from `-init`; the coder calls super and replays the decoded pairs through the primitive
  setter instead of chaining to the canonical constructor;
- the mutable subclass owes a CONVENIENCE override of the immutable's designated constructor (capacity door, then the
  setter), which keeps `designated-extra` at 2;
- **the mutable capacity door must call a DESIGNATED super door** — the canonical constructor with a zero count, not
  `[super init]` — and that is safe because the canonical constructor's empty substitution fires only for
  `isMemberOfClass:[AGDictionaryItems class]`, so a mutable answer stays mutable;
- the two property-list doors were answering a SUBSTITUTE object from an initializer that made no self call; they parse
  and route through the class's own `-initWithArray:`/`-initWithDictionary:`.

State: `designated-present` 32, `missing` 110, `candidates` 142, `extra` 2; 31 of 31 suites green. Left in the
collection family: `NSOrderedSet` (6) and `NSArray` (5), marks not placed — then the 1–3-site tail (26) and the number
cluster (57), which still needs the (a)/(b) decision §4.15 records.

## 15. The number-cluster decision: the sixteen stay unmarked

§4.15 asked for one decision before the last batch, and it is taken: **option (a)** — `NSNumber`'s sixteen typed
constructors stay unmarked, and `designated-missing` carries them.

- **A header states the reference, not this tree.** Marking `NSNumber -init` (option b) would put a fact in the header
  Apple's 10.11 header does not state, and it would be *load-bearing for the build* — the kind of tree-local contract
  §4.13 confines to `AGORA_EXTENSION` spellings.
- **(b) buys 57 quiet diagnostics, not 57 correct contracts.** The concrete subclasses' `[super init]` would become
  legal by fiat of a mark about `-init`, while the re-routing design that made it illegal stays. Silencing a checker
  with an adjacent assertion is what this pass exists to avoid.
- **(a)'s cost is a number that already exists** and is honest: the sixteen are counted as missing, `annotate` keeps
  naming them, and §4.15's paragraph is the reason they stay named. The gate fails on `wrong` and on drift, not on
  `missing`.

So `NSNumber.m` and `NSDecimalNumber.m` are not touched, their 57 sites are **not** part of the pass's remaining count,
and `annotate`'s dry run will keep offering the sixteen as the one refusal on the list.

Remaining, in order: `NSOrderedSet` (6) and `NSArray` (5) — marks unplaced — then the 1–3-site tail (26). That is 37
sites across 13 files; the rules are in §4.15 and every batch so far has been one family, one commit.

## 16. Batch 3c, the family closed — and the residue re-measured

11 sites to 0 (`24e7ca4`): `NSArray`, `NSMutableArray`, `NSOrderedSet`, `NSMutableOrderedSet`, plus `AGArraySmall`.
The collection family is done: `designated-present` 40, `designated-missing` 102.

**The plan's earlier "1–3-site tail (26)" was an undercount, and `annotate`'s dry run is the authority.** It now says 102
unmarked declarations in 54 headers. Of those, 18 are refused by decision (`NSNumber` 16, `NSDecimalNumber` 2 — the same
re-routing cluster), so **84 facts remain, producing roughly 70 diagnostics**, in this size order:

| Group | Warnings |
|---|---:|
| scripting (`NSScriptObjectSpecifiers`, `NSScriptWhoseTests`, `NSScriptCommand`) | 18 |
| `NSFileWrapper` | 7 |
| `NSMachPort` + `NSSocketPort` | 14 |
| `NSString` | 8 |
| 1–2-site classes (values, indexes, streams, hash/map tables, notifications, pointer arrays, archivers, locale,  Apple events, predicate/expression, bundle, file handle, AppleScript) | ~23 |

Nothing else about the pass changed: the four rules in §4.15 plus the pair lesson, one family per commit, the tree green
and the diagnostic count at zero between batches.
