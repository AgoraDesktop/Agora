# The designated-initializer pass, session 2 — handoff

*State at the end of the session that picked up `DESIGNATED-INITIALIZER-HANDOFF.md`'s 42-diagnostic tail and closed it,
and then placed the remaining marks: **every Apple-marked designated initializer this tree declares is marked except the
number cluster's 18**, and the library emits **zero** `-Wobjc-designated-initializers` diagnostics with all of them in
place. Everything below was measured; §6 reproduces every number.*

---

## 1. Where the tree is

All 31 suites green, the library builds with **zero** designated-initializer diagnostics, and nothing is half-applied.

| Gate | Reads |
|---|---|
| `foundation-api-availability` | annotations 800/800, 0 wrong · **designated-candidates 143 · present 125 · missing 18 · extra 2** |
| `foundation-api-10.11-census` | 198 of 219 classes, 3,422 of 3,521 selectors (99 missing), 31 of 40 protocols, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` 4,046, `methods-declared-not-implemented` 0 |
| `foundation-header-compile` | every header alone in ObjC/ObjC++/ARC |
| the suites | 31 of 31 |

**The 18 missing marks are the decision, not debt.** They are exactly `NSNumber`'s 16 and `NSDecimalNumber`'s 2 — the
re-routing class cluster `FOUNDATION-10.11-PLAN.md` §4.15 refuses by name, because Apple's marks describe a cluster
whose storage lives in Core Foundation while this cluster's storage lives here. Do not re-open it without replacing the
re-routing design.

---

## 2. What landed, and the surprise in each batch

Each batch is one commit in `libagora-base`, one family, with the diagnostic count as its gate.

| Batch | Commit | Sites | The surprise |
|---|---|---:|---|
| 5b · `NSSocketPort` | `84b512d` | 8 | The header had **always declared the older spellings** (`initWithRemote…`) beside §63.217's correct `initRemote…` doors, both implemented. Deleting the duplicates left the declarations unimplemented, which the census reports as `selphantom:NSSocketPort 2` — so they became aliases. Also: the designated remote door left a failed connect's socket to dealloc, and both remote paths set `-address` from `getsockname` where the header says `getpeername` (the PEER). |
| 6 · `NSString` + `NSDate` + `NSDataDetector` | `0e4a49b` | 12 | `NSDate`'s storage door was the *1970* door; making the Apple-marked **reference-date** door the constructor and 1970 a route was the whole fix. `NSString`'s front is a re-routing cluster: `-init` stays self-returning (the measured recursion) and every re-router delegates to it before releasing the front and answering `NSOwnedString`. The initializer-shaped funnel `fn_initWithValidatedFormat:` became validation inside the doors, which also stopped a failure path from leaking the receiver. |
| 7 · route-to-a-marked-door group | `ed02640` | 11 | `NSAppleEventDescriptor`'s Apple-marked door **can only refuse** here (no Carbon AEDesc), so the header RESTATES and marks `-init` as this tree's constructor: the one deliberate surface addition, `methods-declared` 4,045 → 4,046. `NSBundle -init`'s private funnel became "the empty path MEANS the bare bundle" at the designated door. |
| 8 · extract-or-flip group | `2f0de76` | 11 | Seven classes have **two designated doors** where one used to chain to the other (`NSAppleScript`, `NSComparisonPredicate`, `NSLocale`, `NSNotification`, `NSHashTable`, `NSMapTable`, `NSPointerArray`). The shared install became a plain method (`fnAdopt…`) and each door chains to super and states it. `NSFileHandle`'s coder door is a raise-only refusal and keeps the local pragma. |
| 9 · the last 29 marks | `9dd0fe2` | 29 marks, 0 diagnostics | Placing them was clean, **except one knock-on the measurement found**: `NSDataDetector` is an `NSRegularExpression` subclass, so marking the super's designated pattern door obliged the detector to override it. A detector has no pattern, so that override refuses with an error naming `-initWithTypes:error:`, and the detector's designated door chains to the super's with the empty pattern (state every matching door bypasses through `-matchesInString:…`). |

The first handoff's 42-diagnostic table is therefore closed by batches 5b–8 (8 + 12 + 11 + 11 = 42); batch 9 worked
the *marks* that had no diagnostic of their own (the 29 declarations whose bodies already conformed).

---

## 3. The recipes, as they now stand

Confirmed by this session, in addition to the first handoff's §3:

- **A convenience door routes to a designated one by BUILDING THE ARGUMENT**, not by copying the constructor:
  `-init`/`-initWithTCPPort:` build the `sockaddr` and call the address door; `-initWithFileAtPath:` is the URL door
  with a file URL; `-initWithIndex:` is the list/range door with a list/range of one.
- **A class that has TWO designated doors cannot chain between them.** The shared install becomes a method
  (`fnAdopt…`), and *both* doors call super and then it. This is the single most common shape in the tail.
- **A subclass's own designated door must chain to the SUPER's designated door**, not `[super init]` — and if the
  superclass's designated door is meaningless for the subclass, call it anyway with the least state it accepts, and say
  why. That is `NSDataDetector`'s empty pattern.
- **A subclass that declares a designated door owes an OVERRIDE of the super's designated doors** — clang warns at the
  `@implementation` ("method override for the designated initializer of the superclass … not found"). If the inherited
  door makes no sense, the override is a refusal with an error naming the door to use, under a local pragma.
- **A header may declare a door twice under two spellings.** Deleting the "wrong" one's implementation is not a
  cleanup; it is a `selphantom`. Check the header before deleting an undeclared-looking method.
- **A re-routing cluster front can satisfy the checker** by delegating to its designated `-init` first and then
  releasing the front and answering the concrete class. `NSString` does this; `NSNumber` still cannot, because its
  designated `-init` would re-enter the re-router.
- **The local pragma is for refusals only** (a raise-only or nil-only door with no initializer to chain to). It is not
  for a door that could route and merely finds it inconvenient.

---

## 4. The one surface addition

`NSAppleEventDescriptor.h` now declares `- (instancetype)init NS_DESIGNATED_INITIALIZER;`. Apple inherits `-init` and
does not mark it, but Apple's marked door (`-initWithAEDescNoCopy:`) can only answer nil in this tree, so `-init` is
what actually defines the class's state. The mark does **not** move `designated-extra` (that counts a tree-local mark
only when the selector is class-owned in the manifest, and `-init` is inherited), but the declaration is new, which is
why `methods-declared` moved 4,045 → 4,046 in both census pins. If the manifest is ever regenerated, this line is the
one to expect as an addition.

---

## 5. What remains

1. **Nothing in this pass.** Every mark Apple states for a declaration this tree makes is placed, except the 18 of the
   refused cluster. `api-ledger annotate` will keep offering those sixteen plus two; that is the decision showing up as
   a work list, and §4.15 of the plan is the reason.
2. **The W1 residue** the plan lists: `AGORA_EXTENSION` for post-10.11 classes, and the **411
   `-Wnullability-completeness` warnings across 194 of the 197 headers**. That sweep is mechanical and now has a
   precedent for how to do it: measure with everything applied, batch by family, pin the movement, and treat a
   knock-on (a subclass obliged by a superclass's annotation, a funnel that has to move) as part of the batch.

---

## 6. Reproducing every number

```sh
cd libagora-base

