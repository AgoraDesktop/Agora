# Developing for Agora in Swift — an investigation into the Objective-C/Swift bridge

*Status: investigation. This document answers whether Agora can support Swift
development, what "the Objective-C–Swift bridge" concretely is, and which of the
proposed routes is worth taking. It is evidence-first: every claim is tied to a
file, a symbol dump, a commit, or a pinned revision.*

---

## Verdict

**The bridge does not need to be re-implemented from scratch, and it is not an
LLVM problem.** Swift's Objective-C interop lives in the **Swift frontend**
(Clang importer + IRGen) and the **Swift runtime** (`libswiftCore`), not in LLVM.
LLVM/clang already do their part, and Agora already builds everything with clang.

A working GNUstep/`libobjc2` interop path **already exists**, and — critically —
it targets the **exact same Objective-C runtime Agora pins** (`libobjc2` v2.3).
The compiler-side change is small: **3 commits, 30 files, ~480 added lines**
(`OpenSwiftProject/swift`, branch `feature/gnu_objc_6.3`).

So the realistic question is not *"can this be built?"* but *"how much of the
residual Cocoa-development semantics (Swift-defined `@objc` classes, `super`
dispatch, Foundation bridging, `#selector`) is missing, and who should own the
fork?"* — and whether a fork is needed at all, or whether Agora should first
consume the existing work.

| Question | Answer |
|---|---|
| Is it possible? | Yes. Demonstrated end-to-end against `libobjc2` v2.3. |
| Does it require modifying LLVM? | No. Requires a patched **Swift frontend + Swift stdlib runtime**. |
| Size of the Swift-side patch? | ~480 lines / 30 files / 3 commits (measured, §3). |
| Same ObjC runtime as Agora? | Yes — both pin `libobjc2` v2.3 (§4). |
| Does it work today for apps? | Only partially. Importing and calling ObjC works; **Swift-defined `@objc` classes/subclasses and Foundation bridging do not** (§6). |
| Recommended first move? | Do **not** fork first. Consume the existing fork/toolchain, point it at `libagora-base`, and measure the gaps (§7). |

---

## 1. What "the Objective-C–Swift bridge" actually is

The phrase bundles three distinct layers. Confusing them is what makes the task
look like a rewrite when it is not.

1. **Compile-time importer.** Swift's `ClangImporter` parses Objective-C headers
   and module maps through an embedded Clang, and surfaces classes, protocols,
   methods and properties as Swift declarations. This is why Agora's headers must
   be clang-moduleable, and it is *not* a runtime concern.
2. **Codegen / ABI.** `IRGen` decides how a Swift declaration becomes Objective-C:
   the **linker symbol spelling** for a class (`OBJC_CLASS_$_Foo` vs
   `._OBJC_CLASS_Foo`), the **selector reference format**, message-send calls
   (`objc_msgSend` / super variants), `@objc` thunk emission, and class metadata.
   **This is the actual "bridge" and it is ABI-specific.**
3. **Runtime glue.** The Swift runtime's ObjC interop entry points
   (`swift_getObjCClassMetadata`, `swift_getObjCClassFromMetadata`, …) plus the
   Objective-C runtime's class-registration SPI
   (`objc_readClassPair`, `_objc_realizeClassFromSwift`, …).

**Terminology correction.** If "our LLVM runtime" means Agora's runtime
(`libobjc2` + `libagora-*`), that is the *Objective-C* runtime, a different thing
from LLVM. LLVM is only the code generator underneath both clang and Swift. No
part of the bridge lives in LLVM, and Agora's LLVM needs no changes. If the
phrase instead means "build the Swift compiler with our LLVM", that is
orthogonal to the bridge and also unnecessary — Swift ships and builds against
stock LLVM.

---

## 2. The ABI mismatch, measured

This is the crux of the whole problem. The two runtimes spell the same concepts
differently, and Swift's IRGen hard-coded the Darwin spelling. Confirmable
locally with the host's clang 19 and Agora's own headers:

