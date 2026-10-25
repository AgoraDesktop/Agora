# The designated-initializer pass — handoff

*State at the end of the session that took Apple's designated-initializer graph from "measured and deferred" to **104 of
146 in-scope diagnostics closed, 63 of 143 leaves marked, and a decision written down for the rest**.
Everything below was measured; §6 reproduces every number.*

---

## 1. Where the tree is

All 31 suites green, the library builds with **zero** `-Wobjc-designated-initializers` diagnostics, and nothing is
half-applied.

| Gate | Reads |
|---|---|
| `foundation-api-availability` | annotations 800/800, 0 wrong · **designated-candidates 143 · present 63 · missing 80 · extra 2** |
| `foundation-api-10.11-census` | 198 of 219 classes, 3,422 of 3,521 selectors (99 missing), 31 of 40 protocols, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` 4,045, `methods-declared-not-implemented` 0 |
| `foundation-header-compile` | every header alone in ObjC/ObjC++/ARC |
| the suites | 31 of 31, including the collection, XML, scripting, archive and URL behaviour tests |

**The two numbers that matter, and how they relate.** With every mark placed the library emits **98 diagnostics in 21
files**. 56 of those are the number cluster (`NSNumber` 34, `NSDecimalNumber` 22), which §5 refuses by decision. The
scope is therefore **146**, of which **104 are closed** and **42 remain** in 19 files.

---

## 2. The rule clang actually enforces, measured

Four minimal compilations against `clang-19 -Wobjc-designated-initializers` (not read off the message text, which
misleads):

1. **A designated initializer may not chain to ANY initializer on `self`** — not even another designated one. The
   diagnostic is worded "should only invoke a designated initializer on 'super'", but a marked initializer that returns
   `[self initWithParts:…]` triggers it, plus a companion "missing a 'super' call".
2. **`[super init]` is legal when the superclass declares NO designated initializers** (`NSObject`, `NSScriptContext`…),
   and illegal when it declares one, unless the callee *is* that designated init.
3. **A class-extension mark does not rescue a self-chain** — the rule is about the chain, not the mark's location.
4. **A designated mark is rejected in a category** ("only applies to init methods of interface or class extension
   declarations") — and a class whose superclass has no designated doors treats every *marked* initializer as designated
   regardless of where the mark lives.

---

## 3. The recipes that follow

Each batch has been one family, one commit, with the diagnostic count as its gate.

- **A marked door is its own constructor**: `self = [super init]` (or the super's designated door), then the work, and
  `[self release]` on failure. A constructor that answers nil without releasing leaks the object it was sent on — the
  funnels that had to be dismantled were full of that.
- **A private funnel becomes a METHOD**, not an initializer: `NSURL -fn_takePartsFromString:` (YES/NO),
  `NSXMLNode -fnSetKind:name:value:` (`+fnNodeWithKind:` factory), `NSDictionary -setObjectInternal:forKey:`.
- **...unless the class is a hierarchy**, where the funnel becomes a factory + method and each class states its own graph.
- **A convenience door routes to a designated one** (build the C list, call the designated door, done).
- **A mutable subclass owes a CONVENIENCE override** of the immutable's designated constructor once it marks one of its
  own — capacity door, then append. Written this way it adds no mark, so `designated-extra` stays at 2.
- **A coder door is where a subclass rebuilds its aligned storage** (`NSCountedSet`'s counts, `NSDictionary`'s pairs).
- **A raise-only door keeps its refusal** and carries a LOCAL `#pragma clang diagnostic` with the reason
  (`NSURL -initByResolvingBookmarkData:…`, `NSXMLNode -initWithXMLString:`, `NSMachPort -initWithMachPort:[options:]`).
- **"Find every caller of the door the constructors route to."** `NSURL`'s first build recursed 174k frames deep because
  `FNURLResolveRelative` finished with `[components URL]`, whose `-URL` calls `+URLWithString:` — the door that resolves.
  The resolver now finishes with `FNURLWithSpelling`, the parse alone.

