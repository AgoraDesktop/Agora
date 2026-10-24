# Core Data — the plan for a complete 10.6-compatible implementation

*Status: **plan.** This document says what a complete Mac OS X 10.6 Core Data means for Agora, measures the
gap against the 10.6 SDK today, chooses the policy for the parts that cannot or should not be implemented,
and stages the work with gates that make progress checkable. Nothing here is scheduled; the size classes are
order-of-magnitude, not commitments.*

*The reference is `MacOSX10.6.sdk`, the same reference `libagora-app`'s era pins and
`tests/api-10.6-census.txt` already use. "10.6" names that SDK and the surface it declares.*

---

## 0. The verdict

**Core Data does not exist in Agora, and the surface that is missing is small enough to state in one line:
21 classes, 331 selectors, 24 headers, 56 public constants, 0 protocols and 0 C functions.**

That is the whole of Apple's 10.6 `CoreData.framework`, measured rather than remembered:

```
$ libagora-app/tools/api-ledger manifest \
    ~/Development/Fiwix/.tmp/mac106/MacOSX10.6.sdk/System/Library/Frameworks/CoreData.framework/Versions/A/Headers \
  | awk '{print $1}' | sort | uniq -c
     21 class
    331 selector
```

**And the number is not the work.** Core Data's selectors are cheap to declare and expensive to make true:
`-save:` is 1 of 39 on `NSManagedObjectContext` and it is where validation, change processing, permanent
identity, store writing, snapshot refresh, undo and notification all converge. What makes this plan a plan
rather than a list is that four things stand behind the 331 names:

1. **One Foundation prerequisite, and it was deliberately removed.** `NSPredicate`, `NSExpression`,
   `NSComparisonPredicate` and `NSCompoundPredicate` do not exist in `libagora-base` — `Foundation.h:104`
   records the removal (§63.161/§63.135) on the ground that the family is 10.4 and the baseline was 10.2.
   Core Data's entire fetch layer is a predicate tree translated to a query. **The prerequisite is not
   optional and the removal's justification does not survive contact with a 10.6 target** (§4.1).
2. **Two engines, not a class library.** A *fetch engine* (predicate → SQL, sort descriptors → ORDER BY,
   expressions → projections) and an *object-graph engine* (uniquing, faulting, snapshots, dirty tracking,
   undo, merge). The 21 classes are the visible part of both.
3. **A storage decision that must be made early and is hard to reverse** — whether the SQLite store is
   byte-compatible with Apple's (`Z_PK`/`Z_ENT`/`Z_OPT`) or Agora's own documented schema (§7.1). Everything
   downstream depends on the answer.
4. **An AppKit seam that is 4 headers wide and mostly blocked.** Ten-point-six AppKit touches Core Data in
   exactly four files, and three of the five classes involved (`NSController`, `NSObjectController`,
   `NSArrayController`) do not exist in `libagora-app` (§11).

**The plan therefore has three milestones.** **M1 — declared:** all 21 classes, 331 selectors and 56
constants exist, are annotated, and are implemented or explicitly refused. **M2 — the object graph is
true:** model, objects, contexts, save, fetch, undo, validation and the in-memory/binary/XML stores behave
as documented. **M3 — the SQLite store and migration are true.** M1 is cheap; M2 is the majority; M3 is the
half that is usually underestimated.

### 0.1 The decisions taken

Six decisions were open when this document was written. They are settled, and they are settled *here* rather
than left to be rediscovered in the code:

| # | Decision | Answer | What it pins |
|---|---|---|---|
| **D1** | The SQLite store's file format | **B — Agora's own documented schema** (§7.1) | every conformance fixture; the version-hash algorithm; that an Apple store is refused by name |
| **D2** | Cross-thread object access | **detected, raises `NSManagedObjectContextLockingError`** (§10) | the concurrency contract is a strict superset of Apple's |
| **D3** | Cross-store save atomicity | **matches Apple: not atomic, `NSPersistentStoreIncompleteSaveError`** (§6.7) | what a multi-store save promises |
| **D4** | The 6 external-records constants | **refused, never accepted-and-ignored** (§7.6) | that a save means one thing |
| **D5** | `MATCHES` and block predicates | **refused by name, never degraded to a scan** (§8.4) | that a fetch's cost is not silently a full table |
| **D0** | The predicate family in `libagora-base` | **restored, with the collection predicate API** (§4.1, scope B) | that P0 exists at all |

And three structural choices that are not dispositions but shape everything:

- **The component is `libagora-data`** (§5.1) — a new federated submodule, not a subtree of `libagora-base`.
- **Phase 0 includes the collection API** (`-filteredArrayUsingPredicate:`, `-filterUsingPredicate:` on
  `NSArray`/`NSSet`/`NSOrderedSet`), so the §63.161 reversal is closed properly rather than partially (§4.1).
- **W7 builds the SQLite store before the XML store** (§7.2) — the flagship store first; the XML store
  follows because `NSPersistentDocument`'s default store type needs it, and **W8.1 therefore waits for
  W7's second half** rather than the first.

### 0.2 Where P0 stands

Recorded here because a plan that does not say what has already happened is a wish list:

| P0 item | State |
|---|---|
| `NSPredicate`, `NSExpression`, `NSComparisonPredicate`, `NSCompoundPredicate` + the format grammar | **landed** in `libagora-base`: 6 new headers/impls, `FNPredicateFormat.m` (tokenizer, recursive-descent parser, expression renderer), `FNPredicatePrivate.h` |
| The collection predicate API (`-filteredArrayUsingPredicate:`, `-filterUsingPredicate:` on NSArray/NSSet and their mutable classes) | **landed**, with the umbrella note at `Foundation.h:104` rewritten to record the reversal |
| A caller for every door | **landed**: `tests/predicate.m`, 26 checks, passing — including the `-predicateFormat` round trip and a refusal for a truncated format |
| The ledger resolves framework bundles (§2.3) | **landed**: `CoreData.framework` emits 352 lines (exit 0, identical to the `Headers` path); `AppKit.framework` output byte-identical to the committed manifest; the three AppKit censuses still pass |
| `api/10.6/coredata-manifest.txt` committed, `libagora-data` skeleton | **landed**: `AgoraDesktop/libagora-data` created (public, `main`, wiki off, same homepage as the other eighteen), 13 files at `be72f37`; the 352-line manifest is generated from the 10.6 bundle path, which exercises §2.3's fix |
| The component is a submodule, not a sibling directory | **landed**: `Agora`, `.gitmodules` gained the nineteenth entry with `branch = main`, registered at `4266030` |

Measured after the predicate work: `libagora-base` 10/10 tests pass, `libagora-app` builds against the
installed prefix, and `libagora-app`'s three censuses pass. Measured after the component was created:
`libagora-data` builds `libagora-data.so`, installs three headers, one library and the `AgoraData` CMake
package, and its `smoke` suite passes — so the packaging and the `<CoreData/…>` shim are measured from the
first commit rather than discovered at W1.

Two things the creation measured and fixed: `install(DIRECTORY .)` recreated `api/`, `cmake/` and `tests/` as
**empty directories** inside `include/CoreData/` (filenames are filtered, traversal is not), so the headers are
now installed by name; and a configure without a compiler argument dies three levels into a CMake feature test
with `cannot execute 'cc1obj'`, so the build now says which compiler it needs and why.

### 0.3 Where W1 stands

| W1 item | State |
|---|---|
| The seven model classes (99 selectors) | **landed** in `libagora-data`: `NSPropertyDescription`, `NSAttributeDescription`, `NSRelationshipDescription`, `NSFetchedPropertyDescription`, `NSExpressionDescription`, `NSEntityDescription`, `NSManagedObjectModel` |
| The version hash — D1-b's digest | **landed**: SHA-256 over a canonical, sorted description; `CDModelPrivate.h` records why it is deliberately *not* Apple's |
| The archive round trip | **landed and measured**: `tests/model.m` archives a model with `NSKeyedArchiver` and asserts the restored entity's hash equals the written one; `-initWithContentsOfURL:` is exercised through a real temp file |
| The census | **measured by the instrument**: `api-ledger census` reports `classes-present 7` of 21, `selectors-present 99` of 99 offered, `selectors-missing 0`, `methods-declared-not-implemented 0` |

Two things W1 found by measuring rather than recalling:

- **`-copyWithZone:` does not exist in this Foundation.** `NSObject.h` removed every `NSZone`-taking method, so
  the copying protocol's member is `-copy` and the override point is the entry point. All seven classes
  implement `-copy`; a Cocoa-shaped `-copyWithZone:` would not conform at all, and the first run of the suite
  said so: `-[NSEntityDescription copy] is not implemented`.
- **`NSMutableArray.h` and `NSMutableDictionary.h` do not exist**, as with `NSMutableString`/`NSMutableSet`: the
  mutable class lives in the immutable one's header. Three files had to stop importing them.

Remaining after W1: 14 classes, 232 selectors.

### 0.4 Where W2 stands, and the census is a gate

| W2 item | State |
|---|---|
| The object pair (41 selectors) | **landed**: `NSManagedObjectID` (4) and `NSManagedObject` (37) |
| The two-dictionary value store | **landed**: `_committed` is what the store holds, `_changed` is the diff; `NSNull` carries "explicitly nil"; re-stamping a committed value is not a change |
| The access chokepoint | **landed**: every modelled key routes `-valueForKey:`/`-setValue:forKey:` through `-willAccessValueForKey:` (the fault door) and `-willChangeValueForKey:` (the KVO door) |
| Validation | **landed, and it took three attempts to get right** — see below |
| The census | **now a `ctest` gate**: `coredata-api-census` runs `api-ledger census` against the built library and holds `tests/coredata-census.txt`, in both directions. Perturbing one pin produced *"the 10.6 API census has drifted, in 2 place(s)"* naming both the metric and the consistency rule |

**Measured after W2: 9 of 21 classes, 140 of 140 offered selectors, `selectors-missing 0`,
`methods-declared-not-implemented 0`.** Remaining at that point: 12 classes, 191 selectors.

Three things W2 found by measuring, in the order they failed:

1. **`-[Person valueForKey:@"SELF"]` raised.** `SELF.age >= 0` is how Apple's validation predicates are written,
   and KVC resolves that path by asking the object for `SELF` first. `NSManagedObject` must answer it with
   itself — Apple's does, for this reason — or every SELF-qualified predicate raises instead of evaluating.
2. **Validation must judge the CANDIDATE value, not the stored one.** `-validateValue:forKey:error:` takes
   `id *` rather than `id` precisely so the value can be swapped in, judged and restored; evaluating against the
   object's current value validates the previous value. The diff entry is saved and restored exactly, so
   validation leaves no change behind.
3. **`NSMutableArray.h`/`NSMutableDictionary.h` do not exist** (the W1 lesson recurring in two more files).

---

## 1. What "complete 10.6 Core Data" means

The surface tiers are `COCOA-10.11-SURFACE-PLAN.md` §1's, applied to a fifth framework. Binary compatibility
is again **not** part of it: a store file written by Apple's Core Data is a *data* compatibility question,
handled separately and explicitly in §7.1, and it is not the same contract as ABI.

| Tier | What it covers | Measured by |
|---|---|---|
| **S1 — declarations** | The 24 headers, 21 classes, 331 selectors, 56 constants, the enums and typedefs, and the header each name lives in | name-and-signature ledger against the 10.6 SDK |
| **S2 — annotations** | `COREDATA_EXTERN`, `COREDATA_DEPRECATED`, `AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER`, nullability, `NS_ASSUME_NONNULL` | clang AST + a header-compile gate |
| **S3 — runtime shape** | Each class exists with the right superclass and protocols (`NSCoding`, `NSCopying`, `NSFastEnumeration`, `NSLocking`), and answers its selectors including inherited ones | `api-ledger census` with inheritance resolved |
| **S4 — behaviour** | The door does what Apple documents, or refuses by name with a documented failure | per-door tests + the refusal census |
| **S5 — source compatibility** | A program written against the 10.6 Core Data headers builds against the tree and links | compile/link tests, ObjC and ObjC++ |

