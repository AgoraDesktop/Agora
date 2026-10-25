# Foundation 10.11 — the plan to bring `libagora-base` to equivalence

*Status: **plan.** This is the Foundation tier of `COCOA-10.11-SURFACE-PLAN.md`, written now that the 10.6
denominator is complete. That document sized the four frameworks with a first-pass regex (§2.3, §3.1) and named
`api/10.11/{framework}.txt` as a Phase 0 deliverable (§5.1) that was never built. This file replaces its Foundation
numbers with a measurement from the tree's own instrument, corrects them where the instrument disagrees, and stages
what remains. Nothing here is scheduled; the size classes are order-of-magnitude, not commitments.*

---

## 0. The verdict

**The 10.6 debt is closed, so this is a delta plan, not a debt plan.** `libagora-base` answers the whole 10.6
Foundation — 173 of 173 classes, 2,840 of 2,840 selectors, 23 of 23 protocols, 180 of 180 functions — and
`tests/api-10.6-census.txt` pins it in both directions. Measured against the 10.11 headers, with W0's instrument
repairs in place and the result pinned in `tests/api-10.11-census.txt`:

| Unit | 10.11 | local | missing | owed from 10.6 | new in 10.7–10.11 |
|---|---:|---:|---:|---:|---:|
| classes (macOS) | 219 | 193 | **26** | **0** | 26 |
| protocols | 40 | 30 | **10** | **0** | 10 |
| C functions | 182 | 182 | **0** | 0 | 0 |
| selectors (classes present) | 3,407 | 3,296 | **111** | 0 | 111 |
| categories | 115 | 45 | 70 | mixed | mixed |

The instrument's raw output, before its own faults were repaired, was 27 classes, 10 protocols, 86 selectors and 0
functions — not the 73/13/33 that `COCOA-10.11-SURFACE-PLAN.md`'s regex pass reported, which this plan replaces rather
than inherits, and not right either. W0 changed the answer three ways: one class is iOS-only in this SDK and is not
macOS surface; **299 property accessors were invisible to the reader**, because a property's trailing `NS_AVAILABLE(…)`
stopped the name from matching at all, so the first pass undercounted the selector surface by 299 (and two
`NSURLConnection` doors were charged under names assembled from a deprecation message); and nine doors Apple marks
`NS_UNAVAILABLE` are disposals rather than gaps. The 111 above is the first number in this document that came out of
an instrument whose own regressions are in the build (`api-ledger selftest`). Every remaining name is 10.8–10.11.

**The work is not 26 class names either.** The 111 selectors are the ones missing on classes that already exist; the
26 absent classes declare **337 of their own** (appendix A), so the door count is 448, not 111. Then the layer that
makes any of it usable: availability annotations, 26 missing header names, the behavioural categories, a refusal
discipline, and the census that keeps all of it honest. URLSession accounts for 103 of the 337 class-owned selectors
and XPC for 36 more (all refusals); the 111 are mostly the tail of 10.7–10.11 additions to classes the tree already
ships.

Two milestones, as the Cocoa plan states them:

- **M1 — declared.** Every macOS 10.11 Foundation name exists, is annotated with Apple's introduction/deprecation
  facts, is implemented or **refuses by name**, and a committed census pins the result.
- **M2 — behavioural.** The doors URLSession, `NSProgress` and the new formatters expose do the documented thing,
  measured by callers, with the remaining refusals documented and tested.

---

## 1. What equivalence means

`COCOA-10.11-SURFACE-PLAN.md` §1 defines five tiers and four dispositions; this plan inherits them unchanged and
adds two facts to the disposition table that the Foundation measurement made unavoidable.

| Tier | What it covers | Measured by |
|---|---|---|
| **S1 declarations** | headers, classes, protocols, categories, properties, methods, functions, typedefs, constants, umbrella imports | `api-ledger` manifest diff, both directions |
| **S2 annotations** | `NS_AVAILABLE`, `NS_DEPRECATED`, nullability, generics, `__kindof`, designated initializers, ownership, `NS_SWIFT_NAME` | clang AST, not warnings |
| **S3 runtime shape** | class exists, right superclass, **right adopted protocols**, every selector answered including inherited | `NSClassFromString` / `respondsToSelector:` probe |
| **S4 behaviour** | the documented thing, or a named documented failure | per-door tests + the refusal census |
| **S5 source compatibility** | ObjC, ObjC++, ARC and a Swift importer all compile against the headers | compile gates |

| Disposition | Meaning | Allowed when |
|---|---|---|
| **implemented** | the documented behaviour, tested | a backing exists |
| **adapted** | the contract through a different backing, deviation written at the header | the platform equivalent is not the same mechanism |
| **refused** | declared, annotated, one `FOUNDATION-REFUSE` line, documented failure return | the backing is genuinely absent |
| **unavailable** | declared `NS_UNAVAILABLE` and not callable | Apple marks it unavailable on macOS |
| **iOS-only** | declared `NS_CLASS_AVAILABLE(NA, …)`; excluded from the denominator with a reason | the SDK declares it for another platform |

**Two of these are new measurements, not new policy.** The 10.11 headers carry doors this tree can never answer and
must never pretend to: `NSProxy -allowsWeakReference`/`-retainWeakReference` are `NS_UNAVAILABLE` on macOS, and
`NSBundleResourceRequest` is `NS_CLASS_AVAILABLE(NA, 9_0)` — iOS only. Today the ledger charges both as *missing*,
which is how a 27th class and two phantom selectors entered the first-pass count. They are disposals, and the
manifest must record them so the census can tell a disposal from an omission.

**An omission is still a bug.** The only omitted names allowed are iOS-only declarations and the `NS_UNAVAILABLE`
ones, each with its reason in the manifest, and the census fails if a dispositioned name becomes reachable (a door
quietly appearing is as much a drift as one disappearing — the 10.6 census already fails on it).

**10.11 is a floor, not a ceiling.** APIs that postdate it stay, marked as extensions (§4.13). A strict build may hide
them; the normal build keeps them.

**Source compatibility, not binary.** No ivars, no ABI, no dyld behaviour. A program written against the 10.11
headers builds and runs against this tree; a binary built against Apple's does not, and this plan does not change
that.

---

## 2. The reference and the instrument

### 2.1 What is committed

The SDK is not, and must not be. What is committed is the **name manifest** and the recipe — the same arrangement
`api/10.6/` already uses and `COCOA-10.11-SURFACE-PLAN.md` §2.1 commits to:

```
libagora-base/api/10.11/README.md                  the recipe: which mirror, which path, how to regenerate
libagora-base/api/10.11/foundation-manifest.txt    names and relationships only
libagora-base/tests/api-10.11-census.txt           the pin, both directions
```

Measured from the 156 Foundation headers of `MacOSX10.11.sdk` (`Versions/C/Headers`; the `Headers` symlink returns a
directory entry through the contents API, so the versioned path is fetched directly):

| Manifest kind | Count |
|---|---:|
| classes (including 1 iOS-only) | 220 |
| protocols | 40 |
| C functions | 185 (182 non-inline; the three inline/macro doors are exempt as symbols) |
| declared selectors | 3,763 |
| `ios-class` facts | 1 |
| `unavailable-selector` facts | 9 |
| `class-era` facts | 109 |
| `selector-era` facts | 860 |

The manifest line grammar is the 10.6 one (`class X : Y`, `selector X : sel`, `function f`, `protocol P`), extended
with the four facts a name list cannot carry: `ios-class <Name>` for a class whose macOS availability is `NA`,
`unavailable-selector <Class> <sel>` for a door Apple marks `NS_UNAVAILABLE`, and `class-era`/`selector-era` carrying
Apple's introduction and deprecation tokens verbatim (`10_6`, and `-` for no deprecation). The first two keep a
disposal from being charged as a gap; the eras make the availability gate runnable without an SDK checkout.