---

## 4. What landed, and the surprise in each batch

| Batch | Commit | Sites | The surprise |
|---|---|---:|---|
| 1 · `NSURL` | `0259d46` | 11 | the resolver recursion above; and the two nil-returning leaks the funnel closed |
| 2 · XML family (5 classes) | `e19b252` | 26 | a mark cannot live in a category; a *private initializer* funnel cascades overrides onto every subclass, so it became a factory + method; a subclass that marks anything must **restate inherited designated doors** (2 of them are tree-local → `extra` 2); the pass exposed that `NSXMLElement -initWithXMLString:error:` had been chaining to the inherited *raise*, so its error out-parameter was never written |
| 3a · set family + `NSCharacterSet` | `6cbe7d4` | 17 | the mutable/immutable pair: one designated door per class turns the funnel into the convenience one; a coder override is where a subclass's aligned storage is rebuilt; an empty **decoded** set stops being the shared empty instance |
| 3b · dictionaries + property-list doors | `5b16759` | 10 | the coder can be the designated door; a mutable capacity door must call a *designated* super door, and that is safe only because the empty substitution is keyed on the immutable concrete class |
| 3c · arrays + ordered sets | `24e7ca4` | 11 | same shapes; `AGArraySmall` starts from the super's designated constructor with an empty list |
| 4 · scripting family | `5a4b052` | 15 | six specifier subclasses each owe an override of the **base's** door: written as a *convenience* override routing to the subclass's own door they need no mark at all, which kept `extra` at 2 instead of 8 |
| 5a · `NSFileWrapper` + `NSMachPort` | `a26683b` | 14 | `NSFileWrapper -init` is a convenience door in Apple's graph (routes to `-initRegularFileWithContents:nil`); an inherited `-initWithCoder:` is not a declaration site, so the fact needed a header line (candidates 142 → 143); `NSMachPort` restates three inherited socket doors and the census does **not** count them as extras because they are not class-owned selectors |

---

## 5. The decision: the number cluster is refused, by name

`NSNumber` is a re-routing class cluster: the front's 16 type constructors do
`[self release]; return [[AGNumber… alloc] initWithX:value]`, and five concrete subclasses override the same 16
selectors. Under rule 2 a concrete override must call a marked super init; under the cluster's design, calling
`[super initWithInt:]` re-enters the front's re-router and recurses forever. So the only legal call is `[super init]`,
which rule 2 forbids. **Apple's marks describe a cluster whose storage lives in Core Foundation, where no clang rule
applies; this cluster's storage lives here.**