```console
$ clang -c -fobjc-runtime=gnustep-2.0 -fobjc-arc abicheck.m   # Agora's ABI
U ._OBJC_CLASS_NSObject
D ._OBJC_CLASS_Widget
D ._OBJC_REF_CLASS_Widget
V .objc_selector_make...
V .objc_sel_name_make
U __start___objc_class_refs
U __start___objc_selectors
        sections: __objc_selectors, __objc_classes, __objc_class_refs

$ clang -c -fobjc-runtime=macosx -fobjc-arc abicheck.m          # Apple's ABI
U OBJC_CLASS_$_NSObject
D OBJC_CLASS_$_Widget
```

Three concrete differences, and they are the entire "bridge" problem:

- **Class symbols.** GNUstep/`libobjc2` v2 uses `._OBJC_CLASS_<Name>` and a
  class-reference slot `._OBJC_REF_CLASS_<Name>`; Darwin uses `OBJC_CLASS_$_<Name>`.
- **Selectors.** GNUstep emits writable two-word selector records into
  `__objc_selectors`, registered by a clang-generated image initializer;
  Darwin uses `__objc_selrefs`.
- **Super dispatch.** Darwin uses `objc_msgSendSuper2`; GNUstep's `libobjc2` does
  not export that symbol (verified in §4).

Agora already sits entirely on the GNUstep side: `libagora-core`,
`libagora-base` and `libagora-objc` all compile with `-fobjc-runtime=gnustep-2.0`,
and `libagora-base` even aliases `._OBJC_CLASS_*` symbols directly
(`libagora-base/NSCFConstantString.m`). **The ABI the Swift fork targets is the
ABI Agora already emits.**

---

## 3. What already exists (evidence)

### 3.1 An end-to-end Swift 6.3 + GNUstep toolchain

`OpenSwiftProject/toolchain-docker` builds an alpha image containing the Swift
compiler, `libobjc2`, GNUstep Foundation, and a SwiftPM/LLBuild toolchain;
`OpenSwiftProject/toolchain-example` is the smoke test. Key pinned revisions
(`scripts/clone-sources.sh`, Dockerfile):

- `SWIFT_BRANCH=feature/gnu_objc_6.3` on `OpenSwiftProject/swift`
- `LIBOBJC2_REF=v2.3`  ← **the same pin as Agora**
- `LIBDISPATCH_BRANCH=release/6.3`, GNUstep `tools-make make-2_9_3`,
  `libs-base base-1_31_1`, `libs-corebase corebase-0_1_1`

The user-facing flags are exactly the missing surface:

```text
-Xfrontend -enable-objc-interop
-Xfrontend -objc-runtime-vendor=gnustep
# importer flags: -fobjc-runtime=gnustep-2.0 -fobjc-arc -fblocks ...
```

and the stdlib is built with `SWIFT_STDLIB_ENABLE_OBJC_INTEROP=TRUE` plus
build-script `--swift-objc-interop=1`.

### 3.2 The compiler patch is small and local

`OpenSwiftProject/swift` `release/6.3...feature/gnu_objc_6.3` =
**3 commits, 30 files, 480 additions, 20 deletions.** The substance:

| File | Change |
|---|---|
| `include/swift/Basic/LangOptions.h` | new `ObjCRuntimeVendor { Apple, GNUstep }`, plumbed into option hashing |
| `include/swift/Option/FrontendOptions.td` | new `-objc-runtime-vendor=<apple\|gnustep>` |
| `lib/Frontend/CompilerInvocation.cpp` | parse/validate the flag; GNUstep **requires ELF** |
| `lib/ClangImporter/ClangImporter.cpp` | pass `-fobjc-runtime=gnustep-2.0` to the embedded Clang |
| `lib/IRGen/Linking.cpp` | emit `._OBJC_CLASS_` / `._OBJC_REF_CLASS_` under GNUstep |
| `lib/IRGen/GenObjC.cpp` | emit GNUstep selector records into `__objc_selectors` |
| `stdlib/public/runtime/GNUstepObjCCompatibility.mm` | new: runtime shims (see below) |
| `stdlib/public/runtime/SwiftObject.{h,mm}`, `HeapObject.cpp`, `Metadata.cpp`, `ErrorObject.mm` | GNUstep guards |
| `stdlib/public/Concurrency/DispatchGlobalExecutor.cpp` | GNUstep guard |
| `docs/GNUstepClassSymbols.md`, `test/IRGen/*`, `test/Frontend/objc_runtime_vendor.swift` | documentation + lit tests |