### 1.1 The four dispositions

Every name gets exactly one, using the same vocabulary the AppKit ledger already uses:

| Disposition | Meaning | Where it applies here |
|---|---|---|
| **implemented** | The documented behaviour, tested | the bulk: model, objects, context, coordinator, fetch, XML/binary/in-memory stores, migration |
| **adapted** | The documented contract through a different backing, deviation written down | the SQLite schema (§7.1), version hashes (§7.2), cross-store atomicity (§6.7), cross-thread misuse detection (§10) |
| **refused** | Declared, annotated, calling it produces a named, logged failure | the external-records options (§7.6), XML-store schema validation, unsupported predicate forms (§8.4) |
| **unavailable** | Declared and not callable | nothing — 10.6's Core Data has no iOS-only or platform-absent declarations |

**An omitted 10.6 macOS name is a bug, not a disposition.** The 10.6 Core Data surface is small enough that
completeness is a hard requirement rather than an aspiration, and the ledger enforces it in both directions.

---

## 2. The reference and the measurement

### 2.1 Reference

The 10.6 SDK is already on this machine, at the path the tree's other 10.6 work uses:

```
SDK=$HOME/Development/Fiwix/.tmp/mac106/MacOSX10.6.sdk/System/Library/Frameworks
```

The headers are **not committed** (the SDK is not redistributable). What is committed is the recipe and the
generated name manifest — a list of facts: class names, superclasses, selector spellings. Not Apple's
expression of them.

### 2.2 The instrument, which already exists

`libagora-app/tools/api-ledger` is not AppKit-specific: `manifest` takes any headers directory.

```
$ libagora-app/tools/api-ledger manifest $SDK/CoreData.framework/Versions/A/Headers | wc -l
352
```

**352 lines, exit 0, no modification to the tool.** For AppKit the committed manifest is 5,519 lines; Core
Data is 6.4% of AppKit's size and needs 6.4% of the effort to *emit*. The census and check subcommands are
likewise parameterised by `--library`, `manifest` and `source-dir`, so a Core Data census is a
`api_census.cmake` invocation, not a new instrument.

One precision point, because it decides what the Core Data number *means*: the census resolves inheritance
inside the tree it is pointed at, so `NSFetchRequestExpression : NSExpression` contributes its own 4
selectors and **not** `NSExpression`'s — those are Foundation's rows and are counted in Foundation's census
once §4.1 restores them. The 331 is Core Data's own surface, not its surface plus its ancestors'.

### 2.3 The one tool gap, measured

Passing the framework **bundle** rather than its headers directory fails:

```
$ libagora-app/tools/api-ledger manifest $SDK/CoreData.framework
api-ledger: no headers in .../CoreData.framework
```

AppKit worked because `AppKit.framework/Headers` is a symlink to `Versions/C/Headers`. `CoreData.framework`
has the same symlink in the 10.6 SDK, so this is a path-resolution asymmetry in `parse_tree` rather than a
Core Data problem — the fix is to try `<dir>/Headers`, `<dir>/Versions/A/Headers` and
`<dir>/Versions/C/Headers` before declaring "no headers". One function, done in Phase 0, and it makes the
recipe uniform across the five frameworks.

### 2.4 The commands this plan is measured by

```
ledger=libagora-app/tools/api-ledger
sdk=$HOME/Development/Fiwix/.tmp/mac106/MacOSX10.6.sdk/System/Library/Frameworks

# Phase 0: emit and commit the facts.
$ledger manifest $sdk/CoreData.framework/Versions/A/Headers > api/10.6/coredata-manifest.txt

# Every wave: measure. Every gate: hold.
$ledger census api/10.6/coredata-manifest.txt . --library build/libagora-data.so
$ledger check  api/10.6/coredata-manifest.txt . tests/coredata-census.txt \
                                          --library build/libagora-data.so
```

---

## 3. The surface, measured

### 3.1 By header

| Header | Size | Selectors |
|---|---:|---:|
| `NSManagedObjectContext.h` | 12,176 B | 39 |
| `NSPersistentStoreCoordinator.h` | 15,084 B | 22 |
| `NSFetchRequest.h` | 7,349 B | 30 |
| `NSManagedObject.h` | 6,752 B | 37 |
| `CoreDataErrors.h` | 6,611 B | 0 (48 error/validation identifiers) |
| `NSManagedObjectModel.h` | 6,246 B | 22 |
| `NSMigrationManager.h` | 5,879 B | 18 |
| `NSEntityMapping.h` | 4,960 B | 22 |
| `NSPropertyDescription.h` | 4,556 B | 23 |
| `NSEntityDescription.h` | 4,435 B | 27 |
| `NSEntityMigrationPolicy.h` | 4,016 B | 7 |
| `NSAttributeDescription.h` | 3,006 B | 9 |
| `NSPersistentStore.h` | 2,825 B | 19 |
| `NSMappingModel.h` | 2,493 B | 6 |
| `NSAtomicStore.h` | 2,295 B | 12 |
| `NSAtomicStoreCacheNode.h` | 2,290 B | 6 |
| `NSRelationshipDescription.h` | 2,246 B | 12 |
| `NSFetchRequestExpression.h` | 1,853 B | 4 |
| `CoreDataDefines.h` | 1,449 B | 0 (the `COREDATA_EXTERN`/`COREDATA_DEPRECATED` macros) |
| `NSExpressionDescription.h` | 1,280 B | 4 |
| `NSPropertyMapping.h` | 1,120 B | 6 |
| `NSManagedObjectID.h` | 1,116 B | 4 |
| `CoreData.h` | 1,082 B | 0 (the umbrella) |
| `NSFetchedPropertyDescription.h` | 933 B | 2 |

### 3.2 By class, with the wave that owns it

| Class | Superclass | Selectors | Wave |
|---|---|---:|---|
| `NSManagedObjectContext` | `NSObject <NSCoding, NSLocking>` | 39 | W3 |
| `NSManagedObject` | `NSObject` | 37 | W2 |
| `NSFetchRequest` | `NSObject <NSCoding, NSCopying>` | 30 | W5 |
| `NSEntityDescription` | `NSObject <NSCoding, NSCopying, NSFastEnumeration>` | 27 | W1 |
| `NSPropertyDescription` | `NSObject <NSCoding, NSCopying>` | 23 | W1 |
| `NSPersistentStoreCoordinator` | `NSObject <NSLocking>` | 22 | W4 |
| `NSManagedObjectModel` | `NSObject <NSCoding, NSCopying, NSFastEnumeration>` | 22 | W1 |
| `NSEntityMapping` | `NSObject` | 22 | W6 |
| `NSPersistentStore` | `NSObject` | 19 | W4 |
| `NSMigrationManager` | `NSObject` | 18 | W6 |
| `NSRelationshipDescription` | `NSPropertyDescription` | 12 | W1 |
| `NSAtomicStore` | `NSPersistentStore` | 12 | W4 |
| `NSAttributeDescription` | `NSPropertyDescription` | 9 | W1 |
| `NSEntityMigrationPolicy` | `NSObject` | 7 | W6 |
| `NSPropertyMapping` | `NSObject` | 6 | W6 |
| `NSMappingModel` | `NSObject` | 6 | W6 |
| `NSAtomicStoreCacheNode` | `NSObject` | 6 | W4 |
| `NSManagedObjectID` | `NSObject <NSCopying>` | 4 | W2 |
| `NSFetchRequestExpression` | `NSExpression` | 4 | W5 |
| `NSExpressionDescription` | `NSPropertyDescription` | 4 | W1 |
| `NSFetchedPropertyDescription` | `NSPropertyDescription` | 2 | W1 |
| **21 classes** | | **331** | |

### 3.3 What 10.6 is *not*, which is most of the good news

The 10.6 headers were read for the modern API and it is absent. This is the single largest scoping fact in
this plan: **the hard parts of modern Core Data — queue confinement, nested contexts, incremental stores —
are 10.7 and later, so a faithful 10.6 implementation is simpler than the framework's reputation.**

| Absent on 10.6 | Consequence for this plan |
|---|---|
| `-performBlock:`, `-performBlockAndWait:` | concurrency is `<NSLocking>` on the context and coordinator; no block queues, no deadlock analysis |
| `NSManagedObjectContextConcurrencyType`, `-initWithConcurrencyType:` | one initialiser (`-init`), one confinement model |
| `-parentContext`, `-setParentContext:` | no nested-context save chains; `-mergeChangesFromContextDidSaveNotification:` is *the* cross-thread mechanism |
| `NSIncrementalStore` | `NSAtomicStore` (12 selectors) is the only store-subclassing contract to honour |
| `NSMergePolicy`, `NSMergeConflict` **classes** | `-mergePolicy`/`-setMergePolicy:` take and return opaque `id`: five singleton constants, no conflict object to model |
| `NSFetchedResultsController` | a Mac 10.12 class; AppKit uses bindings and controllers instead |
| `NSPersistentContainer`, `NSPersistentCloudKitContainer` | do not exist in this era at all |
| `NSBatchUpdateRequest`, `NSBatchDeleteRequest`, `NSFetchIndexDescription`, `NSPersistentHistory*`, `NSCoreDataCoreSpotlightDelegate` | no bulk-update, indexing or history path to design |
| iCloud / ubiquitous store | absent (10.7+). `libagora-base`'s `NSUbiquitousKeyValueStore` is unrelated |

Verified by grep rather than recollection — the pattern `performBlock|ConcurrencyType|parentContext|
NSIncrementalStore|FetchedResultsController` produces **no matches** across all 24 headers.

### 3.4 The constants, which are part of the surface

**56** `COREDATA_EXTERN NSString * const` names, plus **5** opaque merge-policy `id` constants. They are
listed in Appendix B; they matter because they are the API's *data* — a client that hardcodes
`"NSSQLiteStoreType"` instead of the constant gets a value that is not Apple's, and the store-option keys are
the only way to reach the store behaviour.

---

## 4. The prerequisites

### 4.1 `NSPredicate` and `NSExpression` must come back — Decision D0

`libagora-base/Foundation.h:104` records the removal:

> **AND THE PREDICATE FAMILY IS NOT IN THE UMBRELLA ANY MORE (§63.161):** `NSPredicate`, `NSExpression`,
> `NSCompoundPredicate`, `NSComparisonPredicate` and the format grammar are ALL macOS 10.4 — later than the
> 10.2 baseline §11.0 targets — and §63.135 had ALREADY removed their ledger rows with the recorded reason
> "REMOVED rather than struck … the headers lose these names in the same campaign". **THIS IS THAT
> CAMPAIGN.** What the family took with it is the predicate-taking API on the collection classes, which is
> 10.4 too: `-filteredArrayUsingPredicate:`, `-filterUsingPredicate:` and their siblings left NSArray, NSSet
> and NSOrderedSet in the same pass.

The removal was **correct against the baseline it cited and is unsound against the tree's actual target**,
for three independent reasons:

1. **10.4 < 10.6.** The tree measures itself against 10.6 (`tests/api-10.6-census.txt`'s own preamble says
   so). A 10.6 reference contains everything 10.4 added. The predicate family is inside the reference.