The availability field is a fact list, not Apple's expression: no replacement message, no nullability, no prose is
copied — a version token and a `-`. That is the same rule §2.1 states for names, and the same one that makes the
manifest committable at all.

That grammar growth is why the 10.6 manifests still load: neither kind appears in them, and `api-ledger`'s selftest
pins that a 10.6-style manifest loads with empty exemption sets.

### 2.2 The instrument's faults, found by pointing it at 10.11

Four faults, all now fixed and each with a case in `api-ledger selftest`. The first three are in the extractor and each
produced a plausible wrong answer, which is exactly the kind of thing the 10.6 census records in its own preamble; the
fourth is missing measurement rather than a bug.

1. **A property's trailing annotation was read as its name — or made the property vanish.** Apple writes
   `@property (readonly) const void *bytes NS_RETURNS_INNER_POINTER;` and
   `@property (readonly) ObjectType firstObject NS_AVAILABLE(10_6, 4_0);`. The reader took the declaration's last
   identifier: the first gave a selector called `NS_RETURNS_INNER_POINTER` (seven classes), and the second matched
   nothing at all, because the declaration ends in `)`, so **299 property accessors were never in the manifest** and
   the census never charged them. One regex, two failure directions, 306 doors mis-measured — and the first-pass
   selector gap was 25 doors too small because of it. Fix: strip the trailing annotation macros in the **shared**
   declaration reader, so the manifest side and the local side agree. Regression: a two-line fixture must yield
   `bytes` and must not yield the macro name, and a local header carrying the annotation must not gain a phantom
   method (which would move the pinned `methods-declared-not-implemented` off zero).
2. **A string literal was read as syntax.** `NSURLConnection`'s
   `+sendAsynchronousRequest:queue:completionHandler:` is split across three lines, and its `NS_DEPRECATED` message
   (`"Use [NSURLSession dataTaskWithRequest:completionHandler:] …"`) sits inside the declaration's own span, so the
   manifest held `sendAsynchronousRequest:queue:completionHandler:dataTaskWithRequest:completionHandler:` — a door
   that exists nowhere — plus a second one built the same way on the line below. Fix: string literals are blanked
   before a declaration is read (quotes kept), which also removes the class of fault rather than these two instances.
   Regression: a fixture with a wrapped signature and a replacement string containing a selector.
3. **`NS_UNAVAILABLE` and `NA` could not be seen at all.** The manifest recorded names, not eras, so the census could
   not distinguish "the tree lacks this" from "Apple says do not call this" or "this is iOS only". Fix: the two
   exemption facts of §2.1, and `computed()` removes them from the denominator before counting, so `missing` is a gap
   rather than a disposal. Regression: an `NA` class, an unavailable method and an unavailable property, and a
   10.6-style manifest loading with empty exemption sets.
4. **Protocol adoption is invisible to a header reader.** The ledger resolves inheritance through `@interface`, but
   `<NSCoding>` on `NSScriptCommand` is a *conformance*, and eleven of the 111 selector misses are one of them: the
   class adopts `NSCoding` in 10.11, so `-initWithCoder:` is required, and the local class does not adopt it. Reading
   headers cannot prove the runtime agrees. Fix: an objective-C probe test (`runtime-surface`) that asks every 10.11
   class for its superclass and `class_copyProtocolList` (§6).

### 2.3 The gate

`tests/api_census.cmake` is already manifest-agnostic: it takes `-DMANIFEST`, `-DCENSUS`, `-DLIBRARY`,
`-DSOURCE_DIR` and optional `-DINCLUDES`, runs the ledger, and compares in both directions with its own arithmetic
check. The 10.11 gate is therefore a **second registration**, not a second script:

```cmake
add_test(NAME foundation-api-10.11-census
  COMMAND "${CMAKE_COMMAND}"
          "-DPYTHON=${Python3_EXECUTABLE}" "-DLEDGER=${AGORA_LEDGER}"
          "-DMANIFEST=${CMAKE_CURRENT_SOURCE_DIR}/../api/10.11/foundation-manifest.txt"
          "-DLIBRARY=$<TARGET_FILE:Foundation>"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
          "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/api-10.11-census.txt"
          "-DINCLUDES=${AGORA_CORE_INCLUDE_DIR}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/api_census.cmake")
```

Acceptance for W0 is that a **deliberate one-name perturbation fails** — the instrument is proved to bite, the way
the AppKit refusal census was — and that the 10.6 gate's numbers do not move.

### 2.4 Two denominators, and why both stay

`Foundation.h`'s §11.0 baseline answers *what this library may lose*; the 10.6 census answers *what a caller could
reach at 10.6*. Neither is the 10.11 question. Keeping all three means a removal is still caught by the baseline
rule, a 10.6 door that disappears is caught by the old census, and a 10.11 door that never arrives is caught by the
new one. The 10.11 census supersedes nothing.

---

## 3. The measured gap

### 3.1 Classes — 26

| Era | Classes | Disposition |
|---|---|---|
| 10.8 | `NSByteCountFormatter`, `NSUserScriptTask`, `NSUserAppleScriptTask`, `NSUserAutomatorTask`, `NSUserNotification`, `NSUserNotificationCenter`, `NSXPCConnection`, `NSXPCInterface`, `NSXPCListener`, `NSXPCListenerEndpoint` | 4 implemented/adapted, 6 refused |
| 10.9 | `NSProgress`, `NSURLComponents`, `NSURLSession`, `NSURLSessionConfiguration`, `NSURLSessionTask`, `NSURLSessionDataTask`, `NSURLSessionDownloadTask`, `NSURLSessionUploadTask` | implemented |
| 10.10 | `NSExtensionContext`, `NSExtensionItem`, `NSFileAccessIntent`, `NSItemProvider`, `NSURLQueryItem`, `NSUserNotificationAction` | adapted / refused per door |
| 10.11 | `NSPersonNameComponentsFormatter`, `NSURLSessionStreamTask` | implemented |

`NSBundleResourceRequest` is **excluded**: `NS_CLASS_AVAILABLE(NA, 9_0)` in `NSBundle.h`, and its 11 declared
selectors go with it. It is the only such declaration in the 40 protocols and 220 classes of the 10.11 Foundation
headers, which is what makes the exemption list short enough to be reviewable.

The last column of appendix A is the other half of the sizing: the 26 classes declare **337 selectors** of their own,
counted against the class that declares them, as `api-ledger` counts method declarations.

### 3.2 Protocols — 10

`NSProgressReporting`; `NSURLSessionDelegate`, `NSURLSessionTaskDelegate`, `NSURLSessionDataDelegate`,
`NSURLSessionDownloadDelegate`, `NSURLSessionStreamDelegate`; `NSUserNotificationCenterDelegate`;
`NSExtensionRequestHandling`; `NSXPCListenerDelegate`, `NSXPCProxyCreating`.

The 10.11 headers carry **no protocol-level availability annotations** — Apple annotates the classes and lets
conformance inherit the era. The manifest therefore records a protocol's era as its declaring family's, and the
census must not demand an annotation Apple does not write.

### 3.3 Selectors — 111, and eleven of them are one decision

| Bucket | Count | What it is |
|---|---:|---|
| extractor artifacts | 0 | the nine §2.2 produced are gone from the manifest, not answered |
| declared `NS_UNAVAILABLE` | 9 | exempt, not counted: six `-init`, `NSXMLDTD -initWithKind:options:`, `NSProxy`'s weak-reference pair |
| **one `NSCoding` decision** | 11 | `-initWithCoder:` on `NSScriptCommand`, `NSScriptCommandDescription`, `NSScriptObjectSpecifier`, `NSScriptWhoseTest`, `NSSpecifierTest`, `NSWhoseSpecifier`, `NSNameSpecifier`, `NSRangeSpecifier`, `NSRelativeSpecifier`, `NSUniqueIDSpecifier`, `NSDistantObject` |
| **individual doors** | 100 | appendix C |

