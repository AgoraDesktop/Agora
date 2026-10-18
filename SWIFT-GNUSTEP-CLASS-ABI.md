# The GNUstep class ABI for Swift — design and plan

*Decision: **Swift classes on Agora will be GNUstep-ABI class objects**, so that
Agora's libobjc2 can register, resolve and dispatch to them like any other class.
This document is the target ABI, the evidence behind it, the exact changes
required, and a staged plan with verification gates.*

Companion: [`SWIFT-PORT-HANDOFF.md`](SWIFT-PORT-HANDOFF.md) (§4 option C),
[`SWIFT-TOOLCHAIN-INTEGRATION.md`](SWIFT-TOOLCHAIN-INTEGRATION.md).

---

## 0. Prerequisite: how the change can be tested at all

**Resolved (2026-10-17).** Nothing in §4–§6 can be validated until the compiler
can compile a source file; it now can, and how it was unblocked changes this
plan's prerequisites. Two things happened, recorded in
[`SWIFT-PORT-HANDOFF.md`](SWIFT-PORT-HANDOFF.md) §2.3–2.4:

- The **target** stdlib was migrated to the compact class layout
  (`SWIFT_OBJC_CLASS_LAYOUT == 0`), the layout bootstrap-compiled code already
  emits, and IRGen now keys every class-object decision off
  `usesObjcClassObject()` (`IGM.usesObjCClassObject()`), not off interop.
- The **compiler process** was moved onto the host (bootstrap, non-interop)
  standard library, because `_runtime(_ObjC)` changes `Array`'s storage type and
  therefore the stdlib's ABI. The installed `swiftc` is a wrapper that puts the
  host runtime on `LD_LIBRARY_PATH`; programs get the target stdlib through
  `DT_RUNPATH`.

Consequence for this plan: **the compiler no longer loads the target stdlib**,
so the target class layout is a free choice. The two-stage build described below
is no longer required for S1, and neither is recompiling swift-syntax with a
stage-0 compiler. What remains for S1 is the IRGen/runtime emission work in
§6.1a. The rest of this section is the original analysis, kept because it is
still the accurate description of why the host and target runtimes must be
separate. It is worth being explicit about what each stage needs:

- The compiler's **own** Swift code (`SwiftCompilerSources`, both swift-syntax
  copies) is compiled by the **bootstrap** compiler, which cannot emit interop
  code on Linux (its stdlib has no `AutoreleasingUnsafeMutablePointer`, so `&v`
  is a hard error) — verified again while writing this.
- The **compiler itself** (IRGen, Sema, …) is C++, so it *can* be changed freely:
  a stage-0 compiler built from this fork emits whatever class layout its IRGen
  emits, regardless of how its own Swift sources were compiled.
- Therefore the workable order is a **two-stage build**: stage 0 (built today,
  from the bootstrap compiler) with the IRGen/runtime change produces a
  GNUstep-layout stdlib and GNUstep-layout stage-1 modules; the final compiler
  then runs with every Swift object in the process on the same layout.
- The one piece the existing build does not stage is **swift-syntax**: both
  copies (`lib/CompilerSwiftSyntax`, `lib/SwiftSyntax`) are built with
  `CMAKE_Swift_COMPILER` (the bootstrap compiler) and pin it at configure time
  through `project(… LANGUAGES Swift)`. Under this plan they must be compiled by
  the stage-0 compiler, which needs new CMake plumbing (or a separate
  out-of-tree build).

Alternative order, if a working compiler is wanted sooner: make the class layout
*compact* (the layout the bootstrap compiler already produces) instead of
GNUstep's. That fixes the compiler outright — including plain non-interop
`swiftc file.swift`, which is equally broken today — but it makes interop
one-way. It is a strictly smaller change and it is not wasted work: the layout
switch it introduces (a macro independent of `SWIFT_OBJC_INTEROP`, plus
`Runtime::ObjCClassLayout` in `MetadataRef.h:44`) is the same machinery a
GNUstep-layout pass needs.

## 1. Why the layouts cannot be reconciled in place

Swift's ObjC interop uses the **Apple** class ABI. Agora's libobjc2 uses the
**GNUstep** one. Both are `struct objc_class`-shaped and both start with
`isa` + superclass, and that is where the agreement ends:

| word | Swift / Apple (`TargetAnyClassMetadataObjCInterop`) | GNUstep (`libagora-objc/class.h`) |
|---|---|---|
| 0 | `isa` | `isa` |
| 1 | `Superclass` | `super_class` |
| 2 | `CacheData[0]` | `name` |
| 3 | `CacheData[1]` | `version` |
| 4 | `Data` (`ptrtoint(ROData) \| mask`) | `info` (`objc_class_flags`) |
| 5 | `Flags` (u32) + `InstanceAddressPoint` (u32) | `instance_size` |
| 6 | `InstanceSize` (u32) + `InstanceAlignMask`(u16) + `Reserved`(u16) | `ivars` |
| 7 | `ClassSize` (u32) + `ClassAddressPoint` (u32) | `methods` |
| 8 | `Description` (the class descriptor) | `dtable` |
| 9 | `IVarDestroyer` | `subclass_list` |
| 10… | vtable, field offsets, generic args, … | `cxx_construct`, `cxx_destruct`, `sibling_class`, `protocols`, `extra_data`, `abi_version`, `properties` |

Two collisions make a merged struct impossible, not merely awkward:

- word 4: libobjc2 needs `info` to be a small flag word and tests bit 12
  (`objc_class_flag_hidden_class`) and bit 0 (`objc_class_flag_meta`) in it;
  Swift needs `Data` to be a pointer with the "is Swift" bit set.
- word 8: libobjc2 dispatches through `dtable`; Swift needs `Description` to find
  its vtable, field offsets and generic arguments.

Same for the out-of-line Apple `class_ro_t` (`flags, instanceStart, instanceSize,
reserved/ivarLayout, name, methodList, protocolList, ivarList, weakIvarLayout,
propertyList`): GNUstep has no such object — `name`, `methods` and `ivars` live
**in the class struct**, and there is no RO/RW split. So `Data`, `getROData()`,
`setAsTypeMetadata()` and `SWIFT_CLASS_IS_SWIFT_MASK` have no place in the target
design at all.

## 2. Evidence that the target ABI is workable

Four probes in [`swift-interop-probe/class-abi/`](swift-interop-probe/class-abi/)
build the GNUstep-ABI shape by hand and register it four ways.

| probe | registration | result |
|---|---|---|
| `probe.c` | `objc_registerClassPair` on a statically shaped struct | registration, `class_getName`, `objc_getClass`, `class_createInstance`, `object_getClass` all work; the first message send **crashes** |
| `probe2.c` | `objc_allocateClassPair` + `class_addMethod` | instance and class dispatch both work |
| `probe3.c` | `struct objc_init` → `__objc_load` (the **compiler's** path, static classes) | **everything works**, including `+load` delivery: `respondsToSelector` true on both sides, `-greet` dispatched, `+answer` dispatched |
| `probe4.c` | `objc_loadClass_np` (the new hook, **dynamic/generic** classes) | **everything works**: heap-allocated class, `respondsToSelector` true both sides, both dispatches |

### The one non-obvious requirement: `struct objc_method` field order

`libagora-objc/method.h` defines

```c
struct objc_method { IMP imp; SEL selector; const char *types; };
```

**`imp` comes first**, not `selector` — the opposite of Apple's `method_t`
(`{ name, types, imp }`) and easy to get wrong. The first version of `probe3`
declared `{ selector, types, imp }` and produced a class that registered but
whose methods were invisible (and that crashed `+load` delivery inside
`sel_isEqual`). With the order corrected the probe works unchanged. Anything
emitting these lists from IRGen must match this order exactly.

Consequence for the design: **no emitted selector table is required for
dispatch.** `probe3` interns its selectors with `sel_registerName()` and the
loader-based path resolves them fine. clang additionally emits a
`__objc_selectors` table (array of `SEL` in `struct objc_init.sel_begin..sel_end`)
so that selectors can be pre-registered, which is worth mirroring later (it
keeps method lists in read-only data and avoids a registration call per
selector), but it is an optimisation, not a requirement.

### Why `objc_registerClassPair` is not the path for compiler-shaped classes

`dtable_for_class()` (`dtable.h:58`) **never installs** a dispatch table; it only
returns `cls->dtable`. Installation happens in `objc_send_initialize()`
(`dtable.c:726`), which builds the tables with `create_dtable_for_class()`.
`objc_load_class()` (`class_table.c:410`) sets `cls->dtable` to the
`uninstalled_dtable` sentinel, so the send path knows to call
`objc_send_initialize()`. `objc_registerClassPair()` sets neither, leaving
`dtable == NULL`, so the send path treats NULL as an installed table and walks
it — the `probe.c` crash. Calling `objc_send_initialize()` afterwards does not
recover, because the table creation then sees a non-sentinel NULL.

## 3. Where classes come from

Two cases, and they need different mechanisms:

### 3.1 Statically emitted classes → the GNUstep module

libobjc2 discovers classes when a constructor calls
`__objc_load(struct objc_init *)` (`loader.c:170`). clang emits exactly that for
`-fobjc-runtime=gnustep-2.0`:

```
	leaq	.objc_init(%rip), %rdi
	callq	__objc_load@PLT
```

The contract (`loader.c`, `struct objc_init`) is a set of range pairs:

```c
struct objc_init {
  uint64_t version;                 // must be 0
  SEL sel_begin, sel_end;           // emitted selector table
  Class *cls_begin, *cls_end;       // emitted class list
  Class *cls_ref_begin, *cls_ref_end;
  struct objc_category  *cat_begin,  *cat_end;
  struct objc_protocol  *proto_begin,*proto_end;
  struct objc_protocol **proto_ref_begin, **proto_ref_end;
  struct objc_alias     *alias_begin,*alias_end;
  struct nsstr          *strings_begin,*strings_end;
};
```

`__objc_load` registers the selectors, then for each class calls
`objc_load_class()` (insert into the class table, set the dtable sentinel,
root-class/metaclass fixups, `+load` delivery, protocol init), then
`objc_resolve_class_links()`. Everything Swift's runtime does today through
`objc_readClassPair()` / `swift_instantiateObjCClass()` becomes **load-time and
free**.

### 3.2 Dynamically instantiated classes (generic classes) → a small new hook

A generic Swift class's metadata is allocated at runtime from a pattern, so it
cannot be in a `.objc_init` class list. It needs the same treatment
`objc_load_class()` gives emitted classes. That function is `PRIVATE`; the
minimal libobjc2 change for this project is a public entry point:

```c
// libagora-objc: class_table.c
OBJC_PUBLIC void objc_loadClassForSwift_np(Class cls)   // wraps objc_load_class()
```

plus selector interning for the class's method lists if Swift emits names
instead of SELs (§4.3). `objc_load_class` already does the parts that
`objc_registerClassPair` misses, which is the whole reason this hook is needed.
The hook is implemented as `objc_loadClass_np` (wrapping `objc_load_class` and
`objc_send_initialize`) and proven by `probe4`.

S4 showed the case is narrower than "every generic class": a generic Swift class
**cannot have `@objc` members**, so unless it inherits an imported Objective-C
class its instances are never allocated by `objc_allocWithZone` and no
Objective-C code ever holds them. Those classes are handled without the hook -
their metadata is Swift metadata (marked by `ABIVersion`), not a class object
(handoff §2.8). The hook is needed for a generic class *with* an imported ObjC
ancestor (`class Box<T>: NSObject`), which is S4b: the metaclass lives in the
pattern's extra data, the class gets a per-instantiation Objective-C name, and
`swift_instantiateObjCClass()` calls `objc_loadClass_np()` once the instance
layout is complete (handoff §2.9).

## 4. The target ABI

### 4.1 Class metadata = `struct objc_class` + Swift trailing fields

Address point stays word 0 (so `Class` and `Metadata *` are the same pointer, as
GNUstep requires). The first 17 words are exactly GNUstep's struct; Swift's own
fields follow it.

```c
struct swift_gnustep_class {
  /* 0x00 */ Class isa;                    // metaclass
  /* 0x08 */ Class super_class;            // real pointer (v2 ABI) or name ptr
  /* 0x10 */ const char *name;
  /* 0x18 */ long version;
  /* 0x20 */ unsigned long info;           // objc_class_flags, incl. Swift marker
  /* 0x28 */ long instance_size;
  /* 0x30 */ struct objc_ivar_list *ivars;
  /* 0x38 */ struct objc_method_list *methods;
  /* 0x40 */ void *dtable;                 // runtime-owned
  /* 0x48 */ Class subclass_list;          // runtime-owned
  /* 0x50 */ IMP cxx_construct;
  /* 0x58 */ IMP cxx_destruct;
  /* 0x60 */ Class sibling_class;          // runtime-owned
  /* 0x68 */ struct objc_protocol_list *protocols;
  /* 0x70 */ struct reference_list *extra_data;
  /* 0x78 */ long abi_version;             // 3 = Swift
  /* 0x80 */ struct objc_property_list *properties;
  /* --- Swift-specific, offset fixed so IRGen and the runtime agree --- */
  /* 0x88 */ uint32_t classFlags;          // UsesSwiftRefcounting, IsStaticSpecialization, …
  /* 0x8c */ uint32_t instanceAddressPoint;
  /* 0x90 */ uint16_t instanceAlignMask;
  /* 0x92 */ uint16_t reserved;
  /* 0x94 */ uint32_t classSize;           // total metadata size, bytes
  /* 0x98 */ uint32_t reserved2;
  /* 0xa0 */ const ClassDescriptor *description;
  /* 0xa8 */ IVarDestroyer ivarDestroyer;
  /* 0xb0 */ /* immediate members: vtable, field offsets, generic args, … */
};
```

Notes:

- **"Is Swift" is `abi_version == 3`**, not a bit in a data pointer. libobjc2
  ignores unknown `abi_version` values today (`legacy.c` only special-cases the
  gs v1 struct), and the value is available to the runtime without any pointer
  arithmetic. `SWIFT_CLASS_IS_SWIFT_MASK`, `setAsTypeMetadata()` and the whole
  §2.1 handoff bug disappear from this platform.
- `MetadataPositiveSizeInWords` / `ClassSize` / the address point math are
  computed from this header, so the vtable and field-offset vector still follow
  the metadata at offsets the compiler chooses; libobjc2 never looks there.
- `instance_size` must be the real instance size (libobjc2 allocates from it);
  Swift's `InstanceSize` in the Apple layout was a separate field.
- The metaclass is the same struct with `info & objc_class_flag_meta` and
  `ivars = NULL`; libobjc2 wires `isa`/`super_class`/`sibling_class` at resolve.

### 4.2 Methods

Apple's `method_list_t` (`uint32 entsizeAndFlags; uint32 count; { int32 name;
int32 types; int32 imp }[]`, relative) is replaced by GNUstep's
`struct objc_method_list` (`method.h`):

```c
struct objc_method_list { struct objc_method_list *next; int count;
                          size_t size; struct objc_method methods[]; };
