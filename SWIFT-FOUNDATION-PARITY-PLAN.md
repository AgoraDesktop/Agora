# Swift Foundation overlay — the plan to parity

*Status: plan. This document says what "Foundation parity" means for the Swift port, measures where the gap
is today, chooses an implementation strategy, and stages the work with a gate that makes progress
checkable. The round-by-round record stays in [`SWIFT-PORT-HANDOFF.md`](SWIFT-PORT-HANDOFF.md); this is the
plan for the part the handoff calls "the long tail".*

---

## 0. The question this answers

Swift code on Darwin does not see Objective-C Foundation directly. It sees a Swift surface:

- **FoundationEssentials** (open source, pure Swift): `Data`, `Date`, `URL`, `UUID`, `Decimal`,
  `Calendar`, `IndexPath`, `JSONEncoder`/`JSONDecoder`, `AttributedString`, `Predicate`, `FormatStyle`,
  `Measurement`, the `Sendable` conformances, and so on;
- **FoundationInternationalization**: `Locale`, `TimeZone`, formatters, calendars and formatting;
- **the Objective-C classes**, imported by the Clang importer and *renamed/annotated* by the SDK
  (`NSBundle` → `Bundle`, `-countOfIndexesInRange:` → `count(in:)`, `NSNotificationName` →
  `Notification.Name`).

Agora has the third layer's *classes* and a hand-written approximation of the first two
(`swift-toolchain/foundation-overlay/`, 2,047 lines). "Parity" means closing the difference between that
approximation and the surface above it.

---

## 1. What parity means (three tiers)

| Tier | Definition | Status today |
|---|---|---|
| **T1 — bridging** | Every bridged type converts in both directions with Darwin's *semantics*: casts are checks, views where Darwin has views, adoption on the way back, `AnyHashable`/`__SwiftValue`, `Error`↔`NSError`. | **Done** (§2.21/§2.22 of the handoff), with two documented deviations: `AnyHashable` dictionary keys are normalized to `String`, and `getObjects:range:` relies on the runtime's untyped fallback because its encoding is Swift's `_SwiftNSRange`. |
| **T2 — the ObjC-backed Swift surface** | For every subsystem Agora's Objective-C Foundation implements: the Swift names, conformances, members, annotations and property shapes Darwin exposes. | **Partial.** The hand-written value types cover the commonly used calls; the rename/annotation layer is a handful of examples; `Codable`/formatting/coder types are absent. |
| **T3 — Swift-native Foundation** | The parts of Foundation that on Darwin are Swift, not Objective-C: FoundationEssentials and FoundationInternationalization (`AttributedString`, `Predicate`, `FormatStyle`, `JSONEncoder`, `Measurement`, …). | **Absent**, with a strategic decision below: port Apple's implementation rather than re-implement it. |

**Explicitly out of scope for this plan** (separate subsystems, not overlay work): `URLSession` and the
networking stack, XPC, `FileProvider`, `NSFileCoordinator`/`NSFilePresenter`, Spotlight, and anything
Agora's Objective-C Foundation has no subsystem for. T3 includes FoundationEssentials and
FoundationInternationalization; FoundationNetworking is not part of it.

**"Parity" is a surface property, not a performance property.** Zero-copy behaviour where Darwin has it is
part of T1 (and is tested); matching Apple's allocation counts is not a goal.

---

## 2. The reference and the measurement

### 2.1 Reference

The bootstrap Swift toolchain on this host ships the Linux Foundation, which is the *same Swift API*
Darwin ships: `swift-foundation` (FoundationEssentials + FoundationInternationalization) plus the corelibs
compatibility layer. Its symbol graph is the reference:

```
~/.agora-swift/bootstrap/usr/lib/swift/linux/Foundation.swiftmodule
```

Measured today:

| | |
|---|---|
| reference symbols (main `Foundation` graph) | **5,471** |
| reference top-level types (non-underscored) | **186** |
| reference re-export graphs | `Foundation@FoundationEssentials`, `@Dispatch`, `@Glibc`, `@Swift` (4 files, 7.4 MB) |
| our overlay | 2 files, 2,047 lines, ~30 hand-written value types |
| our imported Objective-C classes | **164** |

The bias to keep in mind: the reference is the *Linux* build of the same source, so it is the right
API baseline but not a Darwin SDK. Where corelibs and Darwin differ (e.g. `NSString` literal
conformances, `NSNumber` equality across signedness), the source in `~/.agora-swift/src/swift-foundation`
and `swift-corelibs-foundation` is the tie-breaker, and the difference is recorded rather than averaged.

### 2.2 The diff harness (Phase 0)