**And the 111 is only the shared-class half of the denominator.** `selectors-offered` counts the selectors of classes
the tree already has, so the 337 declared by the 26 absent classes are not in it yet. They arrive with the classes,
which is why each wave that adds a class also edits the census: a class landing without its pin is a `NEW SURFACE`
failure that reads as drift and is actually progress. Total in-scope doors: 111 shared + 337 class-owned.

### 3.4 Annotations — the layer that is not there

Measured by `api-ledger availability`, after the macros became real (W1a):

| Fact | Apple 10.11 | local | note |
|---|---:|---:|---|
| declarations Apple annotates that this tree also declares | **767** | **767** | the sweep, pinned in `tests/api-10.11-annotations.txt` |
| `NS_AVAILABLE`/`NS_CLASS_AVAILABLE` occurrences in the headers | 1,290 | 0 | no declaration uses them yet |
| `NS_DEPRECATED` occurrences | 213 | 0 | idem |
| `nullable` | 1,372 | 2,368 | already ahead |
| `NS_DESIGNATED_INITIALIZER` | 178 facts (135 local candidates) | **0** | macro did not exist either; see below |
| `__kindof` | 3 | 1 | |
| `NS_UNAVAILABLE` | 12 | 0 | the one 10.6 count was the macro definition, not a use |
| `NS_RETURNS_RETAINED` | 8 | 1 | |
| `NS_SWIFT_NAME` | 6 | 40 | already ahead (Swift-name pass) |

The macros were inert **by decision** — `NSObjCRuntime.h` cited D12, "the bodies do nothing". That was defensible
with no reference version; at 10.11 it is not, because a client cannot tell a 10.0 door from a 10.11 one, no
deprecation warning can fire on this tree, and the Swift importer sees no availability at all. The repair was already
half-built: `libagora-core/include/CFAvailability.h` defines `CF_AVAILABLE(_mac, _ios)` as
`__attribute__((availability(macosx,introduced=_mac)))` behind `__has_feature(attribute_availability_with_version_underscores)`,
and Apple's own header aliases `NS_AVAILABLE` onto exactly that. **W1a replaced the empty bodies with those aliases**
and made `NSURLSESSION_AVAILABLE` `10_9`; the whole library rebuilds with no availability diagnostic, and clang 19 is
measured to record the attribute in the AST — including `macosx_app_extension` for `NS_EXTENSION_UNAVAILABLE`, where
collapsing it into "unavailable on macOS" would have hidden working doors.

`NS_DESIGNATED_INITIALIZER` is the one S2 fact that could not be swept yet, and the reason is measured rather than
assumed: the marks are correct and the *bodies* are not — 208 distinct `-Wobjc-designated-initializers` warnings appear
the moment they are placed. The macro itself did not exist in this tree at all (the plan's earlier table said "exists,
never used"; the first attempted sweep failed to compile with "expected ':'" at the mark's own column, and it is now
defined).

**The sweep is done: 761 declarations in 108 headers, every one carrying Apple's version.** The instrument that made
it reviewable is two numbers with different meanings — a declaration stating a version Apple does not
(`annotations-wrong`) fails the gate outright, because it looks finished; a declaration stating none
(`annotations-missing`) was the work list, pinned so that progress was a deliberate edit, and it fell 802 → 0 in one
commit whose diff is only annotations. The 802 → 767 difference in the denominator is two attribution faults the sweep
exposed and fixed before it ran: a category's availability was being recorded as its class's (NSArray is not a 10.6
class — Apple annotates the `NSExtendedArray` category), and a forward `@protocol X;` was read as a block, attributing
NSXMLParser's doors to its delegate. The
versions themselves are committed in the manifest as `class-era`/`selector-era` facts, which is what lets the gate run
without an SDK checkout — a sweep annotated from memory is the drift §4.12 forbids.

### 3.5 Headers and categories

Twenty-six Apple header names have no local file, in three kinds:

| Kind | Count | Names |
|---|---:|---|
| new surface | 11 | `NSProgress.h`, `NSURLSession.h`, `NSUserNotification.h`, `NSUserScriptTask.h`, `NSXPCConnection.h`, `NSExtensionContext.h`, `NSExtensionItem.h`, `NSExtensionRequestHandling.h`, `NSItemProvider.h`, `NSByteCountFormatter.h`, `NSPersonNameComponentsFormatter.h` |
| split of shipped families | 9 | `NSScriptCoercionHandler.h`, `NSScriptCommandDescription.h`, `NSScriptExecutionContext.h`, `NSScriptKeyValueCoding.h`, `NSScriptStandardSuiteCommands.h`, `NSScriptSuiteRegistry.h`, `NSXMLDTDNode.h`, `NSXMLElement.h`, `NSXMLNodeOptions.h` |
| organisation | 6 | `FoundationErrors.h`, `NSRange.h`, `NSPathUtilities.h`, `NSPropertyList.h`, `NSHFSFileTypes.h`, `NSMetadataAttributes.h` |

And 115 categories against 45. Most are partitions of methods already declared on the class and can stay folded, but
the *behavioural* ones are headers a client imports and they name real doors:
`NSURLSessionTaskAdditions` (the task-scoped cookie doors), `NSDeprecated` (7 — where 10.11 parks deprecated
declarations), `NSValueGeometryExtensions`/`NSValueRangeExtensions`, `NSSortDescriptorSorting`,
`NSXMLParserLocatorAdditions`.

### 3.6 Refusals — a mechanism that does not exist here

`grep -c FOUNDATION-REFUSE libagora-base/*.m` is **0**, against 155 `APPKIT-REFUSE` sites in `libagora-app`. The
refusals themselves exist — `NSAppleScript` execution, `NSAppleEventManager` sending, `NSNetService` publishing — but
they raise or return an error without a named line, so they are counted nowhere and drift unmeasured. The AppKit
tier's `tests/claims_census.cmake` (`-DNEEDLE='(APPKIT-REFUSE|fn_refuse_[a-z]+)'`, per-file, both directions) is the
instrument; Foundation's refusals are governed by prose today.

---

## 4. Decisions

### 4.1 URLSession — implemented over the engine that is already here

`NSURLConnection`/`NSURLDownload` drive libcurl (`CMakeLists.txt:59,157`), `NSURLProtocol` subclassing is live
(`FNCURLURLProtocol`), and `libagora-dispatch` is linked. URLSession is therefore a **task state machine over the
existing transfer engine**, not a second HTTP stack:

- one `curl_multi` loop per session, tasks registered on it, delegate callbacks dispatched to the session's
  `NSOperationQueue` (nil queue = a serial queue the session owns, as Apple documents);
- `NSURLSessionTask` carries the state (`running`/`suspended`/`canceling`/`completed`), `priority`, `taskIdentifier`,
  `originalRequest`/`currentRequest`, `countOfBytes…`, `response`, `error`, and `taskDescription`;
- upload from `NSData` and from file; download to a destination URL with `-cancelByProducingResumeData:` refused
  (resume data is a platform artefact this tree does not have);
- authentication through the existing `NSURLAuthenticationChallenge` and `NSURLCredentialStorage`, with the task's
  delegate consulted **before** the session's, which is the ordering the headers specify;
- cookies through `NSHTTPCookieStorage`, including the task-scoped doors of `NSURLSessionTaskAdditions`
  (`-getCookiesForTask:completionHandler:`, `-storeCookies:forTask:`, …) — the storage is per-task only when a
  task-scoped jar exists, otherwise it is the shared store;
