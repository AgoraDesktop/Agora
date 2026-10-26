# W5 — refusals become measured — handoff

*State at the end of the session that declared the XPC and script-task families and closed the refusal census. Every
10.11 class and protocol now exists in the tree.*

## 1. Where the tree is

40 suites green; all API gates green.

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | **219 of 219 classes**, **3,658 of 3,744 selectors** (86 missing), **40 of 40 protocols**, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` **4,287**, not-implemented 0 |
| `foundation-api-availability` | annotations **860/860**, 0 wrong · designated 129/147 present, 18 missing (the number-cluster refusal), extra 2 |
| **`foundation-refusal-census`** (new) | **48** `FOUNDATION-REFUSE` sites over five files, both directions |

## 2. What landed (commit `8fd04ed`)

- **XPC**, all refused by name: `NSXPCConnection` (20 doors), `NSXPCInterface` (7), `NSXPCListener` (9),
  `NSXPCListenerEndpoint` (0), `NSXPCProxyCreating`, `NSXPCListenerDelegate`. Constructors answer nil; the doors that
  take a handler call it with `NSFeatureUnsupportedError`; every other door refuses so no object pretends to hold an
  interface or a proxy for a boundary this system does not have. `-initWithMachServiceName:` is marked designated, as
  the reference marks it.
- **Script tasks**: `NSUserScriptTask` (3), `NSUserAppleScriptTask` (1), `NSUserAutomatorTask` (3). The initializer
  answers nil with `NSUserScriptTaskErrorDomain`; each execute door answers its handler with the same named error
  (no OSA component, no Automator engine). `-initWithURL:error:` carries the reference's designated mark.
- **The refusal census**: `tests/refusal_census.txt` pins the 48 sites per file
  (NSURLSession 16, NSXPCConnection 24, NSUserScriptTask 4, NSExtension 3, NSUserNotification 1) with `# total: 48`;
  `foundation-refusal-census` runs libagora-app's `claims_census.cmake` **by path** (GPL tool, LGPL component — shared,
  not copied) with the needle `(FOUNDATION-REFUSE|fn_refuse_[a-z]+)`. Every door carries its own line so the census
  counts doors, not one helper. Adding or removing a refusal is now a deliberate diff.

## 3. What remains

**W6 — the selector tail**: 86 missing selectors on classes that already exist (the largest debts are
`NSAppleEventDescriptor` 12, `NSOrderedSet` 7, `NSMetadataQuery` 6, `NSFileVersion` 6, `NSProgress` 5, `NSOperation` 5,
`NSXMLParser` 4, `NSURLCredentialStorage` 4 — its task-scoped remainder, `NSPointerArray` 4, `NSOperationQueue` 4,
`NSLinguisticTagger` 4), plus the eleven `NSCoding` conformances and the two `NS_UNAVAILABLE` `NSProxy` doors (declared
with refusing bodies). **W7**: `Foundation.h` re-admits the session family, the 26 header names (11 new, 9 splits,
6 organisation), and the ARC/ObjC++/Swift client gates.

Then M2 — behaviour — per wave.
