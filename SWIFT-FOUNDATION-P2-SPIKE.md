# FoundationEssentials against Agora — the P2 spike

*Status: **in progress, and the build question is answered.** swift-foundation's
`FoundationEssentials` and `FoundationInternationalization` compile, link and run against Agora's
CoreFoundation and ICU **without a change to swift-foundation's sources and without a single CoreFoundation
shim**. What remains is the upstream test suite (it needs swift-testing built for this toolchain), which is
what turns "it builds" into the per-subsystem numbers the plan's decision rule asks for.*

The plan this serves is [`SWIFT-FOUNDATION-PARITY-PLAN.md`](SWIFT-FOUNDATION-PARITY-PLAN.md) §5. P2's job is
to decide between **B** (port swift-foundation and bridge it) and **A** (port its sources by hand); the rule
was registered before the spike ran and is repeated in §6 below.

---

## 1. What was built

`swift-toolchain/scripts/build-swift-foundation.sh` — CMake, because the installed toolchain has no
`swift-build`/`swift-driver` and SwiftPM cannot run. Every input is local:

| Input | Path |
|---|---|
| sources | `~/.agora-swift/src/swift-foundation` (`release/6.3`) |
| collections | `~/.agora-swift/src/swift-collections` |
| ICU | `~/.agora-swift/src/swift-foundation-icu` (ICU 76 sources + packaged data) |
| swift-syntax | `~/.agora-swift/src/build/.../cmake/modules/SwiftSyntaxConfig.cmake` |
| CoreFoundation | `AGORA_PREFIX` via a new Clang module map |

```sh
swift-toolchain/scripts/build-swift-foundation.sh --configure
swift-toolchain/scripts/build-swift-foundation.sh --build FoundationEssentials
swift-toolchain/scripts/build-swift-foundation.sh --build FoundationInternationalization
```

Results (build tree `~/.agora-swift/build/p2-foundation`):

| Target | Result | Artefact |
|---|---|---|
| `FoundationEssentials` | **built and linked, 0 errors** | `lib/libFoundationEssentials.so` (23 MB) |
| `_FoundationCShims`, `_FoundationCollections` | built | static |
| `FoundationInternationalization` | **built and linked, 0 errors** (479 targets, ICU included) | `lib/libFoundationInternationalization.so` (8.8 MB) |
| `_FoundationICU` | built | `lib/lib_FoundationICU.so` |

`git -C ~/.agora-swift/src/swift-foundation status` is **clean**: no source was patched.

The produced `libFoundationEssentials.so` depends directly on `libagora-core.so` (and `libagora-base.so`),
i.e. it is linked against Agora, not against a corelibs CoreFoundation.

## 2. Why it was this easy: what is Darwin-only in the sources

The imports that looked like new dependencies are all behind platform or framework gates:

```swift
#if FOUNDATION_FRAMEWORK
internal import _ForSwiftFoundation      // 39 files
internal import os                       // Logger, on Darwin
internal import Foundation_Private.NSFileManager
#endif
#if canImport(os)                        // os is libdispatch's on Linux, optional
```

There is no `_ForSwiftFoundation` module anywhere in this tree and no `os.swiftmodule` in either toolchain;
on the non-framework Linux build they are simply not imported. `Darwin`/`CRT`/`WinSDK` are chosen by
`canImport`. That leaves the real Linux dependency set small: `CoreFoundation`, `_FoundationCShims`,
`_FoundationCollections`, and (for Internationalization) `_FoundationICU`.

## 3. The Agora side

One new file, `swift-interop-probe/agora-modules/CoreFoundation.modulemap`:

```
module CoreFoundation [system] {
  umbrella header "../../build-prefix/include/CoreFoundation/CoreFoundation.h"
  export *
  link "agora-core"
}
```

`link "agora-core"` is the load-bearing line: Swift autolinks by **module name** unless the module map says
otherwise, and Agora's library is `libagora-core.so`, not `libCoreFoundation.so`. With it the build links
with no `-l` flags of ours.

**The predicted CF shim list was smaller than predicted — it was empty.** Before the build, swift-foundation's
FE/FI sources referenced 73 distinct `CF*` identifiers; 55 appeared in Agora's headers. The 18 textual misses
turned out to be Darwin-only or not-symbols at all (`_CFURLFlags` is a Swift struct; `_CFURLComponentsMatchURLInString`
is a comment; `_CFURLCopy*` live behind `#if FOUNDATION_FRAMEWORK`), and the link reports **zero unresolved
CF symbols**. So the "port the CF SPI first" step the plan budgeted for is not needed for FE/FI to build.

## 4. It runs

Two client programs, compiled with the installed `swiftc` against the spike build (module maps for
`CoreFoundation`, `_FoundationCShims` and `_FoundationICU`; `-I <build>/swift`, `-L <build>/lib`):