Generate a symbol graph for each module and compare `(pathComponents, kind, declarationFragment)` plus
`conformsTo` relationships:

```sh
# reference (works today)
~/.agora-swift/bootstrap/usr/bin/swift-symbolgraph-extract \
  -module-name Foundation -target x86_64-unknown-linux-gnu \
  -I ~/.agora-swift/bootstrap/usr/lib/swift/linux -output-dir ref

# ours — BLOCKED today: the Clang module is built in C mode, so
# CFBridgingTypes.h's `#if defined(__OBJC__)` is skipped and NSUInteger/NSRange
# are unknown.  Fixing this is Phase 0's first task (see §5).
~/.agora-swift/toolchain/usr/bin/swift-symbolgraph-extract \
  -module-name Foundation -target x86_64-unknown-linux-gnu \
  -I ~/.agora-swift/toolchain/usr/lib/swift/linux \
  -Xcc -fmodule-map-file=swift-interop-probe/agora-modules/module.modulemap \
  -Xcc -Ibuild-prefix/include -Xcc -Wno-incomplete-umbrella -output-dir ours
```

Phase 0 outcomes:
1. extraction of *our* Foundation graph (fix the module build's language mode; fall back to
   `swift-api-digester` or a declaration-level diff of the overlay sources if the tool cannot be made to
   build the Clang module);
2. `foundation-parity-diff.py`: a stable, sorted report of missing/extra symbols, missing conformances
   (including re-export graphs), and changed declaration fragments;
3. `verify-foundation-parity.sh`: `--report` (human diff) and `--check` (CI). `--check` fails when a
   symbol outside `parity/foundation-allowlist.txt` is missing, **and** when an allowlisted symbol has
   become present (stale entries force the list to shrink);
4. the allowlist with one line per accepted gap and a reason, e.g.
   `Foundation:URLSession # out of scope: FoundationNetworking`.

---

## 3. Where the gap is today

The first (approximate) pass over the reference graph gives these clusters. The Phase 0 harness replaces
the approximation with exact numbers; the clusters are what it will be grouped by.

### 3.1 Swift names Darwin gives the imported classes (28 still missing)

Darwin exposes `NSFoo` as `Foo`. Our importer does not rename classes, so each needs a Swift-side alias
(and, where Darwin nests types, a wrapper rather than a plain typealias):

```
BlockOperation Bundle DateIntervalFormatter EnergyFormatter FileHandle Formatter Host
ISO8601DateFormatter InputStream JSONSerialization LengthFormatter MassFormatter
NotificationQueue NumberFormatter Operation OperationQueue OutputStream Pipe Port
PortMessage PropertyListSerialization RunLoop Scanner SocketPort Stream Thread Timer
UserDefaults
```

plus irregular names (`NSTask` → `Process`, `NSError`-family types, `NSComparisonPredicate` → the
`Predicate` API). `DateFormatter` and `Notification.Name` are already done; they are the pattern.

### 3.2 Conformances the value types do not carry

The reference's value types carry `Codable` (and `Sendable`) where ours do not:

```
Data  Date  URL  Decimal  DateComponents  URLComponents  IndexPath  …
```

`IndexSet`/`CharacterSet` gained `SetAlgebra` in the last round; the `Codable` family is untouched. There
is no `JSONEncoder`/`JSONDecoder` or `PropertyListEncoder`/`PropertyListDecoder` at all, so those
conformances have nothing to talk to yet.

### 3.3 Swift-native subsystems that are absent

| Subsystem | Darwin source | Note |
|---|---|---|
| `JSONEncoder`/`JSONDecoder`, `PropertyListEncoder`/`Decoder` | FoundationEssentials | pure Swift; depends on `JSONSerialization`/plist underneath |
| `AttributedString`, `AttributeContainer`, attribute scopes | FoundationEssentials | pure Swift, large |
| `Predicate`, `PredicateExpression`, `Expression` | FoundationEssentials + macros | pure Swift, macro-based |
| `FormatStyle` family (`Date.FormatStyle`, integer/floating styles, `ByteCountFormatStyle`, …) | FoundationEssentials | pure Swift |
| `Measurement`/`Unit*` | FoundationEssentials | pure Swift |
| `URLComponents`/`URLQueryItem` | FoundationEssentials | pure Swift |
| `Locale`, `Calendar`, `TimeZone` modern APIs, formatters | FoundationInternationalization | ICU-backed |

### 3.4 Objective-C subsystems Agora's Foundation does not have (caps on T2)

These are absent from the headers, so no overlay can expose them:

```
NSPredicate / NSExpression / NSComparisonPredicate / NSCompoundPredicate
NSMeasurement / NSUnit
NSURLSession
NSURLComponents / NSURLQueryItem
NSProgress
NSByteCountFormatter
```

Under the recommended strategy (§4) the pure-Swift replacements (`Predicate`, `Measurement`,
`URLComponents`, byte-count formatting) arrive with FoundationEssentials/Internationalization; `URLSession`
and `NSProgress` stay out of scope.

### 3.5 Small, known semantics gaps

- `AnyHashable` dictionary keys are normalized to `String` so `d["k"]` finds the entry; the reference
  leaves `AnyHashable(NSString)`. Decide whether to keep the normalization (it makes Swift keys work)
  and document it as a deliberate deviation, or match the reference.
- `getObjects:range:` carries Swift's `{?=qq}` encoding rather than Clang's `{_NSRange=QQ}`, so that one
  typed send takes the runtime's untyped fallback. Either give the Swift implementation a Clang-shaped
  door or record it.
- Property shape: `NSDateFormatter.dateStyle` and friends import as methods; the full property-shaped
  pass is Phase 1.

---

## 4. Strategy: port Swift Foundation, do not re-implement it

The gap between our hand-written overlay and the reference is not a list of methods; it is *most of
swift-foundation*. Two ways to close it:

**A. Grow the hand-written overlay** — port the value types' members and conformances one by one, then
JSON coders, then formatting, then attributed strings. Predictable, no new dependencies, but it
re-implements a large, tested Apple codebase and will keep drifting.

**B. Build `swift-foundation` against Agora (recommended).** `swift-foundation` is already in
`~/.agora-swift/src` (with `swift-collections`, `swift-syntax`, `swift-foundation-icu`), and the bootstrap
toolchain proves it builds on Linux with this Swift. Point its build at Agora's CoreFoundation, libdispatch
and system ICU, and it supplies FoundationEssentials + FoundationInternationalization directly. The
hand-written overlay then shrinks to what Darwin's overlay is: the bridging shims between those Swift
types and the Objective-C classes (`NSData`↔`Data`, `NSDate`↔`Date`, `NSURL`↔`URL`, …), plus the
Cocoa-shaped conveniences.

B is the same architecture as Darwin (Swift Foundation over an Objective-C/CoreFoundation base), removes
the largest clusters at once, and turns "parity" into "run Apple's surface, not a copy of it". Its risk is
the porting tail: FoundationEssentials expects CoreFoundation behaviours and a small `_FoundationInternals`
C shim, and its bridging expects the corelibs class cluster (`_NSCFData`, `_NSCFString`, …). The spike in
Phase 2 measures exactly that.

**Decision rule for the spike:** if FoundationEssentials' own tests for `Data`, `Date`, `URL`, `UUID`,
`Decimal`, `Calendar`, `TimeZone`, `Locale` and JSON pass against Agora's CoreFoundation/ICU/dispatch, take
B. If the number of missing CF SPI/runtime hooks is small and bounded, take B with a shim. Only if the
CoreFoundation model is fundamentally incompatible does A become the fallback — and then the plan ports
`swift-foundation` file by file rather than writing new code.

---

## 5. Phases

Effort is rough and single-developer; gates are what matter.

### P0 — Measurement (1–2 days)

- Fix our symbol-graph extraction (the Clang module must build in Objective-C mode; record the failing
  invocation and the fix). Fallback: generate an interface-level diff from the overlay sources and the
  Clang headers.
