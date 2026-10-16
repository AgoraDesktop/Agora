# Rust bindings to the Agora APIs — practicality and needs

**Question.** Is it practical to ship a set of Rust bindings to the Agora APIs in this
repository, and what would those bindings need?

**Verdict.** Practical, and mostly mechanical for the lower tiers; practical-but-deliberate for
the Cocoa tiers. It is *not* a drop-in re-use of Apple's Rust crates: the APIs are close enough
that those crates are a useful smoke test, but Agora documents many deliberate deviations from
Apple, so the bindings should be generated from **Agora's own headers**, not Apple's. The
enabling dependency is `objc2`'s GNUstep runtime support, which lines up with the
`-fobjc-runtime=gnustep-2.0` ABI the tree already builds with.

This document records what was measured in the tree, the two-track binding strategy, the concrete
gaps that block a `cargo build` today, and a minimal proof-of-concept that would de-risk the two
real unknowns.

---

## 1. What "the Agora APIs" actually are

The stack is a federation of shared libraries, each its own repository, each with a different
language and ABI. They do not all bind the same way.

| Component dir | Product | Language / ABI | Installs a package? | Header prefix | Depends on |
|---|---|---|---|---|---|
| `libagora-objc` | GNUstep libobjc2 (`libobjc.so.4.6`) | C, ObjC runtime | yes — `libobjcConfig.cmake`, `libobjc.pc` | `objc/` | — |
| `libagora-dispatch` | libdispatch + BlocksRuntime | C | yes — `dispatchConfig.cmake` | `dispatch/`, `os/`, `Block.h` | — |
| `libagora-core` | Core Foundation | **C** | yes — `CoreFoundationConfig.cmake` | `CoreFoundation/` | dispatch, ICU |
| `libagora-lcms2` | little CMS | C | yes — `lcms2.pc` | `lcms2.h` | — |
| `libagora-drawing` | Core Graphics | **C** | yes — `AgoraDrawingConfig.cmake` | `CoreGraphics/` | core, lcms2 |
| `libagora-text` | Core Text | **C** | yes — `AgoraTextConfig.cmake` | `CoreText/` | core, drawing |
| `libagora-base` | Foundation | **Objective-C** | yes — `FoundationConfig.cmake` | `Foundation/` | core, objc, dispatch, ICU, curl, zlib, OpenSSL |
| `libagora-app` | AppKit | **Objective-C** | **no** — no `install()`, no package | `AppKit/` (build-tree symlink only) | base, drawing, text, Wayland, xkbcommon |
| `window-server` | Wayland compositor | C | **no** — installs nothing yet | — | wayland, libinput, DRM |

That split is the whole answer in miniature: **five of the nine targets are plain C libraries**
(CF, dispatch, lcms2, CG, CT) and bind like any C library. **Two are Objective-C libraries**
(Foundation, AppKit) and bind through the Objective-C runtime. One is a runtime (libobjc2). One is
a compositor plus a Wayland protocol.

### ABI facts that determine feasibility

- **CF types are the standard opaque-struct ABI.** `libagora-core/include/CFString.h:455`
  declares `typedef const struct CF_BRIDGED_TYPE(NSString) __CFString * CFStringRef;`, and
  `CFBase.h:453` declares `CFTypeRef` as a bridged `void *`. This is exactly what
  `objc2-core-foundation` / `core-foundation-rs` target.
- **Toll-free bridging is implemented.** `CF_BRIDGED_TYPE` / `CF_BRIDGED_MUTABLE_TYPE` are defined
  in `CFBase.h:225-230`, and `libagora-base/Foundation.h` states that after the bridging work
  "its objects ARE Core Foundation objects". So `NSString*` and `CFStringRef` are the same object
  at runtime — but they will be *distinct Rust types*, so the bindings need explicit cast helpers.
- **Objective-C uses the GNUstep "v2" ABI.** `libagora-base/CMakeLists.txt:94,111` and
  `libagora-core/CMakeLists.txt:277` compile with `-fobjc-runtime=gnustep-2.0 -fblocks`.
  `nm -D libagora-base/build/libagora-base.so` shows GNUstep class symbols (`._OBJC_CLASS_*`) and
  the v2 send path (`objc_msgSend`, `objc_msgSend_stret`), plus `objc_autoreleasePoolPush/Pop`,
  `objc_loadWeak`, `_Block_copy/_Block_release`. This is the ABI `objc2`'s GNUstep feature expects.
- **Blocks are pervasive in the ObjC tiers.** 20+ Foundation headers declare block-taking methods
  (`NSArray`, `NSDictionary`, `NSOperationQueue`, `NSNotificationCenter`, …). Rust needs `block2`
  (or equivalent cdecl block plumbing) to call those and to pass blocks in.
- **Ownership is manual (MRC).** `libagora-base/Foundation.h` states the library is compiled
  **without ARC** and that every method "STORES the pointers it is given and owns NOTHING." This
  maps cleanly onto `objc2`'s `Retained<T>`/`Allocated<T>`, but the caller-side lifetime rules are
  real and must be documented per API.
