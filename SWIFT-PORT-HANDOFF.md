# Swift-on-Agora port — handoff

*Status: **the compiler works.** `swiftc` type-checks, compiles, links and runs
Swift against Agora at `-Onone` and `-O`, including classes, generics,
protocols, existentials, error handling and Unicode strings; and Swift can
import Agora's `Foundation`, allocate its `NSObject` and message it. Verified by
[`swift-toolchain/scripts/verify-swift-port.sh`](swift-toolchain/scripts/verify-swift-port.sh).

The wall described in the previous handoff ("one process, two class-metadata
ABIs") is gone, and it was broken in two steps that are worth keeping distinct:

1. **Layout.** The runtime was migrated to the **compact** class layout
   (`SWIFT_OBJC_CLASS_LAYOUT == 0`), the layout the compiler's own Swift
   libraries already had. That is option A of §4 of the previous handoff, taken
   as the migration step rather than as the destination.
2. **Host/target runtime split.** The compiler is a *host tool*; it now runs on
   the non-interop standard library it was built with, while the programs it
   produces use the toolchain's interop stdlib. This is what actually dissolves
   the wall, and it is why stage S1 of
   [`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md) — Swift classes as
   GNUstep class objects — is no longer blocked behind a two-stage build.

Companion documents:
[`SWIFT-INTEROP-INVESTIGATION.md`](SWIFT-INTEROP-INVESTIGATION.md) (feasibility),
[`SWIFT-TOOLCHAIN-INTEGRATION.md`](SWIFT-TOOLCHAIN-INTEGRATION.md) (runtime
reconciliation), [`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md)
(the destination ABI), [`swift-toolchain/README.md`](swift-toolchain/README.md)
(build scripts).

---

## 1. Where it stands

**Works** (all of it re-verified on this host after the changes below):

```
$ swiftc --version
Swift version 6.3.3-dev (LLVM 82cdc19fa54d566, Swift 38cb233d6848882)
Target: x86_64-unknown-linux-gnu

$ swiftc -typecheck empty.swift                       # exit 0
$ swiftc -o prog prog.swift && ./prog                 # runs
$ swiftc -O -o prog prog.swift && ./prog              # runs
```

| Area | Verified |
|---|---|
| parser / Sema / SIL | empty file, multi-file-free single-file programs, `-O` pipelines |
| classes | allocation, deinit, inheritance, `super`, vtables, field offsets |
| generics | generic classes (`_ContiguousArrayStorage`), `Array`, `Set`, `Dictionary`, prespecialised metadata |
| existentials | class existentials (`[any P]`), `AnyObject` boxes holding Swift classes |
| errors | `throw` / `catch` / `try?`, native error boxes (`ErrorObjectNative.cpp`) |
| strings | interpolation, Unicode (`"héllo 🌍"`), `String(repeating:)` |
| concurrency types | `actor` declaration (not exercised at runtime) |
| **Agora interop** | `import Foundation` (Agora's), `NSObject.alloc()`, `isKind(of:)`, `description()`, `object_getClass`/`class_getName` through libobjc2 |
| **default flags** | `swiftc prog.swift` enables Objective-C interop and selects the GNUstep runtime ABI family without any `-Xfrontend` flags |
| **super dispatch** | a Swift `super.` send to an imported class emits `objc_msg_lookup_super` + a direct IMP call, not Apple's `objc_msgSendSuper2`; such a program now **links** (semantics need S1/S5, see below) |
| **the two probes** | `agora-import-probe`: 11/11 checks; `objc-to-swift-probe`: compiles and links, then traps in `objc_allocWithZone` when the Swift subclass is first allocated |

**Not available yet**, and by design with the compact layout (see §4):

- Swift classes are **not** Objective-C class objects: `@objc` members on them,
  subclassing Agora's `NSObject` in Swift, categories, and ObjC→Swift dispatch
  do not work. Interop is one-way: Swift can message Agora objects, Agora never
  sees a Swift class.
- No Foundation *bridging* of Swift values: `String` ↔ `NSString`, `Array` ↔
  `NSArray` and `Error` ↔ `NSError` all need the ObjC-object layout (and, for
  the value types, a Foundation overlay, which this toolchain does not build).
- **Swift class instantiation.** Any Swift class that inherits an imported class
  is instantiated through the Objective-C allocator: even with its own
  initializer, `T(start:)` is emitted as `Counter.__allocating_init(start:)` →
  `objc_allocWithZone`, and libobjc2 then treats the Swift metadata as a class
  object. With the compact layout that is invalid: the probe (and a two-line
  `class Counter: NSObject` with an explicit init) traps in
  `objc_test_class_flag`. S1/S5.
- **`NSObject()` sugar.** Even for a genuine Agora class the sugar goes through
  `objc_allocWithZone`, which sends `+allocWithZone:`; Agora's `NSObject`
  deliberately has no zone-taking API (`libagora-base/NSObject.h`), so the call
  raises `NSInvalidArgumentException`. Use `.alloc()` — this is the open decision
  in §5 item 5.
- **Property-shaped imported accessors.** Agora declares `- (size_t)length` and
  friends as methods (Apple and GNUstep declare a `length` property), so Swift
  writes `text.length()`, not `text.length`. Not a port defect, but it is what
  the probes had to be adapted to.
- **`__SwiftValue` bridging and the `SwiftNativeNS*` wrapper classes** are
  Swift-refcounted Objective-C classes; with layout 0 they have no Swift heap
  header. Untested, expected to fail. Nothing in the verified programs reaches
  them.

---

## 2. What was fixed, in order

### 2.1 (previous rounds, still in force)

- **The "is Swift" bit.** IRGen emitted Darwin's marker bit (2) everywhere;
  `Runtime/Config.h` uses 1 off Darwin. Fixed by choosing the bit per target.
- **`object_getClass()` on Swift metadata** under libobjc2 reads the wrong word;
  the runtime now reads its own ISA on the GNUstep vendor.
- **`swift_instantiateObjCClass`** used to message libobjc2 with Swift metadata;
  it is a no-op under GNUstep.

### 2.2 The compiler started, then trapped on every compile

Root cause (previous handoff §3): the compiler's own Swift libraries
(`SwiftCompilerSources`, both swift-syntax copies, `lib_CompilerSwift*`) are
compiled by the **bootstrap** toolchain without interop, while `libswiftCore`
was compiled **with** it — and interop used to change the size of every class
metadata header from 2 words to 5. The two could not share a process.

### 2.3 The runtime now uses the compact class layout

`SWIFT_OBJC_CLASS_LAYOUT` (0 compact / 1 Apple / 2 GNUstep) existed already but
nothing read it. It is now **0 by default off Darwin**, which is the layout
bootstrap-compiled code emits. The fork gained:

| Layer | Change |
|---|---|
| `Runtime/Config.h` | default layout 0 off Darwin; `SWIFT_OBJC_CLASS_OBJECT_LAYOUT`; `SWIFT_ERROR_IS_NSError` |
| `ABI/Metadata.h` | `TargetMetadata::getRawKind()`; compact `isTypeMetadata()` = *raw* kind is `Class`; `TargetObjCClassWrapperMetadata::Class` typed by layout; `setAsTypeMetadata()` only for layout 1 |
| `ABI/MetadataRef.h` | `TypeReference::getObjCClass`/`getIndirectObjCClass` return the layout-selected class metadata type |
| `IRGen/IRGenModule.h` | `usesObjCClassObject()` — the one predicate IRGen keys "emit an ObjC class object" decisions off |
| `IRGen/ClassMetadataVisitor.h`, `IRGen/GenMeta.cpp`, `IRGen/GenClass.cpp` | the layout-deciding uses of `ObjCInterop` switched to `usesObjCClassObject()`: cache/data slots, metaclass-as-kind, root superclass, resilient/generic metadata pattern offsets, ObjC class registration, constant-ness of specialised metadata, ObjC resilient class stubs |
| `runtime/Metadata.cpp` | class-object-only blocks (RO-data, metaclass, cache data, ivar lists, `objc_readClassPair` registration) guarded by layout 1; no metaclass/RO-data reads in the pattern initialisers under layout 0 |
| `runtime/MetadataImpl.h` | the `AnyObject` box retains/releases through `swift_unknownObjectRetain/Release` under layout 0 (an `AnyObject` box can hold a Swift class there) |
| `runtime/Casting.cpp`, `DynamicCast.cpp` | class-metatype casts walk `Superclass` instead of messaging `isSubclassOfClass:` under layout 0 |
| `runtime/ErrorObject.h`, `ErrorObject.mm`, `ErrorObjectNative.cpp` | the NSError-layout error box model is selected by `SWIFT_ERROR_IS_NSError`; layout 0 uses the native `SwiftError` (plain heap object) |
| `runtime/SwiftObject.mm` | `getRootSuperclass()` is null without a class-object layout; NSError bridging in the ObjC cast helpers gated |

Four runtime defects surfaced only once the compiler could run, and each is
in the table above:

1. **`swift_dynamicCastMetatype` messaged `isSubclassOfClass:`** on compact
   Swift class metadata (the compiler's own `StructExtractInst` class) →
   SIGSEGV inside `objc_msgSend_fpret`. Fixed by walking `Superclass`.
2. **`AnyObject` boxes released Swift classes with `objc_release`**
   (`ObjCRetainableBox`), which is only correct when Swift classes are ObjC
   class objects. Fixed via `swift_unknownObjectRetain/Release`.
3. **`getEnumeratedMetadataKind()` maps every non-enumerated kind to
   `MetadataKind::Class`.** So a GNUstep class object read as compact metadata
   *looks like* Swift class metadata, and `isTypeMetadata()` cannot be
   `getKind() == Class`. It is the *raw* kind word that discriminates
   (`0` for a Swift class, an `isa` pointer for a class object). Getting this
   wrong crashed the runtime while walking a superclass chain that ended in
   `SwiftObject`.
4. **Error boxes were NSError-shaped.** `SwiftError` uses an NSError-compatible
   header under interop, but that header is a *Swift class object*; under layout
   0 the box was released as Swift heap memory and read garbage as its
   destructor. The native error-box implementation is now used.

### 2.4 The host/target runtime split (the important one)

The next failure was not a layout problem:

```
swift-frontend: symbol lookup error: undefined symbol:
  $sSa28_allocateBufferUninitialized15minimumCapacitys016_ContiguousArrayB0VyxGSi_tFZ
```

The compiler wanted the **non-interop** mangling; the installed stdlib exported
the **interop** one. Decoded:

```
static Swift.Array._allocateBufferUninitialized(minimumCapacity: Int)
  -> Swift._ContiguousArrayBuffer<A>   (bootstrap stdlib, compiler binary)
  -> Swift._ArrayBuffer<A>             (toolchain stdlib)
```

because `Array`'s private storage type is chosen by `_runtime(_ObjC)`:

```swift
#if _runtime(_ObjC)
  typealias _Buffer = _ArrayBuffer<Element>
#else
  typealias _Buffer = _ContiguousArrayBuffer<Element>
#endif
```

So enabling interop for the **target** stdlib changes the stdlib's own ABI, and
the compiler binary — built by the bootstrap toolchain against the bootstrap
stdlib — cannot run on it. This would have happened with layout 2 as well; class
layout was never the only difference.

The fix is structural, not a patch: **the compiler is a host tool and must run
on the host standard library it was built against.** The installed `swiftc` is
now a small wrapper that puts the bootstrap Swift runtime on
`LD_LIBRARY_PATH` for the compiler process only, and `exec -a swiftc
swift-frontend` (so the legacy driver still sees the `swiftc` argv[0]):

```sh
#!/usr/bin/env bash
HOST_RUNTIME="${AGORA_SWIFT_HOST_RUNTIME:-$BOOTSTRAP/lib/swift/linux:$BOOTSTRAP/lib}"
export LD_LIBRARY_PATH="$HOST_RUNTIME${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
bindir="$(dirname "$(readlink -f "$0")")"
exec -a swiftc "$bindir/swift-frontend" "$@"
```

Programs are unaffected: the linker records the toolchain's interop stdlib as a
`DT_RUNPATH`, so they never see the bootstrap runtime.

**Why this matters for the destination ABI.** The previous handoff concluded
that a GNUstep class-object layout (option C) needed a two-stage build because
the bootstrap-compiled host libraries would disagree with the toolchain stdlib.
With the split, the compiler process never loads the toolchain stdlib at all, so
the *target* stdlib's class layout is a free choice again: S1 can flip
`SWIFT_OBJC_CLASS_LAYOUT` to 2 without a bootstrap and without rebuilding
swift-syntax. What is left for S1 is exactly the IRGen/runtime emission work in
[`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md) §6.1a, not build
plumbing.

The honest caveat: the wrapper binds the installed toolchain to
`~/.agora-swift/bootstrap`. The self-contained version is to install a
non-interop copy of *this* stdlib as the host runtime (it must stay
ABI-identical to the one the bootstrap compiler produced the host tools with),
or, the real answer, a proper host/target split in the CMake install.

### 2.5 Interop became the default, and super sends changed ABI

Two follow-ups from the previous handoff's §5 landed in this round.

**Step 2 — the target defaults to interop.** `ToolChain::addCommonFrontendArgs`
now pushes `-enable-objc-interop` for Linux instead of
`-disable-objc-interop`, and `CompilerInvocation` defaults
`ObjCRuntimeVendorKind` to `GNUstep` on a non-Darwin ELF target. The vendor is
*not* passed by the driver: `-objc-runtime-vendor=` diagnoses "requires
`-enable-objc-interop`", and inner builds (below) must be able to disable
interop without also having to cancel a vendor flag. An explicit
`-objc-runtime-vendor=` still wins, and `-Xfrontend -disable-objc-interop`
still turns the whole thing off.

This is not cosmetic. The installed stdlib is built with interop, and
`_runtime(_ObjC)` changes the stdlib's own ABI (`Array`'s storage type, §2.4), so
a program compiled without interop is compiled against a different standard
library than the one it links. The verification script now proves the default
by compiling its Agora program with **no** interop flags at all.

One inner build cannot take the default: libdispatch's `Dispatch` overlay is
not interop-aware (its shims use `id`-typed `dispatch_data_t`, which ARC
rejects with bridged-cast errors). It is now built with
`-Xfrontend -disable-objc-interop` —
[`patches/0004-libdispatch-overlay-non-interop.patch`](swift-toolchain/patches/0004-libdispatch-overlay-non-interop.patch),
applied to `~/.agora-swift/src/swift-corelibs-libdispatch`. The stdlib itself
still gets interop through `SWIFT_STDLIB_ENABLE_OBJC_INTEROP`.

**Super sends.** libobjc2 has no `objc_msgSendSuper2` (it exports
`objc_msgSend`/`_stret` and the GCC-style `objc_msg_lookup_super`), so every
Swift `super.` send into an imported class failed at **link** time with
`undefined reference to objc_msgSendSuper2`. `getObjCMethodCallee` now has a
GNUstep path: build the `objc_super`, call `objc_msg_lookup_super`, and call
the returned IMP with `(self, _cmd, ...)` like any other method. Two details
matter:

- libobjc2 starts its search **at** `struct objc_super::class`, while Swift (for
  Apple's `objc_msgSendSuper2`) stores the class that *contains* the method and
  lets the runtime start at its superclass. IRGen therefore names the
  superclass statically (`ClassDecl::getSuperclassDecl()`), which also avoids
  asking libobjc2 about Swift metadata, which is not a class object at layout 0.
- A `Peer` send (`objc_msgSendSuper`) already means "start at this class", so it
  is left as-is.

What is *not* verified yet is semantics: a Swift subclass of `NSObject` still
cannot be allocated (next section), so nothing reaches the super method.

---

## 3. Change inventory

`swift-toolchain/patches/0003-swift-enable-objc-interop.patch`, 40 files,
~743 insertions. New this round, on top of the 29 files of the previous one:

| File | Change |
|---|---|
| `include/swift/Runtime/Config.h` | layout defaults off Darwin; `SWIFT_OBJC_CLASS_OBJECT_LAYOUT`; `SWIFT_ERROR_IS_NSError` |
| `include/swift/ABI/Metadata.h` | `getRawKind()`; raw-kind `isTypeMetadata()`; wrapper `Class` typed by layout; `setAsTypeMetadata()` guard |
| `include/swift/ABI/MetadataRef.h` | `getObjCClass*` return the layout-selected type |
| `lib/IRGen/IRGenModule.h` | `usesObjCClassObject()` |
| `lib/IRGen/ClassMetadataVisitor.h`, `lib/IRGen/GenMeta.cpp`, `lib/IRGen/GenClass.cpp` | layout decisions follow `usesObjCClassObject()` |
| `lib/Driver/ToolChains.cpp` | Linux defaults to `-enable-objc-interop` (and embedded Swift still turns it off) |
| `lib/Frontend/CompilerInvocation.cpp` | non-Darwin ELF targets default `ObjCRuntimeVendorKind` to `GNUstep`; an explicit flag still wins |
| `lib/IRGen/GenObjC.cpp` | GNUstep super sends: `objc_msg_lookup_super` + IMP call, with the superclass named statically |
| `include/swift/Runtime/RuntimeFunctions.def` | `objc_msg_lookup_super` runtime declaration |
| `stdlib/public/runtime/Metadata.cpp` | class-object-only blocks gated on layout 1 |
| `stdlib/public/runtime/MetadataImpl.h` | `AnyObject` box retain/release through the checking helpers |
| `stdlib/public/runtime/Casting.cpp`, `DynamicCast.cpp` | class-metatype casts without ObjC messaging |
| `stdlib/public/runtime/ErrorObject.h`, `.mm`, `ErrorObjectNative.cpp` | error-box model selection; `_swift_stdlib_getErrorDefaultUserInfo` stub for the native model |
| `stdlib/public/runtime/SwiftObject.mm` | root superclass and NSError bridging gated |

Not in the patch, but part of the port:

| File | Change |
|---|---|
| `swift-toolchain/scripts/build-swift-toolchain.sh` | installs the `swiftc` host-runtime wrapper (and removes the `swiftc` symlink first — writing through it overwrites `swift-frontend`) |
| `swift-toolchain/scripts/verify-swift-port.sh` | the end-to-end gate: type-check, compile, run, `-O`, Agora interop (now with no explicit interop flags) |
| `swift-toolchain/patches/0004-libdispatch-overlay-non-interop.patch` | keeps the `Dispatch` overlay on the non-interop ABI the toolchain built it with |
| `swift-interop-probe/scripts/run-native-probe.sh` | builds and runs both probes against the native toolchain (no SwiftPM) |
| `swift-interop-probe/{AgoraProbeKit,Sources}` | adapted to Agora's headers (`length()` as a method, `.alloc()` instead of `NSObject()`), plus `AgoraProbeIsKindOfClassNamed` for class-cluster checks |

Regenerate the fork patch after editing the source tree:

```sh
git -C ~/.agora-swift/src/swift diff > swift-toolchain/patches/0003-swift-enable-objc-interop.patch
```

---

## 4. Reproduce / verify

```sh
# rebuild (incremental: ~1–3 min for runtime-only changes, ~15 min when ABI
# headers or IRGen change)
swift-toolchain/scripts/build-swift-toolchain.sh

# the gate
swift-toolchain/scripts/verify-swift-port.sh
```

A program that uses Agora needs only the module map and the include/library
paths — interop and the GNUstep runtime family are the default for this target:

```sh
T=~/.agora-swift/toolchain/usr; A=/path/to/Agora
"$T/bin/swiftc" -o prog prog.swift \
  -Xcc -fmodule-map-file="$A/swift-interop-probe/agora-modules/module.modulemap" \
  -Xcc -I"$A/build-prefix/include" \
  -Xcc -Wno-incomplete-umbrella \
  -L"$A/build-prefix/lib" -lagora-base -lagora-core -lagora-dispatch \
  -lobjc -lBlocksRuntime -Xlinker -rpath -Xlinker "$A/build-prefix/lib"
LD_LIBRARY_PATH="$A/build-prefix/lib" ./prog
```

The same program with `-Xfrontend -disable-objc-interop` still compiles, for
testing the non-interop path.

Run both interop probes against the native toolchain (no SwiftPM needed):

```sh
swift-interop-probe/scripts/run-native-probe.sh
```

Current result: `agora-import-probe` 11/11; `objc-to-swift-probe` builds and
links, then traps in `objc_allocWithZone` on the first Swift-class allocation,
which is the S1/S5 gate rather than a probe defect.

Debugging techniques that produced the findings above:

- **The driver forks.** `set follow-fork-mode child`; `handle SIGILL stop print
  nopass` (the `ud2` in `swift_unreachable` is SIGILL, and the backtracer hides
  it).
- **Is the failure the compiler or the program?** `swiftc -##` / `-v` shows
  whether the trap is in `swift-frontend` or in the linked binary.
- **Read the failing metadata by hand.** At the fault, `info symbol` the class
  pointer and dump the words: compact class metadata is
  `{Kind=0, Superclass, Flags, InstanceAddressPoint, InstanceSize, AlignMask,
  Reserved, ClassSize, ClassAddressPoint, Description, IVarDestroyer}`, GNUstep's
  class object is `{isa, super_class, name, version, info, instance_size,
  ivars, methods, dtable, ...}`.
- **Check the ABI of a symbol that is "missing".** `swift-demangle` both
  manglings; a `_runtime(_ObjC)`-conditional type alias shows up as two
  manglings of the same function, which is a standard-library ABI split, not a
  missing export.
- **Don't trust `swiftc --version`** as a health check: it never parses a file.

---

## 5. What to do next

1. **S1 of the class-ABI plan** — emit the GNUstep `struct objc_class` shape.
   The machinery is in place (`usesObjCClassObject()`, layout 2 exists in
   `ABI/Metadata.h`), the probe evidence is in
   [`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md) §2, and the
   host/target split removed the build-system blocker. Work through the gates
   S1 → S6 there. The probes now put a precise first failure on the board: with
   the compact layout, `SwiftResponder()` traps in
   `objc_allocWithZone → objc_test_class_flag` because the Swift metadata is not
   a class object. A two-line `class Counter: NSObject { init(start:) { … } }`
   reproduces it: Swift emits `__allocating_init` for every class with ObjC
   ancestry, so *no* Swift subclass of an Agora class can be instantiated until
   S1/S5. That is the first thing S1 fixes.
2. **Self-contained host runtime.** Replace the wrapper's dependence on
   `~/.agora-swift/bootstrap` with a non-interop stdlib installed under the
   toolchain (`lib/swift/host/…`), or do the proper host/target split in the
   CMake install. This is the only remaining build-system "cheat".
3. **`+allocWithZone:` decision.** Confirmed by probe: `NSObject()` (and every
   imported `T()`) goes through `objc_allocWithZone`, which sends
   `+allocWithZone:`, which Agora's `NSObject` deliberately does not implement —
   so the sugar raises `NSInvalidArgumentException`. Either add a compatibility
   `+ (id)allocWithZone:(void *)zone { return [self alloc]; }` that preserves the
   singleton door (`libagora-base/NSObject.h` explains why the door is `+alloc`),
   or make `.alloc()`-style construction the documented Swift idiom. Not a
   defect of the Swift port.
4. **Property-shaped accessors in Agora's headers.** `- (size_t)length` imports
   as `length()`, while Apple and GNUstep declare a `length` property. Writing
   Swift against Agora therefore reads differently from writing it against
   Cocoa. Converting the read-only accessors (`length`, `UTF8String`, …) to
   `@property` declarations is source-compatible for Objective-C and would make
   `text.length` work.
5. **Keep the probes green.** `swift-interop-probe/scripts/run-native-probe.sh`
   is the native harness; `agora-import-probe` is 11/11 today, and
   `objc-to-swift-probe` becomes the S5 gate as soon as Swift classes are class
   objects. The published-container `run-probe.sh` and
   `compat/ObjCInteropShim.c` are now historical.

---

## 6. Artifact index

```
swift-toolchain/
├── README.md                                  build/run instructions
├── compat/ObjCInteropShim.c                   no longer needed (kept for the
│                                              published container)
├── patches/
│   ├── 0001-libagora-base-objcxx-clean.patch   3 hunks / 2 files
│   ├── 0002-libagora-core-objcxx-clean.patch   1 hunk  / 1 file
│   ├── 0003-swift-enable-objc-interop.patch   40 files, ~743 insertions
│   └── 0004-libdispatch-overlay-non-interop.patch  1 file (the Dispatch overlay)
└── scripts/
    ├── build-swift-toolchain.sh               build + install (incl. wrapper)
    └── verify-swift-port.sh                   the end-to-end gate

swift-interop-probe/
├── scripts/run-probe.sh                       the original container harness
├── scripts/run-native-probe.sh                the native harness (current)
└── Sources/, AgoraProbeKit/                   the two probes + ObjC side-channel
```

Related: `swift-interop-probe/` (the two probes),
`../SWIFT-INTEROP-INVESTIGATION.md`, `../SWIFT-TOOLCHAIN-INTEGRATION.md`,
`../SWIFT-GNUSTEP-CLASS-ABI.md`.

## 7. One-paragraph summary

The compiler compiles again. The trap was the class-metadata layout: the
compiler's own Swift libraries are built by the bootstrap toolchain without
interop and therefore emit Swift's compact class header, while `libswiftCore`
was built with interop and emitted Apple's five-word class header. The runtime
now uses the compact layout (`SWIFT_OBJC_CLASS_LAYOUT == 0` off Darwin) and IRGen
keys every "is this an Objective-C class object?" decision off one predicate,
`usesObjCClassObject()`, instead of interop. Four runtime bugs that only became
reachable once the compiler ran are fixed: class-metatype casts messaging
metadata, `AnyObject` boxes releasing Swift classes through `objc_release`, the
`getEnumeratedMetadataKind()` trap that makes every ObjC class look like Swift
class metadata unless the raw kind word is consulted, and NSError-shaped error
boxes. The last failure was not about layout at all: `_runtime(_ObjC)` changes
`Array`'s storage type, so the interop stdlib's ABI differs from the non-interop
one the compiler binary was built against. That is now handled structurally —
the installed `swiftc` runs the compiler on the host (bootstrap) runtime, while
produced programs get the toolchain's interop stdlib through their RUNPATH. That
split is also what unblocks the destination ABI: the compiler no longer loads
the target stdlib, so flipping the target class layout to GNUstep's no longer
needs a two-stage build. On top of that, Objective-C interop and the GNUstep
runtime family are now the compiler's **default** for this target (a program
needs no `-Xfrontend` flags), and Swift's `super.` sends into imported classes
use libobjc2's `objc_msg_lookup_super` instead of the Apple-only
`objc_msgSendSuper2`, so such programs link. The two probes were re-run
natively: `agora-import-probe` passes every check, and `objc-to-swift-probe`
compiles and links but traps in `objc_allocWithZone`, because a Swift subclass
of `NSObject` is still not an Objective-C class object. Interop today is
one-way — Swift messages Agora, Agora does not see Swift classes — which is
exactly the S1 → S6 work in `SWIFT-GNUSTEP-CLASS-ABI.md`.
