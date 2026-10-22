# Swift Foundation overlay — the plan to parity

*Status: **P0 (measurement) landed** — the harness and the gate exist, and §3 carries measured numbers
instead of estimates. P1 (names and annotations) is next; P2 (the strategy spike) still decides the T3
route. The round-by-round record stays in [`SWIFT-PORT-HANDOFF.md`](SWIFT-PORT-HANDOFF.md); this is the
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
compatibility layer. `import Foundation` there is one surface over three modules, so the reference is
three symbol graphs:

```
~/.agora-swift/bootstrap/usr/lib/swift/linux/{Foundation,FoundationEssentials,FoundationInternationalization}.swiftmodule
```

Measured by `verify-foundation-parity.sh --report`:

| | |
|---|---|
| reference symbols | **10,455** — Foundation 5,471, FoundationEssentials 4,531, FoundationInternationalization 453 |
| reference top-level types (non-underscored) | 186 in the main `Foundation` graph alone |
| reference re-export graphs | `Foundation@FoundationEssentials`, `@Dispatch`, `@Glibc`, `@Swift`, and each module's own overlays |
| our symbols | **11,314** — larger than the reference, because the module also carries the CoreFoundation surface (223 `CF*` type containers) that Darwin ships separately |
| our overlay | 2 files, 2,047 lines, ~30 hand-written value types |
| our imported Objective-C classes | **164** |

The bias to keep in mind: the reference is the *Linux* build of the same source, so it is the right
API baseline but not a Darwin SDK. Where corelibs and Darwin differ (e.g. `NSString` literal
conformances, `NSNumber` equality across signedness), the source in `~/.agora-swift/src/swift-foundation`
and `swift-corelibs-foundation` is the tie-breaker, and the difference is recorded rather than averaged.

### 2.2 The diff harness (Phase 0 — landed)

`swift-toolchain/scripts/verify-foundation-parity.sh` extracts a symbol graph per module and
`swift-toolchain/scripts/foundation-parity-diff.py` compares `(pathComponents, kind)` sets plus
`conformsTo` relationships:

```sh
swift-toolchain/scripts/verify-foundation-parity.sh --report            # human diff
swift-toolchain/scripts/verify-foundation-parity.sh --check             # the gate
swift-toolchain/scripts/verify-foundation-parity.sh --update-allowlist  # after a landing
```

The extraction used to be **blocked on our side**: `swift-symbolgraph-extract` builds its own compiler
invocation instead of going through the driver, and it hard-coded
`EnableObjCInterop = Target.isOSDarwin()`. An imported Clang module was therefore built in C mode:
`CoreFoundation/CFBridgingTypes.h` declares `NSInteger`/`NSRange` under `#if defined(__OBJC__)`, they
vanished, and every Foundation declaration that names them failed to import. The fork now applies the
driver's rule (`Target.isOSDarwin() || Target.isOSLinux()`) plus the GNUstep runtime vendor for an ELF
target (patch `0003`, `lib/DriverTool/swift_symbolgraph_extract_main.cpp`). `--keep` retains the graphs
in `$TMPDIR/agora-foundation-parity` for inspection.

What the harness measures:

- **symbol gaps** — `(dotted path, kind)` in the reference and not in ours. A member that exists only in
  the other *shape* (method rather than property) is a gap, which is the point: Darwin's property-shaped
  surface is part of parity;
- **conformance gaps** — `conformsTo` edges from every reference graph against ours, resolving protocol
  targets outside the graph through `targetFallback` (so `Swift.Codable` is measurable) and ignoring
  compiler-synthesized conformances (`Sendable`, `Copyable`, `Escapable`, `SendableMetatype`,
  `BitwiseCopyable`) and typealiases (whose conformances belong to the aliased type);
- **extras** — symbols we publish and the reference does not, reported apart for CoreFoundation;
- **the allowlist gate** — `parity/foundation-allowlist.txt`, one entry per accepted gap with a stage
  reason and a count. `--check` fails on an unallowlisted gap, on a gap that grew past its count, and on
  a count that is now too large, so every landing has to shrink the list.

The allowlist is *prefix*-based (`Foundation:NSData` covers `NSData` and everything under it), so the
baseline is 360 reviewable entries rather than 8,121 lines. `--update-allowlist` rewrites the counts,
*appends* an entry for a gap nothing accepts (a rename can expose one — see §3.1), and keeps the reasons.

---

## 3. Where the gap is today (measured)