struct objc_method      { SEL selector; const char *types; IMP imp; };
```

`size` is per-entry so the runtime can skip unknown trailing fields; IRGen must
emit `sizeof(struct objc_method)`. Selectors must be real `SEL`s from an emitted
selector table (see §3.1), or be interned by the runtime hook (§3.2).

### 4.3 Ivars

GNUstep's `objc_ivar_list` with `ivar_offset` **indirection** (clang emits
`__objc_ivar_offset_Root.isa.#`, and `objc_registerClassPair` rewrites the
`Offset` pointers). Swift's `FieldOffsetVector` in the metadata stays the source
of truth for Swift; the emitted ivar list exists for libobjc2 (KVC, layout
introspection, `class_getInstanceVariable`).

## 5. Change inventory

### 5.1 `swift` (fork)

| Area | Change |
|---|---|
| `include/swift/ABI/Metadata.h` | new layout variant for the GNUstep vendor (`SWIFT_OBJC_CLASS_ABI_GNUSTEP`): the struct above replaces `TargetAnyClassMetadataObjCInterop`; drop `Data`, `CacheData`, `getROData`, `setAsTypeMetadata` on this path; `isTypeMetadata()` = kind test |
| `lib/IRGen/GenMeta.cpp` | `emitClassMetadataStructure`: emit the GNUstep header (name/version/info/instance_size/ivars/methods) and move `Flags`/`Description`/`IVarDestroyer` to the trailing block; `addClassDataPointer`/`addClassCacheData` gone; `getClassDataPointerHasSwiftMetadataBits` gone on this path; `getROData()` gone |
| `lib/IRGen/GenClass.cpp` | `emitROData`/`emitRODataFields` replaced by GNUstep method/ivar/protocol/property lists; `objc_method_list` emission with `next`/`count`/`size`; selector table emission; `name` as a global string |
| `lib/IRGen/Linking.cpp` | class/metaclass symbol spelling and the `objc_init` module globals (`__objc_load` constructor, `cls_begin`/`cls_end`, `sel_begin`/`sel_end`) |
| `lib/IRGen/GenObjC.cpp` | stop emitting Apple `class_ro_t`-shaped metadata and `objc_readClassPair`-style registration |
| `stdlib/public/runtime/Metadata.cpp`, `SwiftObject.mm`, `DynamicCast.cpp` | replace `getROData`/`Data`/mask users with the new fields; `swift_instantiateObjCClass` → the §3.2 hook; `isTypeMetadata` → `abi_version` |
| `stdlib/public/runtime/GNUstepObjCCompatibility.mm` | drop the `objc_readClassPair`/`_objc_realizeClassFromSwift` stubs once registration is real |