- `foundation-parity-diff.py`, `verify-foundation-parity.sh`, `parity/foundation-allowlist.txt`.
- Publish the first real numbers in this document (replace §3's approximation).
- **Gate:** `verify-foundation-parity.sh --check` runs and reports the baseline (allowed to fail only on
  allowlisted entries).

### P1 — Names and annotations (≈1 week)

- Complete the rename layer (`public typealias Bundle = NSBundle`, … and the irregulars), preferring
  `NS_SWIFT_NAME` in the headers where the importer can do it and a Swift alias where it cannot.
- Finish property-shaped accessors across Foundation's headers (the `dateStyle` class of gap).
- `NS_ENUM`/`NS_OPTIONS` for the remaining C enums; `NS_TYPED_ENUM` for the remaining string typedefs;
  `NS_REFINED_FOR_SWIFT` where the overlay wants the un-renamed door; `NS_SWIFT_SENDABLE` for the
  immutable classes.
- Update call sites (the same source migration the property pass already required).
- **Gate:** the diff's "name/annotation" group is empty or allowlisted; all existing gates green.

### P2 — Strategy spike (2–4 days)

- Build `FoundationEssentials` from `~/.agora-swift/src/swift-foundation` against Agora's CoreFoundation,
  libdispatch and system ICU; run its tests.
- Record: which CF SPI/behaviour is missing, which corelibs class-cluster hooks are expected, build-system
  changes needed.
- **Gate:** a written go/no-go with the numbers; if go, P3 starts.

### P3 — Bridge to FoundationEssentials (1–2 weeks, if go)

- Install `FoundationEssentials`/`FoundationInternationalization` next to the target stdlib; make
  `import Foundation` re-export them (Darwin's arrangement).
- Replace the hand-written value types with Apple's; keep a compatibility shim for names the overlay
  already published.
- Implement the bridging layer between them and Agora's classes (`Data`↔`NSData`, `Date`↔`NSDate`,
  `URL`↔`NSURL`, `UUID`↔`NSUUID`, `IndexPath`↔`NSIndexPath`, `Decimal`↔`NSDecimalNumber`, …), using the
  bridge points swift-foundation already declares.
- Delete the duplicated overlay code and its tests; keep the tests that pin the bridge semantics.
- **Gate:** the T2 symbol diff for value types and conformances is zero or allowlisted; language gate,
  zero-copy gate, and the whole class-ABI suite stay green.

### P4 — Internationalization (1–2 weeks, if go)

- `FoundationInternationalization` against Agora's CoreFoundation and system ICU: `Locale`, `Calendar`,
  `TimeZone`, the `FormatStyle` family, the formatters.
- Wire the Objective-C formatter classes to the same code where Darwin does.
- **Gate:** formatting/locale tests from swift-foundation pass; diff for the Internationalization group
  empty or allowlisted.

### P5 — Surviving overlay shims and the long tail (≈1 week)

- `JSONSerialization`/plist conveniences, `NSObjCRuntime` utilities, `CocoaError`/error-code bridging,
  `NSRange`/geometry conveniences, `FileManager`/`Process`/`FileHandle` names and Swift-idiomatic members.
- Remove the hand-written value types that FoundationEssentials now owns.
- **Gate:** diff has only allowlisted entries; every allowlist entry has a reason and an owner.

### P6 — Sendable/availability sweep and documentation (3–5 days)

- `Sendable` conformances and `@available` markers where the reference has them; document the deliberate
  deviations (§3.5).
- Update `SWIFT-PORT-HANDOFF.md`, the toolchain README and this plan's status.
- **Gate:** the parity gate is part of the suite; the allowlist is stable and reviewed.

---

## 6. Definition of done

1. `verify-foundation-parity.sh --check` is green, and the allowlist contains only entries with a written
   reason (out-of-scope subsystems, deliberate deviations).
2. T1 semantics tests pass (existing) and T2/T3 tests come from the reference where possible.
3. The hand-written overlay is reduced to bridging shims; the value types, coders, formatting and
   attributed strings are Apple's swift-foundation code.
4. Every deliberate deviation is listed in §3.5 and in the allowlist.
5. The whole gate suite (language, zero-copy, S1–S5, library evolution, probes) is green against the
   installed toolchain.

## 7. Risks and open decisions

- **Reference bias.** Linux Foundation is the same source as Darwin's Swift Foundation, not the Darwin
  SDK. Where they differ, the source is the tie-breaker; the plan records differences rather than
  averaging them.
- **Source-breaking renames (P1).** The property and name passes change Swift spellings. They need the
  same migration note and call-site sweep the property pass already required.
- **CoreFoundation behaviour (P2).** FoundationEssentials depends on CF semantics (`CFData`, `CFString`,
  `CFURL`, `CFCalendar`, `CFTimeZone`) and a small internal C shim. The spike must quantify the gap; a
  large gap changes the decision, not the goal.
- **Build time and binary size.** FoundationEssentials + Internationalization add modules and ICU linkage
  to the installed toolchain.
- **Licensing.** swift-foundation is Apache-2.0 with the Swift runtime exception (permissive); its NOTICE
  must ship. This is compatible with the project's MIT-first rule.
- **T3 scope.** `AttributedString` and `Predicate` are large even when ported. The plan includes them
  because they are FoundationEssentials; if they are deferred, they are allowlisted explicitly, not
  silently dropped.

## 8. Immediate next actions

1. Fix the our-side symbol-graph extraction (P0) and land the diff/gate scripts with a baseline
   allowlist. The failing invocation and its cause are recorded in §2.2.
2. Do P1's rename layer first: it is cheap, mechanical, and removes 28 names from the visible diff
   before the strategic work starts.
3. Run the P2 spike before writing any more value-type code. The outcome decides whether the remaining
   effort is "port and bridge" or "port the sources"; either way, it is not "re-implement".
