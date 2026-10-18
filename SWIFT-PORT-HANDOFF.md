# Swift-on-Agora port — handoff

*Status: **the compiler works.** `swiftc` type-checks, compiles, links and runs
Swift against Agora at `-Onone` and `-O`, including classes, generics,
protocols, existentials, error handling and Unicode strings; and Swift can
import Agora's `Foundation`, allocate its `NSObject` and message it. Verified by
[`swift-toolchain/scripts/verify-swift-port.sh`](swift-toolchain/scripts/verify-swift-port.sh).

**This round: stage S4 of the class-ABI plan is proven.** With the compiler
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

**Stage S1, proven last round and still green:** a test compiler built with
`SWIFT_OBJC_CLASS_LAYOUT=2` emits a Swift class with Objective-C ancestry as a
real GNUstep `struct objc_class`. An Objective-C constructor finds it with
`objc_getClass("Counter")` *before* `main`; `respondsToSelector` sees its
instance and class methods; an Objective-C category attaches and its `+load` is
delivered; and both method kinds dispatch from C to the Swift IMPs. With that
compiler `Counter()` (through `objc_allocWithZone`), `super -init`, field access
and the whole `objc-to-swift-probe` work too. Reproduce with
[`swift-toolchain/scripts/verify-class-abi.sh`](swift-toolchain/scripts/verify-class-abi.sh).

**What S4 deliberately does not cover, and what is now the next blocker:** a
*generic* class that inherits an imported Objective-C class
(`class Box<T>: NSObject`) is still not a class object, because S4 treats generic
metadata as non-Objective-C. That case is legal Swift and is also broken in the
*installed* layout-0 toolchain (it traps in `objc_allocWithZone`), so it is not a
regression - it is the dynamic-class path of
[`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md) §3.2 (the
`objc_loadClass_np` hook), now recorded there as **S4b**. Everything the stdlib
needs is generic classes *without* an imported ObjC ancestor, and those work.
The *installed* toolchain is still layout 0: the destination is now buildable and
gated, and flipping the default is the next decision, ahead of S5/S6.

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
| generics | generic classes (`_ContiguousArrayStorage`), `Array`, `Set`, `Dictionary`, prespecialised metadata (installed layout 0; a Swift-defined generic class under layout 2 is the S4 blocker) |
| existentials | class existentials (`[any P]`), `AnyObject` boxes holding Swift classes |
| errors | `throw` / `catch` / `try?`, native error boxes (`ErrorObjectNative.cpp`) |
| strings | interpolation, Unicode (`"héllo 🌍"`), `String(repeating:)` |
| concurrency types | `actor` declaration (not exercised at runtime) |
| **Agora interop** | `import Foundation` (Agora's), `NSObject.alloc()`, `isKind(of:)`, `description()`, `object_getClass`/`class_getName` through libobjc2 |
| **generic classes, layout 2** | runtime-instantiated metadata (`Box<T>`, `Pair<A,B>`, class-typed fields, generic subclasses), prespecialized metadata, `Array`/`Set`/`Dictionary`, casts between specializations, `AnyObject` boxing, `Mirror`, `deinit` of a generic instance |
| **default flags** | `swiftc prog.swift` enables Objective-C interop and selects the GNUstep runtime ABI family without any `-Xfrontend` flags |
| **super dispatch** | a Swift `super.` send to an imported class emits `objc_msg_lookup_super` + a direct IMP call, not Apple's `objc_msgSendSuper2`; such a program links, and with the layout-2 test compiler `objc-to-swift-probe` verifies the semantics (`super -init` is reached) |
| **the two probes** | `agora-import-probe`: all 11 checks; `objc-to-swift-probe`: compiles and links, then traps in `objc_allocWithZone` when the Swift subclass is first allocated with the *installed* toolchain — passes every check with the layout-2 compiler (frontend-only and layout-2-stdlib builds alike) |
| **Swift -> Agora class objects** (layout 2, test compiler) | class emitted as a GNUstep `struct objc_class` + metaclass; `objc_getClass` before `main`; `respondsToSelector`; instance and class dispatch from C; category attachment and `+load`; `Counter()` via `objc_allocWithZone`; ivar list keeps `instance_size` intact and is usable from C (`class_getInstanceVariable`, offsets, read/write both ways) |

**Not available yet in the *installed* (layout 0) toolchain.** At layout 2 (§2.7
for fixed classes, §2.8 for generic classes) the class-object items below are
done; they are listed here because the shipped toolchain is still layout 0, and
because the remaining gaps (S4b, S5) are exactly the parts of this list that
layout 2 does not close yet:

- Swift classes are **not** Objective-C class objects in the installed
  toolchain: `@objc` members on them, subclassing Agora's `NSObject` in Swift,
  categories, and ObjC→Swift dispatch do not work. Interop is one-way: Swift can
  message Agora objects, Agora never sees a Swift class. With the layout-2 test
  compiler a *fixed* Swift class is a class object (§2.7); *generic* classes are
  handled as non-class-objects (§2.8) and the stdlib rebuild is green.
- **Generic classes with an imported Objective-C ancestor** (`class Box<T>:
  NSObject`) are not class objects yet, so `Box(5)` still traps in
  `objc_allocWithZone`: the pattern carries no metaclass and the class is never
  registered with libobjc2. Legal Swift, not covered by the stdlib, broken in the
  installed toolchain as well. This is S4b in
  [`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md).