**What S1 actually touched (fixed/non-generic classes).** The design above was
the map; this is the terrain as implemented:

| Area | Reality |
|---|---|
| header order | `ClassMetadataVisitor::layout()` calls `addClassGNUstepHeader()` (a CRTP helper) for layout 2; `ClassMetadataScanner` gives it pointer-sized fields, so `ClassMetadataLayout` sizes follow automatically |
| field values | `ClassMetadataBuilderBase::addGNUstep*()` in `GenMeta.cpp`; the name/method/ivar constants come from `IRGenModule::getGNUstepClassData()` (`GenClass.cpp`), cached per class |
| method lists | `ClassDataBuilder::buildGNUstepMethodList()`; `ObjCMethodDescriptor` grew a `selector` string so a real `SEL` (the `__objc_selectors` record) can be used |
| ivars | `ClassDataBuilder::buildGNUstepIvarList()` — required, not optional: a null list makes libobjc2 overwrite `instance_size` |
| metaclass | `irgen::emitGNUstepMetaclassObject()`; emitted *before* the class metadata initializer, from `addMetadataFlags()`; `Linking.cpp` spells `._OBJC_METACLASS_<name>` for Swift-defined classes |
| registration | nothing new: the embedded Clang CodeGen already emits `.objc_init`/`__objc_load`; only the class-list section changed to `__objc_classes` (`GenDecl.cpp`) |
| selector table | already emitted by the previous round (`getGNUstepSelector` in `GenObjC.cpp`); no registration call is needed because `__objc_load` registers the whole `__objc_selectors` range |

`emitROData`/`emitRODataFields` were **not** deleted: they are still the layout-1
path, and the metadata builder simply never calls `emitClassPrivateData()` at
layout 2. The same is true of `addClassDataPointer`/`addClassCacheData` — unused
at layout 2, still needed for layout 1 and for `@objc @implementation` classes.

### 5.2 `libagora-objc`

| Change | Status |
|---|---|
| `class.h` + `class_table.c`: public `objc_loadClass_np()` for runtime-instantiated (generic) classes | **done**, rebuilt and installed; verified by `probe4` |

### 5.3 Blocking prerequisite — **met by a different route**

The original argument was that a GNUstep class layout would make interop and
non-interop code agree, so the bootstrap-compiled host libraries
(`SwiftCompilerSources`, `lib_CompilerSwift*`) would stop conflicting with
`libswiftCore`. That argument holds for the *class header*, but not for the
stdlib ABI as a whole: `_runtime(_ObjC)` also changes `Array`'s storage type, so
the host libraries and an interop stdlib disagree no matter what the class
layout is. See [`SWIFT-PORT-HANDOFF.md`](SWIFT-PORT-HANDOFF.md) §2.4.

The prerequisite is therefore met by **separating the runtimes**: the compiler
runs on the non-interop host stdlib, the programs it produces run on the target
stdlib. That removes the coupling for every future ABI decision, including this
one, and is why S1 needs no build-system work.

## 6. Staged plan with gates