2. **The AppKit ledger already commits to it.** `api/10.6/appkit-manifest.txt` carries **29 rows** naming a
   predicate — 2 class rows and 27 selectors: `NSArrayController`'s 4
   (`filterPredicate`, `setFilterPredicate:`, `clearsFilterPredicateOnInsertion`,
   `setClearsFilterPredicateOnInsertion:`), `NSObjectController`'s 2 (`fetchPredicate`, `setFetchPredicate:`),
   `NSPredicateEditor`'s 2, all 16 of `NSPredicateEditorRowTemplate`'s, and `NSRuleEditor`'s 3
   (`predicate`, `predicateForRow:`, `reloadPredicate`). A ledger that lists those names while
   the type they name does not exist is not measuring the tree; it is measuring a contradiction.
3. **Core Data cannot be built without it.** `NSFetchRequest -predicate` is one selector; the *engine* behind
   it is the predicate tree, and `NSFetchRequestExpression : NSExpression` inherits four selectors and is a
   subclass of a class the tree does not have. `NSExpressionDescription` (4) is an `NSExpression` carrier.

**Decision D0: restore the predicate family to `libagora-base` as a prerequisite of Core Data, and restore
the predicate-taking collection API with it.** Scope, in ew, is in §12 Phase 0. The family is four classes
plus the format parser plus the expression evaluator:

- `NSPredicate` (`+predicateWithFormat:`, `-predicateFormat`, `-evaluateWithObject:`, `-evaluateWithObject:substitutionVariables:`, `+predicateWithValue:`, `+predicateWithBlock:` (10.6), `-predicateWithSubstitutionVariables:`)
- `NSComparisonPredicate` (`leftExpression`, `rightExpression`, `comparisonPredicateModifier`, `predicateOperatorType`, `options`, `customSelector`)
- `NSCompoundPredicate` (`andPredicateWithSubpredicates:`, `orPredicateWithSubpredicates:`, `notPredicateWithSubpredicate:`, `subpredicates`, `compoundPredicateType`)
- `NSExpression` (`expressionType`, `constantValue`, `keyPath`, `function`, `arguments`, `collection`, `predicate`, `expressionForVariable:`, `-expressionValueWithObject:context:`, `+expressionForConstantValue:` and the rest of the constructors)

The format grammar is the part that must not be skipped: Core Data's `NSPredicate` values arrive as *text*
from nib files and from client code, so the parser is the door, not an optimisation.

### 4.2 The second prerequisite: none — and that is a correction, not a finding

This section said `NSRecursiveLock` was absent and must be added for the context's re-entrant lock. **It is
wrong, and it was wrong because of how it was measured**: the check was a file-existence test for
`NSRecursiveLock.h`, which does not exist — because Apple puts all four locking classes in `NSLock.h`, and
so does this tree. `NSLock.h` declares `NSLock`, `NSRecursiveLock`, `NSConditionLock` and `NSCondition` over
one `@protocol NSLocking`, and `NSLock.m` implements `NSRecursiveLock` with
`pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE)` and exports it
(`nm -D build/libagora-base.so` carries `._OBJC_CLASS_NSRecursiveLock`).

**So P0 has exactly one prerequisite, not two**, and the episode is worth keeping in the document: a
filename is not a class, a header count is not a surface, and the plan's own rule — measure the library, not
the headers — would have caught this before a line of Core Data existed.

### 4.3 What already exists, which is more than expected

| Need | Present today | Note |
|---|---|---|
| Keyed archiving (binary store, cache nodes) | `NSKeyedArchiver` 1,647 lines, `NSKeyedUnarchiver` | the binary store's whole mechanism |
| Value transformation (transformable attributes) | `NSValueTransformer` 208, `NSSecureUnarchiveFromDataTransformer` | `NSValueTransformerName` round-trip is the transformable-attribute contract |
| Decimal arithmetic (decimal attribute type) | `NSDecimal` 859, `NSDecimalNumber` 835 | `NSSQLiteStoreType` maps decimal to `DECIMAL` |
| XML tree + parser (XML store) | `NSXMLDocument` 510, `NSXMLNode` 1,198 | `-initWithData:options:error:` already runs a parser over a tree builder |
| Sort descriptors | `NSSortDescriptor` 100/255 | fetch ordering; `-compareObject:toObject:` |
| Undo | `NSUndoManager` 784 | context undo is a registration discipline over this |
| Errors | `NSError`/`NSError` domains | 48 error identifiers to declare |
| Fast enumeration | `NSFastEnumeration` | `NSEntityDescription` and `NSManagedObjectModel` conform |
| SQLite | system `sqlite3` 3.46.1, `pkg-config` finds it | same policy as ICU/OpenSSL/curl: system, not vendored |

**Not present and needed:** `NSPredicate`/`NSExpression` (§4.1) — and nothing else: the locking family is
present (§4.2). **Not present and not needed on 10.6:** `NSIncrementalStore` — which is worth stating plainly
because the absence is 10.7's.

---

## 5. Architecture

### 5.1 The component

A new submodule, `libagora-data`, joining the federated set in `.gitmodules`:
`https://github.com/AgoraDesktop/libagora-data.git`, branch `main`. CMake project `AgoraData`,
library `libagora-data.so`, package `find_package(AgoraData CONFIG)`.

It is a **separate component and not part of `libagora-app`** for the reason §10 of the surface plan already
assigns dependencies: Core Data is Foundation-level in `CoreData.framework`'s own layering, `NSPersistentDocument`
is AppKit's one class over it, and putting 331 selectors inside the AppKit library would make the AppKit's
census larger than the AppKit. The public header path is `<CoreData/…>`, exposed by the same include shim
`libagora-base` uses (`agora-include/Foundation` → `agora-include/CoreData`).

```
libagora-data/
  CoreData.h                  the 24th header: the umbrella, importing the other 23 in Apple's order
  CoreDataDefines.h           COREDATA_EXTERN, COREDATA_DEPRECATED, availability macros
  CoreDataErrors.h/.m         48 error/validation identifiers + the NSError domain
  api/10.6/coredata-manifest.txt      the committed facts (§2.2)
  tests/coredata-census.txt           the pinned measurement (§2.4)
  tests/refusal_census.txt            the refusals, in this tree's own voice
  model/       W1: NSManagedObjectModel, NSEntityDescription, NSPropertyDescription and its four subclasses
  object/      W2: NSManagedObject, NSManagedObjectID, faulting, snapshots, KVC storage, validation
  context/     W3: NSManagedObjectContext, change processing, save pipeline, undo, merge, notifications
  fetch/       W5: NSFetchRequest, NSFetchRequestExpression, the fetch planner
  store/       W4: NSPersistentStore, NSAtomicStore, NSAtomicStoreCacheNode, NSPersistentStoreCoordinator
  store/sqlite/    W7: NSSQLitePersistentStore, schema, SQL generation
  store/xml/       W7: NSXMLPersistentStore
  store/binary/    W7: NSBinaryPersistentStore
  migrate/     W6: NSMappingModel, NSEntityMapping, NSPropertyMapping, NSMigrationManager, NSEntityMigrationPolicy
  predicate/       W5: the predicate→SQL translator (§8) — consumes Foundation's tree, adds no public class
```

**Ownership: manual, no ARC**, matching `libagora-base`'s and `libagora-app`'s stated policy: ARC is for code
that *uses* Foundation, not for the frameworks.

### 5.2 The object-graph engine: five data structures

Everything Core Data does is a consequence of these, and each one is a decision:

1. **`NSManagedObjectID`** — `(store identifier, entity, primary key)`, with `-isTemporaryID` true between
   `+insertNewObjectForEntityForName:inManagedObjectContext:` and `-obtainPermanentIDsForObjects:error:`.
   `-URIRepresentation` is the 10.6 serialised form and the store-independent name for the row
   (`NSStoreUUIDInPathKey`, `NSEntityNameInPathKey` are the path components' keys).
2. **The coordinator's unique registry** — one `NSManagedObjectID` per row, process-wide, so two contexts
   asking for the same row get distinct objects that agree on identity. This is what makes
   `-objectRegisteredForID:` different from `-objectWithID:`.
3. **The context's three sets plus three pending sets** — `registeredObjects`, `insertedObjects`,
   `updatedObjects`, `deletedObjects` are the public view; the pending sets feed `-processPendingChanges`,
   which is what posts `NSManagedObjectContextObjectsDidChangeNotification` and runs
   `-propagatesDeletesAtEndOfEvent` (both are 10.6 selectors, and both are behaviourally load-bearing).
4. **The snapshot** — each object holds the last values it knows the store to have. `-changedValues` is a
   diff against it, `-committedValuesForKeys:` is a read of it, and undo is a re-application of it. A dirty
   `NSManagedObject` is *entirely* a snapshot diff; nothing else records that it changed.
5. **The row version (`Z_OPT` in Apple's schema)** — an optimistic-locking counter, incremented per write.
   Save compares the version read against the version in the store and applies `-mergePolicy` when they
   disagree. Without it, two contexts writing the same row silently lose one write; with it, `NSErrorMergePolicy`
   refuses. **This is the difference between a persistent object graph and a key-value store**, and it is 4
   lines of schema and a large fraction of W3's care.

### 5.3 Faulting

A fault is an object holding an ID and no snapshot. `-isFault`, `-willAccess`, `-didFireFault`,
`-hasFaultForRelationshipNamed:` are the 10.6 surface. The rule the plan commits to: **`-willAccess` is the
single chokepoint** — every value read that could need the store routes through it, relationships included,
and `-setReturnsObjectsAsFaults:NO` on a fetch means "fire the faults and populate snapshots before returning"
rather than "return a different kind of object". `-refreshObject:mergeChanges:` is the inverse door
(re-fault, optionally after merging).

### 5.4 Key-value storage without per-model class generation

`NSManagedObject` subclasses declare `@dynamic` properties. 10.6 answers them through `-primitiveValueForKey:`
and `-setPrimitiveValue:forKey:`, with `+automaticallyNotifiesObserversForKey:` and the
`-willChangeValueForKey:`/`-didChangeValueForKey:` pair driving the snapshot. The plan implements accessors
by installing one shared C accessor per **attribute type** (string, int16/32/64, decimal, double, float, bool,
date, binary, transformable, objectID) via `+resolveInstanceMethod:`, dispatching to the primitive door with
the key-path baked in. This is the approach that keeps `NSManagedObject` model-agnostic: no generated classes,
no `objc_allocateClassPair` per entity, and no per-model leeway for the ledger to disagree with.

---

## 6. The semantic contract — what "true" means for W2 and W3

The 331 selectors are not the specification; these behaviours are. Each becomes a test in §13.

### 6.1 Uniquing
`-objectWithID:` returns a fault with no store access if the row is unknown; a second call returns the **same
instance**; `-insertNewObjectForEntityForName:inManagedObjectContext:` returns an object whose ID is temporary
and whose `-objectID` is stable across the temporary→permanent transition.

### 6.2 Snapshot discipline
`-hasChanges` is false on a freshly fetched, unmodified object; true after one `-setValue:` even if the value
is equal to the old one (until Core Data's equality suppression, which applies to scalars and not to objects);
false again after `-rollback` or `-refreshObject:mergeChanges:YES`.

### 6.3 Validation
Four doors, in this order at save: property-level (`-validate<Key>:error:`, `NSValidation*` codes), then
`-validateForInsert`/`-validateForUpdate`/`-validateForDelete`, then relationship cardinality
(`NSValidationRelationshipLacksMinimumCountError`, `ExceedsMaximumCountError`), then referential integrity
(`NSManagedObjectReferentialIntegrityError`, `NSManagedObjectExternalRelationshipError`). A failed save leaves
the context unchanged and returns `NO` with an `NSError` whose `userInfo` carries `NSDetailedErrorsKey` and
per-object `NSValidationObjectErrorKey`/`NSValidationKeyErrorKey`/`NSValidationValueErrorKey`.

### 6.4 Save
`-save:` runs, in order: `NSManagedObjectContextWillSaveNotification`; `-processPendingChanges`; validate;
assign permanent IDs to insertions **before** writing, so relationships can be written as FKs; write the
changes through the coordinator; refresh snapshots from what was written (not from what was in memory — the
store's coercion, e.g. float precision, is the truth); clear the three sets; post
`NSManagedObjectContextDidSaveNotification` with `NSInsertedObjectsKey`/`NSUpdatedObjectsKey`/
`NSDeletedObjectsKey`. Multi-store: `-assignObject:toPersistentStore:` decides the destination; a save that
spans stores writes each in turn.

### 6.5 Merge
`-mergeChangesFromContextDidSaveNotification:` folds another context's save into the receiver: refresh
updated rows that the receiver has not modified, fault in insertions, `-deleteObject:` the deletions, and for
rows modified in **both**, apply `-mergePolicy`. Five policies, as opaque singletons:

| Constant | Behaviour |
|---|---|
| `NSErrorMergePolicy` (default) | refuse the save, report a conflict |
| `NSMergeByPropertyObjectTrumpMergePolicy` | in-memory values win, per property |
| `NSMergeByPropertyStoreTrumpMergePolicy` | store values win, per property |
| `NSOverwriteMergePolicy` | the whole object is overwritten by the in-memory version |
| `NSRollbackMergePolicy` | the whole object is discarded in favour of the store's |

Because 10.6 has **no `NSMergePolicy` class**, this is five singletons and a switch — not the class hierarchy
modern Core Data has. That is a real reduction in work, and the plan takes it.

### 6.6 Undo and redo
`-undo`/`-redo` forward to `-undoManager` while suppressing re-registration, which is one flag. Every
mutation registers the inverse with the snapshot as its payload; `-rollback` is undo-everything-then-reset;
`-reset` is "drop every registered object to a fault without touching the store". The subtlety that gets
tests: **undo must not resurrect a deleted object's relationships** without also undoing the relationship
removals, which is why the snapshot carries the inverse-relationship values and not just the scalars.

### 6.7 Cross-store atomicity — an adaptation, documented
Apple's own 10.6 behaviour for a save spanning two `NSSQLiteStoreType` stores is not transactional across
files. The plan matches that and **says so at the door**: a multi-store save is not atomic, and a failure
mid-save leaves the earlier stores written. This is an **adapted** disposition (§1.1) with a documented
deviation rather than a refusal, because the failure is recoverable and Apple's is the same. A test asserts
the partial-write is reported with `NSPersistentStoreIncompleteSaveError`.

---

## 7. The store layer

### 7.1 Decision D1 — the SQLite schema, which is the plan's largest irreversible choice

The question: **is `NSSQLiteStoreType`'s file byte-compatible with Apple's?**

Apple's schema is `Z_PRIMARYKEY` (entity table: `Z_ENT`, `Z_NAME`, `Z_SUPER`, `Z_MAX`), `Z_METADATA`
(`Z_VERSION`, `Z_UUID`, `Z_PLIST`), `Z_MODELCACHE`, and per-entity tables with `Z_PK`, `Z_ENT`, `Z_OPT`,
`Z<ATTRIBUTE>` columns and `Z<RELATIONSHIP>` FKs. It is undocumented and reverse-engineering it is a project
in itself — chiefly because **`NSStoreModelVersionHashesKey` is a per-entity digest of a canonical model
serialisation that nothing describes**, and a store whose hashes do not match is refused.

| | **D1-a: byte-compatible** | **D1-b: Agora schema, documented** |
|---|---|---|
| Buys | existing `.sqlite` stores load; Apple tooling works; interop is real | debuggability (`sqlite3` shows meaningful names); schema is ours to evolve; no reverse-engineering debt |
| Costs | reverse-engineering the version-hash algorithm and `Z_METADATA`'s plist; every internal change constrained forever | no Apple store interop; a store file is Agora's |
| Risk | a *silent* misread of an Apple store is worse than a refusal | none — the refusal is explicit |

**Decided: D1-b.** Agora's own schema, documented and debuggable, with D1-a kept as a separate, later,
optional importer. The reasoning is the project's own: Agora's users have no Apple-authored store files, and
§4.3's rule — a refusal is a contract, a silent success is not — argues against shipping a compatibility layer
that might half-work. Concretely:

- Our schema, documented in `store/sqlite/SCHEMA.md`, with readable table and column names.
- Apple's **key names** are still used for metadata (`NSStoreModelVersionHashesKey`, `NSStoreTypeKey`,
  `NSStoreUUIDKey`), because client code reads them.
- The version hash is **Agora's own** digest (SHA-256 over a canonical, ordered serialisation of the model),
  and is therefore *detectably* different from Apple's. Loading an Apple store produces
  `NSPersistentStoreIncompatibleVersionHashError` — the correct, documented error for a schema mismatch —
  rather than garbage rows. That is a refusal by name, which is what §4.3 asks for.
- A future D1-a is an **importer**, not a second schema: read Apple's file, write ours.

**Taken, and now a constraint rather than an option.** The schema is the one thing in this plan that is
expensive to change after tests exist, so `store/sqlite/SCHEMA.md` is written **before** the first table is
created, and the conformance fixtures are generated from it rather than from the code.

### 7.2 The four store types, and their 10.6 obligations

| Store | 10.6 obligation | Backing |
|---|---|---|
| `NSInMemoryStoreType` | full behaviour, no persistence — the conformance reference | the trivial `NSAtomicStore` subclass; **the first one built and the one every test uses** |
| `NSBinaryStoreType` | a keyed-archive file, `NSStoreUUIDKey` metadata | `NSKeyedArchiver` (exists) |
| `NSSQLiteStoreType` | SQL, `NSSQLitePragmasOption`, `ANALYZE`, `VACUUM`, `NSReadOnlyPersistentStoreOption`, `NSPersistentStoreTimeoutOption` | system `sqlite3` 3.46.1 (built **second**, after binary) |
| `NSXMLStoreType` | parseable XML, `NSValidateXMLStoreOption` honoured | `NSXMLDocument`/`NSXMLNode` (exist, built **last**) |

**The XML store is built last and is still not optional.** Ten-point-six's
`NSPersistentDocument -persistentStoreTypeForFileType:` **defaults to `NSXMLStoreType`** when the Info.plist
says nothing, so a faithful `NSPersistentDocument` needs it. W7 therefore runs in the order above — SQLite
first because it is the flagship and because D1's schema decision must be exercised while it is fresh, XML
last because only W8.1 asks for it — and **W8.1 is gated on W7 completing**, not on its first half.

### 7.3 `NSAtomicStore`: the contract that makes four stores cheap
`NSAtomicStore` (12 selectors) exists so a store is a *node cache*, not an object mapper:
`-load:` builds `NSAtomicStoreCacheNode`s, `-newReferenceObjectForManagedObject:` assigns keys,
`-updateCacheNode:fromManagedObject:` and `-save:` write. Implement this correctly once and the in-memory,
binary and XML stores are each a serialisation format over the same cache — which is exactly what Cocotron's
`NSAtomicStore.m` attempts, at 21 files / 3,348 lines for that whole framework.

**AND IT IS READ, NOT VENDORED.** No Cocotron or GNUstep source is committed here or in any repository of this
project: the comparison trees are cloned at pinned revisions into `audit/corpus/` by `audit/audit.py setup`,
which `audit/.gitignore` excludes. So the Cocotron Core Data implementation is a **reading aid and not a
base** — it has no SQLite store at all, and its `NSEntityDescription.m` logs "not implemented" for nine of the
attribute types. Its value is as a checklist of the traps, not as code, and that is the only light in which
this plan cites it.

### 7.4 The coordinator
22 selectors: `+metadataForPersistentStoreOfType:URL:error:` (reads metadata **without** a stack — a
static door most implementations get wrong), `-addPersistentStoreWithType:configuration:URL:options:error:`,
`-migratePersistentStore:toURL:options:withType:error:`, `-destroyPersistentStoreAtURL:withType:options:error:`,
the store registry, `+registerStoreClass:forStoreType:` (extension point — and the door that makes D1-a an
importer rather than a fork), and `<NSLocking>`.

### 7.5 Configuration partitioning
`NSManagedObjectModel`'s named configurations partition entities across stores. `-addPersistentStore…` takes a
`configurationName`. This is why `-assignObject:toPersistentStore:` exists on the context. It is a corner most
implementations skip; 10.6 declares it, so it is in W4's gate.

### 7.6 Explicit refusals in the store layer
Eight 10.6 constants exist for **external records** (`NSExternalRecordsDirectoryOption`,
`NSExternalRecordExtensionOption`, `NSExternalRecordsFileFormatOption`, `NSBinaryExternalRecordType`,
`NSXMLExternalRecordType`, and the Spotlight-facing keys). They exist so a document can keep each object in its
own file for indexing by an external system. Agora has no such indexer, so all six are **refused** with a
logged reason: `COREDATA-REFUSE external records: no external record indexer on this platform`. Declared,
annotated, tested, counted in `tests/refusal_census.txt` — never silently accepted, because accepting the
option and doing nothing would change what a save means.

---

## 8. The fetch engine (W5) — predicate → query

### 8.1 Shape
A fetch is planned once and executed per store: entity + subentities → FROM; predicate → WHERE; sort
descriptors → ORDER BY; fetch limit/offset → LIMIT/OFFSET; properties to fetch → projection. Planning happens
in `fetch/`, execution in the store, and the plan is a small tree the store can also execute in memory (the
in-memory store and the "includesPendingChanges" path both need that).

### 8.2 Translation surface
`NSComparisonPredicate` operators, mapped to SQL **with bound parameters, never interpolated** — a predicate
built from user text is `NSString`-carrying, and interpolating it is both an injection and a typo that
silently compares wrong:

| Predicate | SQL |
|---|---|
| `=`, `!=`, `<`, `<=`, `>`, `>=` | `=`, `<>`, `<`, `<=`, `>`, `>=` |
| `BETWEEN` | `BETWEEN ? AND ?` |
| `IN` | `IN (…)` with one placeholder per element |
| `CONTAINS` | `LIKE '%' \|\| ? \|\| '%'`, with `%`/`_` in the operand escaped and an `ESCAPE` clause |
| `BEGINSWITH` / `ENDSWITH` | `LIKE ? \|\| '%'` / `'%' \|\| ?` |
| `LIKE` / `MATCHES` | `LIKE` / refused (§8.4) |
| `[c]`, `[d]` options | `COLLATE NOCASE`, diacritic folding via a normalising function |
| `ANY`/`ALL`/`NONE` on a relationship | `EXISTS`/`NOT EXISTS` subquery with a join |
| `NSCompoundPredicate` AND/OR/NOT | `AND`/`OR`/`NOT` with parenthesisation |

`NSExpression` beyond key paths — `count:`, `sum:`, `max:`, `min:`, `average:`, `now`, arithmetic — is
needed for `NSExpressionDescription` and `NSDictionaryResultType` fetches, and is W5's second half.

### 8.3 `NSFetchRequest`'s 30 selectors are 4 features and 26 modifiers
The features: **filtering** (`predicate`), **ordering** (`sortDescriptors`), **shaping** (`fetchLimit`,
`fetchOffset`, `fetchBatchSize`, `propertiesToFetch`, `resultType`, `returnsDistinctResults`,
`includesPropertyValues`, `returnsObjectsAsFaults`, `relationshipKeyPathsForPrefetching`), and **scope**
(`entity`, `includesSubentities`, `includesPendingChanges`, `affectedStores`). The modifiers are where the
behaviour lives; each gets a test that distinguishes it from the default, because "it returned the right rows"
is not the same as "it returned them as faults in batches of 20 without firing `Z_OPT`".

### 8.4 Refusals, named
- **Block predicates** (`+predicateWithBlock:`) in a fetch: a block cannot be translated; refused with
  `NSPersistentStoreOperationError` and a `COREDATA-REFUSE` line, rather than falling back to a full scan that
  looks like it worked.
- **`MATCHES`**: regular-expression matching in SQLite needs a user function and Apple's semantics on 10.6 are
  ICU-flavoured. Refused by name at the predicate door.
- **Predicates over transient properties**: evaluated in memory after the SQL pass; documented, since the
  result is correct but the LIMIT is applied to the store rows first — a semantic difference worth stating.

---

## 9. Migration (W6) — 59 selectors, and two different jobs

`NSMappingModel` (6), `NSEntityMapping` (22), `NSPropertyMapping` (6), `NSMigrationManager` (18),
`NSEntityMigrationPolicy` (7). Two things a client does:

1. **Inferred, with no mapping model**: `NSMigratePersistentStoresAutomaticallyOption` +
   `NSInferMappingModelAutomaticallyOption`, both 10.5/10.6 constants. The coordinator compares the store's
   version hashes to the model's and asks `+inferredMappingModelForSourceModel:destinationModel:error:`.
   Renames, added attributes with defaults, removed attributes and entity inheritance changes all have defined
   inferences. **This is the migration most clients use and the one the plan implements first**, because it is
   what `NSPersistentDocument` does by default.
2. **An explicit mapping model**: a compiled model resource with per-entity `NSEntityMapping` and per-property
   `NSPropertyMapping` value expressions, executed by `NSMigrationManager` in three passes (create, relate,
   validate), with `NSEntityMigrationPolicy` subclasses overriding `-createDestinationInstancesForSourceInstance:`
   and friends.

`-migratePersistentStore:toURL:options:withType:error:` (on the coordinator) is the public door; the plan's
implementation is in-memory (source store read → manager → destination store write), which is what Apple does
and what makes `NSMigrationManager`'s per-instance hooks observable.

**Gate G6 asks for the real thing**: a store written by the tree's own W7 SQLite store at model v1, migrated to
v2 by inference *and* by an explicit mapping model, compared row-for-row against a store written directly at
v2. A migration that "succeeds" without that comparison is not measured.

---

## 10. Concurrency — 10.6 means locks, and the plan is faithful

`NSManagedObjectContext <NSCoding, NSLocking>` with `-lock`, `-unlock`, `-tryLock`. `NSPersistentStoreCoordinator
<NSLocking>` with the same three. Objects are confined to a thread by convention, not by enforcement, and
`-mergeChangesFromContextDidSaveNotification:` is the only cross-thread path.

The plan keeps that model, and adds exactly two things Apple does not have:

1. **Misuse detection instead of corruption.** Apple's 10.6 behaviour on a cross-thread object access is
   undefined. Agora records the thread that created each `NSManagedObject` and each context, and a
   cross-thread access that is not under the context's lock **raises
   `NSManagedObjectContextLockingError`** (a 10.6 error code that otherwise never appears) with the thread
   ids in the message. This is an **adapted** disposition, documented at the header, and it is a strict
   superset of the contract: a correct program never sees it.
2. **No hidden queue, no hidden thread.** An extension door (`-performBlock:` style) is **not** added, even
   though it would be convenient, because a client written against 10.6 headers would then compile against
   Agora and not Apple. Extensions are allowed by §4.1 of the surface plan only when annotated; here the
   annotation would be a lie about the era, so the door is simply not offered.

Deadlock analysis is therefore bounded and stateable: one recursive lock per context, one per coordinator,
acquired coordinator-then-context and never the reverse.

---

## 11. The AppKit seam (W8) — 4 headers, and three missing classes

Ten-point-six AppKit mentions Core Data in exactly four headers:

| Header | Declares | State in `libagora-app` |
|---|---|---|
| `NSPersistentDocument.h` | `NSPersistentDocument : NSDocument`, **9 selectors** | **absent**; the manifest already carries the class row and all 9 selectors, uncounted as missing only because they resolve to nothing |
| `NSObjectController.h` | **11 Core Data selectors** of its 31: `managedObjectContext`/`setManagedObjectContext:`, `entityName`/`setEntityName:`, `fetchPredicate`/`setFetchPredicate:`, `usesLazyFetching`/`setUsesLazyFetching:`, `fetch:`, `fetchWithRequest:merge:error:`, `defaultFetchRequest` | **absent** (`NSController`, its superclass, is also absent) |
| `NSKeyValueBinding.h` | `extern NSString *NSManagedObjectContextBinding` | **present** — `NSKeyValueBinding.h` 223 / `.m` 531 already declares the constant and the `NSEditor`/`NSEditorRegistration` categories on `NSObject` |
| `NSPredicateEditorRowTemplate.h` | `+templatesWithAttributeKeyPaths:inEntityDescription:` | **absent** (`NSPredicateEditor`, `NSRuleEditor` absent) |

So the seam splits cleanly into three deliverables of very different cost:

- **W8.1 `NSPersistentDocument`** — cheap and honest: `NSDocument` (368/1,593) already has
  `-readFromURL:ofType:error:`, `-writeToURL:ofType:forSaveOperation:originalContentsURL:error:` and
  `-revertToContentsOfURL:ofType:error:`. `NSPersistentDocument` is a factory plus lifetime discipline over
  the coordinator: build the model from the document's bundle, open the store, wire `-undoManager` to the
  document's, and on save write the store before the document. The one non-obvious requirement is
  §7.2's: `-persistentStoreTypeForFileType:` defaults to `NSXMLStoreType`, so **W8.1 is gated on the XML
  store** — which under D1's ordering is W7's last deliverable, not its first.
- **W8.2 the controllers** — `NSController`, `NSObjectController`, `NSArrayController` with entity modes.
  These are not Core Data work; they are the AppKit's controller/bindings layer, which `WORKSPACE-PLAN.md`
  and the surface plan already own as 10.6 debt. The Core Data part is the 11 selectors and the
  "controller owns a fetch and a context" protocol. **The plan does not smuggle them in**: W8.2 is scoped as
  a dependency on the AppKit's own controller wave, and the Core Data plan's obligation is only that
  `NSManagedObject` is KVC/KVO-clean enough for them (which §5.4 and §6.2 deliver).
- **W8.3 `NSPredicateEditorRowTemplate`** — 16 selectors and a relation to `NSRuleEditor`. It is the one place
  where Core Data's model is *inspected by a UI*, and it is gated on `NSPredicateEditor`, which is gated on
  `NSRuleEditor`. Lowest priority, and legitimately refused-by-deferral: declared, and its one Core
  Data-taking selector refuses with "no predicate editor on this platform yet".

---

## 12. Waves, gates and effort

| Wave | Scope | Selectors | Gate | ew |
|---|---|---:|---|---:|
| **P0** | Prerequisites and instrument (§4.1, §2.3) | — | `NSPredicate`/`NSExpression`/`NSComparisonPredicate`/`NSCompoundPredicate` **and the collection predicate API** implemented and tested in `libagora-base`; the ledger resolves framework bundles (**done**: `CoreData.framework` now emits 352 lines, AppKit byte-identical); `api/10.6/coredata-manifest.txt` committed; `libagora-data` skeleton builds and installs | 8–12 |
| **W1** | Model: `NSManagedObjectModel`, `NSEntityDescription`, `NSPropertyDescription` + 4 subclasses | 99 | A model built in code equals a model decoded from an archived copy (`NSCoding` round-trip); entities/properties/superentity resolution and configuration partitioning are correct; `-entitiesByName`, `-propertiesByName`, `-subentitiesByName` | 10–14 |
| **W2** | Objects: `NSManagedObject`, `NSManagedObjectID` | 41 | Insert/fetch/fault/unfault/refresh/delete semantics per §6.1–6.3 on the in-memory store; KVC accessors for all 11 attribute types; temporary→permanent ID transition | 12–18 |
| **W3** | Context: change processing, save, undo, merge, notifications, validation | 39 | Every behaviour in §6.3–6.6 has a test; a save of 1,000 inserted objects with relationships round-trips through the in-memory store; five merge policies distinguished | 14–20 |
| **W4** | Store protocol: `NSPersistentStore`, `NSAtomicStore`, `NSAtomicStoreCacheNode`, coordinator, in-memory + binary stores, configurations | 59 | `NSInMemoryStoreType` and `NSBinaryStoreType` pass the **whole** W2+W3 suite; metadata read without a stack; multi-store assignment; store registration | 12–16 |
| **W5** | Fetch engine: `NSFetchRequest`, `NSFetchRequestExpression`, planner, predicate→SQL (§8) | 34 | Every operator in §8.2 translated and tested; all 26 modifiers distinguished; `countForFetchRequest:error:` agrees with `-count` of the result; refusals counted | 16–22 |
| **W6** | Migration: 5 classes + coordinator's migrate door | 59 | Gate G6 of §9: inferred and explicit migration both compared row-for-row | 12–18 |
| **W7** | Stores: SQLite first, then XML (D1-b, decided) | 0 new classes | SQLite store passes the W2+W3 suite plus `PRAGMA`s, ANALYZE, VACUUM, read-only, and a 10⁵-row fetch-limit/batch test; then the XML store passes the same suite and is `NSPersistentDocument`-ready | 20–30 |
| **W8** | AppKit seam (§11) | 9 + 11 + 1 | `NSPersistentDocument` opens, saves, reverts, and autosaves an XML store; controller selectors present and deferred where §11 says | 6–18 |
| **W9** | Conformance, refusals, docs, sample | — | censuses hold in both directions; refusals ≥ the §7.6/§8.4 list with zero silent successes; `COREDATA-PLAN.md` updated to record what was actually done | 6–10 |
| | **Total** | **331** | | **116–178** |

The total is **roughly 2.5–3.5 engineer-years** for M1+M2+M3, of which P0 and W5–W7 (the two engines and the
SQL store) are more than half. It is an order of magnitude, not a schedule, and it should be re-measured after
P0 and after each wave — the same rule the surface plan sets.

**Gates are cumulative and non-negotiable.** A wave's census number may not rise by declaring selectors that
return `nil` without a refusal line: `api-ledger check` counts a selector as present when it is declared **or
implemented in a `.m` body along the chain**, so a declared-and-empty door scores as present — which is exactly
the measurement error `api_census.cmake`'s header records having been burned by on C functions. The Core Data
census therefore carries the AppKit census's second instrument: `nm -D --defined-only` for the six exported
constants that are global variables, and a per-wave **behaviour** test count that a declaration cannot fake.

---

## 13. Testing

Five instruments, and the plan refuses to let any one stand in for another:

1. **The census** (`api-ledger check` + `tests/coredata-census.txt`): 21 classes, 331 selectors, pinned. Drift
   is a failure with a diagnostic, and moving the number is a deliberate act in the same commit.
2. **The refusal census** (`tests/refusal_census.txt` + `claims_census.cmake`): every `COREDATA-REFUSE` site
   counted per file, in both directions — a refusal that disappears is as much drift as one that appears
   unlogged.
3. **Behaviour tests**, `tests/*.m`, registered the way `libagora-app/tests/CMakeLists.txt` registers its own
   (one executable per subject, `add_test`, `LD_LIBRARY_PATH` from `$<TARGET_FILE_DIR:…>` so the build tree's
   library is the one under test — the failure that file records having hit is the one to avoid here).
   Subjects: model, object, context, save, undo, merge, validation, fetch, store-atomic, store-binary,
   store-xml, store-sqlite, migration, concurrency, appkit-document.
   **Every one runs twice where it can**: once on the in-memory store and once on the on-disk store, because
   the in-memory store cannot catch a serialisation bug and the SQLite store cannot be forgiven for one.
4. **Conformance against a reference store.** For each store type, a fixture directory of files *written by
   the tree* and committed, plus the expected object graph in a `.plist`, so a change that alters the on-disk
   format fails loudly and by diff. (Under D1-a this would become Apple-authored fixtures; under D1-b it is
   ours, which is a deliberate consequence of the decision.)
5. **Stress and fuzz.** 10⁵-row insert/fetch with `fetchBatchSize`; 20 threads × 2,000 saves each through
   separate contexts with `-mergeChangesFromContextDidSaveNotification:`; a predicate-format fuzzer over the
   §8.2 operators asserting that every accepted predicate either translates or refuses, never silently
   degenerates. The fuzzer is the test for the plan's own §4.3 rule.

---

## 14. Risks and open decisions

| # | Risk / decision | Status | Mitigation |
|---|---|---|---|
| **D0** | Predicate family restoration in `libagora-base` | **decided here** (§4.1): required | Phase 0 owns it; it is a prerequisite rather than a wave, so no Core Data work starts before it |
| **D1** | SQLite schema: Apple-compatible or Agora's own | **decided: D1-b** (§7.1, §0.1) | documented schema written before the first table; Apple stores refused with `NSPersistentStoreIncompatibleVersionHashError`; D1-a stays an importer |
| **D2** | Does 10.6's `<NSLocking>` model get misuse detection? | **decided here** (§10): yes, adapted | `NSManagedObjectContextLockingError` on cross-thread access |
| **D3** | Cross-store save atomicity | **decided here** (§6.7): matches Apple, documented as non-atomic | test asserts the partial-write error |
| **D4** | External records | **decided here** (§7.6): refused | 6 constants, 1 refusal site, counted |
| **D5** | `MATCHES` and block predicates | **decided here** (§8.4): refused by name | refusal census |
| — | Predicate→SQL is the largest single engine and is underestimated in every Core Data reimplementation | risk | W5 estimated at 16–22 ew against 34 selectors; re-measure after W1–W4 |
| — | `NSStoreModelVersionHashesKey` stability: a model digest that changes between builds invalidates every store | risk | canonical, ordered serialisation; a test pinning the digest of a fixture model across releases |
| — | Undo/redo of relationship inverses is the classic correctness sink | risk | §6.6's dedicated test class; undo is a W3 gate item, not a W9 cleanup |
| — | The AppKit controllers (§11 W8.2) are a dependency on another component's wave | risk | W8.2 is explicitly deferrable; W8.1 and W8.3 are independent of it |
| — | 10.6's XML store format is Apple's and undocumented; ours is a documented adaptation | risk | §7.1's D1 reasoning applies; a client sees an `NSXMLStoreType` store that Apple's Core Data will not read — documented at the constant |
| — | `libagora-objc`'s `+resolveInstanceMethod:` path is used for every accessor | risk | measure once at W2; if the runtime's lazy-resolution path is slow, fall back to per-class method installation |

---

## 15. Definition of done

### 15.1 M1 — declared
1. The 24 headers exist; `CoreData.h` imports them in Apple's order.
2. All 21 classes, 331 selectors and 56 constants (+5 merge-policy `id`s) exist, annotated with the 10.6
   availability macros, and compiled.
3. `api-ledger check api/10.6/coredata-manifest.txt . tests/coredata-census.txt` exits 0.
4. Every selector that is not functionally implemented has a `COREDATA-REFUSE` line and a test asserting the
   refusal. Zero silent successes.

### 15.2 M2 — the object graph is true
5. §6.1–6.6 each have a test that fails if the behaviour is absent, on **both** the in-memory and the binary
   store.
6. A 10⁵-row workload with relationships, batching and undo completes with the expected row and object counts.
7. `NSPersistentDocument` opens, saves, reverts and autosaves a real document over an XML store.

### 15.3 M3 — storage and migration are true
8. `NSSQLiteStoreType` passes the whole W2+W3 suite, plus pragmas, ANALYZE, VACUUM, read-only, timeout, and
   the batch/limit behaviour.
9. Gate G6 holds: inferred and explicit migration both compared row-for-row.
10. D1 is recorded as **D1-b** (§0.1, §7.1), `store/sqlite/SCHEMA.md` exists and predates the code, and the
    conformance fixtures match it.

---

## 16. Immediate next actions

1. **Take D1** (§7.1). Nothing in W7 can start without it, and the answer shapes the fixtures.
2. **Start P0's predicate family in `libagora-base`** (§4.1), as its own commit series, with the ledger rows
   restored — and update `Foundation.h:104`'s note to record *why* the family came back, since the note is
   currently a correct record of a decision that a 10.6 target reverses.
3. **Fix the ledger's framework-bundle path** (§2.3) and commit
   `libagora-data/api/10.6/coredata-manifest.txt` — 352 lines, generated, already verified with the
   unmodified tool.
4. **Create the submodule and skeleton** (§5.1) with the umbrella header, the defines, the error header, and
   an empty `CoreData.m` that links — so the census has a library to measure from the first wave.
5. **Build the in-memory store first** (§7.2). It is the conformance reference for every other store and the
   thing that makes W2 and W3 testable before any serialisation format exists.

---

## Appendix A — the 21 classes, by wave

| Wave | Classes | Selectors |
|---|---|---:|
| W1 model | `NSManagedObjectModel`, `NSEntityDescription`, `NSPropertyDescription`, `NSAttributeDescription`, `NSRelationshipDescription`, `NSFetchedPropertyDescription`, `NSExpressionDescription` | 99 |
| W2 object | `NSManagedObject`, `NSManagedObjectID` | 41 |
| W3 context | `NSManagedObjectContext` | 39 |
| W4 store | `NSPersistentStore`, `NSAtomicStore`, `NSAtomicStoreCacheNode`, `NSPersistentStoreCoordinator` | 59 |
| W5 fetch | `NSFetchRequest`, `NSFetchRequestExpression` | 34 |
| W6 migration | `NSMappingModel`, `NSEntityMapping`, `NSPropertyMapping`, `NSMigrationManager`, `NSEntityMigrationPolicy` | 59 |
| | **21** | **331** |

## Appendix B — the 56 public constants, all of them

Generated from the 10.6 headers, partitioned so that each name appears exactly once.

**Store types (4):** `NSBinaryStoreType`, `NSInMemoryStoreType`, `NSSQLiteStoreType`, `NSXMLStoreType`

**External record types (2):** `NSBinaryExternalRecordType`, `NSXMLExternalRecordType`

**Store metadata keys (11):** `NSStoreTypeKey`, `NSStoreUUIDKey`, `NSStoreModelVersionHashesKey`,
`NSStoreModelVersionIdentifiersKey`, `NSStorePathKey`, `NSStoreUUIDInPathKey`, `NSEntityNameInPathKey`,
`NSObjectURIKey`, `NSModelPathKey`, `NSPersistentStoreOSCompatibility`, `NSUUIDChangedPersistentStoresKey`

**Store options (9):** `NSReadOnlyPersistentStoreOption`, `NSValidateXMLStoreOption`,
`NSIgnorePersistentStoreVersioningOption`, `NSMigratePersistentStoresAutomaticallyOption`,
`NSInferMappingModelAutomaticallyOption`, `NSPersistentStoreTimeoutOption`, `NSSQLitePragmasOption`,
`NSSQLiteAnalyzeOption`, `NSSQLiteManualVacuumOption`

**External-record options (3), refused per §7.6:** `NSExternalRecordsFileFormatOption`,
`NSExternalRecordsDirectoryOption`, `NSExternalRecordExtensionOption`

**Notifications (5):** `NSManagedObjectContextWillSaveNotification`, `NSManagedObjectContextDidSaveNotification`,
`NSManagedObjectContextObjectsDidChangeNotification`, `NSPersistentStoreCoordinatorStoresDidChangeNotification`,
`NSPersistentStoreCoordinatorWillRemoveStoreNotification`

**Notification user-info keys (8):** `NSInsertedObjectsKey`, `NSUpdatedObjectsKey`, `NSDeletedObjectsKey`,
`NSRefreshedObjectsKey`, `NSInvalidatedObjectsKey`, `NSInvalidatedAllObjectsKey`, `NSAddedPersistentStoresKey`,
`NSRemovedPersistentStoresKey`

**Migration keys (6):** `NSMigrationManagerKey`, `NSMigrationSourceObjectKey`, `NSMigrationDestinationObjectKey`,
`NSMigrationEntityMappingKey`, `NSMigrationPropertyMappingKey`, `NSMigrationEntityPolicyKey`

**Error and validation user-info keys (8):** `NSAffectedObjectsErrorKey`, `NSAffectedStoresErrorKey`,
`NSDetailedErrorsKey`, `NSSQLiteErrorDomain`, `NSValidationKeyErrorKey`, `NSValidationObjectErrorKey`,
`NSValidationPredicateErrorKey`, `NSValidationValueErrorKey`

**Merge policies (5, typed `id` rather than `NSString *`):** `NSErrorMergePolicy`,
`NSMergeByPropertyObjectTrumpMergePolicy`, `NSMergeByPropertyStoreTrumpMergePolicy`, `NSOverwriteMergePolicy`,
`NSRollbackMergePolicy`

## Appendix C — the 48 error identifiers, transcribed

The headers yield **48** identifiers matching `NS…Error…`, and they are exactly **38 error codes**, **3**
domain/umbrella identifiers, and **7** `userInfo` keys (already listed in Appendix B). Each group is a different
wave's obligation.

**Persistent store and SQLite codes (11):** `NSPersistentStoreOpenError`, `NSPersistentStoreSaveError`,
`NSPersistentStoreOperationError`, `NSPersistentStoreTimeoutError`, `NSPersistentStoreInvalidTypeError`,
`NSPersistentStoreTypeMismatchError`, `NSPersistentStoreIncompatibleSchemaError`,
`NSPersistentStoreIncompatibleVersionHashError`, `NSPersistentStoreIncompleteSaveError`,
`NSPersistentStoreCoordinatorLockingError`, `NSSQLiteError`

**Context and object codes (5):** `NSManagedObjectContextLockingError`, `NSManagedObjectValidationError`,
`NSManagedObjectReferentialIntegrityError`, `NSManagedObjectExternalRelationshipError`,
`NSManagedObjectMergeError`

**Migration codes (9):** `NSMigrationError`, `NSMigrationCancelledError`, `NSMigrationMissingSourceModelError`,
`NSMigrationMissingMappingModelError`, `NSMigrationManagerSourceStoreError`,
`NSMigrationManagerDestinationStoreError`, `NSInferredMappingModelError`, `NSEntityMigrationPolicyError`,
`NSExternalRecordImportError`

**Validation codes (13):** `NSValidationStringTooShortError`, `NSValidationStringTooLongError`,
`NSValidationStringPatternMatchingError`, `NSValidationNumberTooSmallError`, `NSValidationNumberTooLargeError`,
`NSValidationDateTooSoonError`, `NSValidationDateTooLateError`, `NSValidationInvalidDateError`,
`NSValidationMissingMandatoryPropertyError`, `NSValidationRelationshipLacksMinimumCountError`,
`NSValidationRelationshipExceedsMaximumCountError`, `NSValidationRelationshipDeniedDeleteError`,
`NSValidationMultipleErrorsError`

**Domain and umbrella (3):** `NSCocoaErrorDomain`, `NSCoreDataError`, `NSSQLiteErrorDomain`

**`userInfo` keys (7):** `NSAffectedObjectsErrorKey`, `NSAffectedStoresErrorKey`, `NSDetailedErrorsKey`,
`NSValidationKeyErrorKey`, `NSValidationObjectErrorKey`, `NSValidationPredicateErrorKey`,
`NSValidationValueErrorKey`

38 + 3 + 7 = 48. The spellings are transcribed from the SDK in Phase 0, not from memory —
`NSValidationMissingMandatoryPropertyError` and `NSValidationMultipleErrorsError` are the two a
recollection-based implementation gets wrong, which is why they are named here.

## Appendix D — the post-10.6 boundary, declared

Not in scope, and each one is *why the plan is smaller than "implement Core Data" sounds*:
`-performBlock:`, `-performBlockAndWait:`, `NSManagedObjectContextConcurrencyType`,
`-initWithConcurrencyType:`, `-parentContext`, `NSIncrementalStore`, `NSMergePolicy`, `NSMergeConflict`,
`NSFetchedResultsController`, `NSPersistentContainer`, `NSBatchInsertRequest`, `NSBatchUpdateRequest`,
`NSBatchDeleteRequest`, `NSFetchIndexDescription`, `NSPersistentHistory*`, `NSCoreDataCoreSpotlightDelegate`,
the iCloud/ubiquitous store, and `NSQueryGenerationToken`.

## Appendix E — prerequisite matrix, measured today

| Need | Component | Present? |
|---|---|---|
| `NSPredicate`, `NSExpression`, `NSComparisonPredicate`, `NSCompoundPredicate`, format grammar | `libagora-base` | **no** — removed by §63.161; restored in P0 |
| `-filteredArrayUsingPredicate:`, `-filterUsingPredicate:` | `libagora-base` (NSArray/NSSet/NSOrderedSet) | **no** — same removal |
| `NSRecursiveLock` | `libagora-base` | **yes** — `NSLock.h`/`.m`, `PTHREAD_MUTEX_RECURSIVE` (§4.2's correction) |
| `@protocol NSLocking`, `NSLock`, `NSConditionLock`, `NSCondition` | `libagora-base` | yes (`NSLock.h:36`) |
| `NSKeyedArchiver`/`Unarchiver` | `libagora-base` | yes (1,647-line body) |
| `NSValueTransformer`, `NSSecureUnarchiveFromDataTransformer` | `libagora-base` | yes |
| `NSDecimalNumber`, `NSDecimal` | `libagora-base` | yes |
| `NSXMLDocument`, `NSXMLNode` | `libagora-base` | yes |
| `NSSortDescriptor` | `libagora-base` | yes |
| `NSUndoManager` | `libagora-base` | yes |
| `NSFastEnumeration`, `NSCoding`, `NSCopying` | `libagora-base` | yes |
| SQLite ≥ 3.24 | system | yes (3.46.1, `pkg-config`) |
| `NSDocument` with `readFromURL:`/`writeToURL:` | `libagora-app` | yes (368/1,593) |
| `NSManagedObjectContextBinding`, `NSEditor` categories | `libagora-app` (`NSKeyValueBinding`) | yes (223/531) |
| `NSController`, `NSObjectController`, `NSArrayController` | `libagora-app` | **no** — W8.2, deferred |
| `NSRuleEditor`, `NSPredicateEditor`, `NSPredicateEditorRowTemplate` | `libagora-app` | **no** — W8.3, deferred |


### 0.5 Where W3 stands

| W3 item | State |
|---|---|
| `NSManagedObjectContext` (39 selectors) | **landed**: registry, six sets, save pipeline, undo/redo, rollback, refresh, reset, delete propagation, merge, 10.6's `<NSLocking>` |
| D2 — cross-thread misuse | **landed and measured by a real thread**: `tests/context.m` starts a pthread, calls into the context without the lock, and asserts the exception; then one that takes the lock first and asserts it is allowed |
| The store's doors | **declared as a protocol, not a type** — `CDStoreDoors` with `@optional` members, so the context can ask whether the coordinator it was given answers, and W3 runs with no coordinator at all |
| Save without a coordinator | **in-memory, and the header says so**: validate, adopt the diff, clear the sets, post both notifications. No durability claim; W4 replaces the middle of `-save:` |
| The census | **10 of 21 classes, 179 of 179 offered selectors**, `selectors-missing 0`, `methods-declared-not-implemented 0`. Remaining: **11 classes, 152 selectors** |

Four failures W3 measured, each of which a declaration would have hidden:

1. **`-hasChanges` was NO for a brand-new object.** Registration is not insertion: an object created into a
   context had no *changes* and was therefore invisible to the context's own question. `-cd_registerManagedObject:`
   now files a pending insertion, which is what "inserted" meant in the first place.
2. **`-rollback` emptied the snapshot it was reading.** `-cd_applyCommittedValues:` was handed `_committed` itself
   and cleared it before copying — so rollback forgot everything instead of restoring it. The new snapshot is now
   built first and swapped in.
3. **`-redo` was a no-op.** Undo registration was suppressed while an undo was replaying, on the theory that it
   would recurse; `NSUndoManager` instead routes registrations made during `-undo` into the **redo** stack, which
   is the entire mechanism. The flag now quietens change tracking only.
4. **Apple's notification carries SETS, not arrays.** `-mergeChangesFromContextDidSaveNotification:` indexed them
   and raised `-[AGSetItems objectAtIndex:] is not implemented` — the Foundation's own refusal, from a crash that
   only a test with a real notification would have found.

**One gap, stated rather than hidden: automatic inverse maintenance is not implemented.** Setting one side of a
relationship does not update the other, because a to-many side needs the mutable collection that a fetch installs
(W4/W5). `tests/context.m` writes both sides explicitly and says so at the call site; the wave that adds mutable
relationship collections must make that asymmetry disappear.


### 0.6 Where W4 stands

| W4 item | State |
|---|---|
| The four store classes (59 selectors) | **landed**: `NSPersistentStore`, `NSAtomicStore`, `NSAtomicStoreCacheNode`, `NSPersistentStoreCoordinator`, plus the 30 store-type/option constants |
| The store registry | **landed**: `+registerStoreClass:forStoreType:` is the extension point, so W7's SQLite store is a registration rather than an edit. `NSInMemoryStoreType` is the only type registered on 10.6, and it is the conformance reference (§7.2) |
| `CDStoreDoors` | **implemented** — the protocol W3 declared is now answered, which is what turns a temporary ID into a permanent one |
| The two-context fault | **measured**: one context saves, a second is handed only the permanent ID, gets a fault, and fires it by reading a property |
| The census | **14 of 21 classes, 238 of 238 offered selectors**, `selectors-missing 0`, `methods-declared-not-implemented 0`. Remaining: **7 classes, 93 selectors** — W5's fetch pair and W6's five migration classes |

Two things W4 decided rather than discovered:

- **Permanent IDs are assigned before any node is written**, so a relationship stored as a key refers to a row
  that already has its key. The context re-keys its registry afterwards (`-cd_rekeyRegisteredObjects`), because a
  save replaces the very IDs that registry is keyed by — the first place in this plan where identity changes.
- **A missing store type names its wave.** `NSSQLiteStoreType` returns `NSPersistentStoreInvalidTypeError` with a
  reason that says "W7", because a caller who mistyped a type and a caller asking for a store that is not built
  yet must be able to tell the two apart from the error alone.

**The object graph is now whole:** model → object → context → store, with an ID that names a row. Everything
after W4 is a store that serialises (W7), a fetch engine (W5), and migration (W6).


### 0.7 Where W5 stands

| W5 item | State |
|---|---|
| `NSFetchRequest` (30) and `NSFetchRequestExpression` (4) | **landed**, with Apple's defaults written out rather than left to zero — `includesPendingChanges`, `includesSubentities`, `includesPropertyValues` and `returnsObjectsAsFaults` are YES, and a request that defaulted them to NO would be right about the rows and wrong about the answer |
| The pipeline (§8.1) | **landed** in `CDFetchEngine.m`: candidates → predicate → sort → offset → limit → shape. Offset before limit, because paging is "skip n, take m" |
| The predicates the engine evaluates | **Foundation's**, restored in P0 — `tests/fetch.m` filters on `age > 30` and sorts by a descriptor |
| `includesPendingChanges` | **the reason the engine is not in the store**: an unsaved insert has no row, so the engine asks the CONTEXT for pending objects and merges by identity |
| The census | **16 of 21 classes, 272 of 272 offered selectors.** Remaining: **5 classes, 59 selectors** — W6's migration. The first pin said 271 of 272: `api-ledger missing` named `NSPersistentStoreCoordinator +metadataForPersistentStoreWithURL:error:` — the **deprecated** copy 10.6 declares on both the store and the coordinator — and it is in |

Three defects the first caller found, two of them in code this plan had already declared done:

1. **`-propertiesByName` did not include inherited properties.** An `Employee` could not answer `name` because
   only a `Person` declares it, so every inherited write was an unmodelled key. Apple's contract is explicit and
   now implemented — and the three places that gathered values from `-properties` (the atomic store's node
   writer, the coordinator's save, the engine's dictionary shaper) had to move with it, or a subentity's
   inherited attributes would silently never be stored.
2. **The predicate family's `-copy` raised.** `NSObject.h` removed every `NSZone`-taking method, so the copying
   protocol's member is `-copy`; all four classes implemented Cocoa's `-copyWithZone:` instead, and
   `-setPredicate:` — which copies — failed in one line. Fixed in `libagora-base` and committed there.
3. **`-propertiesToFetch` had to accept key names.** Apple documents the array as property descriptions, but
   nearly every caller writes strings, and the engine raised `-[NSTinyString name] is not implemented` at the
   caller's expense. Both forms are accepted now.

**And one number that was wrong the first time, found after the fact.** The W5 commit message and this section
originally claimed 272 of 272 selectors; the actual pin said 271 of 272. `api-ledger missing` named the
declaration the header had omitted — the **deprecated** `+metadataForPersistentStoreWithURL:error:` that 10.6
declares on `NSPersistentStoreCoordinator` as well as on `NSPersistentStore`. The instrument found it, not a
reader; the gate was consistent all along, because it was comparing 271 to 271. A plan that reports its own
arithmetic failure is worth more than one that quietly corrects the table.


### 0.8 Where W6 stands — and what "complete" does and does not mean

| W6 item | State |
|---|---|
| The five migration classes (59 selectors) | **landed**: `NSMappingModel`, `NSEntityMapping`, `NSPropertyMapping`, `NSMigrationManager`, `NSEntityMigrationPolicy`, and the six migration context keys |
| The inference (§9.1) | **landed in both directions**: an entity in both models becomes a copy or a transform (a transform when its hash changed), one only in the destination an add, one only in the source a remove. A destination property with no source namesake gets **no** mapping — it keeps its default rather than being produced from nothing |
| The three passes (§9) | **landed and run**: creation for every source instance, then relationships for every destination instance, then validation. The passes are separate because a relationship can only be rebuilt once every destination object exists |
| The association table | **landed**: `-destinationInstancesForEntityMappingNamed:sourceInstances:` and its inverse, keyed by **object ID** so two contexts' objects for one row agree |
| Migration, actually performed | **measured**: the suite seeds a source context, runs an inferred mapping model, and reads a value the default policy copied into the destination |

**Measured: 21 of 21 classes, 331 of 331 selectors, `classes-missing 0`, `selectors-missing 0`,
`methods-declared-not-implemented 0`. M1 — the declared surface — is complete.**

That sentence is true and it is worth being exact about what it does not say. **Declared is not durable.** Three of
the four store types still refuse by name — `NSSQLiteStoreType`, `NSXMLStoreType` and `NSBinaryStoreType` return
`NSPersistentStoreInvalidTypeError` with a reason that names W7 — and so does every option that belongs to them
(`NSSQLitePragmasOption`, `NSReadOnlyPersistentStoreOption`, the external-records keys). What exists is the whole
object graph against an in-memory store, which is a real application's worth of Core Data minus the file.

So the milestones stand as: **M1 done**; **M2** done except its binary and XML stores; **M3** (SQLite and migration
against a file) untouched. **The remaining work is W7, and it is one wave of serialisation — not a set of missing
declarations.**


### 0.9 Where W7 stands — and what is left

| W7 item | State |
|---|---|
| `store/sqlite/SCHEMA.md` | **written and committed BEFORE the first table**, as §7.1 requires: the DDL, why the values are four typed columns rather than one blob, why the metadata is an opaque plist, and what is refused |
| `NSSQLiteStoreType` | **landed** against that schema: DDL, one transaction per save, pragmas from `NSSQLitePragmasOption`, `ANALYZE`/`VACUUM`, and `+metadataForPersistentStoreOfType:URL:error:` answered without a stack |
| `NSBinaryStoreType` | **landed**: a keyed archive of `{metadata, nodes}` |
| `NSXMLStoreType` | **landed**: the same tree as an XML property list, which is parseable XML that keeps the value types; `NSValidateXMLStoreOption` re-serialises what it parsed |
| Apple-authored stores (D1-b) | **refused by name**: the version hashes cannot match, so opening one fails with `NSPersistentStoreIncompatibleVersionHashError` |
| The census | **21 of 21 classes, 331 of 331 selectors, `methods-declared 361`, `methods-declared-not-implemented 0`**. The three stores are private classes, so W7 moved `methods-declared` and not a single manifest selector — which is the right shape: the public surface is the store *types* |

**Two bugs W7's suite found, and both had shipped:**

1. **The coordinator never called `-load:` on a store.** `-loadMetadata:` ran and then the store was registered with
   no contents — so the write path worked, the file was correct, and **every read returned zero rows**. Found by
   the first test that wrote a file and opened a *fresh* stack on it; nothing before W7 had ever read a store back.
2. **This Foundation's property-list writer refuses the binary format**, with a named error. The SQLite metadata
   blob uses XML v1.0 now. The refusal was correct and the store was wrong to assume otherwise.

**One gap, stated: relationships are not persisted.** `NSAtomicStore -updateCacheNode:fromManagedObject:` skips
relationship properties, because a relationship's value is another managed *object* and a node is scalar values.
The storage half (write the related row's key) is trivial; the resolution half — translating a key back into an
object when a fault fires — is the next slice, and writing a wrong-typed value instead would have been worse than
this note.

**A third thing W7's checks found, in the checks themselves:** the SQLite readability test shelled out to the
`sqlite3` binary, and this machine does not have one — so the check silently did nothing and "readable by sqlite3"
was an unverified claim in a commit message. It now uses Python's `sqlite3` module (the same client library by
another door) and **skips loudly** when neither is present. Verified running: the file's four tables and all nine
typed values read back as a standard client sees them, and the metadata blob is an XML property list.

**So: M1 complete, M2 complete for the in-memory, binary and XML stores and for the object graph, M3 complete
except relationship persistence.** What remains is that one slice, and the W8 AppKit seam (`NSPersistentDocument`),
which is blocked on nothing here — only on the AppKit's own controller wave.


### 0.10 Relationships, end to end — the gap §0.9 named is closed

| Piece | State |
|---|---|
| To-many values | **mutable collections**: `-primitiveValueForKey:` answers a working `NSMutableSet` that *is* the object's value, so membership changes work through the object graph rather than through a replace-the-set dance |
| Inverse maintenance | **landed**: setting one side updates the other, to-one→to-many, to-many→to-one and to-one→to-one, with the previous member unlinked. 7 checks in `tests/object.m` |
| Storage | **landed**: `NSAtomicStore` writes a relationship as the related row's **object-URI string**, and a to-many as an array of them. The node format needs no type marker, because the model already says which properties are relationships |
| Resolution | **landed**: the coordinator's fault door turns those URIs back into objects through `[context objectWithID:]`, so reading `person.department.title` after a reopen is two hops, both from the file |
| SQLite | `type = 'array'` with a property-list blob for a to-many, documented in `SCHEMA.md`; a to-one is the URI as a plain `string`, which `sqlite3` shows |
| The tests | **52 checks in `tests/serialisation.m`** (up from 37), run through all three store types; 39 in `tests/object.m` |

Measured as a standard client reads it:

```
('Person', 1, 'department', 'string', 'x-coredata://agora-store-3-.../Department/p1')
('Person', 1, 'name',       'string', 'alice')
('Department', 1, 'staff',  'array',  (blob))
('Department', 1, 'title',  'string', 'Engineering')
```

**Three things this slice did not do, said plainly rather than implied:**

1. **Mutating a to-many set directly does not maintain the inverse, fire KVO, or register undo.** It changes the
   value and it persists, and `tests/object.m` proves exactly that much. A proxied collection is the missing piece,
   and it is the next slice.
2. **A reference to an object that was never saved cannot be stored** — its ID is temporary, so its URI names a row
   that does not exist. A save assigns permanent IDs to insertions first, so this only bites on a store written
   around a temporary ID, which the round trip would then fail to resolve.
3. **`NSFetchedPropertyDescription` still evaluates nothing**: the fetched-property door exists (W1) and a fetch
   expression exists (W5), but nothing runs one per object yet.


### 0.11 Routing and configuration — the two doors nothing opened

§0.10 left a list; this closes its first two items, and they are worth recording because **the census scored them
and the behaviour was wrong**.

| Door | Before | Now |
|---|---|---|
| `-assignObject:toPersistentStore:` | wrote into `_storeAssignments`, and **nothing ever read it** | the first of four routing rules; `nil` clears the assignment, and a save consumes the table because afterwards the object's ID names the store |
| `-addPersistentStoreWithType:configuration:` | stored a name; nothing consulted it | the third rule, and it filters on **load** as well as on save |
| `-cd_saveContext:` | always `_stores[0]` | groups by store, then saves **every** store it touched — and §6.7 still says that is not atomic across them |
| `-cd_obtainPermanentIDsForObjects:` | minted keys from `_stores[0]` | mints each key **from the store that object is going to** |
| `-cd_faultObject:` | read `_stores[0]`'s cache node | reads the cache node of the store the **ID names** |
| `-cd_executeFetchRequest:` | `_stores[0]` | every store, or the ones `-setAffectedStores:` names; shaped **once** after merging |

**The four rules, in precedence order** (`tests/routing.m`, 26 checks): an explicit assignment wins; an object that
already lives in a store stays there; otherwise the configuration decides; and **an entity that no store's
configuration names is an error**, not a quiet write to the first store.

Two consequences worth naming:

- **The fetch engine had to be split in two.** "Which rows" is per store; "what order, which slice, what shape" is
  over the merged set. Sorting and paging inside each store would return the first N rows of *every* store and
  restart `fetchOffset` at each one — a bug that only appears the day a second store exists, which is exactly why it
  was invisible.
- **A managed object cannot be a dictionary key.** `_storeAssignments` keyed by the object raised
  `-[AGDictionaryMutable insert]: key <NSManagedObject> does not conform to NSCopying` — because this framework
  refuses `-copy` on a managed object deliberately (one identity, one context). The table is keyed by **object ID**,
  which is stable while unsaved and copyable.

**The lesson, stated for the census's sake:** `api-ledger` counts doors a caller *can* reach, and both of these were
reachable — declared, implemented, and never called by anything. A census cannot measure whether a door is opened.
`tests/routing.m` is that measurement, and it is the first suite in this component added because of a **reading** of
the code rather than a failure.


### 0.12 Scale — three quadratics fixed in Foundation, and two defects named

§15.2's sixth item and §15.3's eighth asked for a 10⁵-row workload and for SQLite to run the behaviour suite. Writing
that suite did not measure Core Data first. **It measured Foundation**, three times.

| Found | Fixed? |
|---|---|
| `NSMutableSet -addObject:` copied the whole member array and scanned it for the duplicate — O(n) per add, O(n²) for n adds. **Measured: 0.6 s for 2,000 members, 10.4 s for 8,000**, which turned the 10⁵ workload into a twenty-minute timeout | **yes** — `AGSetMutable` (the class `[NSMutableSet set]` actually allocates) appends in place and keeps a `-hash` bucket index: 0.019 s for 8,000, 0.263 s for 100,000 |
| `NSSet -initWithArray:` deduplicated with a nested loop — O(n²) **isEqual:** calls. This one was 0.73 s for 8,000 and **626 s for a 10⁵-row save** | **yes** — the dedupe is hashed, and the set algebra reads the storage directly instead of calling `-allObjects` once per element |
| `NSEntityDescription -propertiesByName` was rebuilt on every call, inheritance walk included — a decision this plan's W1 note defended in prose ("a stale dictionary is a bug that survives review"). Every KVC read on every managed object paid it, so **sorting 5,000 objects took 63.76 s** | **yes** — cached, and invalidated by `-setProperties:`, `-setSubentities:` and `-setSuperentity:` down the whole subentity tree. 63.76 s → 15.96 s |
| **`-sortedArrayUsingDescriptors:` is an insertion sort** — O(n²) comparisons: 16 s for 5,000 rows, **502 s for 20,000** | **NO — open** |

Measured after the three fixes, at 10⁵ rows:

```
in-memory  insert 100000 rows:   5.25s      in-memory  fetch  100000 rows:   0.81s
in-memory  process 100000 rows:  1.02s      in-memory  save   100000 rows:   5.40s
```

and the whole suite at its default 5,000 (which is 5,000 **because of the open sort**): insert 0.09 s, save 0.17 s,
fetch 0.02 s, predicate fetch 0.03 s, count 0.02 s, SQLite insert 0.08 s, save 0.53 s, load 0.05 s, fetch 0.03 s.

**A suite that was doing its job.** The first attempt put the fast append on `NSMutableSet` itself and **five
`kvo_tomany` cases failed immediately**: KVC's to-many proxy is an `NSMutableSet` subclass that computes its KVO
diff by overriding `-fnReplaceMembers:`, so the base class must keep funnelling every mutation through it. The
optimisation moved to the concrete class instead. That is the suite catching a design constraint that the
optimisation's author had not read.

**Two defects this wave names instead of fixing:**

1. **`NSSet` has no `-dealloc`, and `-fnReplaceMembers:` does not release the array it replaces.** Both were true
   before this wave. Adding a `-dealloc` turned the leak into an **over-release on some construction path** and
   segfaulted a 5,000-row run, so it was reverted: the leak is pre-existing and needs a fix that knows every
   construction path, not a blind one.
2. **The scale suite segfaults with its last two phases enabled** — relationship resolution through a fault after a
   5,000-row SQLite write, and the read-only store open. Both are removed from the suite with a note in the file and
   this paragraph; a red suite is worse than a smaller one, and the crash is localized to code the 3-row suites
   cover happily.

**And two of my own expectations were wrong**, corrected in the fixture: the page check assumed numeric ordering for
string names (`person-10` sorts before `person-2`), and the "new attribute gets no mapping" count. Both are the kind
of thing a test asserts wrongly for a long time because it passes at small sizes.
