# Swift-on-Agora port — handoff

*Status: **the compiler works.** `swiftc` type-checks, compiles, links and runs
Swift against Agora at `-Onone` and `-O`, including classes, generics,
protocols, existentials, error handling and Unicode strings; and Swift can
import Agora's `Foundation`, allocate its `NSObject` and message it. Verified by
[`swift-toolchain/scripts/verify-swift-port.sh`](swift-toolchain/scripts/verify-swift-port.sh).

**The Swift surface is finished.** The Cocoa value types carry the API a
program actually calls (`Data` is a collection you can slice and mutate,
`IndexSet`/`CharacterSet` are `SetAlgebra`, `Decimal` has arithmetic and
literals, `Calendar` has the date math and `DateFormatter`), Agora's headers use
the four annotations Darwin's do (`NS_TYPED_ENUM`, `NS_SWIFT_NAME`,
`NS_REFINED_FOR_SWIFT`, `NS_SWIFT_SENDABLE`), the collection cores carry
`NSUInteger` encodings on every count parameter, and a generic initializer has a
typed selector record. §2.22.

**Bridging is zero-copy now, as on Darwin.** A Swift `String`, `Array`,
`Dictionary` or `Set` crosses into Objective-C as a *view* over the same storage
(`__StringStorage`, `__SwiftDeferredNSArray`, `_SwiftDeferredNSDictionary`,
`_SwiftDeferredNSSet`, or the contiguous storage itself), and the inverse bridge
adopts that storage instead of copying. Getting there required closing three
defects, each of which crashed: a non-generic Swift class with a generic
superclass was emitted as a class object although its superclass never could be
one; the stdlib's `@_swift_native_objc_runtime_base` collection storages were
*not* emitted as class objects although they are reparented to Foundation's
collections; and `count`'s `NSUInteger` (`Q`) encoding did not match the Swift
`Int` (`q`), so Clang's typed send reached the inherited `NSDictionary`/`NSSet`
method. A libobjc2 autorelease recursion and the `-isNSString__` probe were the
last two. §2.21.

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

**A Swift subclass of an AppKit class is laid out correctly now (2026-10-22).**
The last ABI defect that stood between the bridge and an actual Swift GUI
program: IRGen laid a Swift class's fields out from the isa word, which is what
Darwin can do because objc4 *slides* `instance_size` and the ivar offsets when it
realizes the class. libobjc2 does not slide, so a Swift subclass of `NSView` was
16 bytes with its field at offset 8 while `NSView` is 496 bytes with 54 ivars:
the field aliased the superclass's first ivar and the object was allocated
smaller than the superclass writes to. `ClassLayoutBuilder` now adds an imported
Objective-C superclass's `getASTObjCInterfaceLayout()` size as padding before the
Swift fields (gated on `usesGNUstepClassABI()`, the same computation clang's
`CGObjCGNU` backend makes for `instance_size`). `NSView` + one stored property is
504 bytes with the field at 496; a Swift `NSView` subclass now draws and its
pixels reach the compositor. The one case left is a superclass whose ivars are
synthesized in its `@implementation` (a module importer cannot see them), which
still needs the runtime slide; Agora's own AppKit declares its ivars in headers.
§2.23, `SWIFT-GNUSTEP-CLASS-ABI.md` S3, and
[`swift-interop-probe/conformance/FINDINGS.md`](swift-interop-probe/conformance/FINDINGS.md).

**A `Protocol` object can be messaged now, and `CGFloat` imports (2026-10-22).**
A protocol object aborted the process on any message (`NSLog(@"%@", proto)`),
which predates this work and is unrelated to Swift: its class roots at the legacy
`Object`, whose dispatch table nothing builds; the runtime class carries no
methods; and Foundation's forwarding hook asked the receiver
`-respondsToSelector:` to decide whether to forward, which re-entered itself.
Fixed in three places — libobjc2 builds a superclass's dtable on demand (and
treats a self-super metaclass as a root), Foundation supplies `-name`,
`-description`, `-hash` and `-isEqual:` as a `Protocol` category (the runtime
must not depend on `NSString`), and `fn_proxy_lookup`/`fn_forward_handler` ask
the runtime instead of messaging. `CGFloat` now imports: the Clang importer maps
the C typedef to a Swift type of that name looked up in the Foundation overlay,
which did not declare one. `NSWindow`'s common accessors are `@property`
declarations now, so the demo is written `window.title = …` rather than
`window.setTitle(…)`. §2.28.

**A superclass with no layout in its header is laid out at load time
(2026-10-22).** The last gap in the class layout: a Swift subclass of an
Objective-C class whose ivars exist only in the `@implementation` (declared as
`@property`, synthesized, no ivar block in the header) cannot know that class's
size at compile time, so it was laid out from offset 8 and aliased the
superclass's storage (`OpaqueHost` 24 bytes, the Swift subclass 9 with its field
at 8). IRGen now treats an imported superclass with *no ivars in its
`@interface`* as unknown (`ClassHasOpaqueObjCSuperclass`) and emits the class
late-bound: `instance_size` 0, which libobjc2's `objc_compute_ivar_offsets()`
already reads as "compute from the runtime superclass and the ivar list" — the
path clang's non-fragile emission uses. libobjc2 then calls a weak
`swift_objcClassLayoutDidChange()`, which the Swift runtime implements to mirror
the computed size into Swift's own `InstanceSize` word (which the GNUstep
`instance_size` hides), so a Swift subclass below it lays out correctly too.
Measured: the subclass is 25 bytes with its field at 24 and the superclass's
ivars intact. §2.26.

**Protocols declared in Swift are registered now (2026-10-22).** They were
emitted as Apple's `protocol_t` in the Apple `objc_protolist`/`objc_protorefs`
sections, which libobjc2 never reads, so `objc_getProtocol()` found none and a
class's GNUstep protocol list could not name one. IRGen now emits GNUstep's
`struct objc_protocol` — name, inherited list, required/optional instance/class
method-description lists — into `__objc_protocols`, with clang's
`._OBJC_PROTOCOL_<name>` weak symbol so a declaring and a referencing module
share one object. `class_conformsToProtocol:` and `class_copyProtocolList` now
answer for a Swift-declared protocol, by pointer. §2.27.

**`BOOL` is Apple's now, so a `BOOL` override is reached by a typed send
(2026-10-22).** `libagora-objc` defaulted to GNUstep's `unsigned char`, which
encodes as `C`; Swift's `Bool` encodes as Apple's `c` on x86_64. libobjc2 keys
typed dispatch on (selector, encoding), so a clang-built caller's
`-sharedFlag` (`C16@0:8`) missed a Swift override registered as `c16@0:8` and
the superclass's IMP answered — silently, for every `BOOL`-returning method
(`-validateMenuItem:`, `-windowShouldClose:`, `-isEqual:`). The header now
defines `BOOL` per Apple's rule under `STRICT_APPLE_COMPATIBILITY`, which is the
default: `bool`/`_Bool` on arm64, `signed char` elsewhere; the `@VAR@` form of
the config header was emitting `ON`, colliding with the compile definition, so
the `.in` now emits `1`. Because the encoding is baked into every already-built
library, the whole stack was rebuilt: all suites pass (`libagora-base` 23,
`libagora-app` 125, `workspace` 13, `window-server` 10, ...), and the
conformance matrix is now **31/31 encodings and 46/46 checks**. §2.25.

**A Swift class publishes its `@objc` protocol conformances now (2026-10-22).**
The GNUstep class object's `protocols` field was a null pointer, so
`class_conformsToProtocol:` answered `NO` for a Swift delegate and
`class_copyProtocolList` returned nothing — the kind of reflection Cocoa uses for
delegate validation, `IBOutlet` inspection and KVC. Three things were needed:
the GNUstep `struct objc_protocol_list` shape (`{ next, count, list[] }`, not
Apple's `{ count, refs[] }`); clang's `struct objc_protocol` as the entry for an
*imported* protocol (`emitClangProtocolObject`, previously unused, plus the
`._OBJC_PROTOCOL_X` symbols in the TBD), because conformance is a pointer
compare and Swift's own record was Apple-shaped and never registered; and a
libobjc2 fix — `init_protocols()` now initialises a `protocol_version_gsv2`
record unconditionally, since a class list can name a protocol from another
image, which the old code aborted on. §2.24. A protocol declared in *Swift* is
still Apple-shaped and is filtered out of the list rather than corrupted; that
emitter is the remaining piece.

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
| **runtime-pattern classes without ObjC ancestry** | a non-generic class whose superclass is a generic Swift class (`class Sub: Base<Int>`) or a pure Swift generic class itself: metadata is instantiated at runtime, stays a plain Swift metadata object, and never claims a class-object `isa`; fields, inheritance and `deinit` work (§2.21) |
| **zero-copy bridges** | `String`/`Array`/`Dictionary`/`Set` cross as `__StringStorage` / `__SwiftDeferredNSArray` / `_SwiftDeferredNSDictionary` / `_SwiftDeferredNSSet` views (the storage classes are registered GNUstep class objects), ObjC primitives (`-count`, `-objectAtIndex:`, `-substringFromIndex:`, `-allObjects`, `-objectForKey:`) reach the Swift overrides, and the inverse bridge adopts the storage back (§2.21) |
| **the Cocoa value types** | `Data` is a `RandomAccessCollection`/`MutableCollection`, `IndexSet`/`CharacterSet` are `SetAlgebra`, `Decimal` has arithmetic + literals, `Calendar` has the date arithmetic and `DateFormatter`; `NSNotificationName` is a typed enum, `__getCharacters` is the refined door, and `NSNull`/`NSUUID` are `Sendable` (§2.22) |
| **library evolution, resiliently sized members** (layout 2) | a class with a stored property of a non-frozen struct from another module: `Update` for a pure Swift class, `Singleton` for one libobjc2 allocates from; a client compiled against v1 runs against a v2 library whose struct grew, `-Onone` and `-O` |
| **typed selectors** (S5) | one selector record per (name, encoding) in `__objc_selectors`, symbol-mangled like Clang's GNUstep emitter; typed send reaches Swift methods, including overrides of inherited selectors (`-dealloc`, `-init`); untyped sends keep working through the untyped slot; retain/release from C balances and `deinit` runs exactly once |
| **default flags** | `swiftc prog.swift` enables Objective-C interop and selects the GNUstep runtime ABI family without any `-Xfrontend` flags |
| **super dispatch** | a Swift `super.` send to an imported class emits `objc_msg_lookup_super` + a direct IMP call, not Apple's `objc_msgSendSuper2`; such a program links, and with the layout-2 test compiler `objc-to-swift-probe` verifies the semantics (`super -init` is reached) |
| **the two probes** | `agora-import-probe`: all 11 checks; `objc-to-swift-probe`: every check with the **installed** toolchain (only the known `[gap]`: no `ObjectiveC` overlay, so no `#selector`) |
| **Swift -> Agora class objects** (layout 2, test compiler) | class emitted as a GNUstep `struct objc_class` + metaclass; `objc_getClass` before `main`; `respondsToSelector`; instance and class dispatch from C; category attachment and `+load`; `Counter()` via `objc_allocWithZone`; ivar list keeps `instance_size` intact and is usable from C (`class_getInstanceVariable`, offsets, read/write both ways) |

**What the installed (layout 2) toolchain still does not do.** The class ABI is
closed (S1-S6); these are independent of it:

- Foundation **bridging** is at feature parity with Darwin's (§2.16, §2.19,
  §2.20): the `ObjectiveC` module exists (`BOOL` -> `Bool`, `#selector`,
  `NSZone`), `AnyHashable` bridges to `NSObject`, every fixed-width number and
  `Float` bridges to `NSNumber`, `NSString *`/`NSArray *`/`NSDictionary *`/
  `NSSet *` import as `String`/`[Any]`/`[AnyHashable: Any]`/`Set<AnyHashable>`,
  and the Foundation value types (`Data`, `Date`, `URL`, `UUID`, `IndexPath`,
  `TimeZone`, `Locale`, `Calendar`, `DateComponents`, `DateInterval`,
  `Notification`, `PersonNameComponents`, `CharacterSet`, `IndexSet`, `Decimal`,
  `AffineTransform`, `NSAttributedString.Key`) bridge to their classes, the
  bridge is **zero-copy in both directions** (§2.21), and `as?` on a bridged
  collection or number is a **check, not a conversion** (§2.22): a mismatched
  element or an out-of-range `NSNumber` gives nil, as on Darwin.