- **Coverage is partial and deliberately different from Apple.** `libagora-base` has 193
  `@interface` declarations / 217 class symbols; `libagora-app` has 49 / 48. Apple ships
  thousands. 29 of the base headers explicitly note *removed* API (no `NSZone` at all;
  `NSCopying` is `-copy`, not `-copyWithZone:` — `NSObject.h:43-53`).

*One contradiction to resolve empirically:* `Foundation.h` says the runtime uses the "LEGACY"
ABI and that clang refuses `-fobjc-arc`, while the CMake files explicitly pass
`-fobjc-runtime=gnustep-2.0`. The compiled artifacts and `capabilities.h` (`OBJC_CAP_ARC`,
`OBJC_CAP_NONFRAGILE_IVARS`) suggest the v2 ABI is in use; the comment looks stale. Either way,
the *consumer* side is unaffected: Rust calls runtime functions directly and does not compile with
`-fobjc-arc`.

---

## 2. Two-track binding strategy

### Track A — the C tiers (CoreFoundation, CoreGraphics, CoreText, dispatch, lcms2)

Mechanical. These are `extern "C"` APIs over opaque pointers with no ARC and (in CF/CG/CT) no
blocks in their public headers. Options, in order of preference:

1. **Generate `-sys` crates with `bindgen` against the installed `build-prefix`.** This tracks the
   Agora headers exactly and survives Agora adding/removing declarations.
2. **Re-use `objc2-core-foundation`, `objc2-core-graphics`, `objc2-core-text`, `dispatch2`.** They
   target the same ABI and would likely link. Use them as a fast compatibility smoke test, then
   decide whether to keep them or fork. Risk: they are generated from Apple headers and will name
   a handful of symbols/enums Agora has not implemented.

`bindgen` notes: the headers use Apple availability macros, `__has_attribute`, and
`__has_feature`; keep those working by passing the real include paths and defining
`__APPLE__`-neutral shims only if needed. `CFSTR()` and the `CF_INLINE` helpers are macros/inlines,
not linkable symbols — the safe wrapper layer must provide Rust equivalents. Prefer an explicit
header allowlist (see §4) rather than scanning a directory.

### Track B — the ObjC tiers (Foundation, AppKit) and the runtime

Use the `objc2` ecosystem on its GNUstep runtime feature, plus `block2`:

- `objc2` gives `Retained`, `Allocated`, `autoreleasepool`, `ClassType`, `sel!`, `msg_send!`.
- Compile the Rust crate with `-fobjc-runtime=gnustep-2.0 -fblocks` (via `cc`/`.cargo/config`)
  and link `agora-base` / `agora-app` / `agora-core` / `objc`.
- The runtime is the standard libobjc2 entry points (`objc_msgSend`, retain/release/autorelease,
  `_Block_*`), which `objc2` and `block2` already call.

**Do not** consume `objc2-foundation`/`objc2-app-kit` as the final bindings. They are generated
against Apple's SDK and will call selectors Agora deliberately lacks (the `NSZone`/`copyWithZone:`
family is the clearest example, and it is load-bearing: `NSCopying`'s member is `-copy` here). A
call to a missing selector is an `unrecognized selector` fault at runtime, not a compile error.

The right generator is `objc2`'s own **header translator** (`framework-crates` / `header-translator`
in the objc2 project), pointed at Agora's headers instead of Apple's. That produces crates with the
same ergonomics as the Apple ones, but with Agora's actual surface, deviations included. This is
the single highest-leverage decision in the whole effort.

---

## 3. What is missing today (the "needs")

Measured gaps, in priority order:

1. **AppKit is not installable or `find_package`-able.** `libagora-app/CMakeLists.txt` has no
   `install()` and no `*Config.cmake.in`; `build-prefix/lib/cmake` has no `AppKit`, and
   `build-prefix/include/AppKit` does not exist. A Rust AppKit binding cannot find headers or a
   link target from an installed prefix. **Need:** install rules + `AppKitConfig.cmake` +
   `AppKit/` header destination, mirroring `libagora-drawing`.
2. **The Wayland protocol is not installed.** `libagora-app`'s own comment says window-server
   "installs nothing yet" and reads `protocol/agora-shell.xml` from source. Rust apps that want to
   be first-class Agora clients (rather than going through AppKit) need that XML at build time for
   `wayland-scanner`. **Need:** an install rule for `agora-shell.xml` (or a documented source
   path), and a `wayland-scanner`-generated `agora-shell` crate.
3. **No `.pc` files for most libraries.** Only `libobjc.pc` and `lcms2.pc` install. A cargo
   `-sys` build script is simplest with `pkg-config`; otherwise it must shell out to CMake or
   hardcode paths. **Need:** either install `*.pc` files for `agora-core`, `agora-base`,
   `agora-drawing`, `agora-text`, or standardize build scripts on the `cmake` crate against the
   existing `*Config.cmake` packages.
4. **Installed headers include internals.** `libagora-base/CMakeLists.txt:127` installs *every*
   `.h` under `Foundation/`, including `FN*.h` private headers (`FNArchiverWire.h`,
   `FNStringFormat.h`, …). A directory-scan generator would emit bindings for internals. **Need:**
   an explicit public-header inventory for the generator.