The runtime shim (`GNUstepObjCCompatibility.mm`) is ~60 lines and supplies:
`_objc_empty_cache`, `objc_absolute_packed_isa_class_mask`, `_objc_rootAutorelease`,
`objc_opt_self`, `objc_constructInstance`, `objc_destructInstance`,
`objc_readClassPair`. **These are stubs**, and that is the important caveat — for
example `objc_readClassPair(cls, …)` merely returns `cls`, and `objc_destructInstance`
is a no-op.

### 3.3 What the smoke test proves — and does not

Proven: importing a GNUstep Objective-C module; class references to both a
package class and shared-library Foundation classes (`NSString`, `NSObject`);
instance and class messages; property getters/setters; multi-argument selectors;
repeated selectors across files; ARC; Blocks; linking without per-class linker
aliases or selector patching.

Explicitly **not** proven (quoted from the project's own README and issue
tracker):

- "does not establish general runtime metadata correctness or **support for
  Swift-defined `@objc` classes and subclasses**" — issues #2/#3
- "**No Darwin-equivalent implicit Foundation bridging** in v1" — issue #1
- "Source-level `#selector` also requires the Swift `ObjectiveC` module/overlay,
  which this Linux toolchain does not yet install" — issue #1
- Directly importing the ObjC target from a SwiftPM *test* target is not yet
  supported.

Live tracker: `OpenSwiftProject/swift` issues **#1** (opt-in platform variant),
**#2** (runtime ObjC metadata SPI), **#3** (GNUstep ABI in IRGen — largely
shipped in the `6.3-alpha.3` fork work).

---

## 4. Fit with Agora specifically

**Good news — the important pieces already line up.**

- **Runtime identity.** Agora's `libobjc2` pin is **v2.3**
  (`e877e782fb965c4e870d2ecf6aff58dddc6290ae`); the OpenSwift toolchain pins the
  same `v2.3`. libobjc2 already provides the modern runtime surface Swift needs:
  ARC entry points (`objc_retainAutoreleasedReturnValue`, `objc_autoreleaseReturnValue`),
  weak references (`objc_storeWeak`/`objc_loadWeak`), class-pair allocation
  (`objc_allocateClassPair`, `objc_registerClassPair`, `class_addMethod`,
  `class_addIvar`), protocols (`objc_registerProtocol`), associated objects,
  `sel_registerName`, `objc_getClass`/`objc_lookUpClass`.
- **ABI.** Agora compiles with `-fobjc-runtime=gnustep-2.0` throughout and emits
  the `._OBJC_CLASS_*` spelling the fork's IRGen targets (§2).
- **Licensing.** Swift, LLVM, `libobjc2` and `swift-corelibs-libdispatch` are all
  Apache-2.0/MIT — compatible with Agora's permissive-only rule. Notably,
  Agora's *own* `libagora-base` (MIT) is what must be imported, **not** GNUstep
  `libs-base` (LGPL), which Agora's licence policy excludes anyway. The interop
  path only needs Objective-C *headers* plus the `libobjc2` runtime, so this is
  fine.

**Gaps on the Agora side.**

- **`libobjc2` v2.3 lacks SPI the Swift runtime calls.** Verified by symbol
  search of `libagora-objc`:

  | Swift needs | In libobjc2 v2.3? |
  |---|---|
  | `objc_readClassPair` (dynamic class registration) | **absent** |
  | `_objc_realizeClassFromSwift` (stub-class realization) | **absent** |
  | `objc_loadClassref` (stub classes) | **absent** |
  | `objc_msgSendSuper2` (super dispatch) | **absent** |
  | `objc_opt_self` | **absent** (supplied by Swift shim) |
  | `_objc_empty_cache`, `_objc_rootRetain`, `_objc_rootRelease` | **absent** |
  | `objc_constructInstance` / `objc_destructInstance` | **absent** |
  | ARC retain/release-autorelease, weak, class-pair, method/ivar, protocols, associated objects, selectors | present |

  The OpenSwift fork papers over the absent ones with stubs **in the Swift
  runtime**, deliberately keeping `libobjc2` unmodified. That works for the smoke
  test; it is not a foundation for generic classes or `@objc` subclasses.