| Stage | Work | Gate |
|---|---|---|
| S0 | libobjc2 hook + probes | **passed**: `probe3` (static/loader path) and `probe4` (dynamic path via `objc_loadClass_np`) both register and dispatch, instance and class side |
| S0a | compact target layout (option A of the handoff §4) + host/target runtime split | **passed**: `swiftc` type-checks, compiles and runs at `-Onone` and `-O`; `verify-swift-port.sh` green; every runtime TU compiles under layout 0; interop is one-way |
| S1a | `SWIFT_OBJC_CLASS_LAYOUT` in `Runtime/Config.h` (0 compact / 1 Apple / 2 GNUstep), independent of `SWIFT_OBJC_INTEROP`, default preserved | **done and inert**: `Metadata.cpp` still compiles unchanged with the macro defined |
| S1b | `TargetAnyClassMetadataGNUstep` + `Runtime::ObjCClassLayout` + three-way selection, then flip the default | **layout machinery done; migration measured and applied** — every runtime TU compiles under *both* layouts (see §6.1) |
| S1 | Emit, for a trivial `@objc` class: GNUstep structs, name, method list, **selector table**, `.objc_init`, constructor | **passed** with a test compiler built at layout 2 (`swift-toolchain/scripts/build-layout2-frontend.sh`): `objc_getClass` from a C constructor before `main`, `respondsToSelector`, `+load` via an ObjC category, dispatch — see the note below |
| S2 | Instance-method and class-method dispatch from C and from ObjC onto a Swift class | **passed for the fixed/non-generic case**: `objc_msg_lookup` reaches `-greet` and `+classAnswer`; `objc-to-swift-probe` passes in full with the layout-2 compiler |
| S3 | Instance layout: `instance_size`, ivar list with offset indirection, Swift field offsets still correct | **passed**: the `objc_ivar_list` keeps `instance_size` from being clobbered, `class_getInstanceVariable` finds the Swift field and reports its offset, and the S1 gate proves both directions (C write -> Swift read, Swift write -> C read) |
| S4 | Generic classes: metadata patterns that the layout-2 runtime can complete | **passed for generic classes without an imported ObjC ancestor** (which is all the stdlib has): the pattern carries no Apple extra data, the runtime initializes the GNUstep header with `ABIVersion = 3`, and a full layout-2 stdlib rebuild is green — see the note below. `class Box<T>: NSObject` needs the §3.2 hook and is split out as **S4b** |
| S4b | Generic classes with an imported Objective-C ancestor: GNUstep metaclass in the pattern, unique ObjC name per instantiation, `objc_loadClass_np()` registration, method/ivar lists | **passed** for runtime-instantiated classes: `Box(Int)`, `Box(String)`, `Box<(Int, Int)>`, `Sub<Int>: Box<Int>`, nested `Box<Box<Int>>` are registered class objects, `-init` reaches the Swift initializer, and a 16-thread stress passes — see the note below. `deinit` still misses the typed `dealloc` selector (S5) |
| S4c | Resilient classes (library evolution) with an imported ObjC ancestor: static metaclass, class-side fields in the pattern, registration of the relocated metadata, field-offset globals | **passed**: `Sub: Base` and `GrandSub: Sub` relocate, register, and keep their field values; a pure Swift resilient class stays a non-class-object. The *prespecialized* generic-with-ObjC-ancestor case remains unreachable and unimplemented (see the S4c note) |
| S5 | Refcounting/ARC interop, `+alloc`, `UsesSwiftRefcounting`, `+load`/`+initialize` | **partly**: `+alloc`/`objc_allocWithZone`, `+load` and pure-Swift refcounting work — with a layout-2 runtime a pure Swift class (generic or not) runs `deinit`. A class with ObjC ancestry still releases through libobjc2 (`NSObject -release` -> `objc_release` -> `gc->free_object`), so its `deinit` is skipped |
| S6 | Remove the Apple-layout remnants and the compatibility shims | full `swiftc` + Agora program |

Every stage is independently testable, and S0 needs no compiler rebuild.

**S1 result (2026-10-17).** With `SWIFT_OBJC_CLASS_LAYOUT=2` and the emission
work above, `swift-toolchain/scripts/verify-class-abi.sh` passes every
check from C: the class is registered before `main`, its name and both method
lists are visible, an Objective-C category on the Swift class is attached and its
`+load` delivered, and `class_createInstance` + `objc_msg_lookup` dispatch to the
Swift IMPs. Swift-side `Counter()` (via `objc_allocWithZone`), `super -init`,
property access and `isKind(of:)` work as well. Two requirements surfaced that
are easy to miss:

- a Swift-defined class needs its own `._OBJC_METACLASS_<name>` object;
  libobjc2 exports no metaclass symbols for imported classes, so the compiler's
  previous mapping (metaclass reference → class symbol) is wrong for definitions;
- a null `objc_ivar_list` is not harmless: libobjc2's
  `objc_compute_ivar_offsets()` replaces `instance_size` with the superclass's,
  after which every stored field is written past the allocation (a heap
  corruption that shows up in a later `malloc`). The emitted ivar list fixes it.

**S4 result (2026-10-17).** A generic class's metadata is built at runtime, so
S4 needed both sides of the ABI: IRGen stops adding Apple's `class_ro_t`/
metaclass extra data to the generic pattern at layout 2 (that extra data, and
the `._OBJC_METACLASS__TtCs12_SwiftObject` reference it carried, was the link
failure), and the runtime's `initializeClassMetadataFromPattern` /
`_swift_relocateClassMetadata` now initialize the GNUstep header for
runtime-built metadata — empty ObjC fields and
`ABIVersion = SWIFT_GNUSTEP_CLASS_ABI_VERSION`, which is this layout's
`isTypeMetadata()` marker and what selects Swift refcounting.

Two things are worth keeping:

- **The stdlib rebuild is the test, not a formality.** With a layout-2 frontend
  and the layout-0 stdlib, `Box<Int>` appears to work: generated code reads
  `InstanceSize` at the layout-2 offset while the layout-0 runtime writes it at
  the compact offset, so the field stays 0 and the allocation is too small. The
  failure is a later `malloc` assertion, and only for generic fields wider than a
  word (`Box<String>`, `Box<(Int, Int)>`). The build-tree layout-2 stdlib makes
  it all agree.