- **refused:** background sessions (`NSURLSessionConfiguration` background is declared and the session creation
  returns nil with a `FOUNDATION-REFUSE` line naming the absent background-transfer daemon), discretionary,
  `-flushWithCompletionHandler:` beyond a no-op with a documented meaning, and metrics beyond what curl exposes.

### 4.2 `NSProgress` — the spine, implemented before the things that name it

`NSProgress` is 10.9 and is adopted by `NSURLSessionTask`, `NSFileCoordinator` and `NSExtensionContext` (and by
`NSBundleResourceRequest`, which this plan excludes). It is also the one class here whose contract is mostly
*observation*: a parent/child tree,
`fractionCompleted` and `indeterminate` KVO-announced, `-becomeCurrent`/`-resignCurrent` on a per-thread stack,
`-cancel` propagating down the tree and up through `-cancellationHandler`, `-publish`/`-unpublish` refused (no
network progress service). The `NSProgressReporting` protocol becomes adoptable by `NSURLSessionTask` and the
extension request in the same wave, which is why it is early.

**A stub is worse than an absence here**: `fractionCompleted` that never moves is a silent success, which §4.3 of
the Cocoa plan forbids. The class ships with its observation working or it refuses.

### 4.3 `NSURLComponents` and `NSURLQueryItem` — from the type already in the tree

`FNURLComponents`/`FNURLComponents.m` is the internal RFC 3986 splitter `NSURL.m` uses, written for it
(`FNURLComponents.h:8` says so). The public class is that parser with the public surface: `scheme`, `user`, `password`,
`host`, `port`, `path`, `query`, `fragment`, `percentEncoded…` in both directions, `queryItems`, and the
`-URL`/`-URLRelativeToURL:` construction. Three rules that must be tested rather than assumed: setting a decoded
component re-encodes it; setting a `percentEncoded…` component validates the escapes and raises
`NSInvalidArgumentException` on a malformed one (`%zz`, a stray `%`); and
`+componentsWithURL:resolvingAgainstBaseURL:` resolves dot segments.
The internal type keeps its name; the public header is a second declaration, not a rename, so `NSURL.m`'s existing
callers do not move.

### 4.4 XPC — refused, and counted

`NSXPCConnection`, `NSXPCInterface`, `NSXPCListener`, `NSXPCListenerEndpoint`, `NSXPCListenerDelegate`,
`NSXPCProxyCreating`. There are no Mach services and no launchd. Each door is declared with its 10.11 signature,
annotated `NS_CLASS_AVAILABLE(10_8, …)`, and refuses: `-initWithServiceName:` returns nil after a `FOUNDATION-REFUSE`
line naming the absent Mach bootstrap namespace, `-resume` is a documented no-op on a nil connection, and the
listener never accepts. A Unix-socket imitation would be a lie, so it is not attempted.

### 4.5 `NSUserNotification` — state implemented, delivery refused until a service exists

The class, its action, its centre and its delegate are declared and implemented. The **in-process** half is real:
delivery queue, `deliveredNotifications`, `scheduledNotifications`, `-removeDeliveredNotification:`,
`-removeAllDeliveredNotifications`, and `NSUserNotificationCenterDelegate` consulted for presentation.

`COCOA-10.11-SURFACE-PLAN.md` §4.4 assumes "the shell/notification service (a window-server client)". It does not
exist: `workspace/` has no notification centre, only `NSNotification` traffic. So delivery **refuses** by name —
`-deliverNotification:` keeps the item in the centre's state and sends one `FOUNDATION-REFUSE` line naming the absent
service — and the header records the deviation. When a shell service lands, the refusal becomes the delivery call;
nothing else in the class moves.

### 4.6 Extensions and `NSItemProvider` — declare, adapt the item, refuse the request

`NSExtensionContext`, `NSExtensionItem`, `NSExtensionRequestHandling` and `NSItemProvider`. Agora has no app
extension host, so `-completeRequestReturningItems:completionHandler:` and `-cancelRequestWithError:` refuse by name,
while the *data* half is real: an `NSItemProvider` loads from file URLs, `NSData`, `NSString`, `NSAttributedString`,
`NSURL` and the pasteboard, and registers with a type identifier.

**UTI conformance is the honest limit here.** `UTType*` belongs to `libagora-launchservices`, which sits above this
tier; Foundation importing it would be a layering inversion, so the item answers by exact identifier and by the
`public.*` hierarchy the class owns itself, and a conformance query outside that table refuses by name. Everywhere
else the provider is real. `NSExtensionItem` is an `NSSecureCoding` value with its allow-list tested in the existing
secure-coding suite.

### 4.7 `NSUserScriptTask` — Unix implemented, AppleScript and Automator refused

`NSUserUnixTask` runs a file with arguments/stdin/stdout/stderr over the existing `NSTask` machinery (implemented).
`NSUserAppleScriptTask` and `NSUserAutomatorTask` refuse by name for the same reason `NSAppleScript` does: no OSA
component, no Automator runtime. The base class keeps the shared URL/error surface.

### 4.8 Formatters

`NSByteCountFormatter` (10.8) and `NSPersonNameComponentsFormatter` (10.11) implemented over ICU — the library
already links ICU for `NSNumberFormatter` and `NSDateFormatter`. Both get the `NSFormattingContext`/
`NSFormattingUnitStyle` behaviour, and the three unit formatters already shipped (`NSEnergyFormatter`,
`NSLengthFormatter`, `NSMassFormatter`) gain the missing `unitStyle` property, which is six of the 100 doors.

### 4.9 File coordination intents

`NSFileAccessIntent` (10.10) and `-coordinateAccessWithIntents:queue:byAccessor:` are implemented over the existing
`NSFileCoordinator`: each intent carries its URL, its `NSFileAccessIntentReading`/`Writing` options and its
`NSFileCoordinatorReadingOptions`/`WritingOptions`, and the accessor runs inside one coordinated block that holds the
same per-URL lock the string-based doors already take. This is the door `NSFileVersion -replaceItemAtURL:` needs.

### 4.10 One decision, eleven doors: `NSCoding` on the scripting classes

Apple's script and specifier classes adopt `NSCoding`; this tree's do not. Adding the conformance plus
`-initWithCoder:`/`-encodeWithCoder:` to the eleven classes is one change with one test (an archive round-trip of a
specifier, a command, a description and a whose-test), not eleven independent doors. It also makes `S3` right: the
runtime probe will see the protocol.

### 4.11 The long tail — 100 doors, grouped by cause