**Decision (taken, FOUNDATION-10.11-PLAN.md §4.15): leave the sixteen unmarked and let `designated-missing` carry them**
(`NSDecimalNumber`'s 2 go with them). Reasons: a header states the reference, not this tree; marking `NSNumber -init`
(option b) would buy 57 quiet diagnostics, not 57 correct contracts, and would be a load-bearing tree-local fact in a
reference header; and option (a)'s cost is a number the census already carries and `annotate` already names — it is the
only deliberate refusal on the work list.

**Consequence:** `NSNumber.m` and `NSDecimalNumber.m` are not touched, and their 56 diagnostics are **not** part of the
pass's remaining count.

---

## 6. What remains: 42 diagnostics in 19 files, measured

Measured by placing every remaining mark, building, and counting (then reverting):

| File | Diagnostics | Note |
|---|---:|---|
| `NSSocketPort.m` | 8 | `-init`, `initWithTCPPort:`, the two remote doors call `[super init]` while three socket doors are marked; `-init`'s bind behaviour is the one to check first |
| `NSString.m` | 5 | the string cluster's own doors |
| `NSDate.m` | 4 | |
| `NSDataDetector.m` | 3 | |
| `NSAppleEventDescriptor.m` | 2 | `-init` should route to `-initWithAEDescNoCopy:` |
| `NSComparisonPredicate.m` | 2 | the custom-selector door chains to the 5-argument door |
| `NSExpression.m` | 2 | coder door; investigate which mark makes it non-designated |
| `NSIndexPath.m`, `NSIndexSet.m` | 2 each | `-initWithIndex:` should route to the marked indexed doors |
| `NSInputStream.m`, `NSOutputStream.m` | 2 each | file doors should route to the marked URL/data doors |
| `NSAppleScript.m`, `NSBundle.m`, `NSFileHandle.m`, `NSHashTable.m`, `NSLocale.m`, `NSMapTable.m`, `NSNotification.m`, `NSPointerArray.m` | 1 each | `NSAppleScript`'s URL door is *designated* and chains to `-initWithSource:` (needs the compile body extracted); `NSFileHandle`'s coder door is a refusal → local pragma; `NSNotification`'s coder door should flip to the convenience one; the rest are convenience→super calls that need a route |

The marks for all of these are **reverted**, which is why the tree is warning-free: a partial placement would be a sweep
whose pin reads a number nobody chose.

---

## 7. Reproducing every number

```sh
cd libagora-base

# the availability/designated position (the pinned numbers in §1)
python3 ../libagora-app/tools/api-ledger availability api/10.11/foundation-manifest.txt . \
        --pin tests/api-10.11-annotations.txt

# the work list: 80 declarations, 18 of them the refusal
python3 ../libagora-app/tools/api-ledger annotate api/10.11/foundation-manifest.txt .

# the true remaining diagnostic count: place every mark, build, count, revert
python3 ../libagora-app/tools/api-ledger annotate api/10.11/foundation-manifest.txt . --apply
cd build && make Foundation 2>&1 | grep -c objc-designated-initializers ; cd ..
git checkout -- .        # the marks are a measurement here, not a commit

# the suites
cd build && ctest
```

---

## 8. Working-tree caveats

- **A concurrent editor is active** in this workspace and in `libagora-base`. Commits landed between mine throughout
  (`bd921e5` sits between batches 1 and 2; `cb808bc`, `fe34cd2`, `4a763eb` landed in the workspace mid-session). Every
  commit of this pass touches only the pass's own files, and the submodule pointer has been checked after each.
- One workspace commit here (`c207cc9`) recorded the tail's work list without moving the submodule pointer; `983a63a`
  corrected it. **Check `git submodule status` before trusting a pointer** — that is the same trap the earlier handoff
  recorded.
- `NSNumber.h`, `NSDecimalNumber.h` and the other refused/unfinished headers must stay unmarked. `annotate --apply`
  marks everything; the workflow is apply → revert everything except the batch's headers → fix → commit.

---

## 9. Order I would take next

1. **`NSSocketPort` (8)** — the largest single file left, and it decides how the port family's four convenience doors
   route; check `-init`'s bind behaviour before choosing its marked target.
2. **`NSString` (5) + `NSDate` (4) + `NSDataDetector` (3)** — three clusters in one commit or three; each has its own
   funnel shape rather than a shared one.
3. **The 1–2-site classes (22)** in two commits: the "route to a marked door" group (`NSIndexPath`, `NSIndexSet`,
   `NSInputStream`, `NSOutputStream`, `NSAppleEventDescriptor`, `NSBundle`), then the "extract or flip" group
   (`NSAppleScript`, `NSNotification`, `NSExpression`, `NSComparisonPredicate`, `NSLocale`, `NSHashTable`, `NSMapTable`,
   `NSPointerArray`, `NSFileHandle`).
4. **Then the W1 residue** the plan lists: `AGORA_EXTENSION` for post-10.11 classes and the 411
   `-Wnullability-completeness` warnings across 194 of the 197 headers — the last of which is a mechanical sweep of the
   same shape as this one, and now has a precedent for how to do it (measure, batch by family, pin the movement).

**Do not re-open the number cluster** unless the tree ever replaces the re-routing design: the decision is recorded, and
the twenty-two "missing" facts it contributes are the record of it.