- No Foundation *bridging* of Swift values: `String` ↔ `NSString`, `Array` ↔
  `NSArray` and `Error` ↔ `NSError` all need the ObjC-object layout (and, for
  the value types, a Foundation overlay, which this toolchain does not build).
- **Swift class instantiation.** Any Swift class that inherits an imported class
  is instantiated through the Objective-C allocator: even with its own
  initializer, `T(start:)` is emitted as `Counter.__allocating_init(start:)` →
  `objc_allocWithZone`, and libobjc2 then treats the Swift metadata as a class
  object. With the compact layout that is invalid: the probe (and a two-line
  `class Counter: NSObject` with an explicit init) traps in
  `objc_test_class_flag`. Fixed by the layout-2 emission (§2.7); the installed
  toolchain still has it.
- **`NSObject()` sugar — fixed.** For a genuine Agora class the sugar goes
  through `objc_allocWithZone`, which sends `+allocWithZone:`. `NSObject` now
  implements that selector as a compatibility door that ignores its argument and
  forwards to `+alloc` (§2.6), so `NSObject()`, `NSNull()` and
  `NSMutableArray()` work. It does not help the Swift-class case above:
  libobjc2 inspects `cls->isa` *before* sending any message, so no selector is
  ever involved.
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
`SWIFT_OBJC_CLASS_LAYOUT=2` for the gate. Flipping the default needs S4
(generic-class patterns) first; the stdlib is full of generic classes.

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

**The boundary.** A generic class *cannot* have `@objc` members, so it never has
Objective-C methods to expose - but it **can** inherit an imported Objective-C
class (`class Box<T>: NSObject`), and then Swift allocates instances through
`objc_allocWithZone`. Such a class needs a metaclass in its pattern and runtime
registration through libobjc2's `objc_loadClass_np` (the S0 hook), plus a unique
Objective-C name per instantiation; S4 does not do that. The case traps today in
the installed layout-0 toolchain as well, so nothing regresses, but it is the
next piece of the destination ABI (S4b).

---

## 3. Change inventory

`swift-toolchain/patches/0003-swift-enable-objc-interop.patch`, 45 files,
~1310 insertions. The layout/registration table is from the previous round, the
S1 emission from the round before this one, and S4 is this round's addition:

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
| `swift-interop-probe/{AgoraProbeKit,Sources}` | adapted to Agora's headers (`length()` as a method, `.alloc()` instead of `NSObject()`), plus `AgoraProbeIsKindOfClassNamed` for class-cluster checks |
| `swift-toolchain/scripts/build-layout2-frontend.sh` | configures the existing build tree with `SWIFT_OBJC_CLASS_LAYOUT=2`, builds only `swift-frontend`, and writes a `swiftc-layout2` wrapper (S1 test compiler) |
| `swift-toolchain/scripts/build-layout2-stdlib.sh` | builds the layout-2 frontend **and target stdlib** in the build tree (not installed) and writes `swiftc-layout2-stdlib`; the S4 experiment |
| `swift-toolchain/scripts/verify-class-abi.sh` | the S1 gate: C-side registration/dispatch/`+load` checks against a Swift class |
| `swift-toolchain/scripts/verify-generic-abi.sh` | the S4 gate: generic classes against the layout-2 stdlib, and a check that the binary linked that stdlib |
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