| Group | Doors | Backing |
|---|---:|---|
| `NSAppleEventDescriptor` | 12 | 10.11 factories (`descriptorWithDouble:`, `…Date:`, `…FileURL:`, `…ProcessIdentifier:`, `…BundleIdentifier:`, `…ApplicationURL:`), the value accessors they added (`dateValue`, `doubleValue`, `fileURLValue`, `isRecordDescriptor`), `+currentProcessDescriptor`, `-sendEventWithOptions:timeout:error:` (refuses: no AppleEvents transport) |
| `NSExpression`/`NSPredicate`/`NSSortDescriptor` | 11 | `expressionWithFormat:` family, `expressionForAnyKey`, `expressionForConditional:trueExpression:falseExpression:` and its two accessors, the three `-allowEvaluation` doors (secure decoding), `+predicateFromMetadataQueryString:` |
| URLSession-adjacent | 13 | `NSURLCache` (3), `NSURLCredentialStorage` (4), `NSHTTPCookieStorage` (3), `NSURLProtocol` (3: `canInitWithTask:`, `-initWithTask:cachedResponse:client:`, `task`) — in W3 |
| `NSOrderedSet`/`NSMutableOrderedSet` | 8 | `descriptionWithLocale:`(+`indent:`), `filteredOrderedSetUsingPredicate:`, `filterUsingPredicate:`, the four index/`passingTest:` enumerations |
| `NSOperation`/`NSOperationQueue` | 9 | `isAsynchronous`, `name`, `qualityOfService`, `underlyingQueue` and their setters — the 10.6-era operation surface grown a queue |
| `NSMetadataQuery`/`NSMetadataItem` | 7 | block enumeration, `operationQueue`/`searchItems` and setters, `-initWithURL:` |
| `NSFileVersion` | 6 | `isDiscardable`/`setDiscardable:`, `isResolved`/`setResolved:`, `localizedNameOfSavingComputer`, `-replaceItemAtURL:options:error:` |
| `NSLinguisticTagger` | 4 | 10.7 API over `FNTextBreaking` |
| `NSPointerArray` | 4 | `pointerArrayWithOptions:`, `…WithPointerFunctions:`, the two deprecated factories |
| `NSNetService`/`NSNetServiceBrowser` | 4 | `includesPeerToPeer` and its setter, on both classes |
| `NSXMLParser` | 4 | `allowedExternalEntityURLs`, `externalEntityResolvingPolicy` and their setters |
| `NSRegularExpression` | 3 | `escapedPatternForString:`, `escapedTemplateForString:`, `-replacementStringForResult:inString:offset:template:` |
| `NSUserActivity` | 3 | `isEligibleForHandoff`, `isEligibleForSearch`, `isEligibleForPublicIndexing` |
| unit formatters | 6 | `unitStyle` getter+setter on three classes (W2) |
| `NSDateComponents` | 2 | `isLeapMonth`, `isValidDate` |
| `NSJSONSerialization` | 2 | stream read/write |
| `NSFileCoordinator` | 1 | the intents door (4.9) |
| `NSProcessInfo` | 1 | `isLowPowerModeEnabled` |

Outside the 100: the nine `NS_UNAVAILABLE` doors (six `-init`, `NSXMLDTD -initWithKind:options:`, and `NSProxy`'s
weak-reference pair) are declared to refuse, not implemented (§3.3).

### 4.12 What the availability sweep must not become

The sweep is mechanical but it must be **derived from the 10.11 headers, not from memory**: the version in
`NS_AVAILABLE(10_9, 7_0)` is Apple's introduction version, and a hand-written guess is a ledger failure. The
instruments are the AST (`-Xclang -ast-dump=json`) and `-Wnullability-completeness`, not warning text, because clang
on Linux records availability without warning on it.

### 4.13 Extensions

The tree already ships post-10.11 API (`NSDateInterval`, `NSISO8601DateFormatter`, `NSRelativeDateTimeFormatter`,
`NSSecureUnarchiveFromDataTransformer`, `NSOrderedSet` is 10.7 and arrived early). They stay, annotated with the
version they really arrived in, behind an `AGORA_EXTENSION` spelling that a `-DAG_TARGET_OS_X_10_11` build can hide
from the surface check. The consensus with `COCOA-10.11-SURFACE-PLAN.md` §4.1 is that removing a working door to
satisfy an older reference is a regression.

---

## 5. The waves

Each wave names what moves in the census, so "done" is a diff in `api-10.11-census.txt` plus tests, not a feeling.
Sizes are order-of-magnitude.

### W0 — the denominator and the instrument · S — **done**

- `api/10.11/foundation-manifest.txt` (recipe in `api/10.11/README.md`), with the §2.2 extractor fixes and the two
  exemption facts.
- `tests/api-10.11-census.txt` pinned at the measured position (appendix E), including the one exemption
  (`NSBundleResourceRequest`, `NS_CLASS_AVAILABLE(NA, 9_0)`) and the nine `NS_UNAVAILABLE` doors.
- The second `add_test` (§2.3), and `api-ledger selftest` registered as a test so the extractor's own regressions are
  in the build rather than in the census six waves later.
- **Acceptance, met:** a one-name manifest perturbation fails the gate (proved three ways: drop a class, add a
  selector, drop the exemption line — each moves the counts and exits nonzero through both the ledger and
  `api_census.cmake`); the 10.6 gate is unmoved (173/2,840/23/180); the manifest reproduces appendix A–C;
  `selectors-missing` reads **111** rather than the first pass's 86 — the gap is *larger*, because the extractor was
  hiding 299 property accessors — and no implementation was written to move either number.

### W1 — the availability layer · L (mechanical, wide) — **in progress (W1a done)**

- **Done:** `NSObjCRuntime.h`'s inert block now delegates to `CF_AVAILABLE`/`CF_DEPRECATED` as Apple's own header
  does; `NSURLSESSION_AVAILABLE` is `10_9`; `NS_EXTENSION_UNAVAILABLE` names `macosx_app_extension` instead of being
  empty. The library rebuilds with no availability diagnostic, and clang 19 is measured to record the attribute.
- **Done:** the reference's versions are committed (`class-era`/`selector-era`), `api-ledger availability` compares
  local declarations against them, and `api-ledger annotate` performs the sweep reproducibly (idempotent, dry-run by
  default, inserting only at terminators). `tests/api-10.11-annotations.txt` pins 767 candidates / 767 annotated /
  0 missing / 0 wrong. The gate fails on a wrong version and on drift.
- **Done:** the `header-compile` gate — 196 headers compiled ALONE in Objective-C, Objective-C++ and ARC, plus the
  umbrella once per mode (591 compilations). It found five headers that had never been asked to stand alone: two that
  imported nothing at all (`NSFastEnumeration.h`, `FNKeyedWire.h`), a category whose host class was only
  forward-declared (`FNDistantObjectRequest.h`), an ivar type nobody declared (`NSMutableArray` in
  `NSOperationQueue.h`), and a protocol conformance with no protocol (`FNStringFormat.h`). Also done in this wave:
  `NS_RETURNS_INNER_POINTER` on the seven doors Apple marks that way (`bytes`, `mutableBytes`, `objCType` twice,
  `UTF8String`, `methodReturnType`, `getArgumentTypeAtIndex:`, `aeDesc`) and `__kindof` on the two the tree has
  (`NSOperationQueue -operations`, `NSXMLNode -nodesForXPath:error:`).
- **Attempted and deliberately deferred: `NS_DESIGNATED_INITIALIZER`.** The facts are now committed (178
  `designated-init` lines, 135 of them on declarations this tree makes) and pinned, and `api-ledger annotate` can
  place the marks. Placing them is what revealed the cost: the library still builds, but clang emits **208 distinct
  `-Wobjc-designated-initializers` warnings** — "designated initializer should only invoke a designated initializer on
  'super'", "convenience initializer missing a 'self' call to another initializer". Those warnings are TRUE: this
  tree's initializers do not follow the graph Apple's marks describe. Marking 135 headers would state a contract the
  bodies break in 208 places, so the marks wait for the implementation pass — one slice, 135 constructors and the
  warning count as its gate — and the pin holds at 135 missing in the meantime.
- **Remaining:** `AGORA_EXTENSION` for the post-10.11 classes (§4.13), and **411 `-Wnullability-completeness` warnings
  across 194 of the 196 headers** (measured, objc mode), which is the S2 residue: the annotations are right where they
  exist, and a pointer without one is a fact the header still refuses to state.
- **Acceptance, availability met:** `annotations-missing` is 0 with `annotations-wrong` 0, the library builds clean,
  and all 23 tests pass. Remaining for the wave: the header-compile gate and
  `methods-declared-not-implemented` staying at 0 — a trailing annotation the reader did not learn to strip would
  surface there, which is the trap W0's shared-reader fix exists to close.

