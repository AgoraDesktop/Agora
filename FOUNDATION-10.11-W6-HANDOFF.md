# W6 — the tail — COMPLETE (86 selectors → 0; W7 is next)

*The wave that started as "W6a landed, the 86-selector tail remains" is finished. This file was the tail's work order;
it is now the record of how the tail was closed and what a reader should check before starting W7.*

## 1. Where the tree is

**45 suites green; every API gate green.**

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | **219 of 219 classes**, **3,744 of 3,744 selectors (0 missing)**, **40 of 40 protocols**, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` **4,376**, not-implemented 0 |
| `foundation-api-availability` | annotations **917/917**, 0 wrong · designated 140 of 158 present, 18 missing (the number cluster), extra 2 |
| `foundation-refusal-census` | **54** `FOUNDATION-REFUSE` sites over eight files, both directions |

`api-ledger missing` against the built library now prints `selectors 3744 of 3744 missing 0`; `api-ledger check`
holds all 629 pinned metrics.

## 2. What landed, batch by batch

Each batch was a commit in `libagora-base`, each with its own caller and its own census edit.

| Batch | Doors | Census | Caller |
|---|---|---|---|
| **W6a** | `NSProxy`'s two `NS_UNAVAILABLE` doors, with refusing bodies | methods-declared +2; refusals 48 → 50 | `forwarding` |
| **W6b** | `NSAppleEventDescriptor` 12: the type factories/accessors and a send that refuses | missing 86 → 74; annotations +12 | `scripting_surface` |
| **W6c** | `NSOrderedSet` 7 + `NSMutableOrderedSet` 1: predicate and options enumeration, locale descriptions | missing 74 → 66 | `foundation_10_11_ordered_set` |
| **W6d** | `NSMetadataQuery` 6, `NSMetadataItem` 1, `NSFileVersion` 6, `NSFileCoordinator` 1 | missing 66 → 52; designated +1 | `foundation_10_11_metadata_version` |
| **W6e** | `NSOperation` 5, `NSOperationQueue` 4, `NSProgress` 5, `NSJSONSerialization` 2 | missing 52 → 36; refusals 51 → 52 | `foundation_10_11_operation_progress` |
| **W6f** | `NSLinguisticTagger` 4, `NSRegularExpression` 3, `NSPointerArray` 4, `NSUserActivity` 3, `NSDateComponents` 2, `NSProcessInfo` 1, `NSNetService`/`NSNetServiceBrowser` 2+2, `NSXMLParser` 4 | missing 36 → 11 | `foundation_10_11_tail` |
| **W6g** | the eleven `NSCoding` conformances | missing 11 → **0**; refusals 52 → 54; designated +10 | `foundation_10_11_scripting_archive` |

## 3. The decisions a later reader will want, because they are choices

- **A refusal is a body, and it is counted.** Three doors in this wave refuse by name rather than pretend:
  `-sendEventWithOptions:timeout:error:` (no AppleEvents transport), `-[NSProgress publish]` without
  `NSProgressFileURLKey` (nothing to publish under), and `NSDistantObject`'s two coder doors (a connection cannot be
  rebuilt from an archive). Each has its own census line, and the census is checked in both directions.
- **Stored-and-reported is stated at the door.** `NSMetadataQuery.operationQueue`, `NSOperation`/`NSOperationQueue`
  `qualityOfService`, `NSXMLParser`'s external-entity policy and allowed list, and `NSNetService.includesPeerToPeer`
  are state this system records; each declaration says so rather than implying a service behind it.
  `NSOperationQueue.underlyingQueue` is the exception and is REAL: an operation runs as a dispatch block on the queue
  the caller named.
- **`NSProgress` publishing is IN-PROCESS.** The handler is called, it returns an unpublishing block, `-unpublish`
  runs it — within this process, because there is no cross-process progress service. The header states the boundary.
- **`NSFileVersion -replaceItemAtURL:options:error:` is a real replacement**, because this version's content IS the
  item at its own URL: the door writes those bytes over the target atomically, or moves the item when asked. It is
  driven through `NSFileCoordinator`'s intent door, which is why W4 landed `NSFileAccessIntent`.
- **Apple's getter spellings won where the two disagreed.** `NSUserActivity`, `NSDateComponents` and `NSProcessInfo`
  carried property-named accessors (`eligibleForHandoff`, `leapMonth`, `validDate`, `lowPowerModeEnabled`); the
  ledger asks for the selector Apple declares, which is `isEligibleForHandoff`, `isLeapMonth`, `isValidDate`,
  `isLowPowerModeEnabled`. Nothing else used the old names.
- **`NSDistantObject -classForCoder` answers the proxy's own class.** `NSProxy` is a root class and does not inherit
  NSObject's door, so without this the archiver would forward the question to the object in another process. With it,
  the archiver names the proxy and reaches the coder doors that refuse.
- **One pre-existing behaviour was found and NOT changed:** a specifier whose `childSpecifier` is evaluated twice
  recurses (`-objectsByEvaluatingSpecifier` installs the child's container link, then re-enters itself). The archive
  suite does not evaluate such a graph. Fixing it is an evaluation-semantics change and belongs with its own caller.

## 4. What W7 inherits

- `selectors-missing` is **0**; W7's own item is therefore not selector fill. See `FOUNDATION-10.11-PLAN.md` §W7:
  the 26 header names, the behavioural categories, the umbrella (`Foundation.h` re-admits the session family and the
  §63.159 comment is replaced), ARC/ObjC++ compile passes, and the Swift import probe.
- The 18 missing designated-initializer marks are the number cluster's, and a header pass is where they fit.
- M2 (behaviour) follows W7, using the callers this wave added as the pattern: `foundation_10_11_ordered_set`,
  `foundation_10_11_metadata_version`, `foundation_10_11_operation_progress`, `foundation_10_11_tail`,
  `foundation_10_11_scripting_archive`.