5. **The compiler/flag contract is implicit.** Agora exports `-fobjc-runtime=gnustep-2.0` and
   `-fblocks` on the CMake INTERFACE, but a cargo build does not read CMake INTERFACE flags.
   **Need:** the `-sys` crates' build scripts must replicate the flags, and the crates must fail
   loudly if the flags are absent (otherwise clang silently emits legacy-ABI symbols).
6. **No API ledger in-tree.** The component READMEs refer to a symbol-level "ledger" that is not
   part of these repositories. Without it, "what is actually implemented" must be derived from the
   headers and `nm`. **Need:** generate a machine-readable inventory (classes, protocols,
   selectors, CF/CG/CT symbols) from the installed prefix; use it both to drive binding generation
   and to gate CI.
7. **Toll-free bridging has no ergonomic layer.** `CFStringRef` ↔ `NSString*` are the same object
   but different Rust types. **Need:** conversion helpers in the umbrella crate.
8. **All libraries are shared with no evident SONAME/versioning story.** Fine for development;
   matters for shipping bindings that pin an ABI.

---

## 4. Compatibility risks (concrete)

- **Unimplemented selectors.** `objc2-foundation`-generated code will call `-copyWithZone:`,
  reference `NSZone`, and touch classes Agora does not declare. Runtime fault, not compile error.
  Mitigation: generate from Agora headers; keep an allowlist; add a "responds to selector" test
  suite that mirrors the header surface.
- **`objc2` GNUstep support is the linchpin.** If it does not cover this exact libobjc2 build, the
  ObjC tiers need a bespoke (small) message-send layer instead. This is the first thing to test.
- **MRC semantics.** The "stores, owns nothing" rule means Rust must keep delegate/target/observer
  objects alive for the duration of use; the `Retained<T>` model handles the mechanics but the
  policy must be documented per binding.
- **Block lifetimes.** Foundation copies blocks in some methods and not others; `block2`'s
  `StackBlock`/`RcBlock` distinction must be applied correctly.
- **Header drift.** Because the tree deliberately deviates from Apple and actively removes API,
  hand-maintained bindings will rot. Generation from headers is not a nicety; it is the only way
  this stays correct.
- **Toolchain.** `clang` only, `-fblocks`, `-fobjc-runtime=gnustep-2.0`; gcc is unsupported
  (`libagora-text`'s package config says so explicitly). Build scripts must not let rustc's
  default `cc` pick gcc.

---

## 5. Recommended crate layout

A Cargo workspace mirroring the tiers, generated where possible:

```
agora-sys/            # umbrella re-exports, CF<->NS bridge helpers
  agora-core-sys/     # bindgen over CoreFoundation      (or objc2-core-foundation)
  agora-drawing-sys/  # bindgen over CoreGraphics        (or objc2-core-graphics)
  agora-text-sys/     # bindgen over CoreText            (or objc2-core-text)
  agora-dispatch-sys/ # bindgen over dispatch            (or dispatch2)
agora-objc/           # re-exports objc2 + block2, pinned to the gnustep-2.0 feature
agora-foundation/     # objc2-based, generated from Agora headers
agora-app-kit/        # objc2-based, generated from Agora headers (needs §3.1 first)
agora-shell/          # wayland-scanner over agora-shell.xml (needs §3.2)
```

Generation path: `objc2`'s header translator (`framework-crates`) fed by an explicit list of
Agora public headers, then a thin hand-written layer for toll-free bridging and the documented
deviations.

---

## 6. Minimal proof-of-concept (de-risks the two unknowns)

Before committing to a full workspace, build three small things:

1. **C tier:** a `-sys` crate that links `libagora-core.so` and round-trips
   `CFStringCreateWithCString` → `CFStringGetLength`. Confirms the installed prefix, include
   layout, and link line.
2. **Runtime/ObjC tier:** an `objc2` program that allocates an `NSString`, calls
   `initWithUTF8String:`, wraps it in an autorelease pool, and releases it. This proves
   `objc2`-on-GNUstep-2.0 works against `libagora-base.so` — the single biggest unknown.
3. **Bridging tier:** pass the `NSString` where a `CFStringRef` is expected via a cast and call a
   CF function on it. Proves toll-free bridging holds through Rust's type boundary.

If (2) fails, the fallback is a small in-house runtime shim over `objc_msgSend`; the C tiers are
unaffected either way.

---

## 7. Effort read

- **C tiers:** low. Generation plus a bridge layer; no semantic surprises.
- **ObjC tiers:** medium. The work is in tooling (translator setup, header allowlist, flag
  plumbing) and in faithfully carrying Agora's deviations, not in fundamental difficulty.
- **Blocking prerequisites:** AppKit install rules, the protocol install rule, and a build-script
  bridge to the CMake/pc packages.
- **Overall:** worth doing, and the tree is unusually well set up for it (clean CMake packages,
  installed headers, toll-free bridging, a standard runtime). The win is largest for the C tiers
  (immediate) and for Foundation (the bulk of the useful API surface). AppKit bindings should
  wait until it is installable.