- **A generic class still cannot be an Objective-C class object in this design.**
  `isa`/`name`/`methods`/`ivars` stay empty and the class is never registered;
  `ABIVersion` is what tells the runtime it is Swift metadata. Prespecialized
  generic metadata (`-prespecialize-generic-metadata`, used for the stdlib) is
  emitted the same way, with a null `isa` instead of a static metaclass. That is
  sufficient for the stdlib and for generic classes without an imported ObjC
  ancestor; the ObjC-ancestor case is S4b.

Gate: `swift-toolchain/scripts/verify-generic-abi.sh` (layout-2 compiler **and**
stdlib, built in the build tree by `build-layout2-stdlib.sh`). The S1 gate, the
language/runtime gate and both probes are also green against that same layout-2
stdlib.

**S4b result (2026-10-17).** The dynamic-class path of §3.2 is now used by the
runtime, for the case that needs it: a generic class with an *imported* ObjC
ancestor. `class Box<T>: NSObject` cannot have `@objc` members, but Swift
allocates it through `objc_allocWithZone` and sends `-init` through the ObjC
runtime, so its metadata must be a class object. What the pattern gained:

- the 17-word GNUstep metaclass in the extra data (only when
  `Target->getObjectModel() == ReferenceCounting::ObjC`; a pure Swift generic
  class still stays a metadata-only object, which keeps the stdlib's storage
  classes cheap);
- relative pointers to the class's `objc_method_list` and `objc_ivar_list`
  (built by `ClassDataBuilder`, shared across instantiations). The method list is
  not optional: `-init` is a Swift thunk, and without the list the allocator's
  `objc_msgSend(obj, init)` lands on `NSObject -init` and the stored-property
  initializers never run;
- `instance_size` is mirrored from Swift's `InstanceSize` into the ObjC word at
  completion, and `objc_loadClass_np()` registers the class and installs the
  dispatch tables.

The name has to be unique per instantiation (libobjc2 keys its class table by
name), so the runtime reuses Apple's `copyGenericClassObjCName()` - demangle the
metadata, remangle the type - and installs the buffer on the class and its
metaclass. Two bugs surfaced on the way: `initClassFieldOffsetVector` must start
from the superclass's *ObjC* `instance_size` when the superclass is imported (a
class with ObjC ancestry uses ObjC refcounting and has no inline Swift refcount
word), and the emitted `objc_ivar_list` had `size` and `flags` swapped.

The remaining gap is `deinit`: libobjc2's release path sends the typed
`dealloc_v16@0:8` selector, but Swift's emitted selector records are untyped, so
the typed lookup misses the class's `-dealloc` thunk and falls back to
`NSObject -dealloc` (the object is freed; the Swift destructor is not run). That
is §7.1, and it belongs with S5.

Gate: `swift-toolchain/scripts/verify-generic-objc-abi.sh`.

**S4c result (2026-10-17).** A class from a library-evolution module with an
imported ObjC ancestor has no statically emitted metadata: `ResilientClassMetadata`
is a pattern, and `swift_relocateClassMetadata()` builds the metadata on the heap.
It needs the same three things S4b needed, from static data:

- a **static metaclass** - the class is not generic, so
  `emitGNUstepMetaclassObject()` can define it (name, class-method list) and the
  pattern points at it;
- the class-side fields (`Name`, `InstanceMethods`, `Ivars`) in the pattern,
  because the GNUstep class object keeps them in the class itself;
- registration of the relocated metadata once `instance_size` is known.
  `_swift_initClassMetadataImpl` now registers any runtime-built class whose
  `isa` is non-null, and computes the per-instantiation name only when the class
  does not already have a static one.

