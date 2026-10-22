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

## 7. Next: the suite

1. Build and install **swift-testing** (`Testing`) for the target from `~/.agora-swift/src/swift-testing`;
   the FE/FI suites are `import Testing` (85 of 86 test files; one legacy file still uses XCTest).
2. Build the `FoundationEssentialsTests` / `FoundationInternationalizationTests` targets (CMake, same
   flags), run them directly, and record **per subsystem**: Data, Date, Decimal, UUID, JSON, URL,
   Calendar/TimeZone, Locale/first-party formatting, file system.
3. Write the memo: the numbers, any failing tests and their root cause, and the B / partial-B / A decision
   in §5 of the plan.

## 8. Reproduction

```sh
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