`verify-foundation-parity.sh --report`, against the three reference modules:

| | |
|---|---|
| reference symbols | 10,455 |
| our symbols | 11,314 |
| **missing** | **7,691 distinct `(path, kind)` — 8,121 declarations in 300 containers** |
| … of those, containers absent entirely | 185 |
| … members that exist here only in the other shape | 3 |
| **missing conformances** | **222 edges over 61 types** |
| extra symbols (ours only) | 9,274 — 223 CoreFoundation type containers plus Agora's own additions |

(The name, enum and shape passes of §3.1 have landed — 32 classes, one struct, four option sets, the
`NSObject` description family, `Calendar.Component` as an enum, `CGRectEdge` — hence 7,794 rather than
the 8,259 first measured. Three shape-only gaps remain and each is a recorded decision, not a task:
`CGFloat` and `DateFormatter` are typealiases here, and `NSRectEdge` is Core Graphics' enum under
Darwin's deprecated alias.)

By the allowlist's stage reasons, the missing symbols split roughly: **T3 ≈ 3,000**, **P1 ≈ 2,800**,
**T3/P1 ≈ 1,340** (the value types' long tails), **P4 ≈ 400**, out-of-scope/capped subsystems ≈ 225, and
144 geometry symbols that Darwin's Foundation re-exports from CoreGraphics. The largest containers are
the measurement, in order:

```
933 AttributedString      647 Locale                 402 PredicateExpressions
238 AttributeScopes       195 Data                   194 FileManager
162 Calendar              154 NSCalendar             151 IndexSet
120 NSString              115 URLError               112 IndexPath
```

Every one of those is either T3 (Apple's own Swift code) or a P1 rename/member pass — which is why the
strategy below matters more than any single container.

### 3.1 Swift names Darwin gives the imported classes — **landed**

Darwin exposes `NSFoo` as `Foo`. The importer takes a class's Swift name from `NS_SWIFT_NAME` on the
`@interface`, so each rename is a one-line header annotation, and because the annotation moves the symbol
graph the gate measures it. All 32 names in this group are annotated in `libagora-base`:

```
BlockOperation Bundle DateIntervalFormatter EnergyFormatter FileHandle FileManager
Formatter Host ISO8601DateFormatter InputStream JSONSerialization LengthFormatter
MassFormatter NotificationCenter NotificationQueue NumberFormatter Operation
OperationQueue OutputStream Pipe Port PortMessage Process ProcessInfo
PropertyListSerialization RunLoop Scanner SocketPort Stream Thread Timer UserDefaults
```

plus the struct `NSOperatingSystemVersion` → `OperatingSystemVersion` (6 of its 8 symbols closed; the
remaining two are `Decodable`/`Encodable`.) The 32 classes together closed 292 symbols, `Host` entirely.

What remains under each name is its member surface and the members that exist in our headers in the
method shape where Darwin has a property (`bundleIdentifier`, `resourceURL`, …).

**The enum half landed too, and needed a prerequisite the plan had not priced.** Renaming an enum's
*type* moves one symbol and leaves every constant behind as a global, because constants become members
only when the importer is told what kind of enum it is. Darwin's `NS_ENUM`/`NS_OPTIONS` say it with
attributes:

```c
enum __attribute__((enum_extensibility(open))) _name : _type              /* NS_ENUM */
enum __attribute__((flag_enum, enum_extensibility(open))) _name : _type   /* NS_OPTIONS */
```

This tree's macros emitted only the fixed-underlying-type enum, so `NSAlignmentOptions` imported as
`typealias AlignmentOptions = UInt` and its 47 members never appeared. The macros now carry the
attributes, and the four option sets are real option sets: `NSAlignmentOptions` (47 → 1, the `rawValue`
note below), `NSSortOptions` (27 → 1), `NSEnumerationOptions` (22 → 1), `NSBinarySearchingOptions`
(23 → 1) and `NSQualityOfService` (10 → 0). Three `OptionSet`/`SetAlgebra` conformance edges closed with
them.

Two importer rules fell out of it, both now written down because they decide where the annotations go:

- **the constants are stripped against the ENUM NAME**, so the tag has to start with the constants'
  common prefix. `NSAlignmentOptions` with constants `NSAlign…` strips to `alignMinXInward`; naming the
  tag `AlignmentOptions` strips nothing. A rename therefore goes on the tag as
  `__attribute__((swift_name("AlignmentOptions")))`, keeping the ObjC tag — which is why
  `NSGeometry.h` spells the declaration out instead of calling `NS_OPTIONS`, and why the macro surface
  in `NSObjCRuntime.h` had to move above its first use.
- **a direct frontend invocation is not the driver**: the same ordering lesson as the symbol-graph tool.
  `NS_SWIFT_NAME` had to be defined before the enum that uses it, in the same header.

The four option sets' last missing symbol is `rawValue` as a *property*: the imported Clang option set
has it, but `swift-symbolgraph-extract` does not emit the stored property, so the gap is in the
measurement and is allowlisted as such.

`DateFormatter` and `Notification.Name` were done earlier; they are the pattern.

### 3.2 Conformances the value types do not carry

179 edges over 60 types, down from 380 before the two conformance slices. What is left is blocked on
something other than a declaration:

| Protocol | Edges | Why it is still there |
|---|---|---|
| `NSSecureCoding` / `NSCoding` | 32 / 12 | the classes have no `-encodeWithCoder:`/`-initWithCoder:` at all (checked per class), so the conformance would be a claim without an implementation; secure coding additionally needs `+supportsSecureCoding` and the `decodeObjectOfClass:` doors |
| `CustomReflectable` | 21 | `customMirror` is unwritten. A mirror that delegates to the backing Objective-C object is one line, but it is a P1/P3 judgement rather than a mechanical fix |
| `Decodable` / `Encodable` | 20 / 20 | P3: these belong to FoundationEssentials, which replaces the hand-written types |
| `ReferenceConvertible` | 10 | the protocol itself arrives with FoundationEssentials (T3) |
| `NSMutableCopying` | 8 | no `-mutableCopy` on those classes |
| `Sequence`/`Collection`/`DataProtocol`/… | 20 | P3: the collection surface of `Data`/`NSData`/`IndexPath`/`IndexSet` |
| literal conformances | 7 | `ExpressibleBy*Literal` on `NSNumber`/`NSDecimalNumber`/`NSString`/collections |

Landed in this pass: `CustomStringConvertible` + `CustomDebugStringConvertible` on the overlay's value
types (the debug form is the description form, documented), `Comparable` on `NSDate`,
`NSDateInterval`, `NSIndexPath`, `NSNumber`, `NSString`, `DateInterval` and `UUID`, and
`Equatable`/`Hashable` on `CGPoint`, `CGSize`, `CGRect`, `OperatingSystemVersion` and `Notification`.
`NSComparisonResult` became a real `NS_ENUM` renamed to `ComparisonResult`, which is Darwin's imported
type and the spelling those comparisons use.

**A use-after-free fell out of it, and the story is worth keeping.** With the `Comparable` conformance
on `NSDate` in place, the language gate's value-types program began to segfault inside
`objc_msgSend_fpret` dispatching `-UTF8String` from `-[NSDateFormatter fnRebuild]` — and bisecting the
conformance away made it disappear. It was not the conformance: `libagora-base` is **manual reference
counting** (its CMake says so), and `NSDateFormatter`'s setters assigned their arguments without
retaining them, `-copy` shared them without retaining, and `-dealloc` never released them. Adding one
more record to the binary changed the heap layout and turned a latent dangling `_pattern` into a crash.
The setters retain and release now, `-copy` retains what it shares, and `-dealloc` releases all six
settings. This is the same family as the `NSCalendar` time zone bug (§2.22 of the handoff): **in this
tier, a setter that assigns an object ivar must retain it**, and the port's Swift bridging is what
exposes the ones that do not.

### 3.3 Swift-native subsystems that are absent

| Subsystem | Symbols missing | Darwin source | Note |
|---|---|---|---|
| `AttributedString`, `AttributeContainer`, attribute scopes | 933 + 238 + ~100 | FoundationEssentials | largest single gap |
| `Predicate`, `PredicateExpressions`, `Expression` | 402 + ~20 | FoundationEssentials + macros | macro-based |
| `Locale`, `Calendar`, `TimeZone` modern APIs, formatters | 647 + 162 + ~500 | FoundationInternationalization | ICU-backed |
| `Data`, `URL`, `IndexPath`, `Date`, `Decimal` members | 195 + 75 + 112 + 106 + ~50 | FoundationEssentials | the value types exist here; their long tails do not |
| `FormatStyle` family (`IntegerFormatStyle`, `FloatingPointFormatStyle`, `ByteCountFormatStyle`, …) | ~500 | FoundationEssentials | pure Swift |
| `Measurement`/`Unit*` | ~300 | FoundationEssentials | pure Swift |
| `JSONEncoder`/`JSONDecoder`, `PropertyListEncoder`/`Decoder` | ~150 | FoundationEssentials | pure Swift; depends on `JSONSerialization`/plist underneath |
| `URLComponents`/`URLQueryItem` | ~50 | FoundationEssentials | pure Swift |

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
and `NSProgress` stay out of scope. The measured allowlist marks these `cap:`, and they total ≈ 270
symbols — small, which is the useful finding: the gap is not in Objective-C subsystems.

### 3.5 Small, known semantics gaps

- `AnyHashable` dictionary keys are normalized to `String` so `d["k"]` finds the entry; the reference
  leaves `AnyHashable(NSString)`. Decide whether to keep the normalization (it makes Swift keys work)
  and document it as a deliberate deviation, or match the reference.
- `getObjects:range:` carries Swift's `{?=qq}` encoding rather than Clang's `{_NSRange=QQ}`, so that one
  typed send takes the runtime's untyped fallback. Either give the Swift implementation a Clang-shaped
  door or record it.
- Property shape: `NSDateFormatter.dateStyle` and friends import as methods; the full property-shaped
  pass is Phase 1. The harness counts these as gaps (20 today are the same path with another kind),
  because on Darwin they are properties.
- `CGFloat` is `Double` here and a struct in the reference (103 members), so the geometry containers are
  allowlisted as a deviation rather than a task. Darwin's `CGFloat` is a struct too; whether to match it
  is a decision for P1, not a bug.
- **`NSRectEdge` is an alias of `CGRectEdge`** here, which is Darwin's arrangement (the pre-10.6
  spelling is deprecated). The reference — Linux corelibs — declares a separate `NSRectEdge` enum with
  `.minX`/`.minY`/`.maxX`/`.maxY`, so the diff reports our typealias as a shape gap; the source is the
  tie-breaker, and the deviation is allowlisted with that reason rather than "averaged" into a second
  enum.
- **`DateFormatter` is a typealias of `NSDateFormatter`** (Darwin's imported name), so the type exists but
  its members are counted under the alias; that is the P1/P4 member work, not a shape question.

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

### P0 — Measurement (1–2 days) — **done**

- Fixed the extraction: the fork's `swift-symbolgraph-extract` now enables interop for a Linux target and
  selects the GNUstep runtime vendor, so the imported Clang module builds in Objective-C mode. Recorded in
  §2.2; the change is in patch `0003`.
- `foundation-parity-diff.py` (symbol, conformance and extra diff plus the allowlist ratchet) and
  `verify-foundation-parity.sh` (`--report` / `--check` / `--update-allowlist`, one extraction per module,
  isolated module caches).
- `parity/foundation-allowlist.txt` — 372 entries, each with a stage reason and the count it accepts.
- §3 now carries measured numbers; the first real baseline is 8,259 missing symbols and 320 missing
  conformance edges.
- **Gate:** `verify-foundation-parity.sh --check` is green against the baseline, and fails on an
  unallowlisted gap, a grown gap, or a stale count. Measured cost: ~10 s end to end.

### P1 — Names, annotations and conformances (≈1 week) — **landed apart from what needs implementation**

- ~~Complete the rename layer with `NS_SWIFT_NAME` in the headers.~~ **32 class names, one struct and
  four option sets landed** (§3.1), closing 440 symbols. The enum half needed `NS_ENUM`/`NS_OPTIONS` to
  carry Darwin's `enum_extensibility`/`flag_enum` attributes first; they do now.
- **Property shapes — landed.** `description`/`debugDescription`/`hash` are properties on `NSObject`
  (with the two description conformances, 156 edges), `NSDate`'s reference interval is a class property,
  `Date`'s is a static, `Calendar.Component` is an enum, and `NSExceptionName`/`NSTextCheckingKey` are
  typed string enums. The shape-gap counter went 19 → 3; the three that remain are the recorded
  deviations in §3.5.
- `NS_REFINED_FOR_SWIFT` where the overlay wants the un-renamed door; `NS_SWIFT_SENDABLE` for the
  immutable classes.
- Update call sites (the same source migration the property pass already required): `description()` →
  `description` was the first one, in the overlay and in `verify-swift-port.sh`.
- **Gate:** the diff's "name/annotation" group is empty or allowlisted; all existing gates green.

### P2 — Strategy spike (2–4 days) — **answered: GO**

- ~~Build `FoundationEssentials` against Agora's CoreFoundation, libdispatch and ICU~~ — **done, unmodified
  and with no CF shim**: FE and FI both compile, link and run ([spike record](SWIFT-FOUNDATION-P2-SPIKE.md)).
  The predicted CF SPI list turned out to be Darwin-only; the link has zero unresolved CF symbols.
- **The suite waits on the `ObjectiveC` module, not on CF.** A re-export `Foundation`
  (`swift-toolchain/spike/foundation-reexport/`) was built and carries `Testing` past the overlay's T3
  gaps; it now stops at `public import ObjectiveC`, because our `ObjectiveC` module is Swift-only and
  Darwin's re-exports `objc/runtime.h`. The fix is the Darwin arrangement — `ObjectiveC` as an overlay
  over a Clang module — and it is the single remaining blocker before `Testing` and the suites build.
- Build-system findings for P3: the toolchain's `SwiftSyntaxConfig.cmake` does not export
  `SwiftSyntax::SwiftCompilerPlugin` (the target swift-syntax build fixes it), and clients of the built
  modules need the `CoreFoundation`, `_FoundationCShims` and `_FoundationICU` module maps — but *not* both
  the Foundation and CoreFoundation maps at once (module ownership; see the spike record).
- Two toolchain bugs recorded: a throwing ObjC initializer in a Swift `init` crashes in the
  class-constructor thunk, and the module-map ownership trap above.
- **Gate: met — GO.** `Testing` builds (host macros, target library) and the upstream suites run:
  **251 tests pass** across Data, Date, Decimal, GregorianCalendar and String; three suites
  (`UUIDTests`, `DateIntervalTests`, `IndexPathTests`) crash on one shared defect, a `-release` send
  dispatched through `objc_msgSend_fpret` during `swift_arrayDestroy`, which is a libobjc2 typed-dispatch
  bug rather than missing Foundation API. Sources are unmodified, so the spike lands at **GO / partial
  GO**: P3 starts, with the dispatch defect as its first milestone. Full numbers in the
  [spike record](SWIFT-FOUNDATION-P2-SPIKE.md) §7a.

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

1. `verify-foundation-parity.sh --check` is green with an allowlist that has shrunk to zero missing
   symbols, keeping only entries with a written reason (out-of-scope subsystems, deliberate deviations).
   Today the same command is green against the baseline: the list *is* the remaining work.
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

0. **Done since this list was written** (handoff §2.30, §2.31): the generic-class release crash (every
   runtime-pattern class is a GNUstep class object now, and a pattern class's VWT follows
   `UsesSwiftRefcounting`), and the suite harness (SwiftPM-equivalent compiles, shared helpers, resources):
   `--all` runs 19 suites / 672 tests with 670 passing. Two further runtime bugs were fixed on the way
   (a pattern class's refcount word landing on its first stored property; libobjc2 walking a late-bound
   actor's null ivar offset).
1. **Build the `FoundationMacros` plugin** (target `SwiftCompilerPlugin` + `FoundationMacros`): the one
   remaining *build* failure, `PredicateTests`, and the prerequisite for compiling the test directory as
   one module. Also what `#Predicate` needs in any ported client.
2. **Then P3 proper** (below): install FoundationEssentials/FoundationInternationalization next to the
   target stdlib, make `import Foundation` re-export them, and write the bridge to Agora's classes.
   `run-foundation-tests.sh` is the regression harness for it, and the FI suites (item 3 of the spike's
   list) are the next thing it should learn to run.
3. **P1, `CustomReflectable`**: 21 edges, and the only remaining conformance cluster that is
   mechanical. A `customMirror` per value type, delegating to the backing object.
4. **P5, archiving**: 44 `NSCoding`/`NSSecureCoding` edges need `-encodeWithCoder:`/`-initWithCoder:`
   (and secure decoding) on the classes that have none. That is a subsystem, not a conformance edit.
5. Wire `verify-foundation-parity.sh --check` into the gate suite (§6). The ratchet has been exercised
   by six landings; it is ready to be a required gate.
6. Two single-assertion failures the widened harness reports: `NotificationCenter` subject matching for
   non-object subjects (a real finding), and `ProcessInfo.processName` (a harness artefact — the test
   asserts SwiftPM's executable name).