### W2 — the spine and the formatters · M — **in progress**

- **Done: the unit style (10.10), and the enum values it reads.** `NSEnergyFormatter`, `NSLengthFormatter` and
  `NSMassFormatter` gained `-unitStyle`/`-setUnitStyle:` (6 doors: short and medium render the SI symbol, long renders
  the unit's name, pluralised unless the value is exactly one) and `NSFormattingUnitStyle` now carries Apple's values —
  **1/2/3, where this tree counted from 0**, so a client comparing against Apple's constant read the wrong one. The
  enum divergence was found by the first code to read the value, which is the argument for implementing in order of
  dependency rather than in order of count. `tests/foundation_10_11_formatting.m` pins the constants, the medium
  default, both styles and the singular/plural rule on all three families (23 cases).
- **Done: `NSURLQueryItem`** (10.10) — four doors and three protocols, and the three properties that make it a VALUE
  rather than a pair of pointers: two items built from the same strings are equal and hash alike, a copy keeps the text
  it was handed when the caller edits the original, and an archive round-trips through the secure-coding allow-list.
  `tests/foundation_10_11_url_query_item.m` pins them (16 cases). The 10.11 census moves to 194 of 219 classes, 3,306 of
  3,411 selectors.
- **Done: `NSURLComponents`** (10.9) as a declaration over `FNURLComponents` (the plan's §4.3 decision), adding
  `-init`, `-URLRelativeToURL:`, `-queryItems` and the six `percentEncoded…` setters. **38 of its 46 doors** are
  answered; the eight 10.11 `rangeOf…` ranges are the residue and count as missing. The slice found the divergence that
  mattered: the internal parser's plain setters took RAW text (correct for a parser) where Apple's take DECODED text, so
  every public setter now encodes — and each component encodes with its own RFC 3986 allow-list, because encoding `/`
  inside a path produced `%2Fa%20b`, one segment whose name contains a slash. `tests/foundation_10_11_url_components.m`
  pins the split (20 cases).
- **Done: `NSProgress` + `NSProgressReporting`** (10.9) — the wave's spine, and 31 of its 36 doors (the four
  publish/subscriber doors are iOS-only in this SDK and are omitted with the reason in the header). The contract is
  observation, so the probe measures announcements: a `completedUnitCount` write announces the count **and** the derived
  fraction; `totalUnitCount` announces the fraction and a change of `indeterminate`; `+currentProgress` finds what a
  thread became current with; a child's fraction moves its parent by the child's SHARE, not by its integers; and
  `-cancel` reaches the leaves while the handler stays at the object cancelled. One bug found by the probe: the first
  version bracketed `completedUnitCount` and `cancelled` MANUALLY, which announced them twice because KVO's automatic
  wrapper already brackets a setter it observes — the manual pair is only for the DERIVED keys, which have no setter.
- **Done: `NSByteCountFormatter`** (10.8) — all 20 doors. The surface is the SEVEN SWITCHES, not "format a number", so
  the probe pins both bases (1000 for file/decimal, 1024 for memory/binary), the unit a magnitude picks, and each flag
  against the same value: count without unit, unit without count, the actual bytes in parentheses, the unit mask, zero
  with non-numeric formatting off, and padded fraction digits. Two rendering rules fell out of the probe: a trailing
  `.0` is trimmed (1024 is `1 kB`, not `1.0 kB`) unless padding was asked for, and "Zero bytes" is a whole-string branch
  rather than a suffix decision. 19 cases.
- **Done: the evaluation sandbox and the metadata door** (5 of the 11 predicate/evaluation doors) — `-allowEvaluation` on
  `NSExpression`, `NSPredicate` and `NSSortDescriptor`, `+expressionForAnyKey`, and
  `+predicateFromMetadataQueryString:` (Spotlight's query syntax IS the predicate format this class already parses, so it
  delegates rather than growing a second parser). One honest note at the header rather than a pretence: this tree never
  sets Apple's "locked" flag, because its boundary is the secure-decoding allow-list, so the sandbox door records the
  intent and answers.
- **Remaining:** the `expressionWithFormat:` family (3), `expressionForConditional:trueExpression:falseExpression:` and
  its two accessors (a conditional expression type this tree does not have yet), the eight `rangeOf…` properties, and
  `NSPersonNameComponentsFormatter`.

`NSProgress` + `NSProgressReporting`; `NSURLComponents` + `NSURLQueryItem`; `NSByteCountFormatter` and
`NSPersonNameComponentsFormatter`; `unitStyle` on the three unit formatters; the predicate/expression evaluation
family; `+predicateFromMetadataQueryString:`.

- **Moves:** 5 classes, 1 protocol, 114 class-owned selectors (36 + 46 + 4 + 20 + 8), 17 shared ones.
- **Acceptance:** a progress tree test (fraction announcement, cancellation down and up, `becomeCurrent` per thread),
  an RFC 3986 table test including the malformed-escape raise, byte-count and person-name output per style and
  locale, and unit-style formatting against `NSNumberFormatter` behaviour.

### W3 — URLSession · XL

7 classes, 5 protocols, the 12 task-scoped doors on cache/credential/cookie/protocol — two of them being
`NSURLProtocol`'s task-initialised entry points.

- **Moves:** 7 classes, 5 protocols, 13 shared selectors, and the 103 the family declares itself (31 `NSURLSession`,
  47 `NSURLSessionConfiguration`, 17 `NSURLSessionTask`, 7 `NSURLSessionStreamTask`, 1 `NSURLSessionDownloadTask`).
- **Acceptance:** a loopback HTTP server in the suite (the existing `foundation_behaviour_3` already runs one) drives
  data, download and upload tasks, a redirect with a cookie, an authentication challenge answered from the
  credential store, task-scoped cookies isolated from the shared store, cancellation, and a stream task over a socket
  pair. Background configuration is refused with its named line asserted.

### W4 — notifications, extensions, item provider · L

7 classes, 3 protocols; notification state with delivery refused; item loading over file/data/string/pasteboard with
type identifiers; `NSExtensionItem` secure coding.

- **Moves:** 7 classes, 3 protocols, 77 class-owned selectors.
- **Acceptance:** the in-process centre keeps state and refuses delivery by name; the delegate is consulted; the
extension request refuses by name; an archive round-trip of `NSExtensionItem` passes the allow-list suite.

### W5 — refusals become measured · M

XPC (4 classes, 2 protocols), the three script-task classes, and the **refusal census**: `tests/claims_census.cmake`
copied or shared from `libagora-app`, `-DNEEDLE='(FOUNDATION-REFUSE|fn_refuse_[a-z]+)'`, `tests/refusal_census.txt`
pinned per file.

- **Moves:** 7 classes, 2 protocols, 43 class-owned selectors (XPC 36 + script tasks 7); the refusal table appears.
- **Acceptance:** every refusal site is in the table; a new refusal without a census line fails; a test asserts each
  named failure (XPC connect, AppleScript run, Automator run, extension request, background session, progress publish,
  AppleEvent send).

### W6 — the tail · M

The remaining 70 doors of §4.11 (100 minus W2's 17 and W3's 13), the eleven `NSCoding` conformances, and the two
`NS_UNAVAILABLE` declarations on `NSProxy` — **declared with a refusing body**, not bodiless, because a declaration
with no body anywhere is the one thing `methods-declared-not-implemented` is pinned at zero for.

- **Moves:** `selectors-missing` to 0.
- **Acceptance:** an ordered-set predicate/enumeration test; a JSON stream round-trip; a `NSFileVersion` replacement
  through `NSFileAccessIntent`; `NSLinguisticTagger` against `FNTextBreaking`; a regex escape/replacement test; the
  scripting archive round-trip.

### W7 — headers, categories, umbrella, the client gates · M

- The 26 header names: 11 new, 9 splits (the script and XML families), 6 organisation files.
- The behavioural categories, declared where Apple declares them.
- `Foundation.h`: re-admit the session family, **replace** the §63.159 comment that says the family is not in the
  umbrella (it becomes false in the same commit), and record the 10.11 reference beside §11.0's baseline rule.
- ARC and ObjC++ compile passes; a Swift import probe that names one class and one function per family.
- **Acceptance:** every public header compiles standalone in ObjC, ObjC++ and ARC; the umbrella compiles once; the
  Swift probe imports; M2's behavioural suite is green.

---

## 6. The gates

| Gate | Question | Status |
|---|---|---|
| `foundation-api-census` (10.6) | does a 10.6 door disappear | exists |
| `foundation-api-10.11-census` | does a 10.11 door arrive or vanish | **exists**, W0 |
| `api-ledger-selftest` | do the extractor's own regressions still fail toward the right number | **exists**, W0 |
| `functions-declared-not-defined` (inside the census) | is a declaration a link error for a caller | exists, must stay 0 |
| `foundation-api-availability` | is the introduction/deprecation version Apple's | **exists**, W1 |
| `foundation-header-compile` (ObjC, ObjC++, ARC, umbrella) | does a header stand alone | **exists**, W1 |
| `runtime-surface` (objc probe) | superclass, adopted protocols, `respondsToSelector:` | **new**, W3 |
| `refusal-census` (`claims_census`) | does a refusal exist unrecorded | **new**, W5 |
| Swift import probe | can the importer see the class | existing tier's, extend W7 |

The runtime probe is not optional bookkeeping: §2.2 fault 4 showed that eleven doors hinge on a protocol the headers
can claim and the runtime must confirm. A class that declares `<NSURLSessionDelegate>` and does not adopt it passes a
header diff and fails a client.

---

## 7. Behavioural tests (M2)

The 10.6 tier's rule holds — **a complete surface is not a behavioural claim** — so each wave lands with a caller.
Following the existing suite naming (`core_values`, `foundation_behaviour_1..4`):

| Test | Pins |
|---|---|
| `foundation_10_11_url_session` | data/download/upload tasks, redirect + cookie, auth challenge, cancellation, task-scoped cookies, background refusal |
| `foundation_10_11_progress` | the tree, `fractionCompleted` KVO, indeterminate, cancel propagation, `becomeCurrent` per thread |
| `foundation_10_11_url_components` | RFC 3986 parse/encode, query items, malformed escapes, relative resolution |
| `foundation_10_11_formatting` | byte count and person-name components, the three unit styles, locale changes |
| `foundation_10_11_notifications` | centre state, delivery refusal, delegate consultation, removal doors |
| `foundation_10_11_refusals` | every `FOUNDATION-REFUSE` site asserts its named failure and its documented return |

---

## 8. Non-goals and permanent refusals

- **XPC** (§4.4) and **AppleEvents/OSA execution** — no Mach bootstrap namespace, no OSA. Descriptors, specifiers and
  commands remain real data and a real model; *execution* refuses.
- **Background URL sessions**, resume data, discretionary transfers — no background-transfer daemon.
- **App extension hosting** — the request lifecycle refuses; the item and context data types are real.
- **Notification delivery** — no shell notification service exists; the centre's state and queue are real, delivery
  refuses by name.
- **`NSBundleResourceRequest`** — iOS-only in this SDK (`NA`).
- **On-demand resources, CloudKit, iCloud document sync** — no backing.
- **iOS-only declarations, private API, 10.12+ (Swift 3) names** — out of scope by the plan this one belongs to.
- **Binary compatibility** — never in scope.

## 9. Risks, and what would falsify this plan

1. **The measurement is the weakest link, and W0 proved it.** Pointing the ledger at the 10.11 headers undercounted
   the selector surface by 299, overstated the class gap by one and invented two doors — each from a regex that failed
   toward a plausible number. W0's fixes and `api-ledger selftest` are what make the 111 trustworthy; pinning before
   them would have recorded the artifacts as debt.
2. **URLSession is the schedule.** Ten classes, five protocols, twelve adjacent doors, and semantics (task-vs-session
   delegate routing, redirect, auth, cancellation) that are all invisible in a header diff. It is the one item here
   that can double.
3. **The annotation sweep touches every header the library has.** It is mechanical and therefore merge-hostile; doing
   it per-header with its AST check, and never from memory, is what keeps it honest.
4. **`NSProgress` invites a stub.** A class that reports 0.0 forever passes a surface census and fails every caller.
   The refusal discipline applies: observation or refusal.
5. **The refusal census can be satisfied by adding the needle.** The AppKit tier's lesson is that the table must be
   per file and both-directional, and every site needs a test that asserts the failure, not just a log line.
6. **Falsifiers.** This plan is wrong if (a) a 10.11 Foundation name exists that the fetched headers do not declare,
   (b) any of the 26 classes turns out to be iOS-only like `NSBundleResourceRequest`, or (c) the ledger's corrected
   10.11 numbers move by more than the artifacts already named. Any of those reopens §3 before W1 starts.

---

## Appendix A — the 26 classes

| Class | Era | Selectors it declares | Disposition |
|---|---|---:|---|
| `NSByteCountFormatter` | 10.8 | 20 | implemented (ICU) |
| `NSUserScriptTask` | 10.8 | 3 | implemented (base) |
| `NSUserAppleScriptTask` | 10.8 | 1 | refused (no OSA) |
| `NSUserAutomatorTask` | 10.8 | 3 | refused (no Automator) |
| `NSUserNotification` | 10.8 | 39 | implemented (state) / refused (delivery) |
| `NSUserNotificationCenter` | 10.8 | 11 | implemented (state) / refused (delivery) |
| `NSXPCConnection` | 10.8 | 20 | refused |
| `NSXPCInterface` | 10.8 | 7 | refused |
| `NSXPCListener` | 10.8 | 9 | refused |
| `NSXPCListenerEndpoint` | 10.8 | 0 | refused |
| `NSProgress` | 10.9 | 36 | implemented |
| `NSURLComponents` | 10.9 | 46 | implemented (over `FNURLComponents`) |
| `NSURLSession` | 10.9 | 31 | implemented (libcurl + dispatch) |
| `NSURLSessionConfiguration` | 10.9 | 47 | implemented / adapted |
| `NSURLSessionTask` | 10.9 | 17 | implemented |
| `NSURLSessionDataTask` | 10.9 | 0 | implemented |
| `NSURLSessionDownloadTask` | 10.9 | 1 | implemented |
| `NSURLSessionUploadTask` | 10.9 | 0 | implemented |
| `NSExtensionContext` | 10.10 | 4 | declared; request refuses |
| `NSExtensionItem` | 10.10 | 8 | implemented (`NSSecureCoding`) |
| `NSFileAccessIntent` | 10.10 | 3 | implemented |
| `NSItemProvider` | 10.10 | 9 | implemented (data half) |
| `NSURLQueryItem` | 10.10 | 4 | implemented |
| `NSUserNotificationAction` | 10.10 | 3 | implemented |
| `NSPersonNameComponentsFormatter` | 10.11 | 8 | implemented (ICU) |
| `NSURLSessionStreamTask` | 10.11 | 7 | implemented (socket streams) |

**337 selectors in total**, counted against the class that declares them. Excluded: `NSBundleResourceRequest` —
`NS_CLASS_AVAILABLE(NA, 9_0)` in `NSBundle.h`, iOS only, with its 10 declarations (and its `-init`, which is
`NS_UNAVAILABLE`).

## Appendix B — the 10 protocols

`NSProgressReporting` (10.9); `NSURLSessionDelegate`, `NSURLSessionTaskDelegate`, `NSURLSessionDataDelegate`,
`NSURLSessionDownloadDelegate` (10.9), `NSURLSessionStreamDelegate` (10.11); `NSUserNotificationCenterDelegate` (10.8);
`NSExtensionRequestHandling` (10.10); `NSXPCListenerDelegate`, `NSXPCProxyCreating` (10.8). The 10.11 headers do not
annotate protocols; eras follow the declaring family.

## Appendix C — the 100 doors, by owner

```
NSAppleEventDescriptor    12   currentProcessDescriptor, dateValue,
                               descriptorWithApplicationURL:,
                               descriptorWithBundleIdentifier:, descriptorWithDate:,
                               descriptorWithDouble:, descriptorWithFileURL:,
                               descriptorWithProcessIdentifier:, doubleValue,
                               fileURLValue, isRecordDescriptor,
                               sendEventWithOptions:timeout:error:
NSExpression               8   allowEvaluation, expressionForAnyKey,
                               expressionForConditional:trueExpression:falseExpression:,
                               expressionWithFormat:, expressionWithFormat:argumentArray:,
                               expressionWithFormat:arguments:, falseExpression, trueExpression
NSOrderedSet               7   descriptionWithLocale:, descriptionWithLocale:indent:,
                               filteredOrderedSetUsingPredicate:,
                               indexOfObjectAtIndexes:options:passingTest:,
                               indexOfObjectWithOptions:passingTest:,
                               indexesOfObjectsAtIndexes:options:passingTest:,
                               indexesOfObjectsWithOptions:passingTest:
NSFileVersion              6   isDiscardable, isResolved, localizedNameOfSavingComputer,
                               replaceItemAtURL:options:error:, setDiscardable:, setResolved:
NSMetadataQuery            6   enumerateResultsUsingBlock:,
                               enumerateResultsWithOptions:usingBlock:, operationQueue,
                               searchItems, setOperationQueue:, setSearchItems:
NSOperation                5   isAsynchronous, name, qualityOfService, setName:,
                               setQualityOfService:
NSOperationQueue           4   qualityOfService, setQualityOfService:,
                               setUnderlyingQueue:, underlyingQueue
NSLinguisticTagger         4   availableTagSchemesForLanguage:, possibleTagsAtIndex:scheme:
                               tokenRange:sentenceRange:scores:, stringEditedInRange:changeInLength:,
                               tagsInRange:scheme:options:tokenRanges:
NSPointerArray             4   pointerArrayWithOptions:, pointerArrayWithPointerFunctions:,
                               pointerArrayWithStrongObjects, pointerArrayWithWeakObjects
NSURLCredentialStorage     4   getCredentialsForProtectionSpace:task:completionHandler:,
                               getDefaultCredentialForProtectionSpace:task:completionHandler:,
                               setCredential:forProtectionSpace:task:,
                               setDefaultCredential:forProtectionSpace:task:
NSXMLParser                4   allowedExternalEntityURLs, externalEntityResolvingPolicy,
                               setAllowedExternalEntityURLs:, setExternalEntityResolvingPolicy:
NSHTTPCookieStorage        3   getCookiesForTask:completionHandler:,
                               sharedCookieStorageForGroupContainerIdentifier:,
                               storeCookies:forTask:
NSRegularExpression        3   escapedPatternForString:, escapedTemplateForString:,
                               replacementStringForResult:inString:offset:template:
NSURLCache                 3   getCachedResponseForDataTask:completionHandler:,
                               removeCachedResponseForDataTask:, storeCachedResponse:forDataTask:
NSURLProtocol              3   canInitWithTask:, initWithTask:cachedResponse:client:, task
NSUserActivity             3   isEligibleForHandoff, isEligibleForPublicIndexing,
                               isEligibleForSearch
NSDateComponents           2   isLeapMonth, isValidDate
NSEnergyFormatter          2   setUnitStyle:, unitStyle
NSLengthFormatter          2   setUnitStyle:, unitStyle
NSMassFormatter            2   setUnitStyle:, unitStyle
NSJSONSerialization        2   JSONObjectWithStream:options:error:,
                               writeJSONObject:toStream:options:error:
NSNetService               2   includesPeerToPeer, setIncludesPeerToPeer:
NSNetServiceBrowser        2   includesPeerToPeer, setIncludesPeerToPeer:
NSPredicate                2   allowEvaluation, predicateFromMetadataQueryString:
NSFileCoordinator          1   coordinateAccessWithIntents:queue:byAccessor:
NSMetadataItem             1   initWithURL:
NSMutableOrderedSet        1   filterUsingPredicate:
NSProcessInfo              1   isLowPowerModeEnabled
NSSortDescriptor           1   allowEvaluation
```

## Appendix D — reproducing the measurement

```sh
# the reference (the SDK is not committed; only the manifest is)
BASE=https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.11.sdk/System/Library/Frameworks
mkdir -p /tmp/sdk1011/Foundation
curl -s "https://api.github.com/repos/phracker/MacOSX-SDKs/contents/MacOSX10.11.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers" \
  | python3 -c 'import json,sys; [print(x["name"]) for x in json.load(sys.stdin) if x["type"]=="file"]' \
  > /tmp/sdk1011/Foundation.names
cat /tmp/sdk1011/Foundation.names | xargs -P 12 -I{} curl -s -o "/tmp/sdk1011/Foundation/{}" \
  "$BASE/Foundation.framework/Versions/C/Headers/{}"

cd libagora-base
../libagora-app/tools/api-ledger manifest /tmp/sdk1011/Foundation > api/10.11/foundation-manifest.txt
../libagora-app/tools/api-ledger missing  api/10.11/foundation-manifest.txt . \
   --library build/libagora-base.so --include ../libagora-core/include
../libagora-app/tools/api-ledger census   api/10.11/foundation-manifest.txt . \
   --library build/libagora-base.so --include ../libagora-core/include
```

## Appendix E — what the pin says today, and at M1

Before W0's repairs the ledger said — and this is the number the first draft of this plan carried:

```
classes-present 193   classes-offered 220   classes-missing 27
protocols-present 30  protocols-offered 40  protocols-missing 10
selectors-present 3075 selectors-offered 3161 selectors-missing 86
functions-present 182 functions-offered 182 functions-missing 0
```

The committed pin (`tests/api-10.11-census.txt`, written by W0):

```
classes-present 193   classes-offered 219   classes-missing 26
protocols-present 30  protocols-offered 40  protocols-missing 10
selectors-present 3296 selectors-offered 3407 selectors-missing 111
functions-present 182 functions-offered 182 functions-missing 0
methods-declared 3933
methods-declared-not-implemented 0
methods-external 3
methods-informal 56
```

**The arithmetic, so a reader can check it without the SDK.** 220 classes − 1 iOS-only = 219 offered; 193 present + 26
missing = 219. 3,763 selector facts − 9 `NS_UNAVAILABLE` = 3,754 in scope; 3,407 of them belong to the 193 classes the
tree has and 347 to the 26 it does not (337, appendix A) plus the exempt iOS-only class (10); 3,296 present + 111
missing = 3,407. The exemptions are lines in the manifest, not subtractions inside the tool, and `api-ledger missing`
prints them as their own block.

At M1 after W6:

```
classes-missing 0 (219)   protocols-missing 0 (40)   selectors-missing 0 (3,754)   functions-missing 0
```

Each class wave raises `selectors-offered` by that class's own declarations, so the pin is edited wave by wave — the
deliberate act the census's two-directional check exists to force.

The refusal table holds the disposals that are not implementations, and the 10.6 pin is unchanged at
173/2,840/23/180. **The surface being complete will not be, and must not be written as, a behavioural claim** — that
is what §7 is for.