- **`libagora-dispatch` deliberately removed all Swift support.** Its
  `PROVENANCE.md` records: *"Agora does not support Swift, so the Swift overlay
  and its build integration have been removed: deleted `src/swift/` … removed the
  `ENABLE_SWIFT` option, `enable_language(Swift)`, … the `lib/swift` install
  destinations."* Swift needs that overlay (and its apinotes/shims) for `Dispatch`,
  `DispatchQueue`, and Swift concurrency's executor. It must be restored — and
  note Agora pins dispatch `swift-6.4.0-RELEASE` while the toolchain builds
  `release/6.3`, a version skew to reconcile.

- **Agora has no Swift-facing module map / apinotes.** `build-prefix` installs
  `libagora-base`/`libagora-core` headers and `.so`s, but Swift needs a clang
  module (`module Foundation { … }`) and ideally apinotes for nullability and
  generics, exactly as the DemoKit target provides for GNUstep Foundation.

---

## 5. The directions of the bridge

It is worth separating two directions, because they have very different maturity:

- **Swift → Objective-C** (import a class, call `objc_msgSend`): **works today.**
  This is what the OpenSwift smoke test exercises.
- **Objective-C → Swift** (a Swift class that is an `NSObject` subclass, with
  `@objc` methods that AppKit/protocols/target-action can call): **the gap.**
  This requires Swift to lay down a real Objective-C class and register it with
  `libobjc2`, plus `super` dispatch. Without it, the characteristic Cocoa idioms
  — `NSApplicationDelegate`, target/action, `KVO`, `NSTableViewDataSource`,
  custom `NSView`/`NSControl` subclasses — cannot be written in Swift.

Since Agora's *purpose* is the Cocoa API surface, the second direction is the one
that actually matters, and it is the least proven.

---

## 6. Gaps for real Cocoa-style Swift development, ranked

1. **Swift-defined `@objc` classes / `NSObject` subclasses (blocking).** Needs a
   real `objc_readClassPair` (or equivalent libobjc2 registration), stub-class
   support (`objc_loadClassref`, `_objc_realizeClassFromSwift`), and super
   dispatch (`objc_msgSendSuper2` → GNUstep `objc_msgSendSuper` mapping in IRGen).
   Today these are stubs or absent.
2. **Foundation bridging (`String`↔`NSString`, `Array`↔`NSArray`,
   `Dictionary`↔`NSDictionary`, `NSNumber`).** A v1 non-goal upstream. Requires
   `_ObjectiveCBridgeable` conformances compiled against `libagora-base`'s
   classes (and the stdlib rebuilt with interop). Large but well-understood.
3. **`#selector` / `Selector` / the `ObjectiveC` overlay module.** Not installed
   by the Linux toolchain; required for target/action.
4. **Generic Swift classes.** Dynamically generated classes go through
   `objc_readClassPair`; the current stub does not realize them.
5. **Lifecycle correctness.** `objc_constructInstance`/`objc_destructInstance`
   are stubs; associated-object and ivar teardown are not real.
6. **Module map + apinotes for `libagora-base`/`libagora-app`.** Mechanical, but
   it is what turns raw headers into an ergonomic Swift API.
7. **Toolchain ownership.** Building Swift from source, and rebasing a fork each
   release.

---

## 7. Routes compared, and a recommendation

| Route | What it means | Assessment |
|---|---|---|
| **A. Fork Swift (the proposed route)** | Patch the Swift frontend/IRGen + stdlib runtime for the GNUstep ABI. | **Viable and already ~90% done** by OpenSwiftProject. But LLVM is untouched, and owning a rebasing Swift fork is an ongoing tax. Do this only for the *residual* gaps. |
| **B. Consume the existing fork/toolchain first** | Use `OpenSwiftProject/toolchain-docker` (Swift 6.3, `libobjc2` v2.3), point the Clang importer at `libagora-base`. | **Recommended first step.** Zero fork ownership; immediately answers "what actually breaks with Agora's headers?" |
| **C. Pure Swift, no ObjC interop** | Write Agora apps in Swift against a Swift-native overlay. | Avoids the whole bridge but abandons the Cocoa API surface — contradicts Agora's stated goal. |
| **D. Extend `libobjc2`, not the Swift runtime** | Implement `objc_readClassPair`, `_objc_realizeClassFromSwift`, stub classes and `objc_msgSendSuper2` properly in Agora's runtime component. | **Likely the right home** for the runtime-metadata gap (#2). Agora owns `libobjc2`; the Swift fork's stubs are the wrong long-term location. |
| **E. Upstream the work** | Contribute the GNUstep ABI mode to swiftlang/swift. | Best long-term outcome; removes the fork. Compatible with A–D. |