One additional problem was *not* specific to the class object: a class whose
superclass layout is opaque at compile time is compiled against the superclass's
**minimum** size, and every stored-property access loads the real offset from a
mutable global. Layout 1 fills those globals in `initObjCClass()`; layout 2 had
nothing doing it, so a resilient class read its fields from the wrong offsets
(`var v = 2` returned the superclass's field). `initGNUstepClassFieldOffsets()`
now writes them back through the class's emitted `objc_ivar_list`, which is
therefore emitted for *every* relocated class, class object or not.

Boundary: a **prespecialized** generic class with an ObjC ancestor still has no
metaclass (null `isa`, as in S4) and is not registered. It is unreachable in this
toolchain - canonical metadata prespecialization only happens for the stdlib
module here (a user module compiled with `-O -prespecialize-generic-metadata`,
with or without library evolution, emits none), and the stdlib has no
ObjC-ancestry generic classes. If it becomes reachable, it needs a GNUstep
metaclass at `getAddrOfCanonicalSpecializedGenericMetaclassObject()`'s symbol and
a compile-time unique name; the failure mode until then is the pre-S4b
`objc_allocWithZone` trap.

A separate gap: the `Update`/`FixedOrUpdate` strategy (resiliently *sized* stored
fields) calls `swift_updateClassMetadata2`, which is compiled only at layout 1,
so such a class does not link at layout 0 either. That is orthogonal to class
objects and is recorded in the handoff's next steps.

### 6.0 Where the IRGen work attaches

*Status: the fixed/non-generic path (S1, handoff §2.7), generic classes without
ObjC ancestry (S4, handoff §2.8), runtime-instantiated generic classes with an
imported ObjC ancestor (S4b, handoff §2.9) and relocated resilient classes with
one (S4c, handoff §2.10) are implemented. The bullets below remain the map; the
outstanding entries are prespecialized generic classes with an ObjC ancestor
(unreachable today, see the S4c note), the `Update` strategy, and typed selector
records (S5, §7.1).*

- `lib/IRGen/MetadataLayout.h:168` `ClassMetadataLayout` computes `MetadataSize`,
  `MetadataAddressPoint`, `VTableOffset`, `FieldOffsetVector` and
  `NumImmediateMembers`. These derive from the ABI `TargetClassMetadata` type,
  which IRGen includes from the same C++ header the runtime uses — so once
  `SWIFT_OBJC_CLASS_LAYOUT=2`, the sizes follow automatically and only the
  *emission order* needs hand-editing.
- `lib/IRGen/GenMeta.cpp:4814` — the ordered field emission for class metadata
  (`addClassFlags()` / `addClassDataPointer()` call site); this is where the
  GNUstep header (`name`, `version`, `info`, `instance_size`, `ivars`, `methods`,
  `dtable`, …) and the moved Swift fields get emitted.
- `lib/IRGen/GenMeta.cpp` `ResilientClassMetadataBuilder::layout()`
  (`addClassDataPointer`, `addMetaclass`) — the resilient/generic pattern, which
  carries `ClassRODataOffset`/`MetaclassObjectOffset` and needs the analogous
  GNUstep offsets.
- `lib/IRGen/GenClass.cpp` `emitAndAddMethodList` / `emitRODataFields` — Apple
  `method_list_t`/`class_ro_t` emitters to be replaced by
  `struct objc_method_list` in `{imp, selector, types}` order, plus
  `objc_method`/`objc_ivar`/selector-table data.
- `lib/IRGen/Linking.cpp` — `objc_init` globals and the `__objc_load`
  constructor.

### 6.1a The emission order to transcribe (layout 2)

For a class and its metaclass, in this order (this is what `mini.s` emits and
what `probe3`/`probe4` proved dispatchable):

| # | field | value / source |
|---|---|---|
| 0 | `isa` | metaclass global; 0 in the metaclass object itself (runtime resolves) |
| 1 | `super_class` | superclass metadata; 0 in the metaclass object (runtime resolves) |
| 2 | `name` | emitted `\0`-terminated C string, shared by class and metaclass |
| 3 | `version` | `0` |
| 4 | `info` | `objc_class_flag_meta` (1) on the metaclass, `0` otherwise; the runtime owns the rest |
| 5 | `instance_size` | instance size in bytes (not Swift's `InstanceAlignMask` packing) |
| 6 | `ivars` | emitted `objc_ivar_list`, `NULL` for the metaclass — **not** `NULL` for a class with no ObjC ivars: libobjc2 replaces `instance_size` with the superclass's when the list is null (see §6 note) |
| 7 | `methods` | emitted `objc_method_list` (`next`, `count`, `size`, then `{imp, selector, types}` entries) |
| 8 | `dtable` | `0` — the runtime installs it |
| 9 | `subclass_list` | `0` — runtime |
| 10 | `cxx_construct` | `0` |
| 11 | `cxx_destruct` | `0` |
| 12 | `sibling_class` | `0` — runtime |
| 13 | `protocols` | emitted protocol list, or `0` |
| 14 | `extra_data` | `0` |
| 15 | `abi_version` | `3` |
| 16 | `properties` | emitted property list, or `0` |
| 17… | Swift fields | `Flags`, `InstanceAddressPoint`, `InstanceSize`, `InstanceAlignMask`, `Reserved`, `ClassSize`, `ClassAddressPoint`, `Description`, `IVarDestroyer`, then the immediate members (vtable, field-offset vector, generic args) |

Two details that the implementation settled:

- **The metaclass's own `isa`/`super_class` are emitted as 0.** Clang does the
  same for `-fobjc-runtime=gnustep-2.0`; `objc_resolve_class()` fills both in
  from the class object. The class's `isa` is the metaclass global.
- **`ClassAddressPoint`/`ClassSize` keep their Swift meaning.** The metadata
  allocation still starts with the layout-string/destructor/VWT prefix, so the
  address point (which is also the `Class` pointer) is 24 bytes into it and
  `ClassSize` is the whole allocation. libobjc2 never looks before the address
  point, and the Swift runtime never looks at the GNUstep header, so the two
  descriptions coexist. `MetadataSize` grows by the 17-word GNUstep header (net
  +14 words relative to Apple's 3-word cache/`Data` trio), which falls out of
  `ClassMetadataLayout` once the ABI type is the GNUstep variant — only the
  emission order above had to be written by hand.

### 6.1 The interop-code migration, as measured

Compiling each runtime translation unit with `-DSWIFT_OBJC_CLASS_LAYOUT=2`
(`Metadata.cpp`, `SwiftObject.mm`, `DynamicCast.cpp`, `Casting.cpp`,
`ReflectionMirrorObjC.mm`, `GNUstepObjCCompatibility.mm`, `MetadataLookup.cpp`,
plus the whole `swiftRuntimeCore` and the compiler build) reduced the change set
to **four files and five edits** — far smaller than the ~50 sites the earlier
grep-based estimate suggested, because almost all interop code reads class
metadata through `TargetClassMetadata`/accessors rather than the Apple-only
header fields:

| File | Change |
|---|---|
| `include/swift/ABI/Metadata.h` | `TargetMetadata::getObjCClassObject()` re-types via `void*` instead of `const_cast` to Apple's header; new `TargetObjCClassWrapperMetadata::getClass()` accessor returning the layout-selected metadata type |
| `stdlib/public/runtime/DynamicCast.cpp` | `destObjCType->Class` → `->getClass()` |
| `stdlib/public/runtime/Casting.cpp` | 2 sites → `->getClass()` |
| `stdlib/public/runtime/Private.h` | `getClassObject()` → `wrapper->getClass()` |

New machinery: `SWIFT_OBJC_CLASS_LAYOUT` and `SWIFT_GNUSTEP_CLASS_ABI_VERSION`
(`Runtime/Config.h`), `ObjCClassLayout` on `InProcess`/`External`/
`WithObjCInterop`/`NoObjCInterop` (`ABI/TargetLayout.h`), three-way selection in
`ABI/MetadataRef.h`, and `TargetAnyClassMetadataGNUstep` in `ABI/Metadata.h`
(17 words mirroring `libagora-objc/class.h`, then the Swift fields, with
`isTypeMetadata()` = `ABIVersion == 3`).

Verification: default layout still builds the whole toolchain green
(`build67.log`, 0 errors) and `swiftc --version` works; every TU above compiles
with layout 2; the only remaining step to activate it is IRGen emitting the same
layout plus the `objc_init` registration, and flipping the default in
`Runtime/Config.h`.

## 7. Open questions / risks

1. **Type encodings — measured, and they are not just introspection.** Swift
   computes Apple-style encodings for its methods, but two things are missing
   today: a generic initializer's encoding is **null** (the result type cannot be
   represented as a Clang type), and the emitted GNUstep *selector records* are
   **untyped** (one record per name, `__objc_selectors`, types = null). libobjc2
   dispatches typed selectors by their type, so its own release path - which
   sends `dealloc_v16@0:8` - does not find a Swift class's `-dealloc` thunk and
   falls back to `NSObject -dealloc`. That is why `deinit` is skipped for Swift
   classes with ObjC ancestry (S5). The fix is to emit typed selector records
   keyed by (name, encoding) and give initializers a real encoding; untyped
   sends (`sel_registerName`) keep working as the fallback. KVC/KVO and
   `NSInvocation` read the same strings.
2. **Selector table (optimisation, not a blocker).** `sel_registerName()` is
   sufficient for dispatch (proven by `probe3`/`probe4`), so an emitted
   `__objc_selectors` table like clang's is optional. It is still worth doing
   later: it lets method lists stay in read-only data and avoids one
   registration call per selector.
3. **Superclass as a name.** The v2 ABI allows `super_class` to be a *class name*
   until resolved; a Swift-emitted subclass of a Swift class could use the direct
   pointer, but cross-image (Swift class subclassing an imported ObjC class) must
   follow whatever libobjc2 expects from clang.
4. **Metaclass roots.** `objc_resolve_class()` expects the root class's metaclass
   to be self-`isa`; Swift's root is `SwiftObject`, and `NSObject` bridging needs
   the root-class chain to line up with Agora's `NSObject`.
5. **`+load`/`+initialize`** will now actually run for Swift classes — Swift's
   existing lazy-initialization must not fight the runtime.
6. **Resilient/generic class patterns** (`GenericClassMetadataPattern`) carry
   `MetaclassObjectOffset`/`ClassRODataOffset` today; those fields are Apple-ABI
   specific and must be replaced by the new layout's offsets. S4 sidesteps this
   for generic classes by emitting *no* extra data at layout 2 (nothing in the
   stdlib needs it); a resilient class with imported ObjC ancestry would still
   need the S4b machinery, and library evolution is not used by the stdlib.
7. **Swift's `-class_method` dispatch is unaffected** (it uses its own vtable
   offsets, not `dtable`), which is what makes this design viable at all — worth
   keeping as an invariant in review.

## 8. Reproduce

`swift-interop-probe/` is listed in `.gitignore` (it holds local probes), so
these files live in the working tree only, like the two earlier probes.

```sh
cd swift-interop-probe/class-abi
A=/home/kyle/Development/Agora
for p in probe probe2 probe3 probe4; do
  gcc -g -O0 -I$A/build-prefix/include $p.c -o $p -L$A/build-prefix/lib -lobjc -lBlocksRuntime
done
LD_LIBRARY_PATH=$A/build-prefix/lib ./probe   # registration OK, dispatch crashes on NULL dtable
LD_LIBRARY_PATH=$A/build-prefix/lib ./probe2  # both dispatches OK (canonical public path)
LD_LIBRARY_PATH=$A/build-prefix/lib ./probe3  # loader path: fully works (+load delivery included)
LD_LIBRARY_PATH=$A/build-prefix/lib ./probe4  # dynamic path via objc_loadClass_np: fully works

# clang's reference emission for the target ABI
~/.agora-swift/bootstrap/usr/bin/clang -target x86_64-unknown-linux-gnu \
  -fobjc-runtime=gnustep-2.0 -I$A/build-prefix/include -S -o mini.s mini.m
```

**The S1 gate, with the compiler emitting the ABI** (the script builds a
frontend-only layout-2 compiler against the installed stdlib, then checks the
class from C):

```sh
swift-toolchain/scripts/verify-class-abi.sh
```

It prints `S1 gate: ok (registered, name/methods visible, +load delivered,
dispatch = 42/7, ivar offset = 8 and readable both ways)`. `swift-toolchain/scripts/build-layout2-frontend.sh` on its
own leaves `bin/swiftc-layout2` in the build tree so individual programs can be
compiled against the destination ABI; a *full* `AGORA_SWIFT_CLASS_LAYOUT=2`
`build-swift-toolchain.sh` is the S4→S6 experiment. The S4 gate on its own is
`swift-toolchain/scripts/verify-generic-abi.sh`, which builds the layout-2
frontend and stdlib in the build tree (via `build-layout2-stdlib.sh`) without
touching the installed toolchain.
