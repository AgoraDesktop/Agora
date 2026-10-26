# W7 — headers, categories, umbrella, the client gates — COMPLETE (M2 followed and is also complete)

*M2 is done: see `FOUNDATION-10.11-M2-HANDOFF.md`. The "what M2 inherits" section below is the state at W7's end.*

*The surface is complete (W6) and it now has Apple's names, Apple's categories, one umbrella and three client gates
(W7). This file records what moved, what was measured, the one deliberate deviation, and what M2 inherits.*

## 1. Where the tree is

**45 libagora-base suites green; every gate green.**

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | **219 of 219 classes, 3,744 of 3,744 selectors, 40 of 40 protocols, 182 of 182 functions** |
| `foundation-api-census` (10.6) | `methods-declared` **4,376**, not-implemented 0 |
| `foundation-api-availability` | **917/917**, 0 wrong · designated 140 of 158 present, 18 missing (the number cluster), extra 2 |
| `foundation-header-compile` | **226 headers alone in ObjC, ObjC++ and ARC, plus the umbrella in each — 681 compilations, 0 failures** |
| `foundation-header-nullability` | the same set, 0 missing specifiers |
| `foundation-refusal-census` | **54** sites over eight files, both directions |
| Swift import probe | `agora-import-probe`: **22/22 family checks pass** |

`api-ledger missing` prints zero in every column, and `api-ledger check` holds all 629 half-pinned metrics.

## 2. What landed

| Batch | Work | Evidence |
|---|---|---|
| **W7a** | 17 header names: `NSExtensionContext.h`, `NSExtensionRequestHandling.h`; `NSScriptCommandDescription.h`, `NSScriptSuiteRegistry.h`, `NSScriptStandardSuiteCommands.h`, `NSScriptExecutionContext.h`, `NSScriptCoercionHandler.h`, `NSScriptKeyValueCoding.h`, a real `NSObjectScripting.h`; `NSXMLNodeOptions.h`, `NSXMLElement.h`, `NSXMLDTDNode.h`; `FoundationErrors.h`, `NSRange.h`, `NSPathUtilities.h`, `NSPropertyList.h`, `NSHFSFileTypes.h`, `NSMetadataAttributes.h` | no census movement: every moved declaration keeps its owner, selector and era |
| **W7b** | the behavioural categories: `NSValueGeometryExtensions` in `NSGeometry.h` (and the dependency now runs Apple's way), `NSValueRangeExtensions` in `NSRange.h`, `NSSortDescriptorSorting`, `NSXMLParserLocatorAdditions`; `NSURLSessionTaskAdditions` already Apple's shape | header gates |
| **W7c** | `Foundation.h` re-admits the session family (§63.159 reversed, the two-denominator rule stated in its place), notifications, XPC, extensions, item providers, script tasks, and every header W7 created | umbrella compiles in all three modes; Swift probe |
| **W7d** | the client gates: header compile/nullability over 226 headers, and the Swift probe extended to one class + one function/constant per family | 681/681 compilations, 22/22 Swift checks |

## 3. What a later reader will want, because these were choices

- **The moved declarations are MOVES, not copies** (with one exception): `FoundationErrors.h` really owns the numeric
  codes now, and the component's own files that had relied on `NSError.h`'s reach import it explicitly — Apple's
  arrangement, and the reason a file that names a code imports the header that declares it. The exception is the
  `NSStringPathExtensions` category in `NSPathUtilities.h`: the path doors also stay declared on `NSString` in
  `NSString.h`, because a source file importing only `NSString.h` has always been able to call them. Identical
  declarations are one door to the compiler and the ledger.
- **`NSValue.h` no longer imports `NSGeometry.h`.** The geometry category needed `NSValue`, and `NSValue` needed
  `NSGeometry`'s types; moving the doors made the dependency one-way, which is Apple's direction. `NSValue.m` and
  `NSKeyedArchiver.m` import `NSGeometry.h`/`NSRange.h` for the implementations.
- **`NSMetadataAttributes.h` is a SUBSET, and says so**: the seven kMDItem names this provider observes, now public
  constants with Apple's values (`"kMDItemFSName"`, …). They were private statics in `NSMetadata.m`; a caller composing
  a metadata predicate could not name them.
- **The umbrella's session-family paragraph is a REPLACEMENT, not a deletion.** §63.159 removed the family against a
  baseline that was the wrong question; the new text keeps both rules beside each other so a future removal is checked
  against the rule that governs it.
- **The one deliberate deviation: the `NSDeprecated` partition categories are NOT carved out.** The seven headers Apple
  uses could not be re-derived without the SDK, and deprecation is already on every declaration and pinned by
  `foundation-api-availability`; guessing the wrong seven would claim a fidelity this tree cannot check. What the plan
  asked for that IS observable — a client-facing category for doors a caller imports — is in W7b.
- **The Swift probe records two toolchain faults rather than hiding them**: `NSDecimalIsNotANumber` crashes this
  swiftsharp frontend's type-checker on the const-pointer-to-struct (so the decimal family is checked by class), and
  `NSPointerFunctionsStrongMemory` imports as a plain `Int`.

## 4. What M2 inherits

M2 is behaviour, and W6's callers are its pattern. The plan's §7 names six suites; five exist under those names or
close to them:

| Planned | State |
|---|---|
| `foundation_10_11_url_session` | exists — data/download/upload, redirect + cookie, cancellation, task lists |
| `foundation_10_11_progress` | exists — the tree, fraction KVO, indeterminate, cancel propagation, per-thread current |
| `foundation_10_11_url_components` | exists — parse/encode, query items, malformed escapes, relative resolution |
| `foundation_10_11_formatting` | exists — byte count, person-name components, the three unit styles |
| `foundation_10_11_notifications` | exists as `foundation_10_11_user_notification` — centre state, delivery refusal, delegate |
| `foundation_10_11_refusals` | **NOT WRITTEN** — every `FOUNDATION-REFUSE` site asserting its named failure |

So M2's remaining work is small and named: the consolidated refusal suite (54 sites across eight files — the census
already counts them, and each family's own caller asserts its own; a consolidated suite would read stderr around each
door and check the named line and the documented return), and whatever behavioural depth the plan wants beyond those
five. W6/W7 added five more callers that M2 can lean on: `foundation_10_11_ordered_set`,
`foundation_10_11_metadata_version`, `foundation_10_11_operation_progress`, `foundation_10_11_tail`,
`foundation_10_11_scripting_archive`.

## 5. Cross-component state, measured

- `libagora-app` builds against the new headers, and its suite is at the same two pre-existing failures it had before
  W6 (`appkit-menu-headless`, `appkit-api-census`'s `methods-declared` drift from uncommitted AppKit work in the
  parent checkout) — neither is caused by Foundation, and the second was confirmed against a W6a-built library.
- `workspace` builds and passes 15/15.
- `swift-interop-probe`'s `run-native-probe.sh` passes both probes; it needs `~/.agora-swift/toolchain/usr`, so it is
  not a ctest gate here — the command is the record.