# the availability/designated position (the pinned numbers in §1)
python3 ../libagora-app/tools/api-ledger availability api/10.11/foundation-manifest.txt . \
        --pin tests/api-10.11-annotations.txt

# the work list: 18 declarations, all of them the refusal
python3 ../libagora-app/tools/api-ledger annotate api/10.11/foundation-manifest.txt .

# the true remaining diagnostic count: place the NON-number marks, build, count, revert
python3 ../libagora-app/tools/api-ledger annotate api/10.11/foundation-manifest.txt . --apply
git checkout -- NSNumber.h NSDecimalNumber.h
cd build && make Foundation 2>&1 | grep -c objc-designated-initializers ; cd ..
git checkout -- .
# reads 0: batches 5b-9 are committed, so this now measures "no diagnostics from the body" rather than a residue.

# the marker for the batch 9 knock-on, if it ever regresses
cd build && make Foundation 2>&1 | grep 'objc-designated-initializers' ; cd ..

# the suites
cd build && ctest
```

Runtime probes used this session (each compiled against `libagora-base/build` + `build-prefix`, sources under `/tmp`):
socket port local/remote connect, ephemeral pick, alias spelling and descriptor ownership; bundle bare/main, index
doors, file streams written then read back, descriptor `-init`/typed doors; data detector build/match and the
`initWithPattern:` refusal.

---

## 7. Working-tree caveats

- **A concurrent editor is active** in this workspace. At the start of this session the workspace had `LICENSE-CHANGE.md`,
  `README.md`, `THIRD-PARTY.md`, `audit/`, `demo/` modified and `CONTRIBUTOR-ASSIGNMENT.md`, `PREVIEW-PLAN.md` untracked;
  those are not this session's. The `libagora-base` submodule was clean at `a26683b` and every batch commit touches only
  its own files. Check `git submodule status` before trusting a pointer.
- **`touch` creates files.** A measurement loop that touches `$F.m` for every changed `$F.h` created an empty `NSTimer.m`
  (this tree has no `NSTimer.m`). It was removed before batch 9's commit; watch for it if a similar loop runs again.
- `build/` is gitignored; no build artefact is committed.

---

## 8. Order I would take next

1. **The nullability sweep** (411 warnings, 194 headers): measure with the annotations applied, then batch by family
   (the collections, the strings/URLs, the formatters, the scripting families) exactly as this pass was batched. Expect
   knock-ons of the same shape as `NSDataDetector`'s: a subclass whose override is obliged by its superclass's
   annotation.
2. **`AGORA_EXTENSION` for post-10.11 classes** (§4.13) — small, and it closes the annotations story.
3. **Do not re-open the number cluster** unless the tree ever replaces the re-routing design; the decision is recorded,
   and the 18 "missing" facts it contributes are the record of it.