# the language/runtime gate (installed toolchain, compact layout)
swift-toolchain/scripts/verify-swift-port.sh

# the S1 gate (layout-2 test compiler; builds the frontend if needed)
swift-toolchain/scripts/verify-class-abi.sh

# the S4 gate (layout-2 compiler AND stdlib in the build tree; builds them if
# needed - a full stdlib rebuild is ~15-30 min)
swift-toolchain/scripts/verify-generic-abi.sh

# the S1/probe/language gates against the same layout-2 stdlib
SKIP_BUILD=1 SWIFTC_LAYOUT2=$HOME/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64/bin/swiftc-layout2-stdlib \
  swift-toolchain/scripts/verify-class-abi.sh
VERIFY_SWIFTC=$HOME/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64/bin/swiftc-layout2-stdlib \
  swift-toolchain/scripts/verify-swift-port.sh
SWIFTC=$HOME/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64/bin/swiftc-layout2-stdlib \
  swift-interop-probe/scripts/run-native-probe.sh
```

The destination toolchain itself (installing layout 2 over the working
toolchain) is the same build script with the layout selected; it is *not* run by
default, and it replaces the installed toolchain:

```sh
AGORA_SWIFT_CLASS_LAYOUT=2 swift-toolchain/scripts/build-swift-toolchain.sh
# to go back: swift-toolchain/scripts/build-swift-toolchain.sh   (empty = default)
```

### State on disk at the end of this round

- **Installed toolchain** (`~/.agora-swift/toolchain`): unchanged, compact
  layout 0. `verify-swift-port.sh` is green.
- **Build tree** (`~/.agora-swift/src/build/agora-linux-x86_64/swift-linux-x86_64`):
  configured with `SWIFT_OBJC_CLASS_LAYOUT=2` and contains the layout-2
  `bin/swift-frontend`, the **layout-2 stdlib** (`lib/swift/linux/libswiftCore.so`
  and its `.swiftmodule`s), `bin/swiftc-layout2` (frontend-only, installed
  stdlib) and `bin/swiftc-layout2-stdlib` (frontend + build-tree stdlib). It is
  **not** installed; the installed stdlib is still the compact one.
- **Fork working tree** (`~/.agora-swift/src/swift`): all of patch 0003,
  uncommitted by design. The Agora repository has the doc update committed
  (`f28c8db`); `swift-toolchain/` and `swift-interop-probe/` are git-ignored
  local trees.
- **To restore the build tree to the default**: run
  `swift-toolchain/scripts/build-swift-toolchain.sh` (it always passes
  `-DSWIFT_OBJC_CLASS_LAYOUT:` with an empty default, which resets the cache) or
  `cmake -DSWIFT_OBJC_CLASS_LAYOUT:STRING= <build dir>`. The next build then
  recompiles ~1100 compiler TUs and the stdlib.
- **Current results**: `verify-swift-port.sh` all green;
  `verify-class-abi.sh` `S1 gate: ok` (S1 + S3 checks); probes with the installed toolchain
  11/11 then the known `objc_allocWithZone` trap; the S4 gate green
  (`S4 gate: ok`); and with the layout-2 *stdlib* every gate green - S1, S4,
  language/runtime, and both probes (17/17).

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

Current result with the installed toolchain: `agora-import-probe` passes;
`objc-to-swift-probe` builds and links, then traps in `objc_allocWithZone` on
the first Swift-class allocation, which is the layout-0 gate rather than a probe
defect. With either layout-2 compiler both probes pass:

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

1. **S4b: generic classes with an imported Objective-C ancestor.** The one case
   S4 does not cover, and the next piece of the destination ABI. It is legal
   Swift (`class Box<T>: NSObject`) and it still traps, in the installed layout-0
   toolchain as well as under layout 2:

   ```swift
   class Box<T>: NSObject { var value: T; init(_ v: T) { value = v; super.init() } }
   let b = Box(5)        // objc_allocWithZone -> cls->isa is NULL
   ```

   Swift allocates such a class through `objc_allocWithZone`, so its metadata
   must be a *registered* class object. Per
   [`SWIFT-GNUSTEP-CLASS-ABI.md`](SWIFT-GNUSTEP-CLASS-ABI.md) §3.2 that means:
   put a GNUstep metaclass object (17 words, `info & meta`, class method list)
   in the generic pattern's extra data; have the runtime point `isa`/`name`/
   `methods`/`ivars` at it, mirror `InstanceSize` into the ObjC field, and call
   `objc_loadClass_np()` (the S0 hook, already installed) once the completion
   function has computed the layout; and give each instantiation a unique ObjC
   name (the `setUpGenericClassObjCName` problem). Note the metaclass must be in
   the *copied* extra data, not a static symbol: libobjc2 writes `dtable`,
   `isa`, `super_class` and `subclass_list` into it.
2. **S5: refcounting for classes with Objective-C ancestry.** With the layout-2
   stdlib, a *pure* Swift class (generic or not) releases through Swift's path
   and `deinit` runs - verified, including generic instances. A class that
   inherits an imported ObjC class does not: its retain/release goes through
   libobjc2 (Agora's `NSObject -release` -> `objc_release` -> `gc->free_object`),
   so `deinit` is skipped. Something must make the ObjC path honour Swift's
   `ClassFlags::UsesSwiftRefcounting` - either libobjc2's `-release`/`-retain`
   (or a `-dealloc` installed on Swift classes) dispatching to
   `swift_retain`/`swift_release`, or IRGen emitting the Swift calls for
   `UsesSwiftRefcounting` classes. This also needs `+initialize` and
   `_objc_realizeClassFromSwift`/update-strategy classes revisited at layout 2.
3. **Flip the default.** Everything needed to *build* the destination toolchain
   now works: `AGORA_SWIFT_CLASS_LAYOUT=2 swift-toolchain/scripts/build-swift-toolchain.sh`
   installs a layout-2 compiler + stdlib, and all four gates are green against a
   layout-2 stdlib (§4). The default in `Runtime/Config.h` and
   `native-env.sh` is deliberately still the compact layout; flipping it is a
   decision to take once S4b/S5 either land or are consciously deferred (they
   are both pre-existing gaps in the installed toolchain, not regressions).
4. **S3: read/write the ivars from C - done** (§2.7). The S1 gate now also looks
   the emitted field up with `class_getInstanceVariable`, reads its offset, and
   proves both directions: a value C writes at that offset is read back by a
   Swift accessor, and a value Swift writes is read back by C. The ivar list is
   what keeps `instance_size` alive in the first place (§2.7).
5. **Self-contained host runtime.** Replace the wrapper's dependence on
   `~/.agora-swift/bootstrap` with a non-interop stdlib installed under the
   toolchain (`lib/swift/host/...`), or do the proper host/target split in the
   CMake install. This is the only remaining build-system "cheat".
6. **`+allocWithZone:` - done** (§2.6). `NSObject()` and every imported `T()`
   now work through a compatibility door that forwards to `+alloc`, so a
   subclass's singleton override still wins. Swift classes now use it for real
   (§2.7).
7. **Property-shaped accessors in Agora's headers.** `- (size_t)length` imports
   as `length()`, while Apple and GNUstep declare a `length` property. Writing
   Swift against Agora therefore reads differently from writing it against
   Cocoa. Converting the read-only accessors (`length`, `UTF8String`, ...) to
   `@property` declarations is source-compatible for Objective-C and would make
   `text.length` work.
8. **Keep the gates green.** `verify-swift-port.sh` is the language/runtime
   gate; `verify-class-abi.sh` is the C-side S1 gate; `verify-generic-abi.sh`
   is the S4 gate and the only one that needs a layout-2 stdlib;
   `run-native-probe.sh` is the native probe harness. The published-container
   `run-probe.sh` and `compat/ObjCInteropShim.c` are now historical.

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
│   ├── 0003-swift-enable-objc-interop.patch   45 files, ~1310 insertions
│   ├── 0004-libdispatch-overlay-non-interop.patch  1 file (the Dispatch overlay)
│   └── 0005-libagora-base-allocWithZone.patch      2 files (NSObject)
└── scripts/
    ├── build-swift-toolchain.sh               build + install (incl. wrapper)
    ├── build-layout2-frontend.sh              S1 test compiler only (frontend
    │                                          at layout 2 + swiftc-layout2)
    ├── build-layout2-stdlib.sh                S4 experiment: frontend AND
    │                                          stdlib at layout 2 (not
    │                                          installed) + swiftc-layout2-stdlib
    ├── native-env.sh                          paths; AGORA_SWIFT_CLASS_LAYOUT
    ├── verify-swift-port.sh                   the language/runtime gate
    ├── verify-class-abi.sh                    the S1 gate (C sees the Swift class)
    └── verify-generic-abi.sh                  the S4 gate (needs the layout-2
                                               stdlib)

swift-interop-probe/
├── scripts/run-probe.sh                       the original container harness
├── scripts/run-native-probe.sh                the native harness (current)
└── Sources/, AgoraProbeKit/                   the two probes + ObjC side-channel
```