**Recommendation.** Start at **B**; move the runtime-metadata fixes into **D**
(where Agora controls the code); keep a *minimal* **A** only for frontend/IRGen
pieces and push them **E**. Concretely:

1. Pull the published toolchain image and run the OpenSwift smoke test — confirm
   the environment end to end.
2. Add a clang module map for `build-prefix/include` (`libagora-base`) and import
   `NSObject`/`NSString` from Swift with the GNUstep flags — mirror DemoKit.
3. **Measure the hard case:** `class MyDelegate: NSObject { @objc func
   applicationDidFinishLaunching(...) {} }`, `#selector`, pass an instance to
   Objective-C, and call it back. Every failure here *is* the work list.
4. Decide fork ownership (A/E) vs runtime extension (D) based on step 3.
5. Restore the Swift overlay in `libagora-dispatch` and reconcile the 6.3/6.4 skew.
6. Only then attempt stdlib bridging conformances (§6.2).

---

## 8. Risks and open questions

- **Fork maintenance.** `feature/gnu_objc_6.3` must be rebased onto every Swift
  release, and the fork-local `-objc-runtime-vendor` flag may collide with
  upstream changes.
- **SPI stability.** The interop hook names are documented as "implementation
  details, subject to change" by Swift itself.
- **Runtime-metadata correctness.** The current shims are stubs; generic classes
  and `@objc` subclasses are uncharted until step 3 is run.
- **Dispatch version skew.** Agora `swift-6.4.0-RELEASE` vs toolchain
  `release/6.3`.
- **Build cost.** A full Swift toolchain build is hours of CPU and tens of GB of
  disk; the Docker image is the pragmatic path.
- **Licensing** is *not* a blocker here: everything on the critical path is
  Apache-2.0/MIT. The LGPL GNUstep `libs-base` is avoidable and must be avoided
  under Agora's rules; Agora's own MIT Foundation is the right target.

---

## Appendix — evidence index

- Agora runtime pin: `libagora-objc/PROVENANCE.md` → `libobjc2` v2.3,
  `e877e782fb965c4e870d2ecf6aff58dddc6290ae`.
- Agora ABI: `libagora-core/CMakeLists.txt`, `libagora-base/CMakeLists.txt`,
  `libagora-objc/CMakeLists.txt` → `-fobjc-runtime=gnustep-2.0`;
  `libagora-base/NSCFConstantString.m` → `._OBJC_CLASS_*` alias.
- Agora Swift removal: `libagora-dispatch/PROVENANCE.md` → Swift overlay deleted;
  pin `swift-6.4.0-RELEASE`.
- Swift interop spec: `swiftlang/swift` `docs/ObjCInterop.md` (messaging, class
  emission, `objc_readClassPair`, `objc_loadClassref`, `_objc_realizeClassFromSwift`).
- Existing toolchain: `OpenSwiftProject/toolchain-docker` (Dockerfile,
  `scripts/clone-sources.sh`, `scripts/build-swift-toolchain.sh`) and
  `OpenSwiftProject/toolchain-example` (README, `Package.swift`,
  `DemoKit/ObjCInteropShim.c`).
- Swift patch: `OpenSwiftProject/swift` compare `release/6.3...feature/gnu_objc_6.3`
  — 3 commits, 30 files, +480/−20; `stdlib/public/runtime/GNUstepObjCCompatibility.mm`,
  `lib/IRGen/GenObjC.cpp`, `lib/IRGen/Linking.cpp`, `lib/ClangImporter/ClangImporter.cpp`,
  `lib/Frontend/CompilerInvocation.cpp`, `include/swift/Basic/LangOptions.h`.
- Tracked work: `OpenSwiftProject/swift` issues #1, #2, #3.
- Local ABI measurement: `clang -fobjc-runtime=gnustep-2.0` vs `-fobjc-runtime=macosx`
  symbol/section dump (§2), using `/usr/lib/llvm-19/bin/clang` and Agora's headers.