`FoundationEssentials` alone —

```
data: 4 AQIDBA==
date: true
decimal: ok
uuid: 36
url: example.com /a/b b
components: c=d
json: {"x":1,"y":"z"}
roundtrip: true
indexpath: 2 [1, 2]
calendar: 1970 1
```

`FoundationInternationalization` + `FoundationEssentials` —

```
locale: en_US
formatted: 13 Sep 2020
number: 1,234.50
tz: Europe/Paris
era: 1
```

That is `Data`, `Date`, `Decimal`, `UUID`, `URL`/`URLComponents`, `JSONEncoder`/`JSONDecoder` with a
`Codable` round trip, `IndexPath`, `Calendar`, `Locale`, `TimeZone`, `Date.FormatStyle` and
`FloatingPointFormatStyle` — all on Agora's CoreFoundation. (`TimeZone(identifier:)` answers nil in the
FE-only program because the identifier lookup is an Internationalization extension; with FI loaded it
resolves.)

## 5. What the spike changed in the plan

1. **No CF shim work is needed before P3.** The bounded list of ~15 functions is not on the critical path;
   it can be revisited only if the test suite fails in URL or preferences.
2. **A toolchain-build gap to fix for P3**: `FoundationMacros` links `SwiftSyntax::SwiftCompilerPlugin`,
   which swift-syntax marks `EXCLUDE_FROM_ALL`, so it is absent from the toolchain's exported
   `SwiftSyntaxConfig.cmake`. The spike points `-DSwiftFoundation_MACRO` at an empty directory (no
   FoundationEssentials source uses a Foundation macro). The shipping build must build and export that
   target, or build the plugin directly.
3. **Clients of the built modules need three module maps** (`CoreFoundation`, `_FoundationCShims`,
   `_FoundationICU`) and the `_FoundationCollections`/`_FoundationICU` libraries. That is P3's packaging
   work, and it is why the spike keeps its modules in a private tree instead of installing them next to
   the stdlib.
4. **`import Foundation` is still Agora's overlay.** In the spike the two surfaces coexist only because
   nothing imports both; P3 is where FoundationEssentials becomes the thing Foundation re-exports.

## 6. Decision rule (registered before the spike, unchanged)

- **GO (B)** if FE/FI build with shim additions only (no edits inside swift-foundation's sources), the core
  value-type tests are ≥ 95 % green, and failures are attributable to Agora's CF rather than the Swift layer.
- **PARTIAL GO** if failures concentrate in one or two subsystems (URL and Locale are the likely ones): take
  B and keep the hand-written types there until P4.
- **NO-GO (A)** if staying inside the shim is impossible — swift-foundation needs edits in more than a
  handful of places, or `Data`/`Date` fail for reasons rooted in CF modelling.

Two of the three GO conditions are already met: **the sources are unmodified**, and the core value types,
JSON, URL, formatting and calendars all work. The third — the suite — is the remaining work.

## 7. The suite, and why it waits on the *module arrangement*

The upstream suites are `import Testing` (85 of 86 test files), and the installed toolchain ships no
`Testing`, so the next step was to build swift-testing. That build found the boundary of this phase:

1. **swift-syntax for the target — built.** The compiler's own swift-syntax is a *host* build (made by the
   bootstrap with a non-interop stdlib); compiling a macro against it makes the SIL verifier reject the
   inlined `Array`/`TriviaPiece` code (measured: `MandatorySILLinker` + verifier crash). Building
   swift-syntax with *this* toolchain works (script: `build-swift-testing.sh --syntax`), so **the target
   swift-syntax is a P3 prerequisite that is now solved**.
2. **`TestingMacros` — built** (library mode, `-load-plugin-library`), which also sidesteps the
   `SwiftCompilerPlugin` export gap from §5.
3. **`Testing` — first blocker solved, second one now precise.** Against Agora's overlay it stopped on the
   overlay's T3 gaps (`Data` not `Codable`, `URL(fileURLWithPath:isDirectory:)` absent); against the
   re-export `Foundation` below it gets past all of that and stops at `import ObjectiveC` (§ below).

**P3 step 1 was then built, and the suite runs.** The re-export module is
`swift-toolchain/spike/foundation-reexport/Foundation.swift` — two `@_exported import`s — built as a
`Foundation` module in the spike prefix. A client that says `import Foundation` gets
FoundationEssentials' `Data`/`Date`/`URL`/`JSON` and runs.