- **`__SwiftValue` and the `SwiftNativeNS*` wrapper classes** were expected to
  fail at layout 0 (no Swift heap header); at layout 2 they carry one. The
  class-identity side is exercised (`__SwiftValue` above), and the box's
  `-copy` path (Agora's `NSObject` makes `-copy` the override point) was fixed
  in §2.20. What is left untested is their deeper CoreFoundation fast paths,
  which Agora's classes do not implement and the overlay does not rely on.
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
| `String`, `Substring` ↔ `NSString` | UTF-16 through `-initWithCharacters:length:` / `-getCharacters:range:` (this round; §2.21 replaces the copy with the stdlib's view) |
| `Array` ↔ `NSArray`, `Dictionary` ↔ `NSDictionary`, `Set` ↔ `NSSet` | copies into/out of Agora's mutable collections; elements bridge with `_bridgeAnythingToObjectiveC` (this round; §2.21 replaces the copy with the stdlib's views) |
| `Int`, `Double`, `Bool` ↔ `NSNumber` | the `+numberWith…` factories and the `…Value` accessors |
| `Error` ↔ `NSError` | `_convertErrorToNSError`/`_convertNSErrorToError` (the names SILGen looks up) plus `NSError: Error` |
| `CustomNSError`, `LocalizedError` | the protocols, their defaults, and `_getErrorDefaultUserInfo` (the symbol the runtime `dlsym`s to fill an NSError's userInfo) |

Bridging is deliberately by **copying**, not through the stdlib's
`SwiftNativeNS*` machinery: those classes are reparented to Darwin's
CoreFoundation classes and the fast paths send CoreFoundation SPI to them
(`+newTaggedNSStringWithASCIIBytes_:length_:`, which Agora's `NSString` does not
implement and which raised on the base class). **Superseded by §2.21**: the
overlay uses those views now, and the two SPI gaps named here (the tagged-string
probe and the base classes honouring subclass primitives) were closed on the
way - the probe by answering nil, the primitives by the typed-selector
encodings.

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
conversion (or the importer keeping the unbridged type in the SIL signature).
That gap is closed in §2.19; what was still missing at the time of this round
was the `AnyHashable` bridge, not the importer.

Verified by the language gate's bridging section: `NSError(domain:code:userInfo:)`
with Swift values, iteration over all three collection classes, `NSString(string:)`,
and `NSObject` in `AnyHashable` - plus the whole gate suite (both probes, S1,
S4, S4b/S4c, S5, library evolution) against the installed toolchain.

### 2.19 `swift_bridge`: the importer/thunk gap

The Clang attribute was the last piece of the Cocoa surface: with
`__attribute__((swift_bridge("Swift.String")))` on `NSString` the importer
rewrites every `NSString *` to Swift `String`, and `NSArray` gets the same for
`[Any]` (patch `0010-libagora-base-swift-bridge-attributes.patch`). What the
previous round could not do was make that safe, because the rewrite happens at
the *AST* level while the Objective-C ABI is reconstructed from it later:

```
Clang:  - (void)initWithDomain:(NSString *)d code:(NSInteger)c
                         userInfo:(NSDictionary *)u;
AST:    init(domain: String, code: Int, userInfo: [AnyHashable : Any]?)
SIL:    @convention(objc_method) (NSString, Int, NSDictionary, ...)   <-- rebuilt
```

`TypeConverter::getLoweredFormalTypes()` builds that third line by asking each
bridged Swift type for its `_ObjectiveCBridgeable._ObjectiveCType`, and SILGen
then inserts `_bridgeToObjectiveC()` / `_unconditionallyBridgeFromObjectiveC()`
at the boundary - which is why a *direct* call with a `String` already worked
and produced the right message send. When the conformance is not there the
lookup returns the input unchanged (`getLoweredCBridgedType()`'s
`ForeignRepresentableKind::None` arm), and the compiler then holds a Swift value
type in an Objective-C argument slot. That is the failure the previous round
saw: IRGen's `SignatureExpansion::expandExternalSignatureTypes()` asks Clang
for a type for `Optional<Dictionary<AnyHashable, Any>>`, gets a null `QualType`
and asserts (`Cannot retrieve a NULL type pointer`). The previous round recorded
the other half of the same defect - a build in which IRGen did produce a call,
and a Swift `Dictionary`'s storage pointer went out where the `NSDictionary *`
belonged.

The conformance the lookup wanted was `AnyHashable: _ObjectiveCBridgeable`,
which on Darwin lives in the **`ObjectiveC` overlay** - the same overlay this
toolchain does not build (no `#selector`, §2.16). So `[AnyHashable: Any]` was
never representable in Objective-C here (a plain `@objc func` taking one is
rejected with "Swift structs cannot be represented in Objective-C"), while
`String` and `[Any]` were.

**The fix is in the importer, at the point where the choice is made.** A
`swift_bridge` attribute is a claim about a Swift type, not a promise that the
conformance exists, so `adjustTypeForConcreteImport()` now adopts the bridged
type only when the round trip is possible:

```cpp
// lib/ClangImporter/ImportType.cpp
static bool canBridgeBackToObjectiveC(ClangImporter::Implementation &impl,
                                      Type bridgedType) {
  if (!bridgedType->isPotentiallyBridgedValueType())
    return true;                       // classes and `id`/`Any`: identity
  auto *foundation = impl.tryLoadFoundationModule();
  if (!foundation) return false;       // no overlay: keep the ObjC types
  return bridgedType->isRepresentableIn(ForeignLanguage::ObjectiveC, foundation);
}
```

Applied to both places the hint can rewrite a signature (the `NSString *`
global special case and the general `ImportHint::ObjCBridged` case). The
consequence is a *graceful* fallback rather than a crash: with the attribute on
`NSDictionary`, `NSException.userInfo` keeps importing as `NSDictionary` and
passing a Swift `[AnyHashable: Any]` is an honest type error; with the
attribute off, nothing changes at all. The check costs a cached conformance
lookup per bridged type, and a negative result does not stick: `ForeignRepresentableCache`
entries are generation-tagged, and the module that supplies the conformance is
loaded through `tryLoadFoundationModule()` before the question is asked.

It is a source change for Swift, the same kind §2.17 recorded for the property
spellings: a parameter that was `NSString` is now `String`, so an `NSString`
*variable* at that boundary needs `as String` (a `String` needs nothing, and a
literal needs nothing); and a parameter that was `NSArray` is now `[Any]`, so an
`NSArray` variable needs `as! [Any]`. Objective-C is untouched - the selectors,
the encodings and the ABI are the ones the headers declared. The probes, the
overlay and every gate script were updated where they crossed those boundaries.

Verified by the language gate's new `swift_bridge` section - `NSString *` ->
`String` at a parameter, a result, a property getter and an initializer;
`NSArray *` -> `[Any]`; `String` -> `NSString *` on the way back; and the
fallback (`NSException(name:reason:userInfo:)` with an `NSDictionary`) - plus
both probes, the language/runtime gate and the S1, S4, S4b/S4c, S5 and
library-evolution gates against the installed toolchain. The before/after is
reproducible: the same `neg2`-shaped program aborts the *previous* frontend
with `While using clang to expand signature for type '@convention(objc_method)
(NSException) -> @autoreleased Optional<Dictionary<AnyHashable, Any>>'`, and
compiles (or reports the type error) with this one.

---

### 2.20 Bridging parity with Apple

*"Parity" in this section means coverage - which types bridge, in which
directions, and with what shape. The cast semantics were checked against
corelibs Foundation's reference implementation later and two of them were
wrong; §2.22 records that and the fix.*

The previous round closed the `swift_bridge` *mechanism* (§2.19) but left four
kinds of gap against Darwin. This round closes them:

**1. The `ObjectiveC` module.** The Clang importer looks three types up *by name*
in a module called `ObjectiveC`, and without it (a) every `BOOL` imported as
`UInt8` - Agora's `objc/runtime.h` makes it `unsigned char`, and the importer's
`ObjCBool` mapping only fires when Clang's `BOOLDecl` is recorded (it is only
recorded from an `__objc_yes`/`__objc_no` literal) or the typedef is C's
`bool`; (b) `SEL`/`#selector` were unavailable; (c) `NSZone` had no Swift
spelling. `swift-toolchain/objectivec-overlay/ObjectiveC.swift` now provides
`ObjCBool`, `Selector` (with `sel_getUid`/`sel_isEqual`/`sel_getName` declared
through `@_silgen_name`, since Agora's libobjc2 headers are not a Clang module),
`NSZone`, and the two `_convertBool…` helpers SILGen calls. The Foundation
overlay re-exports it, and the fork's `getSwiftStdlibType` now accepts a
one-byte `BOOL` typedef (the typedef's *name* is the contract); the
`getLoweredCBridgedType` Bool branch falls back to `ObjCBool` when the `Darwin`
module (and its `DarwinBoolean`) is absent. Result: `isEqual(_:)`, `isKind(of:)`,
`boolValue`, every `BOOL` parameter is `Bool` - and the probe's last `[gap]`,
`#selector`, is now `[ok]`.

**2. `AnyHashable` and `__SwiftValue`.** `AnyHashable: _ObjectiveCBridgeable`
(which the `ObjectiveC` overlay carries on Darwin) is now in the Foundation
overlay, bridging a class base verbatim and everything else through the
stdlib's boxer. That is what makes `[AnyHashable: Any]` and
`Set<AnyHashable>` representable in Objective-C, and therefore what lets
`swift_bridge` take effect on `NSDictionary`/`NSSet` (patch 0010 now annotates
all four classes). Bridged dictionary keys are normalized to `String`, so
`d["k"]` finds the entry an `NSDictionary` carried. The runtime's `__SwiftValue`
box implemented `-copyWithZone:` only, and Agora's `NSObject` makes `-copy` the
override point (zones are 32-bit API it does not have), so a boxed Swift value
used as a dictionary key aborted; `SwiftValue.mm` now implements `-copy` too.

**3. Numbers.** Every fixed-width integer, `Float`, `Double` and `Bool` bridges
to `NSNumber` (before: `Int`, `Double`, `Bool` only), through the matching
`numberWith…`/`…Value` pair, so `Int8(3) as NSNumber`, `UInt64.max as NSNumber`
and `NSNumber as? Float` all work.

**4. The value types.** `FoundationValueTypes.swift` declares the Swift types
Darwin's Foundation overlay declares, each bridged to Agora's class: `Data`,
`Date`, `URL`, `UUID`, `IndexPath`, `TimeZone`, `Locale`, `Calendar`,
`DateComponents`, `DateInterval`, `Notification` (+ `Notification.Name`),
`PersonNameComponents`, `CharacterSet`, `IndexSet`, `Decimal`,
`AffineTransform` and `NSAttributedString.Key`. Each carries the API surface a
program actually calls and conforms to `_ObjectiveCBridgeable`, so
`Data() as NSData`, `date as NSDate` and the reverse all work. `Decimal` is a
wrapper over Agora's `NSDecimal` struct with `NSDecimalNumber` doing the
comparisons; it does not yet implement arithmetic operators.

**5. Error extras.** `RecoverableError`, `_ErrorCodeProtocol`,
`_ObjectiveCBridgeableError` and the `_BridgedStoredNSError` machinery the
imported `NS_ERROR_ENUM` shape uses, alongside the `CustomNSError`/
`LocalizedError`/`NSError` bridges that were already there.

**The zero-copy bridges were the last gap, and they are closed (§2.21).**
Darwin's `Array`/`String` bridges hand back *views* (`__SwiftDeferredNSArray`,
`__StringStorage`) over the same storage, and adopt them back
(`_bridgeFromObjectiveCAdoptingNativeStorageOf`). The machinery was already
compiled into our `libswiftCore.so`, but asking for a view crashed for three
independent reasons - a runtime-pattern class without ObjC ancestry claiming a
class-object `isa`, the `@_swift_native_objc_runtime_base` storage classes not
getting one, and `count`'s `NSUInteger`/`Int` encodings selecting different
selectors - so the overlay copied. This round fixed all three (plus a libobjc2
autorelease recursion and the `-isNSString__` probe), and the overlay now
bridges by view in both directions. See §2.21 for the measurements.


The value types' long tails and the header annotations are done too (§2.22):
`Data` is a `RandomAccessCollection`/`MutableCollection` with the mutation
surface, `IndexSet` and `CharacterSet` are `SetAlgebra`, `Decimal` has its
arithmetic and literal conformances, `Calendar` has the date math and
`DateFormatter`, and Agora's headers use `NS_TYPED_ENUM`, `NS_SWIFT_NAME`,
`NS_REFINED_FOR_SWIFT` and `NS_SWIFT_SENDABLE`. The one item that is not a
missing feature is the *unreachable* prespecialized-generic-with-ObjC-ancestor
case (§2.10's boundary note, re-measured in §2.22); everything a program can
instantiate today works.

---

### 2.21 Zero-copy bridging: the deferred wrappers become class objects

Darwin's bridges hand back *views* over the same storage (`__SwiftDeferredNSArray`,
`__StringStorage`, ...) and adopt them on the way back. Ours copied (§2.20),
because asking for the view crashed. This round removed every one of those
crashes, and the overlay now uses the views. Five independent defects stood in
the way, and each was a real bug rather than a bridging one.

**1. A fixed class with a generic Swift superclass was treated as a class
object, and crashed.** The smallest reproduction is five lines:

```swift
class Base<T> { var x: T; init(_ x: T) { self.x = x } }
class Sub: Base<Int> { init() { super.init(1) } }
let s = Sub()      // SIGSEGV in objc_resolve_class()
```

`Sub` is not generic, but its metadata is built at run time from a *pattern*
(the strategy is `Singleton`, because the superclass's layout is not known until
the generic argument is bound). `addMetadataFlags()` decided "is this a pattern?"
with `Target->isGenericContext()`, which is false for `Sub`, so the pattern
carried a **metaclass** and its `isa`. At completion the runtime saw a non-null
`isa` and did what S4b/S4c taught it to do: `objc_loadClass_np(Sub)`. libobjc2
then resolved the superclass chain - and `Base<Int>` is a pure Swift generic
class, which is deliberately *not* a class object (S4), so it has no `isa`, no
name, and no place in the class table. `objc_resolve_class()` walked into a
metadata object that was never a class and faulted.

The fix is one predicate, in `addMetadataFlags()`: a class whose metadata is
instantiated from a pattern is a class object only when it has **Objective-C
ancestry**; otherwise its pattern carries `MetadataKind::Class` (a null `isa`),
which is the state the runtime already handles for generic classes. "Is a
pattern" is `isGenericContext() || checkAncestry(AncestryFlags::Generic)` - the
second half is the case `Sub` exposed. A class with generic ancestry *and* an
Objective-C ancestor (e.g. `class Sub: Box<Int>` where `Box<T>: NSObject`) is
unchanged: the pattern's extra data carries its metaclass (S4b)/the resilient
pattern carries it (S4c), and the value emitted here is a placeholder.

**2. The standard library's collection storage classes were not class objects.**
`_DictionaryStorage`, `_SetStorage`, `_ContiguousArrayStorage` and friends are
reparented to `NSDictionary`/`NSSet`/`NSArray` at run time through
`@_swift_native_objc_runtime_base`, but they keep Swift's allocator and
reference counting - that is what the attribute is for - so
`ClassDecl::getObjectModel()` answers `Native` for them. The generic-pattern
builder asked exactly that question (`Target->getObjectModel() ==
ReferenceCounting::ObjC`) to decide whether to put a metaclass in the pattern,
so these classes never got one and were never registered: retaining a bridged
`Dictionary` faulted, and its class name was NULL.

The predicate is now `isGNUstepClassObject()`: the ObjC object model **or**
`checkAncestry(AncestryFlags::ObjC)` (which is set by `@objc`, and Sema only
permits `@objc` on a class with an Objective-C ancestor - including the
`@_swift_native_objc_runtime_base` storage classes, whose ancestor is named by
the attribute). The three class-object decisions in `GenMeta.cpp` use it.
With it, the storages are registered with a unique mangled name per
instantiation, and their `-objectForKey:`, `-count`, `-keyEnumerator`, etc. are
real Objective-C methods.

**3. Autoreleasing a Swift object recursed until the stack overflowed.**
libobjc2 picks its autorelease mechanism lazily: `useARCAutoreleasePool` is
zero-initialised, and until `initAutorelease()` runs, `autorelease()` falls
through to a manual `-autorelease` send. A Swift object at layout 2 has no
Objective-C `-autorelease` of its own, so it inherits `NSObject`'s, which calls
`objc_autorelease()`, which lands in `autorelease()` again. The first Swift
object ever autoreleased in a process therefore overflowed the stack - reached
for real through `-[NSDictionary allKeys]`, which autoreleases the Swift
`_SwiftDictionaryNSEnumerator` that `-keyEnumerator` returns. `autorelease()`
now calls the idempotent `initAutorelease()` first (patch 0011).

**4. `NSUInteger` and `Int` are different selectors under type-dependent
dispatch.** The last crash was `-[NSSet allObjects]` on a Swift set: it starts
with `[self count]`, Clang encodes that as `Q16@0:8`, the Swift classes declared
`@objc var count: Int` (encoding `q`), and libobjc2 keyed them as two different
selectors. The `Q` lookup hit the *inherited* `NSSet -count`, which read
`_members` at an offset the Swift object does not have. The fix follows the
precedent the string and array cores already set: the shadow protocols'
`count` requirement is `UInt` (`_NSSetCore`, `_NSDictionaryCore`), the four
storage classes answer it as `UInt`, and the `__Cocoa*` wrappers convert at
their edge. `-[NSSet count]`, `-[NSDictionary count]` and every method that
walks them (`allObjects`, `member:`, `objectForKey:`, ...) now reach Swift.

**5. The stdlib's "is this an NSString?" probe needs an answer.** `__StringStorage
-isEqual:` asks the *other* object `-isNSString__` before comparing against a
non-Swift string (Darwin's CoreFoundation strings answer it). Agora's `NSString`
did not, so `swiftString == nsString` raised `doesNotRecognizeSelector:`. The
base class now answers YES (patch 0007, next to the tagged-string probe it
already carries).

**The overlay now bridges by view.** `String`, `Array`, `Dictionary` and `Set`
call `_bridgeToObjectiveCImpl()` (which is what Darwin's overlay does), and
`Array`'s and the collections' inverse bridges adopt native storage through
`_bridgeFromObjectiveCAdoptingNativeStorageOf()` before falling back to an
element-wise copy. Measured on the installed toolchain: `"héllo 🌍" as NSString`
is a `__StringStorage` (length, `-substringFromIndex:`, `-characterAtIndex:`,
`-isEqual:`, `-rangeOfString:` all work), `[Int]` is a
`__SwiftDeferredNSArray` (`-objectAtIndex:`, `-subarrayWithRange:`, and the
round trip through `as? [Int]`), `[NSObject]` is the
`_ContiguousArrayStorage<NSObject>` itself, and `Dictionary`/`Set` are
`_SwiftDeferredNSDictionary`/`_SwiftDeferredNSSet` - all registered GNUstep
class objects. Reproduce with the language gate's new "zero-copy bridges"
section; the S4 gate gained the fixed-class-with-generic-superclass regression.

One consequence worth recording: `-[NSSet allObjects]`, `-[NSSet member:]` and
the other Agora methods that walk a Swift collection now genuinely run on it,
so this is also the first time the class-cluster primitives are exercised from
the other direction. They are correct because they were written over the
primitives rather than the ivars; the zero-copy bridge is what proves it.

### 2.22 Finishing the surface: typed parameters, value types, annotations

This round took the four items that were left over from §5, and the work split
into one compiler change, one stdlib change, one overlay change and two Agora
bug fixes.

**The `NSUInteger` *parameter* selectors.** §2.21 fixed `count`; the same
(name, encoding) mismatch existed on every collection method that takes a
count in a scalar parameter: `-getObjects:andKeys:count:`,
`-initWithObjects:count:` and
`-countByEnumeratingWithState:objects:count:` (whose return value is an
`NSUInteger` too). The shadow protocols and the concrete storage classes now
use `UInt` for those parameters and the enumeration result, so a
Clang-compiled fast-enumeration loop or a `-getObjects:andKeys:count:` walk
reaches the Swift implementation instead of the inherited Foundation one. The
call sites inside the `__Cocoa*` wrappers convert at their edge.
(`-getObjects:range:` has no scalar count - its arguments are a pointer and
the `NSRange` struct - so its encoding did not change.)

**Typed initializer records (the S5 residual).** `getObjCEncodingForTypes()`
returned a null encoding when a method's *result* type had no Clang type. That
is exactly a generic class's initializer (`Self`/`Box<T>`), so the thunk kept
an untyped selector record and a typed `init` send missed it. An Objective-C
method can only return an object as `id`, so a class-instance result that has
no Clang type is now encoded as `@`. Measured on `class Box<T>: NSObject`: the
method list carries `init @16@0:8` instead of `init` with a null encoding.

**The value types' long tails.** The overlay's hand-written Cocoa surface now
carries what Darwin's has beyond the first draft:

| Type | Added |
|---|---|
| `Data` | `RandomAccessCollection` + `MutableCollection` (indexes, `first`/`last`, slicing), `init(UnsafeRawBufferPointer)`, `init(bytes:count:)`, `subdata(in:)`, `range(of:options:in:)`, `replaceSubrange`, `insert`, `remove`, `removeSubrange`, `removeAll` |
| `IndexSet` | `SetAlgebra` (`union`, `intersection`, `symmetricDifference`, `subtracting`, `form*`, `insert`, `remove`, `update`), `init<S: Sequence>`, `count(in:)`, `contains(integersIn:)`, `remove(integersIn:)` |
| `CharacterSet` | `SetAlgebra` over `Unicode.Scalar` (the same set operations), the remaining standard sets (`alphanumerics`, `punctuationCharacters`, `controlCharacters`, `lowercaseLetters`, `uppercaseLetters`, `symbols`, `illegalCharacters`, `capitalizedLetters`, `nonBaseCharacters`, `decomposables`, the six `url*Allowed` sets) |
| `Decimal` | `+`, `-`, `*`, `/`, the compound assignments, unary `-`, `zero`/`one`/`nan`, `isZero`, `sign`, `magnitude`, `ExpressibleByIntegerLiteral`/`FloatLiteral` |
| `Calendar` | `startOfDay(for:)`, `date(byAdding:value:to:)`, `date(byAdding:to:)`, `dateComponents(_:from:to:)`, `dateComponents(in:from:)`, `component(_:from:)`, `range(of:in:for:)`, `range(of:start:interval:for:)`, `dateInterval(of:for:)`, `compare(_:to:toGranularity:)`, `isDate(_:equalTo:toGranularity:)`, `isDate(_:inSameDayAs:)`, `isDateInToday/Yesterday/Tomorrow/Weekend` |
| `Date`/formatting | `TimeInterval`, `typealias DateFormatter = NSDateFormatter`, `Date.formatted(date:time:)`, `Date.ISO8601Format()` |

**The header annotations.** `NS_TYPED_ENUM`/`NS_TYPED_EXTENSIBLE_ENUM` were
defined as *bare names*; they now expand to Clang's `swift_wrapper(struct)`
(the attribute Darwin's SDK uses), and `NS_SWIFT_NAME`,
`NS_REFINED_FOR_SWIFT` and `NS_SWIFT_SENDABLE` are defined for the first time
(`swift_name`, `swift_private`, `swift_attr("@Sendable")`). Used where the
effect is observable and the change is safe:

- `NSNotificationName` is `NS_TYPED_EXTENSIBLE_ENUM`: Swift sees the struct
  wrapper with `rawValue` and the importer's automatic `_ObjectiveCBridgeable`
  (the overlay's hand-written `Notification.Name` struct is now a typealias);
- `-[NSIndexSet countOfIndexesInRange:]` carries `NS_SWIFT_NAME(count(in:))`;
- `-[NSString getCharacters:range:]` carries `NS_REFINED_FOR_SWIFT`, so it is
  `__getCharacters(_:range:)` in Swift (the overlay's string bridge calls the
  refined name);
- `NSNull` and `NSUUID` are `NS_SWIFT_SENDABLE`.

**Two Agora bugs the gate found.**

1. `-[NSCalendar setTimeZone:]` stored the zone without retaining it. The
   overlay's `calendar.timeZone = TimeZone(identifier: "UTC")` passes a
   temporary, so the next `-startOfDayForDate:` read freed memory. The setter
   retains now (the class has no `-dealloc`, so the calendar keeps the zones it
   was given).
2. The overlay's `IndexSet` iterator started at `-1`, but
   `-indexGreaterThanIndex:` takes an `NSUInteger`: the sentinel arrives as its
   unsigned bit pattern, no index is greater, and iteration yielded nothing.
   It starts at `first` now. (The `Set(indexSet)` path in the new gate is what
   caught it; nothing had iterated an `IndexSet` before.)

**The prespecialized-generic boundary, re-measured.** §2.10 said a
prespecialized generic class with an ObjC ancestor keeps a null `isa` and
would trap in `objc_allocWithZone`. The case is still unreachable: a user
module built with `-Xfrontend -prespecialize-generic-metadata`, declaring
`public class Box<T>: NSObject` and instantiating `Box<Int>`, emits **no**
`_OBJC_METACLASS_` symbol and no prespecialized class metadata - `makeInt()`
compiles to `__swift_instantiateConcreteTypeFromMangledName` plus
`objc_allocWithZone`, i.e. the S4b runtime path - and the resulting
`Box<Int>` is a registered class object named `_TtGC1P3BoxSi_` that answers
`isKind(of:)` and lives in an `NSMutableArray`. Closing the compiler case
(when a stdlib-like module first needs it) means having
`SpecializedGenericClassMetadataBuilder` emit a GNUstep metaclass and a
per-specialization name and putting the metadata in `__objc_classes`; the
handoff records it rather than implementing an unreachable path.

**Cast semantics are checks, not conversions.** Asking "is the bridge at parity?"
with the overlay open showed that the *coverage* was there but two casts were
wrong, and both are silent-data bugs rather than performance deltas:

- the collection bridges were implemented as `_unconditionallyBridgeFromObjectiveC`
  and both the conditional and the force entry points called it, so
  `[1, "x"] as NSArray as? [Int]` returned `[1]` (the string was dropped) and
  `as!` did not trap. Darwin's conditional bridge checks every element and
  returns nil; the force bridge traps. The overlay now does the same for
  `Array`, `Dictionary` and `Set` (keys and values), and its `AnyHashable` key
  helper no longer invents `AnyHashable(0)` for an unbridgeable key - it fails
  the cast.
- the numeric bridges used `integerValue()`/`charValue()`/`boolValue()`
  unconditionally, so `NSNumber(value: 1.5) as? Int` was `1`,
  `NSNumber(integer: 300) as? Int8` was `44`, `NSNumber(integer: -1) as? UInt`
  was `UInt.max`, and `NSNumber(integer: 2) as? Bool` was `true`. The
  reference implementation (swift-corelibs-foundation's `NSNumber.swift`, the
  same semantics as Darwin's overlay) makes `as?` an *exact* check: every
  integer type uses the NSNumber's own encoding plus a range check, `Float`/
  `Double` use `exactly:`, and `Bool` accepts only 0/1. Ours now does the same.
  (Agora's `-isEqualToNumber:` compares across the signed/unsigned line in the
  unsigned domain - `-1` equals `UINT64_MAX` - which is right for `NSNumber`
  equality and wrong for a bridge, so the exact check uses the encoding and
  range, not `-isEqual:`.)

Measured before/after on the installed toolchain:
`([1, "x"] as NSArray) as? [Int]` was `[1]`, now `nil`;
`NSNumber(double: 1.5) as? Int` was `1`, now `nil`;
`NSNumber(integer: 300) as? Int8` was `44`, now `nil`;
`NSNumber(integer: -1) as? UInt` was `UInt.max`, now `nil`;
`NSNumber(integer: 2) as? Bool` was `true`, now `nil`. The gate's bridging
section now pins all five, plus the successful directions (a good cast still
returns the array; `NSNumber(integer: 1) as? Bool` is true; `UInt64.max` still
bridges to `UInt`).

Verified by the language gate's new "value types and header annotations"
section (the table above, the four annotations, and `Sendable`), the existing
bridging/zero-copy sections (now including the cast-semantics checks), and the
whole gate suite plus both probes against the installed toolchain.

### 2.23 The imported superclass's size is part of the static layout

The last ABI defect between this toolchain and a real Swift GUI program. IRGen
laid a Swift class's own fields out from the isa word (offset 8), which is what
Darwin can do because objc4 *slides* `instance_size` and the ivar offsets when it
realizes the class — that is why `ClassLayout.h` says "the Objective-C runtime
will slide offsets based on the actual superclass size". libobjc2 has no such
step: the GNUstep class object's `instance_size` is what libobjc2 allocates
from, and its ivar offsets are what it reports.

What that looked like measured:

```
NSView:       instanceSize=496, 54 ivars, _frame at offset 32
CounterView:  instanceSize=16,  ticks at offset 8        (Darwin: 504, 496)
NSViewController   subclass: 16  (superclass 72)
NSWindowController subclass: 16  (superclass 82)
```

So the Swift field aliased the superclass's first ivar, and the instance was
allocated smaller than the superclass writes to: asking `NSView` for its frame
aborted in `malloc`/`free`, and a weakly-referenced instance died at teardown.
`conformance/appkit/SubclassLayout.swift` reproduced it in fifteen lines.

The fix is in `ClassLayoutBuilder`. When the walk up the superclass chain reaches
a class that came from Clang, its `getASTObjCInterfaceLayout()` size is added as
padding and the Swift fields are laid out after it — the same computation clang's
own GNUstep backend makes for `instance_size` (`CGObjCGNU`:

```cpp
int superInstanceSize = !SuperClassDecl ? 0 :
  Context.getASTObjCInterfaceLayout(SuperClassDecl).getSize().getQuantity();
```

). It is gated on `usesGNUstepClassABI() && superclass`, so the Darwin path is
untouched, and it needs no runtime change and no rebuild of the Objective-C
stack: only Swift code compiled with the fixed compiler carries the new offsets.

Verified: `NSView` + one stored property is 504 bytes with the field at 496;
`NSViewController` 72 → 80; `NSWindowController` 82 → 96; every S1–S6 and
library-evolution gate passes unchanged; the conformance layout checks pass; the
layout crash probe exits 0; and a Swift `NSView` subclass now draws — the pixels
it fills reach the headless compositor
(`conformance/scripts/run-appkit.sh`).

**Not covered:** a superclass whose ivars are synthesized in its
`@implementation` and never appear in the header. A Swift module importer sees
only the header, so that class looks eight bytes wide and the old layout is used.
204 of Agora's 288 Foundation/AppKit headers declare their ivars in the
`@interface` — every AppKit class a program subclasses (`NSView`, `NSWindow`,
`NSResponder`, `NSApplication`, `NSControl`, `NSTextView`, `NSViewController`,
`NSWindowController`, `NSCell`) among them — so Agora's own stack is covered.
Closing it for third-party classes needs an `instanceStart` and the objc4-style
slide in libobjc2; the conformance suite measures it as a `[gap]` so it cannot be
forgotten.

### 2.24 The class object publishes its `@objc` protocol conformances

`class_copyProtocolList` returned `NULL` and `class_conformsToProtocol` answered
`0` for a Swift class conforming to an imported `@objc` protocol, although the
required method was implemented and the optional one correctly absent: the
GNUstep class object's `protocols` field was emitted as a null pointer.

The list has to be GNUstep's shape — `struct objc_protocol_list { next, count,
list[] }` — not Apple's `protocol_list_t { count, refs[] }`, so Apple's
`buildProtocolList` cannot be reused. `ClassDataBuilder::buildGNUstepProtocolList`
builds it from the class's explicit conformances, `GNUstepClassData::Protocols`
carries it, and `addGNUstepProtocols()` (reachable through
`ClassMetadataVisitor::addClassGNUstepHeader`) puts it in the class object.

The entry for an imported protocol must be **clang's** record: `._OBJC_PROTOCOL_X`
in the defining image's `__objc_protocols` section, which is the object libobjc2
registered. Swift used to emit its own `protocol_t` into the Apple
`objc_protolist`/`objc_protorefs` sections (different shape, never registered),
and conformance is a pointer compare, so a copy can never match.
`emitLazyObjCProtocolDefinition` now routes an imported protocol through
`emitClangProtocolObject` — a helper that existed but had no caller — and that
helper no longer applies Apple's `updateProtocolRefs` rewrite to a GNUstep
record. The referenced symbols go into the TBD (`TBDGenVisitor`), which the
debug-build validation requires for an external record.

The runtime needed one fix too, and the toolchain self-check found it: a class
list can name a protocol defined in *another image* (a Swift class in
`libswiftCore` listing a Foundation protocol), so at class-load time the record
still carries its `protocol_version_gsv2` marker (`isa = 4`) and
`init_protocols()` hit `default: abort()` — the case was compiled only under
`OLDABI_COMPAT`. It is now handled unconditionally: initialise the record in
place and let `unique_protocol()` merge it with the canonical one.

Verified: five protocol checks green in `swift-interop-probe/conformance/`
(`class_copyProtocolList -> 1`, `class_conformsToProtocol == 1`, required method
reachable, optional absent, `objc_getProtocol` finds the protocol); 42/46 →
44/46; every S1–S6 and library-evolution gate unchanged; both interop probes and
the toolchain self-check green.

**Not covered:** a protocol declared in Swift is still emitted as Apple's
`protocol_t` and is not registered, so it is filtered out of the GNUstep list
(`hasClangNode()`) instead of being handed to libobjc2 in a shape it would
misread. Every Cocoa protocol is imported, so the AppKit/Foundation case is
covered; a GNUstep protocol emitter for Swift-declared protocols is the
remaining piece.

### 2.25 `BOOL` is Apple's: the encoding that typed dispatch keys on

GNUstep's `BOOL` is `unsigned char` (encoding `C`); Apple's is `signed char` on
x86_64 and `bool` on arm64 (`c` and `B`). libobjc2 keys typed dispatch on
(selector, encoding) and a class's dispatch table starts as its superclass's, so
a clang-built caller of `-sharedFlag` typed `C16@0:8` missed a Swift override
registered as `c16@0:8` and the **superclass's** implementation answered — wrong
result, no diagnostic, for every `BOOL`-returning method in Cocoa.

`objc/runtime.h` now defines `BOOL` as Apple does, per architecture, under
`STRICT_APPLE_COMPATIBILITY` (default ON in `CMakeLists.txt`); the option's
"always signed char" spelling was wrong for arm64. `objc/objc-config.h.in` uses
`#cmakedefine VAR 1` — the `@VAR@` form wrote `ON`, which both collided with the
`add_compile_definitions` copy and is not a valid preprocessor value — and the
duplicate definition is gone.

The encoding is baked into every library already compiled, so the whole stack
must be rebuilt; a *partially* rebuilt stack reproduces the symptom from the
other direction. Measured: rebuilding only `libagora-base` left
`libagora-core`'s `__NSCFURL` override at `C16@0:8`, the typed send fell through
to `-[NSURL isFileURL]`, which read an uninitialised ivar (`_isFile = 11`), and
three `bridges` cases failed until every component was rebuilt together.

Verified: the encoding matrix is 31/31 (was 30/31), the conformance suite 46/46
(was 44/46), and every component's ctest suite passes.

### 2.26 An opaque superclass is laid out at load time

The last layout gap.  A Swift subclass of an Objective-C class whose ivars exist
only in its `@implementation` — declared as `@property`, synthesized, no ivar
block in the `@interface` — cannot know the superclass's size at compile time,
so the class was laid out from offset 8 and its fields aliased the superclass's
storage (`OpaqueHost` is 24 bytes; the Swift subclass was 9 with its field at
offset 8, so writing the Swift property turned the superclass's `counter` from 7
into 1 and eventually corrupted the heap).

IRGen now detects the case — an imported superclass with no ivars in its
`@interface`, since the importer can never see the `@implementation` — and sets
`ClassMetadataFlags::ClassHasOpaqueObjCSuperclass`. `addGNUstepInstanceSize()`
then emits `instance_size` 0, which is libobjc2's existing **late-bound**
encoding: `objc_compute_ivar_offsets()` reads a size `<= 0` as "compute this
class's layout", starts at the runtime superclass's size, walks the ivar list,
and writes the absolute offsets back through the ivar-offset globals (the same
path clang's non-fragile emission uses, and the reason the globals exist even for
statically laid-out classes).

One thing libobjc2 could not fix alone: a Swift class object carries the size
twice — the GNUstep `instance_size` it allocates from, and Swift's own
`InstanceSize`, which the first one hides. libobjc2 now calls a weak
`swift_objcClassLayoutDidChange(Class)` after computing the offsets, and the
Swift runtime mirrors the GNUstep word into Swift's word. That matters for
`MemoryLayout`/reflection and, more importantly, for a Swift class *below* this
one: `initClassFieldOffsetVector` starts from `super->getInstanceSize()`.

Verified: `OpaqueHost` 24 bytes, the Swift subclass 25 with its field at 24,
`-counter` intact after writing the Swift property; the suite is **51/51**; all
S1–S6 and library-evolution gates pass (a direct `NSObject` subclass is
late-bound too now, and the S1 gate still measures its ivar at offset 8).

### 2.27 Protocols declared in Swift are emitted in GNUstep's shape

A Swift `@objc protocol` was emitted as Apple's `protocol_t` into the Apple
`objc_protolist`/`objc_protorefs` sections, which libobjc2 does not read: so
`objc_getProtocol()` never found one, and a class's GNUstep protocol list had to
filter them out rather than hand the runtime a record it would misread.

`ClassDataBuilder::emitGNUstepProtocol()` now emits GNUstep's own record into
`__objc_protocols`, where the loader registers it:

```
struct objc_protocol {
  id isa;                    // protocol_version_gsv2 (4) until load
  char *name;
  struct objc_protocol_list *protocol_list;
  struct objc_protocol_method_description_list *instance_methods;
  ... required/optional, class/instance ...
  struct objc_property_list *properties;  // x4 (null: Swift's protocol
                                          // properties have no GNUstep emission yet)
};
```

Method descriptions are `{ SEL record, type encoding }` — the same selector
records a method list uses, so `-conformsToSelector:`-style lookups compare
correctly. The symbol is clang's `._OBJC_PROTOCOL_<name>` with **weak** linkage,
so a module that declares the protocol and one that only references it share a
single object, exactly as two clang translation units do. The class's protocol
list no longer filters: both kinds point at a record libobjc2 registered, so a
pointer-compare conformance check succeeds.

Verified: `objc_getProtocol("SwiftConformanceSide")` finds it,
`class_conformsToProtocol` and `class_copyProtocolList` see it, the suite is
**51/51**, and a plain `@objc protocol` (without the explicit name) works too —
its Objective-C name is just the mangled `_TtP...`.

Found on the way, and unrelated: this runtime cannot answer a message sent to a
`Protocol` object (`NSLog(@"%@", @protocol(P))` aborts in
`create_dtable_for_class`). The harness walks the list through a C helper for
that reason; the defect predates this work and is recorded in
[`swift-interop-probe/conformance/FINDINGS.md`](swift-interop-probe/conformance/FINDINGS.md) §5.

### 2.28 Messaging a `Protocol` object, and two surface gaps

A `Protocol` object could not be messaged: `NSLog(@"%@", proto)` aborted. Three
separate defects:

1. **The dispatch table.** `create_dtable_for_class(Protocol)` found its
   superclass's table uninstalled and aborted. `Protocol` roots at the legacy
   `Object` class, which nothing messages, so nothing ever built it.
   `dtable.c` now builds a superclass's table on demand (the runtime lock is
   recursive; the walk ends at a root) and treats `super == class` as a root,
   which is what a metaclass whose parent was never resolved looks like.
2. **The methods.** The runtime's `Protocol` class is a C data structure with an
   isa and no methods, so `-name`, `-description`, `-hash` and `-isEqual:` all
   missed — and a miss on an object with no NSObject ancestry re-entered
   Foundation's forwarding hook forever. Foundation now supplies them as a
   category (`FNProtocolMethods.m`), because `-name`/`-description` answer an
   `NSString` and libobjc2 must not depend on Foundation; the interface is in
   `Foundation/NSObjCRuntime.h`. Darwin's contract: `name` is an `NSString`,
   `description` is the name, equal protocols hash equally.
3. **The forwarding hook.** `fn_proxy_lookup` asked the receiver
   `-respondsToSelector:` to decide whether to forward, and `fn_forward_handler`
   asked `-methodSignatureForSelector:`; both are messages, so both re-entered.
   Both now use `class_respondsToSelector` on the receiver's class, and the
   handler reports "does not respond" rather than recursing.

Verified: `-name`, `-description`, `-hash`, `-isEqual:` from Objective-C and from
Swift, and `[Protocol]` arrays in Swift; the conformance suite is 55/55.

Two surface gaps closed with it:

- **`CGFloat` imports.** The importer maps the C typedef to a Swift type of that
  name looked up in the imported module (then `CoreFoundation`); the Foundation
  overlay declared none, so the type was dropped and `let w: CGFloat` was
  "cannot find type". The overlay now declares `public typealias CGFloat =
  Double`.
- **`NSWindow`'s accessors are properties.** `title`, `contentView`, `delegate`,
  `minSize`, `maxSize`, `contentMinSize`, `contentMaxSize`, `frame`, `styleMask`,
  `windowNumber`, `visible`/`keyWindow`/`mainWindow` are `@property`
  declarations with the ownership the implementations already have (`copy` for
  the title, `assign` for the delegate, `strong` for the content view; the ones
  with no setter are `readonly` — this tree has `-setFrame:display:` and no
  `-setFrame:`). The AppKit demo is written `window.title = …` and still draws.

`libagora-core`'s CF-bridged class tables also carried hand-written `C` type
encodings for `BOOL`-returning methods; under the `BOOL` fix they no longer
matched the compiler's selectors, and `-[__NSCFURL isFileURL]` fell through to
the base class. They now carry the compiler's exact encodings.

### 2.29 Foundation parity: the measurement, and the one-sided tool

The next piece of work has its own plan
([`SWIFT-FOUNDATION-PARITY-PLAN.md`](SWIFT-FOUNDATION-PARITY-PLAN.md)); this round
took its P0, the measurement, because a gap you cannot count is a gap you cannot
close.

**The tool was the blocker.** `swift-symbolgraph-extract` is `swift-frontend`
invoked directly, so it builds its compiler invocation by hand instead of going
through the driver. It hard-coded

```cpp
Invocation.getLangOptions().EnableObjCInterop = Target.isOSDarwin();
```

The frontend's own default is the same expression (`CompilerInvocation.cpp`), and
the *driver* is what turns interop on for Linux; a direct tool invocation never
sees that. An imported Clang module was therefore built in **C mode**, so
`CoreFoundation/CFBridgingTypes.h` — which declares `NSInteger`, `NSUInteger` and
`NSRange` under `#if defined(__OBJC__)` — declared nothing, and every Foundation
header that names them failed to import:

```
Foundation/NSObjCRuntime.h:83:9: error: unknown type name 'NSUInteger'
```

Passing `-Xcc -x objective-c` does not help (`-x` from `-Xcc` lands after the
importer's own input files, and the importer appends its own `-x` anyway). The
fix is in the fork (`lib/DriverTool/swift_symbolgraph_extract_main.cpp`, in patch
`0003`): apply the driver's platform rule (`isOSDarwin() || isOSLinux()`) and
select the GNUstep runtime vendor for a non-Darwin ELF target, so the importer
also gets `-fobjc-runtime=gnustep-2.0` instead of `ios-7.0`. A frontend-only
rebuild (`ninja swift-frontend`, ~26 s) and a copy into the install is enough.

**The harness.** `swift-toolchain/scripts/verify-foundation-parity.sh` extracts
the reference graphs (`Foundation`, `FoundationEssentials`,
`FoundationInternationalization` — `import Foundation` is one surface over three
modules, and without the last two the value types' `Codable` conformances and the
whole of T3 are invisible) and Agora's graph, then
`foundation-parity-diff.py` compares `(dotted path, kind)` sets and `conformsTo`
edges. Two details that make it trustworthy:

- a conformance target outside the graph is named via `targetFallback`, so
  `Data -> Codable` is measurable even though `Codable` lives in the stdlib;
- compiler-synthesized conformances (`Sendable`, `Copyable`, `Escapable`, …) and
  conformances on **typealiases** are excluded: the first are the compiler's, not
  the declaration's, and the second (`CGFloat` here *is* `Double`) would measure
  the alias rather than a missing declaration.

**The baseline** (2026-10-22, installed toolchain, before the P1 slices below):

```
reference symbols 10,455      our symbols 11,314
missing           8,259 distinct (8,704 declarations, 301 containers)
conformance gaps  320 edges over 71 types
```

Eight thousand sounds worse than the earlier "surface is finished" (§2.22) — it is
the same tree, measured against a bigger reference: 5,471 of those come from the
`FoundationEssentials`/`Internationalization` graphs that the hand-written overlay
does not implement at all (`AttributedString` 933, `PredicateExpressions` 402,
`Locale` 647, …). The plan's T3 was exactly that, and the gate now counts it. The
allowlist (`swift-toolchain/parity/foundation-allowlist.txt`, 372 prefix entries
with a stage reason and a count) makes the gap a ratchet: `--check` fails on an
unallowlisted symbol, on a grown count, **and** on a count that is now too small,
so a landing has to shrink the list. End-to-end cost: ~10 s.

One measured correction to the plan's earlier estimate: the "caps on T2" (missing
Objective-C subsystems: `NSPredicate`, `NSMeasurement`, `NSProgress`,
`NSByteCountFormatter`, `URLSession`) total ≈ 270 symbols — the gap is
overwhelmingly Swift-native Foundation, not Objective-C Foundation.

**P1 is under way, and the gate has now moved twice.** The first slice was
`Bundle`, to prove the mechanism: a class-level `NS_SWIFT_NAME` on the
`@interface` is honoured by the importer (verified first with a throwaway module),
so the rename layer is header annotations, not Swift aliases — and because the
annotation moves the symbol graph, the diff measures it. The second slice was the
other 27 class names (all of §3.1's list), which closed 246 symbols and left
`Host` with nothing missing at all; the third was the `NSObject` shape and
conformance pass:

- `NSObject.h` declared `description` and `debugDescription` twice — as protocol
  properties and as class methods — and the class's method declaration wins the
  import, so Swift saw `func description() -> String`, which cannot satisfy
  `CustomStringConvertible`. They are properties on the class now, and so is
  `hash` (the overlay's `Hashable` conformance used to call `hash()`).
- With the shape right, `extension NSObject: CustomStringConvertible,
  CustomDebugStringConvertible {}` (in the overlay, no body) closed **156**
  conformance edges at once, because the symbol graph records inherited
  conformances on every subclass.

The measurement after three slices: **8,010 missing symbols, 224 missing
conformance edges, 360 allowlist entries** — from 8,259 / 322 / 372 at the
baseline. (A fourth slice follows.) Two gate behaviours were learned on the way and are now part of the
tooling:

- a rename *exposes* gaps: a type's conformances are unmeasurable until it exists
  under its Swift name, so `--update-allowlist` now appends an entry for a gap
  nothing accepts (the old one would have left the gate failing, which is correct
  but unusable);
- a landing *closes* entries: `--update-allowlist` drops a count that reaches zero
  and `--check` reports a zero-count entry as empty, so the file shrinks instead
  of accumulating dead lines.

The call-site cost of the shape pass was one line each in the overlay
(`description()` → `description`, three places) and one in
`verify-swift-port.sh`.

**The irregulars, and a prerequisite the enum half was hiding.** The fourth
slice took the four names that are not a mechanical `NS`-strip — `NSTask` →
`Process`, `NSFileManager` → `FileManager`, `NSNotificationCenter` →
`NotificationCenter`, `NSProcessInfo` → `ProcessInfo` — and the struct
`NSOperatingSystemVersion` → `OperatingSystemVersion` (its struct fields import as
properties, so 6 of 8 symbols closed). Total after four slices: **7,958 missing
symbols, 228 conformance edges, 361 allowlist entries**.

Renaming the enum *types* (`NSAlignmentOptions` → `AlignmentOptions`,
`NSQualityOfService` → `QualityOfService`) moves the type and nothing else: the
constants stay globals. They become members only when the importer is told the
enum is extensible/an option set, and that is what `NS_ENUM`/`NS_OPTIONS` mean on
Darwin —

```c
enum __attribute__((enum_extensibility(open))) _name : _type          /* NS_ENUM  */
enum __attribute__((flag_enum, enum_extensibility(open))) _name : _type  /* NS_OPTIONS */
```

— while this tree's macros emit only the fixed-underlying-type enum. Measured
with a throwaway module: `typedef NS_OPTIONS(NSUInteger, NSFooOptions) {
NSFooMinXInward = … }` imports as a plain struct with no `.minXInward`. So the
enum pass starts with the macros, not with the headers; that is recorded in
§3.1 of the plan.

**The enum slice.** The macros now carry the attributes, and the four option sets
are real option sets: `NSAlignmentOptions` (47 -> 1), `NSSortOptions` (27 -> 1),
`NSEnumerationOptions` (22 -> 1), `NSBinarySearchingOptions` (23 -> 1) and
`NSQualityOfService` (10 -> 0), with three `OptionSet`/`SetAlgebra` conformance
edges. Two rules decided where the annotations go, and both took a measurement to
learn:

- **constants strip against the enum name**, so the tag must start with the
  constants' common prefix: `NSAlignmentOptions` plus `NSAlign...` strips to
  `alignMinXInward`, while a tag named `AlignmentOptions` strips nothing. The
  rename therefore goes on the tag as
  `__attribute__((swift_name("AlignmentOptions")))` and the ObjC tag stays --
  which is why `NSGeometry.h` spells the declaration out instead of calling
  `NS_OPTIONS`.
- **`NS_SWIFT_NAME` and the enum macros had to move above their first use** in
  `NSObjCRuntime.h`; the file had the macro surface below the enums that wanted
  it, which is the same ordering mistake as the symbol-graph tool's hard-coded
  default.

The last symbol under each option set is `rawValue` as a *property*: the imported
Clang option set has it, but `swift-symbolgraph-extract` does not emit the stored
property, so it is allowlisted as a measurement gap rather than papered over.

A Swift program now writes `NSSortOptions.concurrent`, `NSEnumerationOptions.reverse`,
`AlignmentOptions.alignMinXInward`, `NSBinarySearchingOptions.firstEqual` and
`QualityOfService.background`, and `SetAlgebra` containment works -- checked by
compiling and running one.

**The shape pass.** The diff's "same path, other shape" counter went 19 -> 3, and
each fix was a declaration whose *form* was wrong rather than missing:

- `NSDate`'s `+timeIntervalSinceReferenceDate` was a class method; Darwin has a
  class property, and the reference's `NSDate.timeIntervalSinceReferenceDate` is
  a type property. Same for the overlay's `Date` (which now has both the instance
  and the static, as Darwin does).
- `Calendar.Component` was a struct of static values in the overlay; it is an enum
  with cases now, so `.day` is an enum case and a `[Component]` is an honest
  collection. Nine cases.
- `NSExceptionName` and `NSTextCheckingKey` gained `NS_TYPED_ENUM`: they are
  `NSString *` typedefs Darwin wraps in a struct, and without `swift_wrapper` the
  importer handed back a bare typealias.
- `NSRectEdge` was a second enum renamed to `CGRectEdge`, which collided with Core
  Graphics' own `CGRectEdge` (two Swift types of that name). Darwin's arrangement
  is that `NSRectEdge` is a deprecated *alias* of `CGRectEdge`, so it is one now,
  with the pre-10.6 spellings kept as macros naming Core Graphics' cases
  (`case NSMinXEdge:` still compiles in ObjC). `CGRectEdge` itself became an
  attributed enum in `libagora-drawing`, so its four constants import as cases
  (`CGRectEdge.minXEdge`).

The three remaining shape gaps are recorded deviations rather than tasks: `CGFloat`
and `DateFormatter` are typealiases here, and `NSRectEdge` is an alias whose
reference (corelibs) declares a separate enum -- the source is the tie-breaker and
the allowlist says so.

**The conformance slice, and a use-after-free it found.** The overlay's value types
are now `CustomStringConvertible`/`CustomDebugStringConvertible`, `NSDate`,
`NSDateInterval`, `NSIndexPath`, `NSNumber`, `NSString`, `DateInterval` and `UUID`
are `Comparable`, the C structs (`CGPoint`, `CGSize`, `CGRect`,
`OperatingSystemVersion`) and `Notification` are `Equatable`/`Hashable`, and
`NSComparisonResult` is a real `NS_ENUM` named `ComparisonResult` for Swift.
Conformance edges: 222 -> 179. What remains is a list of *implementations*, not
declarations: archiving (44 edges, the classes have no coder methods at all),
`CustomReflectable` (21, `customMirror` unwritten), `Codable` and the collection
conformances (P3), `ReferenceConvertible` (T3), `NSMutableCopying` (8).

The slice also produced the round's best bug. With `extension NSDate: Comparable`
in place, the language gate's value-types program started to segfault in
`objc_msgSend_fpret`, dispatching `-UTF8String` from `-[NSDateFormatter
fnRebuild]`; removing the conformance made it disappear, and a plain method
category on `NSDate` did *not* reproduce it. It was not the conformance at all:
`libagora-base` is **manual reference counting**, and `NSDateFormatter`'s setters
assigned their arguments without retaining them, `-copy` shared them without
retaining, and `-dealloc` never released them. One more record in the binary
changed the heap layout and turned the latent dangling `_pattern` into a crash,
which is why it surfaced only under the conformance. The setters retain and
release now, `-copy` retains what it shares, and `-dealloc` releases all six
settings.

The rule is the one the `NSCalendar` time zone fix (§2.22) already stated, in a
sharper form: **in this tier a setter that assigns an object ivar must retain
it**, and the Swift overlay is exactly the client that exposes the setters which
do not. Auditing the rest of `libagora-base` for the same pattern is open work
(the setters that take objects are few, and grep finds them).

**The P2 spike, first half.** The Foundation-overlay plan's strategy phase asks
whether swift-foundation can be built against Agora instead of re-implemented.
It can: `FoundationEssentials` and `FoundationInternationalization` **compile,
link and run unmodified** — no source patch, and no CoreFoundation shim at all —
against Agora's CoreFoundation and ICU 76. A Swift client prints correct results
for `Data`, `Date`, `Decimal`, `UUID`, `URL`/`URLComponents`, a `Codable` JSON
round trip, `IndexPath`, `Calendar`, `Locale`, `TimeZone`, `Date.FormatStyle`
and `FloatingPointFormatStyle`. The build is CMake (no SwiftPM in this install),
offline, and needs one new module map — `CoreFoundation.modulemap` — whose
`link "agora-core"` is what makes the autolink resolve to Agora's library.

The predicted CF SPI list dissolved on contact: the 18 textual misses are
Darwin-only or not symbols, and the produced library has zero unresolved `CF`
symbols. The remaining half is the upstream test suite, which needs swift-testing
built for this toolchain; that is what separates a full **GO** from a partial one.
Full record: [`SWIFT-FOUNDATION-P2-SPIKE.md`](SWIFT-FOUNDATION-P2-SPIKE.md).

The suite half found the next boundary rather than a failure in Agora: swift-testing
needs swift-syntax **for the target** (the compiler's copy is a host build, and
compiling a macro against it makes the SIL verifier reject the inlined
`Array`/`TriviaPiece` code — building it with this toolchain works and is now
scripted), `TestingMacros` then builds, and `Testing` itself stops on the *overlay's*
T3 gaps (`Data` is not `Codable`, `URL(fileURLWithPath:isDirectory:)` is absent)
because on this target `Foundation` is still the overlay. So the suite needs P3's
first deliverable — a `Foundation` that re-exports FoundationEssentials — before it
can run; the ordering is a finding, not a setback. Two toolchain bugs came out of
the attempt and are recorded in the spike: a throwing ObjC initializer called from a
Swift `init` crashes while lowering the class-constructor thunk, and passing both the
Foundation and CoreFoundation module maps makes `CFBridgingTypes.h`'s `__OBJC__`
block disappear (module ownership, not a compiler bug).

P3's first deliverable exists: `swift-toolchain/spike/foundation-reexport/Foundation.swift`,
a `Foundation` that re-exports FoundationEssentials and FoundationInternationalization
(the first half of the P3 arrangement, no bridging yet). A client `import Foundation`
gets FE's `Data`/`Date`/`URL`/`JSON` and runs, and `Testing` compiles past the
overlay gaps that stopped it. It now stops one module later: `public import
ObjectiveC` (under `_runtime(_ObjC)`) needs `objc_getClass`, and Agora's
`ObjectiveC` is Swift-only. `_silgen_name` and `@_extern(c,)` were both tried and
rejected (reserved-symbol warning; `AnyClass?` is not C-representable), so the fix is
the Darwin shape: `ObjectiveC` becomes an overlay over a Clang module of
`objc/objc.h` + `objc/runtime.h`. That is the single remaining step before the
suite builds.

**P2 finished, with numbers.** `ObjectiveC` gained its runtime surface — not as a
Clang module (that works for compilation but *cannot pass module-interface
verification*, because the verifier re-parses the interface without the `-Xcc` flags
that locate the map), but as a C shim of `agora_`-prefixed wrappers linked into
`libObjectiveC.so`; `_silgen_name` may not name `objc_getClass` directly. With the
re-export `Foundation`, `Testing` builds (target library, **host** macros: the plugin
server runs on the host stdlib, so `TestingMacros` is built by the bootstrap
compiler against the toolchain's swift-syntax), and
`swift-toolchain/scripts/run-foundation-tests.sh` runs the upstream suites:
**251 tests pass** (Data 152, Date 12, Decimal 32, GregorianCalendar 20, String 35).
Three suites crash on one shared defect — `swift_arrayDestroy` sends `-release`
through `objc_msgSend_fpret` (typed dispatch, libobjc2) — which is the first P3
milestone, and the plan records **GO** for strategy B: sources unmodified, core
value types green, failures in the runtime rather than in missing Foundation API.

That defect has since been reduced to five lines and is not Foundation's at all:

```swift
final class Box<T> { var value: T; init(_ v: T) { value = v } }
var a: [Box<Int>] = []
for n in 0..<8 { a.append(Box(n)) }
a.removeAll()                       // SIGSEGV
```

A non-generic pure-Swift class releases correctly. The chain is `swift_arrayDestroy`
→ the element metadata's value witnesses → `objc_release` → `objc_msgSend_fpret` on a
class with no dispatch table: a generically-instantiated pure-Swift class is a
runtime **pattern** class, emitted at layout 2 with the Objective-C class witnesses,
while §2.21 deliberately makes such a pattern class **not a class object** (null isa).
Narrowed the next day: the discriminator is Objective-C ancestry — `Box<T>: NSObject`
releases correctly (it *is* a class object), the pure-Swift one does not — and the
compiled IR contains no `objc_release` at all, so the Objective-C destroy is arriving
from the element type's **value witnesses**, not from the call site. That puts the fix
in the compiler's class value-witness/metadata-kind decision for generic pattern
classes (Swift witnesses for a Swift class, or make the pattern a class object), with
`swift-toolchain/scripts/verify-generic-release.sh` as its gate — RED today, on
purpose.

Two hypotheses were then tested and both came back negative. (1) The runtime chooses
the class VWT from the generic pattern's `UsesSwiftRefcounting` flag; a guard now
gives *any* pattern without a metaclass Swift witnesses unconditionally
(`stdlib/public/runtime/Metadata.cpp`, in patch `0003`) — the gate stayed red, so that
is not the path this program takes, and the guard stands on its own as a correctness
measure rather than as the fix. (2) The compiled IR has no `objc_release`, so the
Objective-C destroy is chosen at run time from a witness table *or* a layout string.
The probes have since been run, and they move the target again. The generic pattern's
`ClassFlags` are **2** — `UsesSwiftRefcounting` *is* set, so the runtime already picks
Swift's class witnesses, and the flags branch was never the problem. The layout-string
destroy symbols are never reached either. The crashing call is `swift_arrayDestroy`
with a small count whose `self` metadata sits beside `Any`/`AnyObject`, i.e. the array
being destroyed is an **existential** one; its element destroy is `objc_release` by
design, and the element is an instance of a Swift class that is not a class object.
The next probe was to read that element's type descriptor, and it turned up the ABI
fact that frames the fix: `asFullMetadata()` reaches the value-witness table at **one
word before** the metadata pointer, and in the GNUstep layout a class object's first
word is `isa` — so a class's VWT lives in the word *before* the class object. A
statically emitted class gets that word from IRGen; a runtime-instantiated generic
class gets it from `swift_allocateGenericClassMetadata`, and that allocation is where
the two halves can disagree. The breakpoint readings that followed are not trustworthy,
though: they were taken against the installed `-O` libswiftCore, where breakpoints land
after the prologue and the argument registers have moved. Instead of a debug build, the runtime now carries an env-gated diagnostic
(`SWIFT_LAYOUT2_DIAG=1`, folded into patch `0003`): the pattern initialiser prints the
flags, the bounds and the VWT word it installs, and `swift_arrayDestroy` prints its
`self`, that `self`'s kind word, the witness table, the `destroy` symbol and its caller.
It settled two things at once. The class's own witnesses are correct (`flags=2`, a `Bo`
table), and the `self` that `_ContiguousArrayStorage.deinit` hands to
`swift_arrayDestroy` is **not the element class's metadata** — its first word is `0x303`,
which is a witness-table flags word, not a metadata kind. So the defect is in how the
generic array storage passes (or destroys) its element metadata at layout 2, not in the
class pattern or the VWT choice. The next probe prints that `self`'s first words and the
element metadata the storage holds; the fix follows from which pointer it is.

---

## 3. Change inventory

`swift-toolchain/patches/0003-swift-enable-objc-interop.patch`, 63 files,
~2620 insertions. The layout/registration table is from two rounds ago, the S1
emission from three, S4/S4b from before that, S5 and the flip from earlier, the
library-evolution `Update` strategy and GNUstep-shaped categories from two
rounds ago, the importer's bridge check (§2.19) from the last one, and this
round adds the class-object predicate and the collection-core encodings
(§2.21). S6 changed only the Agora-side scripts and docs. The libobjc2 side
is `0006-libagora-objc-loadClass-np.patch`,
`0008-libagora-objc-dtable-rebase-untyped.patch` and (this round)
`0011-libagora-objc-autorelease-pool-init.patch`; the Agora-side shims are
`0007-libagora-base-tagged-string-probe.patch` (now also the `-isNSString__`
door), `0010-libagora-base-swift-bridge-attributes.patch`,
`0012-libagora-base-swift-annotations.patch` and
`0013-libagora-base-nscalendar-retain-timezone.patch`. `0009` now also carries
the `NS_SWIFT_NAME`/`NS_REFINED_FOR_SWIFT` lines that land in `NSIndexSet.h`
and `NSString.h`.

| File (bridging) | Change |
|---|---|
| `lib/IRGen/GenClass.{h,cpp}` | `emitGNUstepCategory()`: a `struct objc_category` with GNUstep method lists; `emitGNUstepCategoryData()` puts it in `__objc_cats` and marks it used |
| `lib/IRGen/GenDecl.cpp` | at layout 2 an extension's category takes that path instead of Apple's `category_t *` list |
| `lib/IRGen/GenMeta.cpp` | `isGNUstepClassObject()` (ObjC object model **or** `@objc` ancestry) for the pattern metaclass, and a runtime-pattern class without ObjC ancestry keeps a null `isa` (§2.21) |
| `lib/IRGen/GenObjC.cpp` | a class-instance result with no Clang type (a generic initializer's `Self`) is encoded as `@`, so the thunk gets a typed selector record (§2.22) |
| `stdlib/public/core/ShadowProtocols.swift` | `_NSSetCore.count`/`_NSDictionaryCore.count` are `UInt` (`NSUInteger`'s `Q`), so Clang's typed `count` reaches the Swift override (§2.21) |
| `stdlib/public/core/{Set,Dictionary}{Bridging,Storage}.swift` | the four storage classes answer `count` as `UInt`; the `__Cocoa*` wrappers convert to `Int` at their edge (§2.21) |
| `stdlib/public/core/ShadowProtocols.swift`, the four collection storage files, `ContiguousArrayBuffer.swift`, `SwiftNativeNSArray.swift`, `Hashing.swift` | `count`, `getObjects:andKeys:count:`, `initWithObjects:count:` and `countByEnumeratingWithState:objects:count:` take/return `UInt` (`NSUInteger`'s `Q`), so Clang's typed sends reach the Swift implementations (§2.22) |
| `libagora-base/NSString.m` | `+newTaggedNSStringWithASCIIBytes_:length_:` answers nil (the Darwin SPI the stdlib probes; nil = use the storage fallback); `-isNSString__` answers YES (the stdlib's "is the other object a string?" probe, §2.21) |
| `libagora-objc/arc.mm` | `autorelease()` calls the idempotent `initAutorelease()` first, so the first Swift object autoreleased in a process does not recurse through `NSObject -autorelease` (§2.21; patch 0011) |
| `libagora-objc/dtable.c` | `rebaseDtableRecursive()` reinstalls each of the class's own methods under its *untyped* selector index too (TDD mode), so `class_setSuperclass` does not lose an override to the new parent |
| `libagora-base/*.h` (19 files) | the read-only getters become `@property` declarations (§2.17; patch 0009), so Swift reads `text.length`, not `text.length()` |
| `lib/ClangImporter/ImportType.cpp` | `canBridgeBackToObjectiveC()`: adopt a `swift_bridge`d signature only when the Swift type is representable back in Objective-C, otherwise keep the Objective-C type (§2.19) |
| `lib/ClangImporter/ImportDecl.cpp` | `getSwiftStdlibType`'s `ObjCBool` case accepts a one-byte `BOOL` typedef; the typedef's name is the contract (§2.20) |
| `lib/SIL/IR/Bridging.cpp` | the `Bool` bridge uses `ObjCBool` when the clang type is a one-byte `unsigned char` and the `Darwin` module (`DarwinBoolean`) is absent (§2.20) |
| `stdlib/public/runtime/SwiftValue.mm` | `__SwiftValue` implements `-copy` (Agora's `NSCopying` member), so a boxed value can be an `NSDictionary` key (§2.20) |
| `libagora-base/{NSString,NSArray,NSDictionary,NSSet}.h` | `swift_bridge` attributes (patch 0010): `String`, `[Any]`, `[AnyHashable: Any]`, `Set<AnyHashable>` (§2.19, §2.20) |
| `swift-toolchain/foundation-overlay/FoundationOverlay.swift` | the Swift-typed signatures the attributes produce (`allKeys` is `[Any]`, `NSError.init(domain:code:userInfo:)`'s overloads are no longer ambiguous, `NSString(string:)` is the imported initializer) |

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
# the Foundation overlay's value bridges, swift_bridge, the zero-copy
# collection/string views, and the value types + header annotations)
swift-toolchain/scripts/verify-swift-port.sh

# the Foundation-surface gate (§2.29): extracts the reference graphs
# (Foundation + FoundationEssentials + FoundationInternationalization) and ours,
# diffs symbols/conformances/extras, and ratchets parity/foundation-allowlist.txt;
# --report for the human diff, --update-allowlist after a landing. ~10 s.
swift-toolchain/scripts/verify-foundation-parity.sh --check

# the S1 gate (layout-2 test compiler; builds the frontend if needed)
swift-toolchain/scripts/verify-class-abi.sh

# the S4 gate (layout-2 compiler AND stdlib in the build tree; builds them if
# needed - a full stdlib rebuild is ~15-30 min); it includes the regression for
# a fixed class with a generic Swift superclass (§2.21)
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
  uncommitted by design (63 files now, including the class-object predicate,
  the `NSUInteger` parameter encodings and the initializer encoding). The Agora
  repository has each round's doc update committed (`53657c7` for zero-copy
  bridging, `2a7c7a1` for the surface round). `swift-toolchain/` and
  `swift-interop-probe/` are component repositories of the same federation now
  (submodules of the workspace, with their own `main` and `LICENSE`); they are
  no longer git-ignored local trees.
- **To change the layout**: `AGORA_SWIFT_CLASS_LAYOUT=0` (or `2`, the default)
  `swift-toolchain/scripts/build-swift-toolchain.sh`. The build script always
  passes `-DSWIFT_OBJC_CLASS_LAYOUT:` explicitly, so the cache cannot go stale.
- **Foundation overlay**: `usr/lib/swift/linux/Foundation.swiftmodule/` and
  `libFoundation.so`, built by
  `swift-toolchain/scripts/build-foundation-overlay.sh` (called by
  `build-swift-toolchain.sh` after the install), rebuilt this round against the
  `swift_bridge` headers. It belongs to the *installed* toolchain; the
  build-tree compiler does not have it, which is why the language gate skips
  the bridging checks when `VERIFY_SWIFTC` points there.
- **This round's install**: `swift-frontend` and `libswiftCore.so` were rebuilt
  with the class-object, typed-parameter and initializer-encoding changes, and
  the ObjectiveC and Foundation overlays were reinstalled next to the target
  stdlib (the Foundation overlay now carries the value types and the annotation
  surface). The authoritative rebuild is
  `swift-toolchain/scripts/build-swift-toolchain.sh`; it builds the ObjectiveC
  module before the Foundation overlay and reinstalls both.
- **Clang module cache**: a compiler that predates a change to the imported
  signature must not share a cache with one that has it; use
  `-module-cache-path` (or clear `~/.cache/clang/ModuleCache`) when comparing
  frontends. The `BOOL` change and the `swift_bridge` attributes both alter
  imported signatures.
- **Clang module cache**: the importer's bridge decision is baked into the
  cached Foundation Clang module, so a compiler that predates §2.19 and one
  that has it must not share a cache. Use `-module-cache-path` when comparing
  frontends (the before/after in §2.19 was produced that way).
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
  (bridging, `swift_bridge`, zero-copy and value-types/annotations sections),
  `run-native-probe.sh` every check (including `#selector`), the
  library-evolution gate green (`Update` + `Singleton`, evolved v2 layout at
  `-Onone` and `-O`), and with
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
7. **Foundation bridging - feature parity with Darwin - done** (§2.16,
   §2.18, §2.19, §2.20, §2.21). The `ObjectiveC` module ships (`BOOL` -> `Bool`,
   `#selector`, `NSZone`), `AnyHashable` bridges to `NSObject` (which makes
   `[AnyHashable: Any]`/`Set<AnyHashable>` representable and so lets
   `swift_bridge` cover `NSDictionary`/`NSSet` too), every fixed-width number
   and `Float` bridges to `NSNumber`, the Foundation value types exist and
   bridge, the error protocols include `RecoverableError` and the
   `_BridgedStoredNSError` family, the importer only rewrites a signature when
   the bridge can be undone (§2.19), and the bridge is now **zero-copy** in
   both directions (§2.21) - the same shape Darwin's has. That last step was
   not an overlay change: it needed the class-object predicate fixed for
   runtime-pattern classes, the `@_swift_native_objc_runtime_base` storages to
   become class objects, the collection cores' `count` to carry the
   `NSUInteger` encoding, a libobjc2 autorelease-pool init, and the
   `-isNSString__` door.
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
   gate and now runs the *installed* layout-2 toolchain; it carries the
   bridging, `swift_bridge` and (this round) zero-copy sections.
   `verify-class-abi.sh` is the C-side S1/S3 gate; `verify-generic-abi.sh`
   (S4, including the fixed-class-with-generic-superclass regression from
   §2.21), `verify-generic-objc-abi.sh` (S4b/S4c) and `verify-refcount-abi.sh`
   (S5) check the stdlib too (`STDLIB_DIR`); `run-native-probe.sh` is the
   native probe harness and passes every check against the installed
   toolchain. The published-container `run-probe.sh` and
   `compat/ObjCInteropShim.c` were deleted in S6 (§2.13).
11. **The surface is finished** (§2.22): the value types' long tails, the four
   header annotations, the `NSUInteger`-encoded *parameter* selectors
   (`getObjects:range:`, `getObjects:andKeys:count:`,
   `countByEnumeratingWithState:objects:count:`, `initWithObjects:count:`) and
   the typed initializer encoding are all implemented and gated. What is left
   is one *unreachable* compiler case: prespecialized generic class metadata
   for a class with an Objective-C ancestor (§2.10, re-measured in §2.22). No
   module the toolchain builds emits one, so no program can reach it; closing
   it is a compiler task for the day a stdlib-like module declares such a
   class, and the handoff records what it would take.
   **Foundation *overlay* parity** is a different, larger project and has its
   own plan: [`SWIFT-FOUNDATION-PARITY-PLAN.md`](SWIFT-FOUNDATION-PARITY-PLAN.md).
   Its P0 (measurement) landed this round (§2.29): the harness, the gate and a
   measured baseline (7,691 missing symbols, 179 missing conformance edges
   against a 10,455-symbol three-module reference, after the name, enum, shape and conformance passes). P1 (the rename/annotation
   pass) is next; P2 (the `swift-foundation` spike) decides whether the T3 work
   is "port and bridge" or "port the sources".
12. **Two Agora-side bugs surfaced by the value-type gate and are fixed**
   (§2.22): `NSCalendar -setTimeZone:` stored the zone without retaining it
   (the next `-startOfDayForDate:` read freed memory), and `IndexSet`'s Swift
   iterator started at `-1` against an `NSUInteger` API, so iteration yielded
   nothing.

---

## 6. Artifact index

```
swift-toolchain/
├── README.md                                  build/run instructions
├── patches/
│   ├── 0001-libagora-base-objcxx-clean.patch   3 hunks / 2 files
│   ├── 0002-libagora-core-objcxx-clean.patch   1 hunk  / 1 file
│   ├── 0003-swift-enable-objc-interop.patch   57 files, ~2150 insertions
│   ├── 0004-libdispatch-overlay-non-interop.patch  1 file (the Dispatch overlay)
│   ├── 0005-libagora-base-allocWithZone.patch      2 files (NSObject)
│   ├── 0006-libagora-objc-loadClass-np.patch       3 files (the runtime hook,
│   │                                               its lock, the SONAME)
│   ├── 0007-libagora-base-tagged-string-probe.patch 1 file (NSString, the
│   │                                               stdlib's tagged-string SPI
│   │                                               and -isNSString__)
│   ├── 0008-libagora-objc-dtable-rebase-untyped.patch 1 file (the dtable
│   │                                               rebuild after class_setSuperclass)
│   ├── 0009-libagora-base-property-shaped-accessors.patch 19 headers (readonly
│   │                                               getters declared as properties)
│   ├── 0010-libagora-base-swift-bridge-attributes.patch 4 headers (NSString ->
│   │                                               String, NSArray -> [Any],
│   │                                               NSDictionary ->
│   │                                               [AnyHashable: Any], NSSet ->
│   │                                               Set<AnyHashable>; §2.19/2.20)
│   ├── 0011-libagora-objc-autorelease-pool-init.patch 1 file (arc.mm: choose the
│   │                                               ARC pool before the first
│   │                                               autorelease; §2.21)
│   ├── 0012-libagora-base-swift-annotations.patch 6 headers (the four
│   │                                               annotations, NSNotificationName
│   │                                               as a typed enum; §2.22)
│   └── 0013-libagora-base-nscalendar-retain-timezone.patch 1 file (NSCalendar
│                                                   keeps the zone it is given;
│                                                   §2.22)
├── objectivec-overlay/
│   └── ObjectiveC.swift                       the `ObjectiveC` module the
│                                              importer looks BOOL/SEL/NSZone
│                                              up in: ObjCBool, Selector,
│                                              NSZone (§2.20)
├── foundation-overlay/
│   ├── FoundationOverlay.swift                bridges (String, collections,
│   │                                          every number, AnyHashable),
│   │                                          Error <-> NSError and the error
│   │                                          protocols, Sequence collections
│   └── FoundationValueTypes.swift             Data, Date, URL, UUID, IndexPath,
│                                              TimeZone, Locale, Calendar,
│                                              DateComponents, DateInterval,
│                                              Notification, PersonNameComponents,
│                                              CharacterSet, IndexSet, Decimal,
│                                              AffineTransform,
│                                              NSAttributedString.Key
└── scripts/
    ├── build-swift-toolchain.sh               build + install (incl. wrapper,
    │                                          host runtime, clang, overlay)
    ├── build-objectivec-overlay.sh            build + install the ObjectiveC
    │                                          module and self-check it
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
    ├── verify-update-abi.sh                   the library-evolution gate
    │                                          (resiliently sized members:
    │                                          Update + Singleton, evolved v2)
    ├── verify-foundation-parity.sh            the Foundation-surface gate
    │                                          (--report / --check /
    │                                          --update-allowlist; §2.29)
    └── foundation-parity-diff.py              the symbol/conformance diff
swift-toolchain/
└── parity/foundation-allowlist.txt            the accepted gaps, one prefix
                                               entry each with its count and
                                               stage reason (the ratchet)

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
`NSError` initializers, `NSObject: Hashable` for `AnyHashable`). The last
importer gap is closed too: `NSString *` now imports as `String` and `NSArray *`
as `[Any]` (`swift_bridge` in the headers), and the importer adopts such a
signature only when the Swift type can be converted back to an object type at
the Objective-C boundary - so an attribute on a type without a bridge leaves
the Objective-C type in place instead of handing the back end a Swift value
where an object pointer belongs, which is exactly what used to abort IRGen
(§2.19). Bridging is zero-copy now too (§2.21): `String`, `Array`, `Dictionary`
and `Set` cross as views over their own storage and adopt it back, and that
required fixing a class-object predicate that treated a non-generic class with a
generic Swift superclass as registrable (it crashed in `objc_resolve_class`),
extending the same predicate to the stdlib's `@_swift_native_objc_runtime_base`
storage classes (they are reparented to Foundation's collections but answer
`Native` to the object-model question), giving the collection cores' `count` the
`NSUInteger` encoding Clang sends (typed dispatch keys on (name, encoding)), a
libobjc2 autorelease-pool initialisation, and an `-isNSString__` door in
NSString. The surface is finished as well (§2.22): every count *parameter* in
the collection cores carries the `NSUInteger` encoding, a generic initializer
gets a typed selector record, the Cocoa value types carry the API a program
actually calls (`Data` as a collection, `IndexSet`/`CharacterSet` as
`SetAlgebra`, `Decimal` arithmetic, `Calendar` date math and `DateFormatter`),
and Agora's headers use `NS_TYPED_ENUM`/`NS_SWIFT_NAME`/`NS_REFINED_FOR_SWIFT`/
`NS_SWIFT_SENDABLE`. Two Agora bugs fell out of the new gate: an unretained
`NSCalendar` time zone (use-after-free) and an `IndexSet` iterator that started
at `-1` against an `NSUInteger` API (empty iteration); both are fixed. The
bridging *semantics* were then checked against swift-corelibs-foundation and
brought into line: a conditional collection/number cast is a check that fails
(nil), not a conversion that truncates or drops - a data-loss bug the earlier
"parity" claim had missed. The only
item left is the *unreachable* prespecialized-generic-with-ObjC-ancestor
compiler case, recorded with what it would take. The installed toolchain no longer borrows the bootstrap's runtime either:
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

The Foundation *overlay* is now measured rather than estimated (§2.29): a
three-module reference (Foundation + FoundationEssentials +
FoundationInternationalization, 10,455 symbols) against Agora's 11,314, with
7,691 symbols and 179 conformance edges still missing, recorded in a 360-entry
allowlist that `verify-foundation-parity.sh --check` ratchets in both directions
(a gap may not grow, and a count that is now too large must shrink). The
measurement needed one compiler fix: `swift-symbolgraph-extract` is a direct
frontend invocation, so it inherited the frontend's Darwin-only interop default
instead of the driver's Linux one, and imported Agora's module in C mode.