Related: `swift-interop-probe/` (the two probes),
`../SWIFT-INTEROP-INVESTIGATION.md`, `../SWIFT-TOOLCHAIN-INTEGRATION.md`,
`../SWIFT-GNUSTEP-CLASS-ABI.md`.

## 7. One-paragraph summary

Two things are true at once. The installed toolchain works at the compact class
layout and can message Agora from Swift (one-way interop); and the destination
ABI is proven in a full layout-2 build of the compiler *and* stdlib: with
`SWIFT_OBJC_CLASS_LAYOUT=2`, a Swift class with Objective-C ancestry is a real
GNUstep `struct objc_class` — found by `objc_getClass` before `main`, visible to
`respondsToSelector`, dispatchable from C for instance and class methods, able to
receive categories and `+load`, and instantiable through `objc_allocWithZone` —
and generic classes work too, including `Array`/`Set`/`Dictionary` (which are
built out of generic classes), generic-to-generic inheritance, casts between
specializations, `AnyObject` boxes, `Mirror`, and `deinit` of generic instances.
The discoveries that mattered: a Swift-defined class needs its own
`._OBJC_METACLASS_<name>` (libobjc2 exports no metaclass symbols); a null
`objc_ivar_list` makes libobjc2 overwrite `instance_size` with the superclass's,
silently corrupting the heap; and a generic class's metadata is built by the
*runtime*, so the compiler and the stdlib must both be layout 2 (a mixed build
leaves `InstanceSize` unwritten and corrupts the heap for any field wider than a
word). S4 therefore stops at generic classes without an imported ObjC ancestor,
which is everything the stdlib needs; `class Box<T>: NSObject` remains the next
piece (S4b, via the `objc_loadClass_np` hook), and classes with ObjC ancestry
still lose `deinit` to libobjc2's release path (S5). Flipping the shipped default
to layout 2 is now a decision, not a blocker. The rest of this summary is the
previous rounds' record of how the compiler got here.

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
natively: `agora-import-probe` passes every check (including the `NSObject()`
sugar, which needed a `+allocWithZone:` compatibility door in Agora's NSObject),
and `objc-to-swift-probe`
compiled and linked but trapped in `objc_allocWithZone`, because a Swift
subclass of `NSObject` was not an Objective-C class object. At that point
interop was one-way — Swift messaged Agora, Agora did not see Swift classes —
which is the S1 → S6 work in `SWIFT-GNUSTEP-CLASS-ABI.md`. This round took S1:
the layout-2 test compiler makes fixed Swift classes class objects, and S4
(generic patterns) is what stands between it and the default.