Getting `Testing` to load macros in the *compiler's* process needed one more arrangement: the plugin server
runs on the **host** stdlib, so `TestingMacros` is built with the **bootstrap** compiler against the
toolchain's own swift-syntax (`SwiftTesting_MACRO_Swift_COMPILER`), while `Testing` itself is a target
build. `ObjectiveC` then needed its runtime surface: `_silgen_name("objc_getClass")` is rejected as a
reserved name, and making `ObjectiveC` a Clang module (Darwin's shape) works for compilation but **cannot
pass module-interface verification** — the verifier re-parses the interface without the `-Xcc` flags that
locate the map. The contained fix is a C shim (`objectivec-overlay/objc-runtime-shim.c`) with
`agora_`-prefixed wrappers linked into `libObjectiveC.so`.

## 7a. The suites: the first numbers

`swift-toolchain/scripts/run-foundation-tests.sh` compiles one test file at a time with `Testing` (static)
plus the testing-enabled FE/FI and the re-export `Foundation`, links the swift-testing runner, and runs it.
Result on the default set:

| Suite | Result |
|---|---|
| `DataTests` | **152 tests passed** (2 suites) |
| `DateTests` | **12 passed** |
| `DecimalTests` | **32 passed** |
| `GregorianCalendarTests` | **20 passed** |
| `StringTests` | **35 passed** |
| `DateIntervalTests` | **7 passed** (was a crash — fixed, §2.30 of the handoff) |
| `IndexPathTests` | **42 passed** (was a crash — fixed) |
| `UUIDTests` | **10 passed** (was a crash — fixed) |
| `DataIOTests` | **9 passed** (was a build failure — the harness now compiles `DataTests.swift` for `LargeDataTests`, §2.31 of the handoff) |
| `URLTests` | **35 passed** (was a build failure — `FilePlayground` + `FileManagerTests.swift`) |
| `PropertyListEncoderTests` | **79 passed** (was a build failure) |
| `NotificationCenterTests`, `NotificationCenterMessageTests` | **35 run, 1 fails** (`internalPostNotificationForValue`: a non-object subject does not match) — was a build failure |
| `BufferViewTests`, `BuiltInUnicodeScalarSetTests`, `ErrorTests`, `LockedStateTests`, `SortComparatorTests`, `GregorianCalendarRecurrenceRuleTests` | **70 passed** |
| `PredicateCodableTests`, `PredicateConversionTests` | build, **no tests on this platform** (`#if FOUNDATION_FRAMEWORK`) |
| `PredicateTests` | still does not build: needs the `FoundationMacros` plugin (`Predicate`/`Expression`) |
| `ProcessInfoTests` | 13 run, 1 fails: `processName()` asserts the SwiftPM executable's name, which this harness does not use |

**670 of 672 upstream tests pass, in 19 suites** (672 run, from 8 suites/251 tests before the harness
was fixed — see the handoff's §2.31). The harness compiles the shared helpers into every binary, borrows
a sibling *file* when a suite uses a type from it (with a run filter so the borrowed suite does not run
twice), and links `FoundationEssentialsTests/Resources` next to the binaries at the path
`testData(forResource:)` looks for on Linux. The three crashes shared one stack, in a hashing test:

```
swift_arrayDestroy → objc_release → objc_msgSend_fpret (selector `release`) → SIGSEGV
```

The diagnosis is in the handoff's §2.30 and it was not where the first five hypotheses looked: the array
being destroyed was a `_ContiguousArrayStorage<AnyObject>` (the stdlib stores *class* elements with that
type, a bridging optimization), so the element destroy is `objc_release` by design — and a
runtime-instantiated pure-Swift class was not an Objective-C class object, so it had no dispatch table to
inherit `-release` from. Every runtime-pattern class is one now, which is also what makes
`-[NSMutableArray addObject:]` work on a generic class instance.

Two toolchain findings from the attempt, both recorded because they will recur:

- **a throwing Objective-C initializer called from a Swift `init` crashes the compiler** while lowering
  the class-constructor thunk (`_convertNSErrorToError` is reported as "not of the correct type", then
  `unable to set up the ObjC bridge`). The overlay's new `Data(contentsOf:options:)` avoids it by using
  the non-throwing read; the bug itself is unfixed and belongs in the Swift-port handoff.
- **passing both the Foundation and CoreFoundation module maps is a trap**: Foundation's umbrella includes
  CoreFoundation's headers, so a standalone `CoreFoundation` module is built in *C* mode, and
  `CFBridgingTypes.h`'s `#if defined(__OBJC__)` block is skipped — Foundation then sees the header through
  that module and `NSInteger` never exists. Clients import one or the other, not both.

## 8. The decision, and what is left

**Verdict: GO for strategy B** (port swift-foundation and bridge it). The registered conditions:

- sources unmodified — **yes** (no patch to swift-foundation, swift-collections or swift-foundation-icu);
- core value-type tests largely green — **yes**: 310 tests across Data, Date, Decimal, Calendar, String,
  IndexPath, DateInterval and UUID pass, and no suite crashes any more (the shared runtime defect behind
  the three crashes was fixed — handoff §2.30);
- failures attributable to Agora rather than the Swift layer — **yes**: the crash was in the class-ABI
  layer (a runtime-pattern Swift class was not a class object, so `objc_release` could not reach it), not
  in FoundationEssentials.

That places the spike at **GO**: B is right, and the first P3 step is to widen the harness to
whole-directory test compiles (the three single-file build failures are test coupling, not API gaps) and
run the FI suites (Locale/formatting), which need the same harness plus ICU already in place.

Open items, in order:

1. **Fix the generic-class release crash — fixed (handoff §2.30), and the gate is green.**
   The diagnosis below was the first half of the story: the destroy really does arrive as
   `objc_release`, but from the *array storage's* `<AnyObject>` value witnesses, not the
   element class's, and a runtime-pattern class had no `isa` for the send to land on.  Every
   pattern class is a class object now, and `verify-generic-release.sh` checks all three
   shapes (array destroy, `NSMutableArray` retain/release, nested instantiation). It is not
   Foundation-specific at all:

   ```swift
   final class Box<T> { var value: T; init(_ v: T) { value = v } }
   var a: [Box<Int>] = []
   for n in 0..<8 { a.append(Box(n)) }
   a.removeAll()                     // SIGSEGV
   ```

   A **non-generic** pure-Swift class releases correctly. The chain is `swift_arrayDestroy` → the element
   metadata's value witnesses → `objc_release` → `objc_msgSend_fpret` on a class with no dispatch table.
   The two facts that collide are in `SWIFT-GNUSTEP-CLASS-ABI.md`: a generically-instantiated pure-Swift
   class is a runtime **pattern** class, emitted at layout 2 with the Objective-C class witnesses (whose
   `destroy` is `objc_release`), while §2.21 deliberately makes such a pattern class **not a class object**
   (null `isa`, no dtable). Releasing it therefore messages nothing. Two further measurements pin the fix:
   a generic class **with** Objective-C ancestry (`Box<T>: NSObject`) releases correctly, and the compiled
   IR contains **no** `objc_release` — so the Objective-C destroy comes from a **value witness
   table**, not the call site. Acceptance test: `swift-toolchain/scripts/verify-generic-release.sh`
   (green since the fix).
2. **Whole-directory test builds — done, per file** (handoff §2.31). Compiling the directory as one
   module needs the `FoundationMacros` plugin (the predicate suites), which is the item below; the
   per-file harness now resolves the cross-file helpers and resources without it, and every suite that
   can build does. The one remaining build failure is `PredicateTests`.
3. **FI suites** (`FoundationInternationalizationTests`) — Locale/formatting, with ICU already built.
4. **P3's first slice — in** (handoff §2.33): the `Foundation` module now re-exports FE + FI and bridges
   eleven value types to Agora's classes (`Data`, `Date`, `URL`, `UUID`, `IndexPath`, `Decimal`, `TimeZone`,
   `Locale`, `Calendar`, `DateComponents`, `DateInterval`), with `build-foundation-p3.sh` rounding every one
   through a probe, and it is **installed**: `import Foundation` is FoundationEssentials +
   FoundationInternationalization + the bridges, over Agora's Clang Foundation, with the overlay retired
   (handoff §2.34, §2.35). Both harnesses run against that installed module. Still to do: the
   `Data`/`String` bridges as views instead of copies, the setter-retain audit the `NSCalendar -setLocale:`
   fix opened, and the T2 value-type diff.

## 9. Reproduction

```sh
swift-toolchain/scripts/build-foundation-macros.sh          # #Predicate/#Expression (§2.32)
swift-toolchain/scripts/build-swift-foundation.sh --configure
swift-toolchain/scripts/build-swift-foundation.sh --build FoundationEssentials FoundationInternationalization

B=~/.agora-swift/build/p2-foundation
T=~/.agora-swift/toolchain/usr
S=~/.agora-swift/src/swift-foundation
I=~/.agora-swift/src/swift-foundation-icu/icuSources/include

LD_LIBRARY_PATH=$B/lib:$AGORA_PREFIX/lib \
"$T/bin/swiftc" -o smoke smoke.swift \
  -I "$B/swift" -L "$B/lib" \
  -lFoundationEssentials -lFoundationInternationalization \
  -l_FoundationCollections -l_FoundationCShims -l_FoundationICU \
  -Xcc -fmodule-map-file="$AGORA_ROOT/swift-interop-probe/agora-modules/CoreFoundation.modulemap" \
  -Xcc -fmodule-map-file="$S/Sources/_FoundationCShims/include/module.modulemap" \
  -Xcc -fmodule-map-file="$I/_foundation_unicode/module.modulemap" \
  -Xcc -I"$I" -Xcc -I"$S/Sources/_FoundationCShims/include" \
  -Xcc -I"$AGORA_PREFIX/include" -Xcc -Wno-incomplete-umbrella \
  -L "$AGORA_PREFIX/lib"
```
