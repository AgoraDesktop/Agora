# Swift-on-Agora port — handoff

*Status: **the compiler works.** `swiftc` type-checks, compiles, links and runs
Swift against Agora at `-Onone` and `-O`, including classes, generics,
protocols, existentials, error handling and Unicode strings; and Swift can
import Agora's `Foundation`, allocate its `NSObject` and message it. Verified by
[`swift-toolchain/scripts/verify-swift-port.sh`](swift-toolchain/scripts/verify-swift-port.sh).

**Foundation bridging works: the toolchain now ships a Swift Foundation
overlay.** `String`/`Substring` ↔ `NSString`, `Array` ↔ `NSArray`, `Dictionary` ↔
`NSDictionary`, `Set` ↔ `NSSet`, `Int`/`Double`/`Bool` ↔ `NSNumber`, and
`Error` ↔ `NSError` (including `CustomNSError` and `LocalizedError`) convert
with `as`/`as?`, and the runtime's error box is a full NSError whose
domain/code/userInfo come from the Swift error. The overlay is built against
Agora's Clang `Foundation` with `-import-underlying-module` - the way Darwin's
Foundation overlay is built - and installed next to the target stdlib, so
`import Foundation` picks it up with no extra flags. Two bugs had to be fixed on
the way: Swift-emitted categories (the `@objc` members of *extensions*, which is
how the stdlib's own string bridges are declared) were emitted in Apple's shape
into a section libobjc2 never reads, and libobjc2's dtable rebuild after
`class_setSuperclass` lost a subclass's untyped dispatch slot. §2.16.

**The installed toolchain is self-contained: it no longer needs
`~/.agora-swift/bootstrap` at run time.** The compiler is a host tool, so it
must run on a non-interop, compact-layout stdlib that the target install does
not have; the wrapper used to borrow the bootstrap's. The toolchain now ships
that runtime under `lib/swift/host/runtime/` (plus the host clang it links
with), and the wrapper resolves both relative to itself. Verified by moving the
bootstrap tree away and running the language gate, both probes, and the S1, S5
and library-evolution gates against the installed toolchain (§2.15).

**Library evolution's `Update` strategy works at layout 2; the class-ABI
staging plan is complete.** A class whose stored property is a non-frozen
struct from another module now links and runs: `swift_updateClassMetadata2`
had a layout-1-only implementation, so at layout 2 the call did not even link.
The layout-2 implementation recomputes the layout, fills the field-offset
globals and mirrors `instance_size`; a class libobjc2 allocates from is built
with the `Singleton` strategy instead (compute first, register after), because
libobjc2 has no update hook and would otherwise allocate from a stale size. The
gate builds a library-evolution module, compiles a client against v1, swaps in a
v2 with one more struct field *without recompiling the client*, and verifies the
runtime layout at `-Onone` and `-O` (§2.14).

**The default is flipped: the installed toolchain is layout 2.** Since
2026-10-17 `swiftc` and its stdlib are built with `SWIFT_OBJC_CLASS_LAYOUT=2`
(`Runtime/Config.h` and `native-env.sh`), so Agora sees Swift classes as real
GNUstep class objects in the shipped toolchain - not just in the build tree.
Every gate runs green against the installed compiler and stdlib, and
`objc-to-swift-probe` now passes end to end (the old layout-0
`objc_allocWithZone` trap is gone). The flip needed one code fix: a layout-2
build compiles the Dispatch overlay with `-disable-objc-interop`, and that
combination had no implementation (it asked Sema for a metaclass). Such a
compilation now keeps the GNUstep metadata *shape* but emits no class-object
identity, because there is no Objective-C runtime to register it with (§2.12).
Rollback is a rebuild with `AGORA_SWIFT_CLASS_LAYOUT=0`; the previous installed
tree is kept at `~/.agora-swift/toolchain.layout0-backup`.

**This round's other work closed S5: Swift methods are reached by *typed*
Objective-C sends, so `deinit` runs.** The last functional gap in the class ABI was that
libobjc2's release path sends the typed `dealloc_v16@0:8` selector while IRGen
emitted untyped selector records: type-dependent dispatch is keyed by
(name, encoding), and a class's dispatch table starts as its superclass's, so
the typed send found `NSObject -dealloc` instead of the Swift destructor. IRGen
now emits one selector record per (name, encoding), carrying the same encoding
as the method entry and using Clang's own symbol mangling so the records merge.
`deinit` runs for fixed, generic and resilient classes with Objective-C
ancestry; retain/release from Objective-C balance; 50k allocate/init/release
cycles neither leak nor climb in RSS. Typed dispatch from Clang-compiled
Objective-C now reaches Swift methods in general, including overrides of
inherited selectors (`-init` verified) and typed class-method sends.
Reproduce with
[`swift-toolchain/scripts/verify-refcount-abi.sh`](swift-toolchain/scripts/verify-refcount-abi.sh).

**The previous round took S4 of the class-ABI plan.** With the compiler
*and* the target standard library built at `SWIFT_OBJC_CLASS_LAYOUT=2`, generic
Swift classes work: metadata instantiated at runtime, `Array`/`Set`/`Dictionary`
(and their own generic classes), prespecialized generic metadata,
generic-to-generic inheritance, casts between specializations, `AnyObject`
boxes, `Mirror`, and `deinit` of a generic instance. Reproduce with
[`swift-toolchain/scripts/verify-generic-abi.sh`](swift-toolchain/scripts/verify-generic-abi.sh).
That gate is the first one that needs a layout-2 *stdlib*, not just a layout-2
frontend: a generic class's metadata is built by the runtime, so a layout-0
runtime and a layout-2 compiler disagree about where `InstanceSize` lives (the
mixed build corrupts the heap for any generic field wider than a word).

**Stage S1, proven two rounds ago and still green:** a test compiler built with
`SWIFT_OBJC_CLASS_LAYOUT=2` emits a Swift class with Objective-C ancestry as a
real GNUstep `struct objc_class`. An Objective-C constructor finds it with
`objc_getClass("Counter")` *before* `main`; `respondsToSelector` sees its
instance and class methods; an Objective-C category attaches and its `+load` is
delivered; and both method kinds dispatch from C to the Swift IMPs. With that
compiler `Counter()` (through `objc_allocWithZone`), `super -init`, field access
and the whole `objc-to-swift-probe` work too. Reproduce with
[`swift-toolchain/scripts/verify-class-abi.sh`](swift-toolchain/scripts/verify-class-abi.sh).

**The round before took S4b: a *generic* class that inherits an imported
Objective-C class is a class object too.** `class Box<T>: NSObject` is legal
Swift (it cannot have `@objc` members, but it can inherit `NSObject`), and Swift
allocates such a class through `objc_allocWithZone` and sends `-init` through the
Objective-C runtime. The metadata pattern now carries a GNUstep metaclass, the
runtime registers the class with libobjc2's `objc_loadClass_np()` once the
instance layout is known, gives it a unique Objective-C name per instantiation,
and installs the class's method list (the initializer and `-dealloc` thunks) so
`-init` reaches the Swift initializer. `Box<Int>`, `Box<String>`,
`Box<(Int, Int)>`, `Sub<Int>: Box<Int>` and nested `Box<Box<Int>>` all allocate,
initialize, message and go into `NSMutableArray`s. Reproduce with
[`swift-toolchain/scripts/verify-generic-objc-abi.sh`](swift-toolchain/scripts/verify-generic-objc-abi.sh).

**S4c closes the resilient case.** A class from a library-evolution module with
an imported ObjC ancestor has no statically emitted metadata at all: the runtime
relocates it from a pattern. At layout 2 that pattern now carries the metaclass
and the class-side fields (name, method list, ivar list) from the class's static
data, and the relocated metadata is registered like S4b's. A pure Swift class
with a resilient superclass keeps working as a plain Swift metadata object, and
the field-offset globals of *every* runtime-relocated class are now filled in
(without that, a resilient class's stored properties read the wrong slots: they
are compiled against the superclass's minimum size and the runtime is expected
to slide the globals). See
[`swift-toolchain/scripts/verify-generic-objc-abi.sh`](swift-toolchain/scripts/verify-generic-objc-abi.sh).

`deinit` of these classes now runs — that was S5 (§2.11). The diagnosis was
exact: the `-dealloc` thunk was in the class's method list and dispatched when
called directly, but libobjc2's release path sends the *typed*
`dealloc_v16@0:8` selector while our emitted selector records were untyped, and
a class's dispatch table starts as its superclass's, so the typed slot still
pointed at `NSObject -dealloc`: the object was freed and the Swift destructor
skipped. Emitting typed records fixed it without changing the release path.

The installed toolchain is layout 2, and the class ABI is complete: S1, S2, S3,
S4, S4b, S4c, S5 and S6 are all shipped and gated, as are library evolution's
runtime-layout classes, the self-contained host runtime, Foundation bridging and
the Cocoa-shaped API surface. The toolchain is usable for real Swift-on-Agora
programs; what is left is polish (§5), plus the importer work that rewriting
every imported signature with `swift_bridge` would need.

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
| generics | generic classes (`_ContiguousArrayStorage`), `Array`, `Set`, `Dictionary`, prespecialised metadata (installed layout 2, and under the S4 gate's build-tree pair) |
| existentials | class existentials (`[any P]`), `AnyObject` boxes holding Swift classes |
| errors | `throw` / `catch` / `try?`, native error boxes (`ErrorObjectNative.cpp`) |
| strings | interpolation, Unicode (`"héllo 🌍"`), `String(repeating:)` |
| concurrency types | `actor` declaration (not exercised at runtime) |
| **Agora interop** | `import Foundation` (Agora's), `NSObject.alloc()`, `isKind(of:)`, `description()`, `object_getClass`/`class_getName` through libobjc2 |
| **generic classes, layout 2** | runtime-instantiated metadata (`Box<T>`, `Pair<A,B>`, class-typed fields, generic subclasses), prespecialized metadata, `Array`/`Set`/`Dictionary`, casts between specializations, `AnyObject` boxing, `Mirror`, `deinit` of a generic instance |
| **generic classes with an ObjC ancestor** | `class Box<T>: NSObject` is a registered GNUstep class object: unique mangled names, `-init` reaches the Swift initializer, `objc_getClass` round-trip, metaclass chain, `NSMutableArray` ownership, and `deinit` runs (S5) |
| **resilient classes** (layout 2) | a library-evolution class with an ObjC ancestor is relocated at runtime, registered, and gets correct field offsets (including through a resilient superclass chain); a pure Swift resilient class stays a non-class-object; `class_getInstanceVariable`, sizes and `isKind(of:)` verified; its `deinit` runs (S5) |
| **library evolution, resiliently sized members** (layout 2) | a class with a stored property of a non-frozen struct from another module: `Update` for a pure Swift class, `Singleton` for one libobjc2 allocates from; a client compiled against v1 runs against a v2 library whose struct grew, `-Onone` and `-O` |
| **typed selectors** (S5) | one selector record per (name, encoding) in `__objc_selectors`, symbol-mangled like Clang's GNUstep emitter; typed send reaches Swift methods, including overrides of inherited selectors (`-dealloc`, `-init`); untyped sends keep working through the untyped slot; retain/release from C balances and `deinit` runs exactly once |
| **default flags** | `swiftc prog.swift` enables Objective-C interop and selects the GNUstep runtime ABI family without any `-Xfrontend` flags |
| **super dispatch** | a Swift `super.` send to an imported class emits `objc_msg_lookup_super` + a direct IMP call, not Apple's `objc_msgSendSuper2`; such a program links, and with the layout-2 test compiler `objc-to-swift-probe` verifies the semantics (`super -init` is reached) |
| **the two probes** | `agora-import-probe`: all 11 checks; `objc-to-swift-probe`: every check with the **installed** toolchain (only the known `[gap]`: no `ObjectiveC` overlay, so no `#selector`) |
| **Swift -> Agora class objects** (layout 2, test compiler) | class emitted as a GNUstep `struct objc_class` + metaclass; `objc_getClass` before `main`; `respondsToSelector`; instance and class dispatch from C; category attachment and `+load`; `Counter()` via `objc_allocWithZone`; ivar list keeps `instance_size` intact and is usable from C (`class_getInstanceVariable`, offsets, read/write both ways) |

**What the installed (layout 2) toolchain still does not do.** The class ABI is
closed (S1-S6); these are independent of it:

- Foundation **bridging** works through the overlay (§2.16), with the boundary
  Swift itself draws: `as`/`as?` conversions between the bridged types, and
  bridging at `id` parameters, are supported; an imported `NSString *` /
  `NSArray *` parameter still *imports* as the Objective-C class (so call it
  with `as NSString`, the same spelling the upstream corelibs toolchain needs
  for a variable), because the overlay does not re-declare Agora's Foundation
  API surface in Swift. That re-declaration (the Cocoa value-type surface) is
  the remaining piece.
- **`__SwiftValue` and the `SwiftNativeNS*` wrapper classes** were expected to
  fail at layout 0 (no Swift heap header); at layout 2 they carry one. Only the
  class-identity side is exercised (`__SwiftValue` above); their Foundation
  bridging paths are still untested because there is no overlay to drive them.
- **Property-shaped accessors - done** (§2.17). Agora's read-only getters
  (`length`, `UTF8String`, `count`, `firstObject`, `allKeys`, `domain`, `code`,
  `userInfo`, ...) are `@property` declarations now, so Swift reads
  `text.length`, `array.count`, `error.domain` the way it reads Cocoa. This is
  source-compatible with the Objective-C API (a readonly property *is* its
  getter).
- **Library evolution's runtime-layout classes** work (§2.14), with one
  visibility rule: a class whose layout is only final at runtime is registered
  with libobjc2 when its Swift metadata is first requested, so
  `objc_getClass(name)` answers nil before that (the resilient path already
  behaved this way at layout 2). Use `@objc(Name)` and take a Swift reference
  first, or a fixed-layout class, if C code must find it at load time.
- **The `SWIFT_OBJC_CLASS_LAYOUT=0` rollback path** is still compiled in
  (`#if` branches, zero runtime cost) and is not gated any more. S6 kept it on
  purpose (§2.13): it is the documented rollback and the non-Apple default of
  upstream, while Darwin keeps layout 1. Only the Agora-side shims and the
  redundant build flags were removed.

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
| `Runtime/Config.h` | default layout (0 off Darwin when this line was written; 2 since the flip, see the S5/flip table); `SWIFT_OBJC_CLASS_OBJECT_LAYOUT`; `SWIFT_ERROR_IS_NSError` |
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

Semantics needed a class object: at layout 0 nothing can allocate a Swift
subclass of `NSObject` (next section), so nothing reaches the super method. The
layout-2 test compiler closes that: `objc-to-swift-probe`'s "Swift subclass
reached super -init" check passes.

### 2.6 `+allocWithZone:` is back, as a compatibility door

**§5 item 3 of the previous round, resolved.** libobjc2's `objc_allocWithZone()`
ends in `[cls allocWithZone: NULL]`, and Swift's `__allocating_init` — which
every `T()` on an imported class goes through — reaches the runtime that way.
Agora's zone-API removal left no such selector, so `NSObject()` raised
`NSInvalidArgumentException` (README finding 3).

`NSObject` now implements:

```objc
+ (id)allocWithZone:(struct _NSZone *)zone
{
	(void)zone;
	return [self alloc];
}
```

The forwarding is the important part: `+alloc` stays **the** singleton door, so
a subclass that overrides it still answers its shared instance — verified with
`NSNull() === NSNull()`. (The same shape NSProxy already had.)

The parameter is spelled `struct _NSZone *` only for its **type encoding**. It is
an opaque tag, never dereferenced, and no `NSZone` type enters the SDK. libobjc2
compares a method's encoding with the selector's registered encoding and prints
`Calling [NSObject +allocWithZone:] with incorrect signature` when they differ;
the runtime's own declaration (`libagora-objc/fast_paths.m`) registers
`@24@0:8^{_NSZone=}16`, so `void *` (what NSProxy uses) works but is noisy on
every allocation.

Verified: `NSObject()`, `NSNull()` (singleton preserved), `NSMutableArray()`
(`AGArrayMutable`); `verify-swift-port.sh` now exercises the sugar as well, and
`agora-import-probe` passes all 11 checks.

**What it does not fix.** A Swift class with Objective-C ancestry is still
unallocatable at layout 0 (the layout-2 test compiler, §2.7, does fix it).
`objc_allocWithZone(cls)` starts with
`objc_test_class_flag(cls->isa, …)`; for compact Swift class metadata word 0 is
`Kind == 0`, so `isa` is NULL and libobjc2 dereferences NULL at offset `0x20`
before any message is sent. Adding selectors cannot change that — only S1 can.

### 2.7 S1: a Swift class is a GNUstep class object (test compiler)

The emission work for stage S1 of
[`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md) is in place and
verified. It is deliberately **not** the installed default yet:
`SWIFT_OBJC_CLASS_LAYOUT` still resolves to 0 (`Runtime/Config.h`), so the
working toolchain and stdlib are untouched, and a second compiler is built with
`SWIFT_OBJC_CLASS_LAYOUT=2` for the gate. (S4, the generic-class patterns that
used to stand between this compiler and a layout-2 toolchain, is done - §2.8.)

For a class with Objective-C ancestry, layout 2 now emits:

- the 17-word GNUstep `struct objc_class` header, then Swift's own
  `Flags`/`InstanceSize`/`Description`/… fields. The address point stays at the
  third word of the metadata allocation, and the stored `ClassAddressPoint`
  stays 24, because that describes the Swift allocation, not the ObjC ABI;
- a real `._OBJC_METACLASS_<name>` object (17 words, `info & meta`), with null
  `isa`/`super_class`: libobjc2's `objc_resolve_class` fills those in, exactly as
  it does for Clang-emitted classes;
- the class name, an `objc_method_list` for the instance methods and one for the
  class methods (`{next, count, size, {imp, SEL, types}[]}`, `imp` first), and
  an `objc_ivar_list` for the stored fields with the ivar-offset indirection;
- the class in the `__objc_classes` section rather than Apple's
  `__objc_classlist`, so the `__objc_load` constructor that IRGen already emits
  (via its embedded Clang CodeGen) registers it before `main`.

Selectors were already emitted as GNUstep `objc_selector` records in
`__objc_selectors`; the method lists now point at those records directly, so the
`sel_begin`/`sel_end` range that `__objc_load` registers matches what dispatch
looks up. No `sel_registerName()` call is needed.

Two failures had to be fixed on the way, and both are worth keeping in mind:

1. **The metaclass needs its own symbol.** `LinkEntity::forObjCMetaclass` mapped
   every GNUstep metaclass reference to the *class* symbol (because libobjc2
   exports no metaclass symbols for imported classes). That is right for a
   reference to `NSObject`'s metaclass and wrong for a class defined in Swift,
   which needs a real `._OBJC_METACLASS_<name>` object to be its class's `isa`.
   The mangling now distinguishes `hasClangNode()`.
2. **A null ivar list destroys `instance_size`.** libobjc2's
   `objc_compute_ivar_offsets()` replaces `instance_size` with the superclass's
   when `class->ivars == NULL`. A Swift subclass of `NSObject` therefore became
   8 bytes large and every stored field was written past the allocation — a
   silent heap corruption that only showed up in a later `malloc()`. Emitting the
   `objc_ivar_list` (even an empty one would do) keeps the size. This is why S3
   is not optional bookkeeping.

Verified by [`swift-toolchain/scripts/verify-class-abi.sh`](swift-toolchain/scripts/verify-class-abi.sh):
from an Objective-C constructor, `objc_getClass("Counter")` finds the class
before `main`; `class_getName` is `Counter`; `respondsToSelector` is true for
`-greet` and `+classAnswer`; an Objective-C category's `+load` is attached and
delivered; and `class_createInstance` + `objc_msg_lookup` dispatch to the Swift
IMPs (`42`/`7`). The gate also finishes S3: `class_getInstanceVariable` finds
`start` in the emitted ivar list and reports its offset, a value C writes at that
offset is read back through a Swift accessor, and a value Swift writes is read
back by C. The Swift side works as well: `Counter()`, `super -init`, property
access, `isKind(of:)`, String and Array operations. With the same compiler,
`objc-to-swift-probe` passes **every** check (the only remaining item is its
pre-existing `[gap]`: this toolchain still has no `ObjectiveC` overlay for
`#selector`).

Build and run it (the target stdlib is not rebuilt; programs use the installed
one):

```sh
swift-toolchain/scripts/build-layout2-frontend.sh   # cmake -DSWIFT_OBJC_CLASS_LAYOUT=2 + ninja swift-frontend
swift-toolchain/scripts/verify-class-abi.sh

# the probes against the layout-2 compiler:
SWIFTC=~/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64/bin/swiftc-layout2 \
  swift-interop-probe/scripts/run-native-probe.sh
```

The knob is `-DSWIFT_OBJC_CLASS_LAYOUT:` on the Swift CMake project (empty =
`Runtime/Config.h`'s platform default), and `AGORA_SWIFT_CLASS_LAYOUT` feeds it
from `build-swift-toolchain.sh`; the build script always passes it, so a stale
value in `CMakeCache.txt` cannot silently change the ABI.

### 2.8 S4: generic classes at layout 2 (compiler **and** stdlib)

A fixed class's metadata is emitted by the compiler; a generic class's metadata
is **built at runtime** from a pattern. That makes S4 two changes, one on each
side of the ABI:

1. **IRGen stops emitting an Apple-shaped pattern for a generic class.**
   `GenericClassMetadataBuilder` used to add `class_ro_t`/metaclass extra data
   whenever `usesObjCClassObject()` (which is true at layout 2 as well), which
   is what produced the link failure
   `undefined reference to ._OBJC_METACLASS__TtCs12_SwiftObject`: the pattern
   named the *root class's* metaclass, and that symbol is local to the installed
   stdlib. The extra data, its three offsets and the `hasExtraDataPattern` flag
   are now gated on `usesObjCClassObject() && !usesGNUstepClassABI()`.
   `addMetadataFlags` leaves a **null `isa`** for a prespecialized generic class
   (`-prespecialize-generic-metadata` is on for the stdlib, so this path runs a
   lot) instead of asserting on "generic classes do not have a static metaclass
   object".
2. **The runtime initializes the GNUstep header of runtime-built metadata.**
   `initializeClassMetadataFromPattern` and `_swift_relocateClassMetadata` (the
   generic and resilient patterns) now call `initializeGNUstepClassHeader()` at
   layout 2. It zeroes the Objective-C fields and sets `ABIVersion = 3`, which
   is this layout's "this is Swift metadata" marker: `isTypeMetadata()` reads
   it, and `usesNativeSwiftReferenceCounting()` keys off it. Without it the
   metadata looks like a plain Objective-C class object with a null `Flags` and
   no usable `Description`.

**Why the stdlib rebuild is not optional.** The first attempt used the layout-2
frontend with the installed layout-0 stdlib, which links fine and *appears* to
work for `Box<Int>`: `InstanceSize` is read by generated code at the compiler's
layout-2 offset, but it is written by the layout-0 runtime at the compact
offset. The field is therefore never filled in, the allocation is too small, and
any generic field wider than a word (`Box<String>`, `Box<(Int, Int)>`) is a heap
corruption - the failure is a later `malloc` assertion, not a clean crash. Once
frontend and stdlib are both layout 2 the sizes agree and everything passes.

Verified by [`swift-toolchain/scripts/verify-generic-abi.sh`](swift-toolchain/scripts/verify-generic-abi.sh)
against the layout-2 stdlib, and by running the other three gates against the
*same* layout-2 stdlib:

| Gate | Result (layout-2 compiler + layout-2 stdlib) |
|---|---|
| `verify-generic-abi.sh` (new, S4) | generic classes, 200 instantiations, collections, casts, `AnyObject`, `Mirror`, `deinit` |
| `verify-class-abi.sh` (S1) | `S1 gate: ok` (fixed class registered, methods, `+load`, dispatch, ivar offsets and C/Swift read-write) |
| `verify-swift-port.sh` | all checks, `-Onone` and `-O`, plus Agora interop |
| `run-native-probe.sh` | `agora-import-probe` 11/11; `objc-to-swift-probe` all checks (only the known `[gap]`) |

`deinit` of a generic instance runs under the layout-2 stdlib, which is the S5
refcounting question answered for this case: the metadata is recognized as
Swift's (`ABIVersion`), so release goes through the Swift destructor rather than
libobjc2's free path.

**The boundary that S4b closes.** A generic class *cannot* have `@objc`
members, so it never has Objective-C methods to expose - but it **can** inherit
an imported Objective-C class (`class Box<T>: NSObject`), and then Swift
allocates instances through `objc_allocWithZone`. §2.9 adds that case: a
metaclass in the pattern, a unique Objective-C name per instantiation, the
class's method list, and registration through libobjc2's `objc_loadClass_np`.

### 2.9 S4b: a generic class with an Objective-C ancestor is a class object

`class Box<T>: NSObject` is legal Swift. It cannot have `@objc` members, but it
*can* inherit `NSObject`, and then `Lowering::usesObjCAllocator()` is true:
`Box(5)` is compiled to `objc_allocWithZone(cls)` followed by
`objc_msgSend(obj, init)`, and release goes through the Objective-C runtime.
That makes the class object mandatory, and it needs four things that S4's
"generic metadata is not a class object" design did not provide:

1. **A metaclass.** `IRGenModule`'s `GenericClassMetadataBuilder` now emits a
   17-word GNUstep metaclass into the pattern's extra data when
   `Target->getObjectModel() == ReferenceCounting::ObjC`
   (`needsGNUstepClassObject()`). Its `isa`/`super_class` are zero - libobjc2
   resolves them from the class - and its name is left to the runtime. A generic
   class with a pure Swift root still gets no metaclass and stays a non-class
   object, exactly as in S4 (this keeps `Array`/`Set`/`Dictionary`'s storage
   classes cheap).
2. **The class's method list.** `-init` is a Swift thunk that the ObjC allocator
   reaches with `objc_msgSend`; without a method list the send falls through to
   `NSObject -init` and the stored-property initializers never run (the object
   comes back with garbage fields - a failure mode worth knowing). The pattern
   now points at the static `objc_method_list` and `objc_ivar_list` that
   `ClassDataBuilder` already builds, and the runtime installs them on the class
   and its metaclass.
3. **A unique name per instantiation.** libobjc2 keys its class table by name,
   and `Box<Int>` and `Box<String>` are different classes. The runtime reuses
   the Apple path's `copyGenericClassObjCName()` (hoisted out of the layout-1
   block): it demangles the metadata and remangles it, which includes the
   generic arguments, giving e.g. `_TtGC4main3BoxSi_`. The same buffer is
   installed on the class and the metaclass.
4. **Registration.** `initializeClassMetadataFromPattern` points `isa` at the
   pattern's metaclass and sets `MetadataKind`/`ABIVersion` as before. The
   instance size is only known in `_swift_initClassMetadataImpl`, after
   `initClassFieldOffsetVector`; there the runtime mirrors Swift's `InstanceSize`
   into the GNUstep `instance_size` (a separate word, hidden behind
   `setObjCInstanceSize()` because `TargetClassMetadata::InstanceSize` shadows
   it), installs the name and calls `swift_instantiateObjCClass()`. On the
   GNUstep vendor that now calls libobjc2's `objc_loadClass_np()`, which inserts
   the class into the class table, resolves the class/metaclass links, installs
   the dispatch tables and sends `+initialize`. `objc_loadClass_np` also gained
   the runtime lock around `objc_load_class()` (it is called from arbitrary
   threads now, not just from a constructor as in `probe4`).

Two runtime details that were wrong and only mattered here:

- `initClassFieldOffsetVector` read the superclass's *Swift* `InstanceSize` even
  when the superclass is imported Objective-C; at layout 2 that has to be the
  superclass's ObjC `instance_size` (8 for `NSObject`), with malloc alignment,
  because a class with ObjC ancestry uses ObjC refcounting and therefore has no
  inline Swift refcount word - its first field starts at offset 8.
- The emitted `objc_ivar_list` entries had `size` and `flags` swapped (IRGen
  wrote `log2(align)` where libobjc2's `struct objc_ivar` has `size`). It was
  latent while every class's `instance_size` was static and positive; it is
  fixed to match clang's `{name, type, offset, size, align<<3}`.

Verified by [`swift-toolchain/scripts/verify-generic-objc-abi.sh`](swift-toolchain/scripts/verify-generic-objc-abi.sh)
against the layout-2 stdlib, `-Onone` and `-O`: Swift-side values and
initializers, distinct mangled names per instantiation, `objc_getClass`
round-trip, `class_getSuperclass`, `isKind(of:)`, instance size, one class
object per instantiation, `NSMutableArray` ownership, nested generic
instantiations, and a C-side check that allocates and `-init`s through the
Objective-C runtime and verifies the class/metaclass shape, `-init`/`-dealloc`
responders and the metaclass isa. A 16-thread pthread test instantiates the same
generics concurrently (registration takes the runtime lock).

**`deinit` was still missing at that point (S5, now fixed in §2.11):** the
class's `-dealloc` thunk was in the method list and dispatch reached it when it
was called directly, but libobjc2's release path sends the *typed*
`dealloc_v16@0:8` selector while the selector records IRGen emitted were
untyped. The typed slot in the subclass's table is inherited from `NSObject`, so
the send found `NSObject -dealloc` and the object was freed without the
destructor (RSS stayed flat over 500k instances, which is why the leak was not
visible). Typed selector records - §2.11 - are the fix, and the type-encoding
question in [`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md) §7.1 is
closed with it.

**The resilient case is S4c (§2.10).** The *prespecialized* one is not: see
§2.10's boundary note.

### 2.10 S4c: resilient classes with an Objective-C ancestor

A class in a module built with `-enable-library-evolution` whose superclass comes
from another resilience domain has **no statically emitted metadata**:
`getClassMetadataStrategy()` returns `Resilient`, the compiler emits a
`ResilientClassMetadataPattern`, and `swift_relocateClassMetadata()` builds the
metadata on the heap at first use. If that class inherits an imported ObjC class,
Swift allocates it through `objc_allocWithZone` and the relocated metadata has to
be a registered class object - the S1 machinery, but for heap metadata.

What changed:

- `TargetResilientClassMetadataPattern` gained the GNUstep class-side fields at
  layout 2 (`Name`, `InstanceMethods`, `Ivars`); `ResilientClassMetadataBuilder`
  defines the class's **static metaclass** with `emitGNUstepMetaclassObject()`
  (the class is not generic, so its name and method/ivar lists are static) and
  fills them. Unlike the generic case, the metaclass is not in the pattern's
  extra data: it is the same object for the single relocated metadata instance.
- `_swift_relocateClassMetadata()` installs them (metaclass as `isa`, name,
  method list, ivar list) and `_swift_initClassMetadataImpl` registers the class
  once `instance_size` is known. Registration is now keyed on `isa != nullptr`
  rather than on "is generic", which covers generic (S4b) and resilient (S4c)
  classes; a generic one computes a per-instantiation name, a resilient one uses
  the static name from the pattern.
- **Field-offset globals.** A class whose superclass layout is opaque at compile
  time is compiled against the superclass's *minimum* size; every stored-property
  access loads the real offset from a mutable global, and the runtime is expected
  to slide it. Layout 1 does that in `initObjCClass()`; at layout 2 nothing did,
  so a resilient class read its fields from the wrong slots (a `var v = 2` came
  back as its superclass's field). `initGNUstepClassFieldOffsets()` now writes
  the computed offsets back through the class's emitted `objc_ivar_list`, and the
  ivar list is emitted for every relocated class - not only for class objects -
  because that is where the globals' addresses live.

Verified by the same gate (it now builds a `ResilientLib` module with
`-enable-library-evolution` and an app that subclasses both its ObjC-rooted
`Base` and its pure-Swift `PureBase`), `-Onone` and `-O`: `Sub: Base` and
`GrandSub: Sub` relocate, register, keep their field values and report correct
`instance_size`, ivar offsets, superclass and metaclass; `Pure: PureBase`
relocates as a plain Swift metadata object.

**Boundary - prespecialized generic classes.** A *prespecialized* generic class
with an ObjC ancestor still gets no metaclass (it keeps S4's null `isa`). That
case needs `SpecializedGenericClassMetadataBuilder` to emit a GNUstep metaclass
at the *specialized* symbol plus a compile-time unique name, and it is not
reachable today: canonical metadata prespecialization only happens for the
stdlib module on this target (a user module compiled with `-O
-prespecialize-generic-metadata`, with or without library evolution, emits no
prespecialized class metadata; the canonical-use path requires statically
addressable metadata), and the stdlib has no ObjC-ancestry generic classes. If a
stdlib-like module ever declares one, the failure is the pre-S4b
`objc_allocWithZone` trap, not silent corruption.

A separate, layout-independent gap surfaced while testing: a class with
*resiliently sized stored fields* (not resilient ancestry) uses the
`Update`/`FixedOrUpdate` strategy, whose runtime entry points
(`swift_updateClassMetadata2`) are compiled only at layout 1 - so such a class
fails to link at layout 0 as well. It is not part of S4c but is worth its own
item before library evolution is a supported use case.

### 2.11 S5: typed selector records, so `deinit` runs

The last functional gap was not in the class object at all. `-dealloc` was in
the method list and sending it directly ran `deinit`, but releasing an object
did not. The mechanism is worth stating precisely, because "emit the type
encodings" sounds cosmetic and is not:

- libobjc2 is built with `TYPE_DEPENDENT_DISPATCH`, so a selector **record**
  `{name-or-index, types}` has one dtable index per *(name, type encoding)*
  pair, not per name. `objc_release_fast_np` releases the last reference with
  `[obj dealloc]`, compiled by Clang: a *typed* `dealloc_v16@0:8`.
- A class's dispatch table **starts as its superclass's**. `NSObject -dealloc`
  is a Clang-emitted typed record, so the subclass table already had the typed
  `dealloc` slot filled with `NSObject`'s IMP. Swift's `-dealloc` thunk was
  installed under the *untyped* `dealloc` index (and, in TDD mode, under the
  untyped index of its own untyped record), so the typed lookup **hit** - the
  wrong entry - and never reached the untyped fallback.
- Therefore the record has to claim the method's encoding, i.e. `dealloc` has to
  be emitted as `{dealloc, v16@0:8}` with the same index Clang's record has.

The change is entirely in IRGen; the runtime and the stdlib are untouched:

1. `getGNUstepSelector()` takes the selector *and* its type encoding, and emits
   **one record per (name, encoding)**. The symbol is mangled exactly the way
   Clang's GNUstep ABI v2 emitter mangles it - `.objc_selector_<name>_<encoding
   with '@' replaced by '\1'>` - so a Swift record and a Clang record for the
   same pair are the same symbol, merge at link time, and the linker also
   resolves `__start___objc_selectors`/`__stop___objc_selectors` (Clang uses
   section bounds on ELF, so `__objc_load` registers every record in the image,
   including the new typed ones). The encoding string lives in
   `.objc_sel_types_<mangled>`, again the symbol Clang uses.
2. `collectGNUstepMethods()` recovers the encoding text from the method
   descriptor's `types` constant (`typeEncodingText()`) and passes it to the
   selector emitter, so the record and the method entry carry the **same**
   encoding. The method entry's `types` field was already correct: `dealloc` had
   `v16@0:8` all along; only the record was untyped.
3. Two guards keep registration safe, because libobjc2's
   `objc_register_selector()` asserts on an encoding containing `@"` (an object
   type *name*): an encoding with a `"` in it, and a **null** encoding (a generic
   initializer whose result type cannot be represented as a Clang type), keep
   the untyped record. Swift's own send sites also keep using untyped records
   (`getAddrOfObjCSelectorRef`), and untyped sends fall back to the untyped slot
   that every method is installed under, so nothing that worked before depends
   on the typed path.

Verified by
[`swift-toolchain/scripts/verify-refcount-abi.sh`](swift-toolchain/scripts/verify-refcount-abi.sh),
`-Onone` and `-O`, through the public Objective-C API:

| Check | Result |
|---|---|
| `deinit` of a pure class, a pure generic class, a fixed ObjC-ancestry class and a generic ObjC-ancestry class | 4/4 |
| typed and untyped `-dealloc`/`-init` lookups return the *same* IMP for a Swift class | same |
| typed Clang send reaches a Swift `@objc` method (`-read`) | 10 |
| typed Clang *class* send reaches a Swift class method (`+version`) | 9 |
| `[[DeinitBox alloc] init]` typed initialization reaches Swift's `override init()` | 7 |
| retain/release from Objective-C balance; the destructor runs exactly once at the last release | ok |
| 50k alloc/init/release cycles from ObjC: deinit count exact, RSS delta < 8 MB (measured ~1 MB) | ok |
| a 400k-instance Swift loop: 400k deinits, RSS delta ~1 MB | ok |

The same gate is what catches a regression: before the change the four `deinit`s
are two (`deinit.swift`'s minimal repro printed `deinits: 2 (expected 4)`), and
the typed/untyped IMP comparison fails for `dealloc` (different IMPs) even
though `class_respondsToSelector` is true for both.

`deinit` also runs for a **resilient** class with an ObjC ancestor (its static
method list is installed on the runtime-relocated metadata); the S4b/S4c gate
now asserts that too, as it does for `WithDeinit<T>`.

### 2.12 The flip: layout 2 is the default (and a no-interop build keeps working)

With S5 closed there was no functional gap left, so the default moved:

- `Runtime/Config.h`: the non-Darwin default of `SWIFT_OBJC_CLASS_LAYOUT` is
  **2** (it was 0). Darwin is unchanged (`SWIFT_OBJC_CLASS_LAYOUT ==
  SWIFT_OBJC_INTEROP`, Apple's layout).
- `swift-toolchain/scripts/native-env.sh`: `AGORA_SWIFT_CLASS_LAYOUT` defaults to
  **2**, so the build passes the value explicitly and a stale `CMakeCache.txt`
  cannot silently change the ABI.
- `AGORA_SWIFT_CLASS_LAYOUT=0 swift-toolchain/scripts/build-swift-toolchain.sh`
  goes back to the compact layout (a full rebuild; the previous installed tree
  is preserved at `~/.agora-swift/toolchain.layout0-backup` on this host).

The rebuild is a normal `build-swift-toolchain.sh`: the layout define is
directory-wide (`CMakeLists.txt`), so the compiler, the Swift libraries, the
Dispatch overlay and the stdlib all recompile and the toolchain installs over
itself. ~5 minutes of build after the compiler had already been rebuilt at
layout 2, plus ~1.5 h from cold.

**The one code fix the flip needed.** A layout-2 build also compiles things that
have no Objective-C interop: `swift-corelibs-libdispatch`'s `Dispatch` overlay
is built with `-disable-objc-interop` (patch `0004`), because that overlay must
not depend on the Objective-C runtime. Two places assumed "layout 2 implies
interop":

1. `addMetadataFlags()` called `emitGNUstepMetaclassObject()`, which asks Sema
   for `ClassDecl::getMetaclassKind()` - and that asserts
   `EnableObjCInterop`. Fixed in `GenMeta.cpp`: with layout 2 and no interop, the
   `isa`/flags word is `MetadataKind::Class` (null), exactly the state a generic
   class already uses. `GenClass.cpp`'s `buildMetaclassStub()` returns without
   emitting a metaclass in that case.
2. `addSuperclass()` named the root class's ObjC parent (`SwiftObject` as an ObjC
   class ref) through `getAddrOfObjCClass()`, which asserts interop. Fixed: a
   root class compiled without interop keeps the compact layout's null
   superclass.

The result is the right one rather than a dodge: such a compilation emits
**GNUstep-shaped metadata without a class-object identity** - the runtime it
links against is layout 2, so the fields must be at layout-2 offsets, but there
is no Objective-C runtime in the image to register the class with, so there is
no metaclass, no name, no method list, and no `__objc_classes` entry. Verified
directly (`-Xfrontend -disable-objc-interop` on a class hierarchy with a
generic and a `deinit`) and indirectly: `import Dispatch` builds and runs
against the installed toolchain, and the installed `libswiftDispatch.so` is the
product of that path.

Verified after the install, against the **installed** compiler and stdlib:

| Gate | Result |
|---|---|
| `verify-swift-port.sh` (installed `swiftc`) | all green, `-Onone` and `-O` |
| `run-native-probe.sh` (installed `swiftc`) | `agora-import-probe` 11/11; `objc-to-swift-probe` every check (only the known `#selector` gap) |
| S1/S3 (`SWIFTC_LAYOUT2=$T/bin/swiftc`) | `S1 gate: ok` |
| S4 (`STDLIB_DIR=$T/lib/swift`) | `S4 gate: ok` |
| S4b/S4c | `S4b/S4c gate: ok` |
| S5 | `S5 gate: ok` |
| `import Dispatch` + a queue round-trip | ok (the no-interop layout-2 overlay) |

`nm $T/lib/swift/linux/libswiftCore.so | grep _OBJC_METACLASS__TtCs12_SwiftObject`
is the one-line check that the installed stdlib really is the layout-2 one.

### 2.13 S6: the compatibility shims and redundant flags are gone

S6 is the cleanup stage of the class-ABI plan, and it is deliberately *not* a
rewrite of the fork: the ABI is shipped, and the remaining `#if
SWIFT_OBJC_CLASS_LAYOUT` branches are kept for Darwin (layout 1) and for the
documented rollback (layout 0). What was actually dead, and is now gone:

1. **`swift-toolchain/compat/ObjCInteropShim.c` - deleted.** It supplied
   `objc_opt_self`, `swift_getObjCClassMetadata`,
   `swift_getObjCClassFromMetadata` and
   `swift_getObjCClassFromMetadataConditional` when the built `libswiftCore`
   did not export them. The fork's runtime exports the first three
   (`GNUstepObjCCompatibility.mm` and `Metadata.cpp`); the fourth has no
   `SWIFT_RUNTIME_EXPORT` upstream and is only called inside the runtime
   (`MetadataLookup.cpp`, `ProtocolConformance.cpp`), so a program never needed
   it. Nothing referenced the file any more; it is not in any build.
2. **`swift-interop-probe/scripts/run-probe.sh` - deleted.** It drove the
   published aarch64 container image, which predates the class-ABI work and
   cannot observe the current state. `run-native-probe.sh` is the harness, and
   `swift-interop-probe/README.md` now documents only that (it also stopped
   claiming the Objective-C→Swift probe fails, which the flip made untrue).
3. **A duplicated build flag - removed.**
   `SWIFT_EXPERIMENTAL_EXTRA_FLAGS` carried
   `-Xfrontend -objc-runtime-vendor=gnustep`, and `SwiftSource.cmake` already
   passes exactly that for a non-Apple interop build (and the frontend defaults
   the vendor to GNUstep for a non-Darwin ELF target, `CompilerInvocation.cpp`).
   The stdlib now compiles with one fewer redundant flag. The other two entries
   stay, with their reasons now written down: `-validate-tbd-against-ir=none`
   (the TBD checker does not know the ObjC class symbols interop emits) and
   `-sil-disable-pass=code-sinking` (predates this work; untested without it).
4. **A gate that keeps the shim dead.** `verify-swift-port.sh` now resolves the
   `libswiftCore` the interop test program actually loads and asserts that it
   exports `objc_opt_self`, `swift_getObjCClassMetadata` and
   `swift_getObjCClassFromMetadata`. A regression that stopped exporting them
   would otherwise reintroduce the "every user must link a shim" state silently.

The published patch is unaffected: S6 changed the Agora-side scripts and docs,
not the Swift fork. Its regeneration command is now the safe one
(`git diff HEAD`, which also catches the intent-to-add
`TargetConditionals.h`).

### 2.14 Library evolution: the `Update` strategy at layout 2

Library evolution's *resiliently sized members* are the last class-layout gap.
A class with a stored property whose type is a non-frozen struct from another
module cannot know its instance layout at compile time. The compiler emits two
strategies for it (§5 used to list this as open):

- **`Update`** (pure Swift class): the metadata is emitted statically and the
  metadata accessor calls `swift_updateClassMetadata2` before the first
  allocation.
- **`Singleton`** (at layout 2, any class libobjc2 allocates from): the metadata
  is filled in and the class registered only after the layout is final, exactly
  like the resilient path of S4c.

Before this round `_swift_updateClassMetadataImpl` and both
`swift_updateClassMetadata{,2}` wrappers were compiled only at layout 1, so a
program with an `Update` class did not link:
`undefined reference to 'swift_updateClassMetadata2'`. The layout-2
implementation is the layout-neutral core of the layout-1 one:

1. realize the superclass (returning its dependency), and check the statically
   emitted superclass pointer against it (SwiftObject for a root class);
2. `initClassFieldOffsetVector()` — recompute the field offset vector and the
   instance size/alignment from the runtime superclass layout and the *real*
   field layouts. At layout 2 this also writes the size into the GNUstep
   `instance_size` word, which libobjc2 allocates from;
3. `initGNUstepClassFieldOffsets()` — slide the field-offset globals that
   compiled accesses load (they are also the `int *Offset` targets of the
   emitted `objc_ivar_list`, so libobjc2's view stays consistent).

**Why the ObjC-allocated case is Singleton, not Update.** The update pattern
leans on the Objective-C runtime calling the class's update callback before it
allocates (Darwin's `_objc_realizeClassFromSwift`). libobjc2 has no such hook,
and it registers a class from `__objc_classes` at load time with the statically
emitted - i.e. minimum - `instance_size`. A C-side `[cls alloc]` before the
first Swift metadata access would therefore allocate too little. So
`getClassMetadataStrategy()` now returns `Singleton` for a class that
`Lowering::usesObjCAllocator()` and is compiled at layout 2; its method list and
ivar list are still emitted statically, and `_swift_initClassMetadataImpl`
registers it through `swift_instantiateObjCClass()` once the size is final.
Pure Swift classes keep `Update` (Swift always runs the metadata accessor
before allocating).

Verified by
[`swift-toolchain/scripts/verify-update-abi.sh`](swift-toolchain/scripts/verify-update-abi.sh),
which is the first gate that tests *resilience* rather than a single build:

- builds a library-evolution module v1 with a non-frozen `Payload { a, b }`;
- compiles the client against v1: a pure Swift `PureHolder` (Update) and an
  `@objc(ObjCHolder)` class (Singleton), plus a loop of 20k allocations;
- rebuilds the module as v2 with `Payload { a, b, c }` — **the same initializer
  symbol**, so the v1 client still links — and runs the *same client binary*
  against it, `-Onone` and `-O`.

| Check | v1 | v2 |
|---|---|---|
| pure-Swift holder fields | ok | ok |
| ObjC-rooted holder fields, `@objc` method | ok | ok |
| `class_getInstanceSize` = 8 + runtime `Payload` + 8 | 32 | 40 |
| 20k allocations through the ObjC allocator | ok | ok |
| `objc_getClass` before / after the Swift access | nil / found | nil / found |
| both strategies present in the client IR | `swift_updateClassMetadata2` + `swift_initClassMetadata2` | same client |

The lazy registration is deliberate and matches the resilient classes: a class
whose layout is only final at runtime is not in `__objc_classes`, so
`objc_getClass(name)` answers nil until the first Swift metadata access. C code
that must find such a class at load time should use a fixed-layout class (or
take a Swift reference first).


### 2.15 The host runtime is now shipped with the toolchain

The compiler is a *host tool*: it was built by the bootstrap toolchain, and its
own Swift libraries (`lib/swift/host/compiler/*.so`, swift-syntax etc.) are
ABI-locked to that toolchain's stdlib - non-interop, compact class layout. The
stdlib installed for Agora is the opposite (interop, layout 2); `_runtime(_ObjC)`
changes `Array`'s storage type and the class header, so the compiler process
cannot load the target stdlib. Until this round the installed `swiftc` was a
wrapper that set `LD_LIBRARY_PATH` to `~/.agora-swift/bootstrap/...`, and the
`clang` symlink in `usr/bin` pointed into the same tree: the install only worked
on the machine (and in the directory) that built it.

What the install does now (all in `build-swift-toolchain.sh`, after
`--install-swift`):

1. **Stage the host runtime.** Copy the six shared libraries the compiler
   process loads from the bootstrap's `lib/swift/linux` into
   `usr/lib/swift/host/runtime/`: `libswiftCore`, `libswift_Concurrency`,
   `libswiftGlibc`, `libswift_Builtin_float`, `libBlocksRuntime`,
   `libdispatch`. (That is the exact `ldd` closure under the old wrapper; a
   `README` there records why and where they come from - the bootstrap Swift
   release, Apache 2.0 with Runtime Library Exception.)
2. **Stage the host clang.** The legacy driver shells out to `clang` to link and
   looks for it next to the frontend. The bootstrap's single static
   `clang-21` binary is copied to `usr/bin/clang` (with `clang++` as a relative
   symlink) and its `lib/clang/21` resource directory to `usr/lib/clang`.
3. **Make the wrapper relocatable.** `swiftc` no longer hard-codes a bootstrap
   path: it computes `$bindir/../lib/swift/host/runtime` from its own resolved
   location, puts that first on `LD_LIBRARY_PATH`, and execs the frontend.
   `AGORA_SWIFT_HOST_RUNTIME` still overrides it (the build-tree wrappers use
   that).
4. **Self-check the install.** With a clean environment (`env -i`, no bootstrap
   on any path) it compiles, links and runs a `print` program using only the
   toolchain plus Agora's prefix. The prefix is still needed because the stdlib
   autolinks Agora's Foundation - that is the product, not a build cheat.

Verified by moving `~/.agora-swift/bootstrap` aside entirely and running against
the installed toolchain:

| Check | Result |
|---|---|
| `swiftc --version` | works |
| clean-env `swiftc` compile + link + run (staged clang, no PATH to the bootstrap) | works |
| `verify-swift-port.sh` (language/runtime + interop + S6 export check) | all green |
| `run-native-probe.sh` (both probes, ObjC side built with the staged clang) | 17/17 |
| S1/S3, S5 and library-evolution gates against the installed `swiftc` | green |
| `ldd` of the compiler | every Swift lib from `usr/lib/swift/host/runtime` |

The build still needs the bootstrap toolchain (it compiles the compiler), but
the *installed* toolchain does not. The two build-tree wrappers
(`bin/swiftc-layout2*`) still point at the bootstrap runtime on purpose: they
exist to test an uninstalled compiler change, in a tree that was just built with
the bootstrap. Remaining external dependencies of the installed toolchain are
ordinary OS ones: glibc/libstdc++/libm/libz/libuuid and the system
`libobjc.so.4` that the compiler binary has always linked (it does not call into
it).


### 2.16 Foundation bridging: the Swift Foundation overlay

The standard library leaves the value bridges to a **Foundation overlay**; this
toolchain only had Agora's *Clang* `Foundation`, which is why `"x" as NSString`
did not compile. The overlay is now a real Swift module of the same name, built
with `-module-name Foundation -import-underlying-module` against Agora's module
map - the layout Darwin uses for its own overlay - and installed next to the
target stdlib:

```
usr/lib/swift/linux/Foundation.swiftmodule/x86_64-unknown-linux-gnu.swiftmodule
usr/lib/swift/linux/libFoundation.so
```

`import Foundation` finds it through the resource dir (`-module-link-name
Foundation` autolinks the library); users need no extra flags. What it
declares (`swift-toolchain/foundation-overlay/FoundationOverlay.swift`):

| Bridge | Direction |
|---|---|
| `String`, `Substring` ↔ `NSString` | UTF-16 through `-initWithCharacters:length:` / `-getCharacters:range:` |
| `Array` ↔ `NSArray`, `Dictionary` ↔ `NSDictionary`, `Set` ↔ `NSSet` | copies into/out of Agora's mutable collections; elements bridge with `_bridgeAnythingToObjectiveC` |
| `Int`, `Double`, `Bool` ↔ `NSNumber` | the `+numberWith…` factories and the `…Value` accessors |
| `Error` ↔ `NSError` | `_convertErrorToNSError`/`_convertNSErrorToError` (the names SILGen looks up) plus `NSError: Error` |
| `CustomNSError`, `LocalizedError` | the protocols, their defaults, and `_getErrorDefaultUserInfo` (the symbol the runtime `dlsym`s to fill an NSError's userInfo) |

Bridging is deliberately by **copying**, not through the stdlib's
`SwiftNativeNS*` machinery: those classes are reparented to Darwin's
CoreFoundation classes and the fast paths send CoreFoundation SPI to them
(`+newTaggedNSStringWithASCIIBytes_:length_:`, which Agora's `NSString` does not
implement and which raised on the base class).

**Two bugs this exposed.**

1. **Swift-emitted categories.** `@objc` members declared in an *extension* are
   emitted as an Objective-C category (that is where the stdlib's own
   `__StringStorage` bridges live). At layout 2 the category was emitted in
   Apple's shape (`category_t *` in a pointer list, in a section libobjc2 never
   reads). It is now a GNUstep `struct objc_category` - `{name, class_name,
   instance_methods, class_methods, protocols, properties, class_properties}` -
   placed directly in `__objc_cats` (Clang's GNUstep section name) and added to
   `llvm.used`, because the loader reaches it through the section bounds and
   nothing in the module references it. Without this, `__StringStorage` had only
   `-init`: every `@objc(length)` etc. was missing and the error path aborted in
   `-[NSString length]`.
2. **The dtable rebuild lost untyped dispatch.** The Swift runtime reparents
   `__SwiftNativeNSError` to Agora's `NSError` with `class_setSuperclass`, which
   makes libobjc2 rebuild the class's dispatch table. `rebaseDtableRecursive`
   collected the class's own methods by their *typed* selector indices and then
   filled the *untyped* slot from the new parent - and Swift sends use untyped
   selectors. `-domain` therefore reached `NSError -domain` (which reads
   `_domain` at offset 8, i.e. nil) instead of `__SwiftNativeNSError -domain`.
   Every method is now installed under its untyped index as well, matching
   `installMethodInDtable`.
3. **A one-line Agora shim.** The stdlib's own `String._bridgeToObjectiveCImpl()`
   probes `+[NSString newTaggedNSStringWithASCIIBytes_:length_:]` for the
   Darwin tagged-pointer fast path and it is *sent* to the class, so an
   unimplemented selector raises. Agora's `NSString` now answers it with nil
   ("no tagged representation"), which makes the stdlib fall back to
   `__StringStorage` - a Swift-native NSString reparented under Agora's
   `NSString`, which the runtime's error-domain bridging uses.

Verified by
[`swift-toolchain/scripts/build-foundation-overlay.sh`](swift-toolchain/scripts/build-foundation-overlay.sh)'s
self-check (run at install time with `env -i`) and by the language gate's
bridging section, which converts in both directions, round-trips `[String]`,
`[String: Int]` and `Set<Int>`, bridges `Int` through `NSNumber`, turns a
`throw` into an `NSError` with the default domain/code, and checks that a
`CustomNSError`'s domain/code/userInfo reach the `NSError`.

**The Cocoa-shaped API surface (§2.18).** The overlay also re-declares the
parts of Foundation that Swift should spell with its own types: `NSArray`,
`NSDictionary` and `NSSet` are `Sequence`, `NSError(domain:code:userInfo:)`
takes a Swift `String` and `[String: Any]`, `NSString(string:)` takes a Swift
`String`, and `NSObject` is `Hashable` (which `AnyHashable` needs for an
Objective-C key; the `ObjectiveC` overlay that normally provides it is not
built here). What remains out of reach is *rewriting every imported signature*:
`NSString *` parameters still import as `NSString`, because the headers carry no
`swift_bridge` attribute, and adding one is not currently viable - the importer
rewrites the signature but the native-to-foreign thunk then passes the Swift
value's *storage* where the Objective-C class pointer is expected (a Swift
`Dictionary` handed to `-[NSError initWithDomain:code:userInfo:]` crashed in
`-copy`). That is an importer/thunk ABI gap, not an overlay one; the
hand-written surface above covers the entry points programs actually call, and
`"x" as NSString` remains the spelling for the rest (upstream corelibs requires
it for a *variable* too).

### 2.17 Property-shaped accessors

Cocoa declares its read-only getters as `@property`s (`length`, `count`,
`firstObject`, `domain`, `code`, `userInfo`, `UTF8String`, ...), and Agora
declared them as plain methods - so Swift read `text.length()` where Cocoa code
reads `text.length`. The headers now declare the property form (patch
`0009-libagora-base-property-shaped-accessors.patch`, 19 headers):

| Class | Properties |
|---|---|
| `NSString` | `length`, `UTF8String` |
| `NSArray` | `count`, `firstObject`, `lastObject` |
| `NSDictionary` | `count`, `allKeys`, `allValues` |
| `NSSet` | `count`, `anyObject`, `allObjects` |
| `NSOrderedSet` | `count`, `firstObject`, `lastObject` |
| `NSError` | `domain`, `code`, `userInfo`, `localizedDescription`, `localizedFailureReason` |
| `NSData` | `length`, `bytes` |
| `NSDate` | `timeIntervalSinceReferenceDate` |
| `NSIndexPath` | `length` |
| `NSIndexSet` | `count`, `firstIndex`, `lastIndex` |
| `NSNumber` / `NSValue` / `NSDecimalNumber` | `objCType` |
| `NSException` | `userInfo` |
| `NSHashTable` | `count`, `allObjects` |
| `NSMapTable`, `NSPointerArray` | `count` |
| `NSTimer`, `NSUserActivity` | `userInfo` |

This is source-compatible for Objective-C, because a readonly property *is* its
getter: the selectors, implementations and ABI do not change, and every
`[obj length]` still compiles. It is a *source change for Swift* in two ways
worth knowing: the call syntax (`text.length`), and the imported name of
`UTF8String`, which becomes the property spelling `utf8String`. The probes, the
gate scripts and the Foundation overlay were updated; the ABI doc's old note
that "Swift writes `text.length()`" is gone.

Verified by compiling and running a program that reads every converted property
through the importer (`length`, `utf8String`, `count`, `firstObject`/
`lastObject`, `allKeys`/`allValues`, `anyObject`/`allObjects`, `domain`/`code`/
`userInfo`/`localizedDescription`, `data.length`/`bytes`,
`timeIntervalSinceReferenceDate`, `length` on `NSIndexPath`, `count`/`firstIndex`/
`lastIndex` on `NSIndexSet`, `objCType`, `userInfo` on `NSTimer`), plus the full
gate suite (language/runtime with bridging, both probes, S1, S4, S4b/S4c, S5,
library evolution).

### 2.18 The Cocoa-shaped API surface

With bridging in place, the last ergonomic gap was what an *imported signature*
looks like: `NSString *` is `NSString` (so `"x" as NSString`), `NSError`'s
initializer took `NSString`/`NSDictionary`, and the collection classes did not
iterate. The overlay now re-declares the parts a program actually calls, on top
of the Objective-C API:

| Declared in the overlay | Effect |
|---|---|
| `NSArray: Sequence`, `NSDictionary: Sequence`, `NSSet: Sequence` | `for x in nsArray`, `for (k, v) in nsDictionary`, `for _ in nsSet` (elements are `Any`, the shape an unparameterized `NSArray` has in Swift) |
| `extension NSError { convenience init?(domain: String, code: Int, userInfo: [String: Any]?) }` | `NSError(domain: "d", code: 1, userInfo: ["k": "v"])` |
| `extension NSString { convenience init(string: String) }` | `NSString(string: "abc")` |
| `extension NSObject: Equatable, Hashable` | `AnyHashable` can hold an Objective-C object; without it a bridged `[AnyHashable: Any]` dictionary **silently drops its entries** (`key as? AnyHashable` fails) - the `ObjectiveC` overlay that provides this on Darwin is not built here |

`extension NSObject: Equatable, Hashable` is the subtle one: `AnyHashable` is
what an `NSDictionary` bridges to, and the stdlib's `AnyHashable` hashing of an
Objective-C object goes through `NSObject`'s `hash`/`isEqual:`. With the
conformance the error `userInfo` round-trips; without it, `e.userInfo` looked
empty/garbage (`count 8` for one entry).

**Why not `swift_bridge`?** The clean way to make *every* imported
`NSString *`/`NSArray *` a Swift `String`/`[Any]` is the Clang attribute the
Darwin SDK carries (`__attribute__((swift_bridge("Swift.String")))`). Adding it
to Agora's headers produces the right *signatures* but not the right *calls*:
IRGen expands the foreign method's signature from the rewritten (Swift) types,
finds no bridging to do, and passes the Swift value's representation - e.g. a
`Dictionary`'s storage pointer - where the Objective-C class pointer belongs.
The process dies in `-[NSError initWithDomain:code:userInfo:]`'s `-copy` of
`__EmptyDictionarySingleton`. Fixing that means teaching the native-to-foreign
thunk that a `swift_bridge`d parameter still needs a `_bridgeToObjectiveC`
conversion (or the importer keeping the unbridged type in the SIL signature) -
an upstream-sized change, deliberately not attempted here. The attributes were
added, exercised, and removed; the overlay's hand-written surface is the
supported path.

Verified by the language gate's bridging section: `NSError(domain:code:userInfo:)`
with Swift values, iteration over all three collection classes, `NSString(string:)`,
and `NSObject` in `AnyHashable` - plus the whole gate suite (both probes, S1,
S4, S4b/S4c, S5, library evolution) against the installed toolchain.

---

## 3. Change inventory

`swift-toolchain/patches/0003-swift-enable-objc-interop.patch`, 45 files,
~1950 insertions. The layout/registration table is from two rounds ago, the S1
emission from three, S4/S4b from before that, S5 and the flip from earlier, and
this round adds library evolution's `Update` strategy and GNUstep-shaped
categories. S6 changed only the Agora-side scripts and docs. The libobjc2 side
is `0006-libagora-objc-loadClass-np.patch` plus the new
`0008-libagora-objc-dtable-rebase-untyped.patch`; the Agora-side shim is
`0007-libagora-base-tagged-string-probe.patch`.

| File (bridging) | Change |
|---|---|
| `lib/IRGen/GenClass.{h,cpp}` | `emitGNUstepCategory()`: a `struct objc_category` with GNUstep method lists; `emitGNUstepCategoryData()` puts it in `__objc_cats` and marks it used |
| `lib/IRGen/GenDecl.cpp` | at layout 2 an extension's category takes that path instead of Apple's `category_t *` list |
| `libagora-base/NSString.m` | `+newTaggedNSStringWithASCIIBytes_:length_:` answers nil (the Darwin SPI the stdlib probes; nil = use the storage fallback) |
| `libagora-objc/dtable.c` | `rebaseDtableRecursive()` reinstalls each of the class's own methods under its *untyped* selector index too (TDD mode), so `class_setSuperclass` does not lose an override to the new parent |
| `libagora-base/*.h` (19 files) | the read-only getters become `@property` declarations (§2.17; patch 0009), so Swift reads `text.length`, not `text.length()` |

| File (library evolution) | Change |
|---|---|
| `stdlib/public/runtime/Metadata.cpp` | `_swift_updateClassMetadataImpl` + `swift_updateClassMetadata{,2}` are compiled at layout 1 **and** 2; the layout-2 body recomputes the field offset vector and size (`initClassFieldOffsetVector`), slides the field-offset globals (`initGNUstepClassFieldOffsets`) and mirrors `instance_size`. `swift_updatePureObjCClassMetadata` stays layout-1-only (it walks `class_ro_t`) |
| `lib/IRGen/GenClass.cpp` | `getClassMetadataStrategy()`: an `Update` class that libobjc2 allocates from (`Lowering::usesObjCAllocator`) uses `Singleton` at layout 2, so the layout is final before the class is registered |

| File (flip) | Change |
|---|---|
| `include/swift/Runtime/Config.h` | non-Darwin default `SWIFT_OBJC_CLASS_LAYOUT` 0 -> 2 |
| `lib/IRGen/GenMeta.cpp` | layout 2 without interop: no metaclass for the `isa`/flags word (use `MetadataKind::Class`) and a null root superclass instead of an ObjC class ref |
| `lib/IRGen/GenClass.cpp` | `buildMetaclassStub()` emits nothing at layout 2 without interop |

| File (S5) | Change |
|---|---|
| `lib/IRGen/GenObjC.cpp` | `getGNUstepSelector()` takes the type encoding and emits one record per (name, encoding); Clang-compatible symbol and types-string mangling (`.objc_selector_<name>_<encoding, '@' -> '\1'>`); the encoding string is shared with Clang's `.objc_sel_types_<mangled>` |
| `lib/IRGen/GenClass.{h,cpp}` | `getAddrOfGNUstepSelector()` grew the encoding; `GNUstepMethodEntry::typeEncoding` plus `typeEncodingText()` recover the method descriptor's encoding text; `isRegistrableTypeEncoding()` keeps a null or `@"...`-bearing encoding on the untyped record |

| File (S4b) | Change |
|---|---|
| `lib/IRGen/GenMeta.cpp` | `needsGNUstepClassObject()`; a 17-word GNUstep metaclass in the generic pattern's extra data; the pattern's instance/class method and ivar lists; `addMetadataFlags` still leaves a null `isa` for prespecialized generic classes |
| `lib/IRGen/GenObjC.cpp` | GNUstep super sends name the superclass at runtime when it is generic (`emitClassHeapMetadataRef` of the bound superclass type) instead of asserting on an unbound generic type; metaclass for class-method super sends |
| `lib/IRGen/GenClass.cpp` | `objc_ivar_list` entry order fixed to libobjc2's `{name, type, offset, size, flags}` (size before flags) |
| `include/swift/ABI/Metadata.h` | the generic pattern's `InstanceMethods`/`ClassMethods`/`Ivars` relative pointers (layout 2); `getObjCInstanceSize()`/`setObjCInstanceSize()` on the GNUstep header (Swift's `InstanceSize` shadows it) |
| `stdlib/public/runtime/Metadata.cpp` | metaclass from the pattern, method/ivar lists, shared empty ivar list; `copyGenericClassObjCName()` hoisted to both class-object layouts; `initGNUstepGenericClassObjCName()`; registration and `instance_size` mirroring in `_swift_initClassMetadataImpl`; ObjC-superclass branch in `initClassFieldOffsetVector` |
| `stdlib/public/runtime/SwiftObject.mm` | `swift_instantiateObjCClass()` calls `objc_loadClass_np()` at layout 2 |
| `libagora-objc/{class.h,class_table.c}` | `objc_loadClass_np()` (S0 hook) plus the runtime lock around `objc_load_class()` (patch 0006) |

| File (S4c) | Change |
|---|---|
| `include/swift/ABI/Metadata.h` | the resilient pattern's `Name`/`InstanceMethods`/`Ivars` relative pointers (layout 2) |
| `lib/IRGen/GenMeta.cpp` | `ResilientClassMetadataBuilder`: a static GNUstep metaclass for an ObjC-ancestry resilient class, and the class-side fields in the pattern (the ivar list is emitted even for a pure Swift resilient class, for the field-offset globals) |
| `stdlib/public/runtime/Metadata.cpp` | `initializeGNUstepClassHeader()` overload for the resilient pattern; registration for any runtime-built class with an `isa`; `initGNUstepClassFieldOffsets()` |

| File (S4) | Change |
|---|---|
| `lib/IRGen/GenMeta.cpp` | generic pattern: no Apple extra data (metaclass/RO data, offsets, flag) at layout 2; null `isa` for prespecialized generic metadata instead of a static metaclass; the resilient pattern's `class_ro_t`/metaclass pointers are also null at layout 2 (they used to reference a metaclass symbol nothing defined) |
| `stdlib/public/runtime/Metadata.cpp` | `initializeGNUstepClassHeader()`; call it from `initializeClassMetadataFromPattern` and `_swift_relocateClassMetadata` so runtime-built metadata gets `ABIVersion = 3` and empty ObjC fields |

| File (S1) | Change |
|---|---|
| `CMakeLists.txt` | `SWIFT_OBJC_CLASS_LAYOUT` cache option → directory-wide `-D`, empty by default |
| `lib/IRGen/IRGenModule.h` | `usesGNUstepClassABI()`; `GNUstepClassStructTy`; `GNUstepClassData` cache and accessor |
| `lib/IRGen/IRGenModule.cpp` | the 17-word GNUstep `objc_class` LLVM type |
| `lib/IRGen/ClassMetadataVisitor.h` | GNUstep header field order after `super_class`; scanner sizes |
| `lib/IRGen/GenMeta.cpp` | name/version/info/instance_size/ivars/methods/… emission; metaclass definition before the class initializer |
| `lib/IRGen/GenClass.{h,cpp}` | `objc_method_list` and `objc_ivar_list` emission; GNUstep metaclass; per-class data cache; `getAddrOfGNUstepSelector` |
| `lib/IRGen/GenObjC.{h,cpp}` | `ObjCMethodDescriptor::selector` (the name, so GNUstep can intern a real `SEL`) |
| `lib/IRGen/GenDecl.cpp` | class list section `__objc_classes` when GNUstep |
| `lib/IRGen/Linking.cpp` | `._OBJC_METACLASS_<name>` for Swift-defined classes; GNUstep type for metaclass entities |

Previous round, still current:

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
| `libagora-base/NSObject.h`, `NSObject.m` (patch 0005) | `+allocWithZone:` compatibility door: ignores the zone, forwards to `+alloc`; the parameter is `struct _NSZone *` for type-encoding compatibility |
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
| `swift-toolchain/patches/0005-libagora-base-allocWithZone.patch` | the `NSObject` compatibility door (applied to the `libagora-base` working tree, like 0001/0002) |
| `swift-interop-probe/scripts/run-native-probe.sh` | builds and runs both probes against the native toolchain (no SwiftPM); `SWIFTC=` selects the layout-2 compiler |
| `swift-interop-probe/{AgoraProbeKit,Sources}` | adapted to Agora's headers (`.alloc()` instead of `NSObject()`; the accessors read as properties since §2.17), plus `AgoraProbeIsKindOfClassNamed` for class-cluster checks |
| `swift-toolchain/scripts/build-layout2-frontend.sh` | configures the existing build tree with `SWIFT_OBJC_CLASS_LAYOUT=2`, builds only `swift-frontend`, and writes a `swiftc-layout2` wrapper (S1 test compiler) |
| `swift-toolchain/scripts/build-layout2-stdlib.sh` | builds the layout-2 frontend **and target stdlib** in the build tree (not installed) and writes `swiftc-layout2-stdlib`; the S4 experiment |
| `swift-toolchain/scripts/verify-class-abi.sh` | the S1 gate: C-side registration/dispatch/`+load` checks against a Swift class |
| `swift-toolchain/scripts/verify-generic-abi.sh` | the S4 gate: generic classes against the layout-2 stdlib, and a check that the binary linked that stdlib |
| `swift-toolchain/scripts/verify-generic-objc-abi.sh` | the S4b gate: generic ObjC-ancestry classes as class objects (Swift side + C-side alloc/init shape check) |
| `swift-toolchain/patches/0006-libagora-objc-loadClass-np.patch` | the libobjc2 working-tree changes the toolchain depends on: `objc_loadClass_np`, the runtime lock, and the `libobjc.so.4` SONAME |
| `swift-toolchain/scripts/verify-swift-port.sh` | `VERIFY_SWIFTC` override, so the language/runtime gate can also run against a test compiler |
| `swift-toolchain/scripts/native-env.sh` | `AGORA_SWIFT_CLASS_LAYOUT` (empty = platform default) |

Regenerate the fork patch after editing the source tree:

```sh
git -C ~/.agora-swift/src/swift diff HEAD \
  > swift-toolchain/patches/0003-swift-enable-objc-interop.patch
```

`HEAD` matters: `stdlib/public/SwiftShims/TargetConditionals.h` is a staged
addition, and a plain `git diff` omits it.

---

## 4. Reproduce / verify

```sh
# rebuild (incremental: ~1–3 min for runtime-only changes, ~15 min when ABI
# headers or IRGen change)
swift-toolchain/scripts/build-swift-toolchain.sh

# the language/runtime gate (installed toolchain, now layout 2; also checks
# the Foundation overlay's value bridges)
swift-toolchain/scripts/verify-swift-port.sh

# the S1 gate (layout-2 test compiler; builds the frontend if needed)
swift-toolchain/scripts/verify-class-abi.sh

# the S4 gate (layout-2 compiler AND stdlib in the build tree; builds them if
# needed - a full stdlib rebuild is ~15-30 min)
swift-toolchain/scripts/verify-generic-abi.sh

# the S4b/S4c gate (same build tree; generic classes with an ObjC ancestor, and
# resilient classes built with -enable-library-evolution)
swift-toolchain/scripts/verify-generic-objc-abi.sh

# the S5 gate (same build tree; typed selector records: deinit, typed init and
# method dispatch from Clang-compiled Objective-C, retain/release, no leak)
swift-toolchain/scripts/verify-refcount-abi.sh

# the library-evolution gate (same build tree; a class with a resiliently sized
# member: Update and Singleton, and a client run against an evolved v2 library)
swift-toolchain/scripts/verify-update-abi.sh

# the S1/probe/language gates against the same layout-2 stdlib
SKIP_BUILD=1 SWIFTC_LAYOUT2=$HOME/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64/bin/swiftc-layout2-stdlib \
  swift-toolchain/scripts/verify-class-abi.sh
VERIFY_SWIFTC=$HOME/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64/bin/swiftc-layout2-stdlib \
  swift-toolchain/scripts/verify-swift-port.sh
SWIFTC=$HOME/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64/bin/swiftc-layout2-stdlib \
  swift-interop-probe/scripts/run-native-probe.sh
```

The layout is a build-time choice and 2 is now the default:

```sh
# install layout 2 (the default; this is what is installed today)
swift-toolchain/scripts/build-swift-toolchain.sh

# go back to the compact layout (full rebuild; the old tree can be kept)
AGORA_SWIFT_CLASS_LAYOUT=0 swift-toolchain/scripts/build-swift-toolchain.sh
```

On this host the pre-flip install is preserved at
`~/.agora-swift/toolchain.layout0-backup`, and the build tree was already at
layout 2, so the flip took one `build-swift-toolchain.sh` run (~5 minutes of
incremental build and install).

To run the layout-2 gates against the **installed** toolchain (they default to
the build tree, which matters only for testing an uninstalled compiler change):

```sh
T=~/.agora-swift/toolchain/usr
SKIP_BUILD=1 SWIFTC_LAYOUT2=$T/bin/swiftc \
  swift-toolchain/scripts/verify-class-abi.sh
for g in verify-generic-abi verify-generic-objc-abi verify-refcount-abi; do
  SKIP_BUILD=1 SWIFTC_LAYOUT2=$T/bin/swiftc STDLIB_DIR=$T/lib/swift \
    swift-toolchain/scripts/$g.sh
done
```

### State on disk at the end of this round

- **Installed toolchain** (`~/.agora-swift/toolchain`): **layout 2**. The
  `swiftc` wrapper, `swift-frontend`, the Swift modules and the stdlib are all
  the flip build; `nm .../lib/swift/linux/libswiftCore.so | grep
  _OBJC_METACLASS__TtCs12_SwiftObject` finds the GNUstep root metaclass.
  `verify-swift-port.sh` and both probes are green against it.
- **Pre-flip backup** (`~/.agora-swift/toolchain.layout0-backup`): the previous
  layout-0 install, 3.3 GB, kept for rollback. It is not on any PATH; the
  documented rollback is a rebuild with `AGORA_SWIFT_CLASS_LAYOUT=0`.
- **Build tree** (`~/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64`):
  configured with `SWIFT_OBJC_CLASS_LAYOUT=2`; contains the full compiler built
  by `build-swift-toolchain.sh`, the layout-2 stdlib, and the convenience
  wrappers `bin/swiftc-layout2` (frontend only) and `bin/swiftc-layout2-stdlib`
  (frontend + build-tree stdlib).
- **Fork working tree** (`~/.agora-swift/src/swift`): all of patch 0003,
  uncommitted by design (now including the `Config.h` default and the two
  no-interop fixes). The Agora repository has the doc update committed
  (`76a5ad5` for S5; the flip is the next commit); `swift-toolchain/` and
  `swift-interop-probe/` are git-ignored local trees.
- **To change the layout**: `AGORA_SWIFT_CLASS_LAYOUT=0` (or `2`, the default)
  `swift-toolchain/scripts/build-swift-toolchain.sh`. The build script always
  passes `-DSWIFT_OBJC_CLASS_LAYOUT:` explicitly, so the cache cannot go stale.
- **Foundation overlay**: `usr/lib/swift/linux/Foundation.swiftmodule/` and
  `libFoundation.so`, built by
  `swift-toolchain/scripts/build-foundation-overlay.sh` (called by
  `build-swift-toolchain.sh` after the install). It belongs to the *installed*
  toolchain; the build-tree compiler does not have it, which is why the
  language gate skips the bridging check when `VERIFY_SWIFTC` points there.
- **Self-contained install**: `usr/lib/swift/host/runtime/` (the six host Swift
  runtime libraries), `usr/bin/clang` (a staged copy of the bootstrap clang) and
  `usr/lib/clang/21`; `usr/bin/swiftc` resolves the runtime relative to itself.
  `grep -rl agora-swift/bootstrap` over the whole installed tree finds nothing,
  and the build script's final self-check compiles, links and runs a program
  with `env -i`.
- **S6 state**: `swift-toolchain/compat/` and
  `swift-interop-probe/scripts/run-probe.sh` are deleted, and the stdlib's
  `SWIFT_EXPERIMENTAL_EXTRA_FLAGS` no longer carries the duplicated
  `-objc-runtime-vendor=gnustep` (so this round recompiled the Swift stdlib,
  ~5 minutes). The language gate's new export check runs against whichever
  `libswiftCore` the test program links.
- **Current results**: installed toolchain - `verify-swift-port.sh` all green
  (including S6's interop-export check), `run-native-probe.sh` 17/17 (only the
  known `#selector` gap), the library-evolution gate green (`Update` +
  `Singleton`, evolved v2 layout at `-Onone` and `-O`), and with
  `SWIFTC_LAYOUT2=$T/bin/swiftc STDLIB_DIR=$T/lib/swift`: `S1 gate: ok`,
  `S4 gate: ok`, `S4b/S4c gate: ok`, `S5 gate: ok`. `import Dispatch` (the
  no-interop layout-2 overlay) builds and runs.
  `build-prefix/lib/libobjc.so.4` is the rebuilt runtime with
  `objc_loadClass_np` and the lock (unchanged this round).

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

Current result with the **installed** toolchain: both probes pass (17/17; the
only `[gap]` is the missing `ObjectiveC` overlay), which is the point of the
flip - the Objective-C→Swift direction no longer needs a test compiler. The
build-tree wrappers can still be selected explicitly:

```sh
B=~/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64
SWIFTC=$B/bin/swiftc-layout2        swift-interop-probe/scripts/run-native-probe.sh
SWIFTC=$B/bin/swiftc-layout2-stdlib swift-interop-probe/scripts/run-native-probe.sh
```

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

1. **S5: typed selector records - done** (§2.11). Every method known to a
   GNUstep method list gets a selector record keyed by (name, encoding), with
   Clang's symbol mangling so the records merge; libobjc2's typed release send
   now reaches the Swift `-dealloc` and `deinit` runs. One residual case is
   documented, not hidden: an initializer whose encoding cannot be derived (a
   generic `Self` result) keeps the untyped record, so a *typed* ObjC send to
   that initializer would miss - Swift's own `objc_msgSend(obj, init)` is
   untyped and works. Closing it means giving those initializers a synthesized
   `@16@0:8` encoding; nothing in the stdlib needs it.
2. **Library evolution: the `Update` strategy - done** (§2.14). The runtime
   entry points are implemented at layout 2 (recompute the layout, slide the
   field-offset globals, mirror `instance_size`), and a class libobjc2 allocates
   from is built with `Singleton` so its layout is final before registration.
   The gate tests the actual promise: a client compiled against v1 runs against
   a v2 library whose struct has one more field, at `-Onone` and `-O`. What is
   still unimplemented is only the prespecialized-generic-with-ObjC-ancestor
   case, which stays unreachable (see §2.10) until a stdlib-like module
   declares one.
3. **Flip the default - done** (§2.12). `Runtime/Config.h` and `native-env.sh`
   default to layout 2, the installed toolchain is layout 2, and every gate is
   green against it, including both probes. The flip also fixed layout 2 *
   without* interop (the Dispatch overlay), which had no implementation. The
   rollback is `AGORA_SWIFT_CLASS_LAYOUT=0 <build script>`; the previous install
   is kept at `~/.agora-swift/toolchain.layout0-backup`.
4. **S6 - done** (§2.13). The dead bootstrap shim (`compat/ObjCInteropShim.c`)
   and the container probe harness are deleted, the duplicated
   `-objc-runtime-vendor=gnustep` build flag is gone, and the language gate now
   asserts that the interop entry points come from `libswiftCore`. The
   `#if SWIFT_OBJC_CLASS_LAYOUT` branches stay: Darwin uses layout 1, and layout
   0 is the documented rollback. What the plan calls "Apple-layout remnants" in
   the *fork* is therefore intentionally retained; what was dead in the Agora
   tree is not.
5. **S3: read/write the ivars from C - done** (§2.7). The S1 gate looks the
   emitted field up with `class_getInstanceVariable`, reads its offset, and
   proves both directions.
6. **Self-contained host runtime - done** (§2.15). The toolchain installs the
   host Swift runtime it needs under `lib/swift/host/runtime/` and the host
   clang it links with, and `swiftc` resolves both relative to itself; the
   bootstrap tree is needed to *build* the toolchain, not to use it. What a
   target program still needs is Agora's own prefix (`-L$AGORA_PREFIX/lib`);
   that is the product, not a build cheat.
7. **Foundation bridging and the Cocoa-shaped surface - done** (§2.16,
   §2.18). The overlay ships the value bridges, `Error` ↔ `NSError`, and the
   hand-written API surface (`Sequence` collections, Swift-typed
   `NSError`/`NSString` initializers, `NSObject: Hashable`). The one thing not
   done is rewriting *every* imported signature via `swift_bridge`: the
   importer then fails to bridge the arguments in the foreign thunk (a Swift
   `Dictionary`'s storage pointer reaches Objective-C), which is an
   importer/thunk ABI gap rather than an overlay one (§2.18).
8. **`+allocWithZone:` - done** (§2.6). `NSObject()` and every imported `T()`
   now work through a compatibility door that forwards to `+alloc`, so a
   subclass's singleton override still wins. Swift classes now use it for real
   (§2.7, §2.9).
9. **Property-shaped accessors - done** (§2.17). The read-only getters are
   `@property` declarations, so Swift reads `text.length`, `array.count`,
   `error.domain`. One consequence worth knowing: the Swift *names* follow the
   property (`utf8String`, not `UTF8String()`), so call sites written against
   the method spelling were updated.
10. **Keep the gates green.** `verify-swift-port.sh` is the language/runtime
   gate and now runs the *installed* layout-2 toolchain; `verify-class-abi.sh`
   is the C-side S1/S3 gate; `verify-generic-abi.sh` (S4),
   `verify-generic-objc-abi.sh` (S4b/S4c) and `verify-refcount-abi.sh` (S5)
   check the stdlib too (`STDLIB_DIR`); `run-native-probe.sh` is the native
   probe harness and passes 17/17 against the installed toolchain. The
   published-container `run-probe.sh` and `compat/ObjCInteropShim.c` were
   deleted in S6 (§2.13).

---

## 6. Artifact index

```
swift-toolchain/
├── README.md                                  build/run instructions
├── patches/
│   ├── 0001-libagora-base-objcxx-clean.patch   3 hunks / 2 files
│   ├── 0002-libagora-core-objcxx-clean.patch   1 hunk  / 1 file
│   ├── 0003-swift-enable-objc-interop.patch   45 files, ~1950 insertions
│   ├── 0004-libdispatch-overlay-non-interop.patch  1 file (the Dispatch overlay)
│   ├── 0005-libagora-base-allocWithZone.patch      2 files (NSObject)
│   ├── 0006-libagora-objc-loadClass-np.patch       3 files (the runtime hook,
│   │                                               its lock, the SONAME)
│   ├── 0007-libagora-base-tagged-string-probe.patch 1 file (NSString, the
│   │                                               stdlib's tagged-string SPI)
│   ├── 0008-libagora-objc-dtable-rebase-untyped.patch 1 file (the dtable
│   │                                               rebuild after class_setSuperclass)
│   └── 0009-libagora-base-property-shaped-accessors.patch 19 headers (readonly
│                                                   getters declared as properties)
├── foundation-overlay/
│   └── FoundationOverlay.swift                the Swift Foundation overlay:
│                                              String/Array/Dictionary/Set,
│                                              NSNumber, Error <-> NSError,
│                                              CustomNSError/LocalizedError
└── scripts/
    ├── build-swift-toolchain.sh               build + install (incl. wrapper,
    │                                          host runtime, clang, overlay)
    ├── build-foundation-overlay.sh            build + install the overlay and
    │                                          self-check it
    ├── build-layout2-frontend.sh              rebuild the in-tree frontend
    │                                          (+ swiftc-layout2 wrapper)
    ├── build-layout2-stdlib.sh                rebuild frontend AND stdlib in
    │                                          the tree (+ swiftc-layout2-stdlib)
    ├── native-env.sh                          paths; AGORA_SWIFT_CLASS_LAYOUT
    ├── verify-swift-port.sh                   the language/runtime gate
    ├── verify-class-abi.sh                    the S1/S3 gate (C sees the Swift
    │                                          class and its ivars)
    ├── verify-generic-abi.sh                  the S4 gate (needs the layout-2
    │                                          stdlib)
    ├── verify-generic-objc-abi.sh             the S4b/S4c gate (ObjC-ancestry
    │                                          generic and resilient classes)
    ├── verify-refcount-abi.sh                 the S5 gate (typed selectors:
    │                                          deinit, retain/release, typed
    │                                          dispatch from Objective-C)
    └── verify-update-abi.sh                   the library-evolution gate
                                               (resiliently sized members:
                                               Update + Singleton, evolved v2)

swift-interop-probe/
├── scripts/run-native-probe.sh                the harness (the only one; the
│                                              container harness was deleted)
├── class-abi/                                 the four standalone ABI probes
└── Sources/, AgoraProbeKit/                   the two probes + ObjC side-channel
```

Installed layout (what makes the toolchain self-contained, §2.15), under
`$OPEN_SWIFT_TOOLCHAIN_DESTDIR/usr`:

```
bin/swiftc                     wrapper: host runtime + swift-frontend
bin/clang, bin/clang++         staged host C compiler (links Swift programs)
bin/swift-frontend             the compiler (do not use directly: it would load
                               the target stdlib via its own RUNPATH)
lib/swift/host/runtime/        the compiler's own stdlib (non-interop, layout 0)
lib/swift/host/compiler/       the compiler's Swift libraries (swift-syntax, ...)
lib/clang/21/                  clang's resource directory
lib/swift/linux/               the target stdlib (interop, layout 2) - what
                               produced programs link through RUNPATH
lib/swift/linux/Foundation.swiftmodule/   the Foundation overlay (value
lib/swift/linux/libFoundation.so          bridges, Error <-> NSError)
```

Related: `swift-interop-probe/` (the two probes),
`../SWIFT-INTEROP-INVESTIGATION.md`, `../SWIFT-TOOLCHAIN-INTEGRATION.md`,
`../SWIFT-GNUSTEP-CLASS-ABI.md`.

## 7. One-paragraph summary

The installed toolchain *is* the destination ABI now. With
`SWIFT_OBJC_CLASS_LAYOUT=2` as the default (`Runtime/Config.h` and
`native-env.sh`), a Swift class with Objective-C ancestry is a real GNUstep
`struct objc_class` — found by `objc_getClass` before `main`, visible to
`respondsToSelector`, dispatchable from C for instance and class methods, able to
receive categories and `+load`, and instantiable through `objc_allocWithZone` —
and generic classes work too, including `Array`/`Set`/`Dictionary` (which are
built out of generic classes), generic-to-generic inheritance, casts between
specializations, `AnyObject` boxes, `Mirror`, and `deinit` of generic instances.
Interop is two-way in the shipped toolchain: `objc-to-swift-probe` passes end to
end. A layout-2 build also covers `-disable-objc-interop` compilations (the
Dispatch overlay) by emitting GNUstep-shaped metadata with no class-object
identity, its own fix from the flip.
The discoveries that mattered: a Swift-defined class needs its own
`._OBJC_METACLASS_<name>` (libobjc2 exports no metaclass symbols); a null
`objc_ivar_list` makes libobjc2 overwrite `instance_size` with the superclass's,
silently corrupting the heap; and a generic class's metadata is built by the
*runtime*, so the compiler and the stdlib must both be layout 2 (a mixed build
leaves `InstanceSize` unwritten and corrupts the heap for any field wider than a
word). S4 handles generic classes without an imported ObjC ancestor (everything
the stdlib has); S4b handles the rest of the common case: a generic class that
inherits `NSObject` gets a GNUstep metaclass in its pattern, a unique mangled
name per instantiation, its initializer/`-dealloc` method list, and registration
through libobjc2's `objc_loadClass_np`, so `Box(5)` allocates, initializes and
messages like any class object. S5 closed the last functional gap: selector
records are typed now - one per (name, encoding), mangled like Clang's - so a
typed send from Clang-compiled Objective-C (and from libobjc2's own release
path, which sends `dealloc_v16@0:8`) reaches a Swift method. That is why
`deinit` runs for fixed, generic and resilient classes with an Objective-C
ancestor, why `-init`/`-dealloc` overrides are reachable from C, and why
retain/release from C balance. The default is flipped, so all of that is what
the installed toolchain does, and S6 removed the last of the migration
scaffolding: the bootstrap interop shim and the container probe harness are
deleted, the duplicated vendor build flag is gone, and a gate keeps the shim
dead by checking `libswiftCore`'s exports. Library evolution's last gap is
closed as well: a class with a resiliently sized member works at layout 2 - the
`Update` entry points recompute the layout in place for pure Swift classes, and
a class libobjc2 allocates from is registered only after its layout is final -
verified by running one client binary against two versions of its library. What
remains is outside the class ABI: Foundation bridging and the
property-shaped accessors. Bridging has arrived with a named boundary: the
toolchain ships a Swift Foundation overlay (built with Agora's Clang Foundation
as its underlying module) that gives `as`/`as?` conversions for `String`,
`Substring`, `Array`, `Dictionary`, `Set`, the numeric types and `Error` <->
`NSError`, including `CustomNSError`/`LocalizedError`; what it does not do is
re-declare Agora's API surface so `NSString *` parameters import as `String`.
The read-only getters are `@property` declarations too, so Swift reads
`text.length`, `array.count` and `error.domain` the way it reads Cocoa.
Getting there needed two fixes worth remembering: Swift-emitted categories are
GNUstep structs in `__objc_cats` (not Apple's pointer list), and libobjc2's
dtable rebuild after `class_setSuperclass` has to keep the untyped dispatch
slot. The overlay also re-declares the Cocoa-shaped surface a program actually
calls (`NSArray`/`NSDictionary`/`NSSet` are `Sequence`, Swift-typed
`NSError`/`NSString` initializers, `NSObject: Hashable` for `AnyHashable`); the
`swift_bridge` attribute that would rewrite every imported signature is not
usable yet - the foreign thunk then hands a Swift value's storage to
Objective-C (§2.18). The installed toolchain no longer borrows the bootstrap's runtime either:
it ships the host Swift runtime and clang it needs and resolves them relative to
itself, so the bootstrap is build-time only. The rest of this summary is the
previous rounds' record of how the compiler got here.

The compiler compiles again. The trap was the class-metadata layout: the
compiler's own Swift libraries are built by the bootstrap toolchain without
interop and therefore emit Swift's compact class header, while `libswiftCore`
was built with interop and emitted Apple's five-word class header. The runtime
now uses the compact layout (`SWIFT_OBJC_CLASS_LAYOUT == 0` off Darwin; the
default has since moved to 2, §2.12) and IRGen keys every "is this an
Objective-C class object?" decision off one predicate, `usesObjCClassObject()`,
instead of interop. Four runtime bugs that only became
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
natively: `agora-import-probe` passes every check (including the `NSObject()`
sugar, which needed a `+allocWithZone:` compatibility door in Agora's NSObject),
and `objc-to-swift-probe`
compiled and linked but trapped in `objc_allocWithZone`, because a Swift
subclass of `NSObject` was not an Objective-C class object. At that point
interop was one-way — Swift messaged Agora, Agora did not see Swift classes —
which is the S1 → S6 work in `SWIFT-GNUSTEP-CLASS-ABI.md`. A previous round took
S1: the layout-2 test compiler makes fixed Swift classes class objects. This
round took S4: with a layout-2 stdlib, generic classes work as well, so the
destination toolchain is buildable and gated; S4b (generic classes with an ObjC
ancestor) and S5 (refcounting for classes with ObjC ancestry) are what remain
before the default flips.
