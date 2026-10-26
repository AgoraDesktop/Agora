# W6 — the tail — handoff (W6a landed; the selector tail remains)

*State at the end of the session that landed W6's first item and stopped: the 86-selector tail needs its own session,
and this file is where it starts.*

## 1. Where the tree is

40 suites green; all API gates green.

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | **219 of 219 classes**, **3,658 of 3,744 selectors** (86 missing), **40 of 40 protocols**, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` **4,289**, not-implemented 0 |
| `foundation-api-availability` | annotations **860/860**, 0 wrong · designated 129/147 present, 18 missing (the number cluster), extra 2 |
| `foundation-refusal-census` | **50** `FOUNDATION-REFUSE` sites over six files, both directions |

## 2. What landed: W6a — `NSProxy`'s two `NS_UNAVAILABLE` doors

`-allowsWeakReference` and `-retainWeakReference` are declared with `NS_UNAVAILABLE` and each has a BODY that refuses by
name. A declaration with no body anywhere is what `methods-declared-not-implemented` is pinned at zero for, and a
caller reaching the door through the runtime gets a reason rather than a silent NO. The two sites join
`tests/refusal_census.txt` (48 → 50). The manifest lists them as `unavailable-selector`, so they were never in the
86-selector denominator: `methods-declared` 4,287 → 4,289, missing unchanged at 86.

## 3. The tail, in the order I would take it

All counts from `api-ledger missing` against the built library:

1. **`NSAppleEventDescriptor` (12)** — the largest single debt; the descriptor-type doors (enum/type/boolean/list/record
   accessors).
2. **`NSOrderedSet` (7) + `NSMutableOrderedSet` (2)** — predicate/enumeration fill; the wave's ordered-set test.
3. **`NSMetadataQuery` (6) + `NSFileVersion` (6)** — including the `NSFileVersion` replacement through
   `NSFileAccessIntent`, which is why the intent landed in W4.
4. **`NSProgress` (5) + `NSOperation` (5) + `NSOperationQueue` (4)** — including the JSON stream round-trip (JSON is
   `NSJSONSerialization`'s two doors).
5. **`NSXMLParser` (4) + the XML family's singles**, **`NSLinguisticTagger` (4)** against `FNTextBreaking`,
   **`NSRegularExpression` (3)** with the replacement test, **`NSPointerArray` (4)**, **`NSUserActivity` (3)**, and the
   scripting family's singles (the scripting archive round-trip).
6. **The eleven `NSCoding` conformances**, then re-run `api-ledger missing` to zero.

Every batch keeps `methods-declared-not-implemented` at 0 and the refusal census in step; a refusal is a body, and a
new one needs a census line. W7 (the umbrella, 26 header names, client gates) follows W6; **M2 (behaviour)** follows W7.
