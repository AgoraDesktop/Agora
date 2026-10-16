# A Swift compiler that targets Agora — and GNUstep only for libobjc2

*Goal: a Swift toolchain whose Objective-C platform is Agora, and whose only
GNUstep dependency is the runtime Agora already ships (`libagora-objc`,
libobjc2 v2.3). No GNUstep Foundation, no GNUstep make, no GNUstep corebase.*

Companion to `SWIFT-INTEROP-INVESTIGATION.md`.

---

## Verdict

**Yes — and it is smaller than it looks, because the OpenSwiftProject fork was
already written to tolerate a non-GNUstep Foundation.**

Three facts decide it:

1. **GNUstep's only load-bearing contribution to the Swift toolchain is
   libobjc2** — which Agora ships. Everything else GNUstep
   (`tools-make`, `libs-base`, `libs-corebase`) exists for OpenSwiftProject's
   *demo*, not for building Swift. Evidence below.
2. **libswiftCore needs a Foundation header surface at build time**, but the fork
   already made that surface Foundation-agnostic with `__has_include` fallbacks.
   Agora provides every header in that surface.
3. **`<objc/NSObject.h>` — the one header Agora does not ship — is exactly the
   one the fork falls back on.** No shim is required.

What remains genuinely non-Agora is libdispatch's Swift overlay (Agora's own
dispatch has Swift support deleted) and `swift-corelibs-foundation` for the Swift
*tools*. Neither is GNUstep.

## 1. What the Swift build actually takes from GNUstep

`OpenSwiftProject/toolchain-docker/scripts/build-gnustep-baseline.sh` builds five
things into `$GNUSTEP_PREFIX`: libobjc2, swift-corelibs-libdispatch,
`tools-make`, `libs-base`, `libs-corebase`.

`build-swift-toolchain.sh` — the script that actually builds Swift — **contains
no reference to `$GNUSTEP_PREFIX` or to any GNUstep repository.** It builds
Swift against whatever `libobjc2` and headers are on the ambient paths
(`CPATH`, `LIBRARY_PATH`, `LD_LIBRARY_PATH`), which the Dockerfile sets to the
GNUstep prefix *as a convenience*:

```
ENV CPATH=/opt/openswift/gnustep/include:/opt/openswift/gnustep/include/GNUstep
ENV LIBRARY_PATH=/opt/openswift/gnustep/lib
```

So:

| GNUstep artifact | Needed to build Swift? |
|---|---|
| libobjc2 | **Yes** — linked by libswiftCore; Agora already ships it |
| swift-corelibs-libdispatch | It is not GNUstep (Apache-2.0); needed, and Agora's copy is Swift-stripped |
| tools-make | No — demo only |
| libs-base (GNUstep Foundation) | No — demo only; supplies the `<Foundation/…>` headers today |
| libs-corebase | No — demo only |

**The whole GNUstep Foundation stack is a build-time include path, not a
dependency of the compiler.**

## 2. The exact Foundation surface libswiftCore needs

With `SWIFT_STDLIB_ENABLE_OBJC_INTEROP`, the runtime compiles five Objective-C
sources (`stdlib/public/runtime/CMakeLists.txt`, `swift_runtime_objc_sources`):
`ErrorObject.mm`, `SwiftObject.mm`, `SwiftValue.mm`, `ReflectionMirrorObjC.mm`,
`ObjCRuntimeGetImageNameFromClass.mm`.

The headers they require are a short, fixed list:

| Header | From | Agora ships? |
|---|---|---|
| `<objc/runtime.h>`, `<objc/message.h>`, `<objc/objc.h>`, `<objc/objc-arc.h>` | the runtime | **yes** (`build-prefix/include/objc/`) |
| `<objc/NSObject.h>` | Apple runtime | **no** — but see below |
| `<Foundation/NSObject.h>` | Foundation | **yes** |
| `<Foundation/Foundation.h>` | Foundation | **yes** |
| `<CoreFoundation/CFBase.h>` (`CFTypeID`) | CoreFoundation | **yes** |
| `<dispatch/dispatch.h>` | libdispatch | **yes** |
| `<malloc.h>` / `<malloc/malloc.h>` | libc | system |

`SwiftObject.mm` matters most: it defines the ObjC root class for pure Swift
classes, conforms it to the `NSObject` protocol, and does
`[NSObject class]` for `getNSObjectMetadata()`; `getNSStringMetadata()` uses
`objc_lookUpClass("NSString")`. `ReflectionMirrorObjC.mm` includes
`<Foundation/Foundation.h>` directly. So **libswiftCore is inherently bound to
some Foundation** — on Darwin, Apple's; on OpenSwiftProject, GNUstep's; on Agora,
yours.

### The fork already made this Foundation-agnostic

`OpenSwiftProject/swift` `feature/gnu_objc_6.3` patches exactly these includes
(`stdlib/public/runtime/SwiftObject.mm`, `SwiftObject.h`, `ErrorObject.mm`,
`HeapObject.cpp`):

```objc
#if SWIFT_OBJC_INTEROP
#if __has_include(<objc/NSObject.h>)
#include <objc/NSObject.h>
#elif __has_include(<Foundation/NSObject.h>)
#import <Foundation/NSObject.h>
#endif
```

and

```objc
-# include <malloc/malloc.h>
+# if __has_include(<malloc/malloc.h>)
+#  include <malloc/malloc.h>
+# elif __has_include(<malloc.h>)
+#  include <malloc.h>
+# endif
```

plus a non-Apple `- (struct _NSZone *)zone { return nullptr; }`.

**That is the whole reason a non-GNUstep Foundation can be substituted:**
Agora has `Foundation/NSObject.h`, so `__has_include` takes the second branch and
never needs `<objc/NSObject.h>` at all. Agora's headers were already proven to
compile under clang with `-fobjc-runtime=gnustep-2.0` (see
`swift-interop-probe/`).

## 3. What changes to drop GNUstep

1. **Replace `build-gnustep-baseline.sh` with a runtime-baseline script** that
   builds only libobjc2 + libdispatch — or, better, uses Agora's already-built
   libobjc2 (`build-prefix/lib/libobjc.so.4.6`) and builds only a Swift-enabled
   libdispatch. Delete the `tools-make`, `libs-base`, `libs-corebase` clones and
   steps (`clone-sources.sh`, `build-gnustep-baseline.sh`).
2. **Point the include/link paths at Agora** instead of the GNUstep prefix:
   ```
   CPATH=$AGORA_PREFIX/include
   LIBRARY_PATH=$AGORA_PREFIX/lib
   LD_LIBRARY_PATH=$AGORA_PREFIX/lib
   ```
   That single swap is what makes `#import <Foundation/Foundation.h>` resolve to
   Agora's Foundation.
3. **Keep** `SWIFT_STDLIB_ENABLE_OBJC_INTEROP=TRUE`, `--swift-objc-interop=1`, and
   `-Xfrontend -objc-runtime-vendor=gnustep` — the vendor name is just libobjc2's
   ABI, which Agora already emits (`-fobjc-runtime=gnustep-2.0`).
4. **Optionally rename the vendor to `agora`** for cosmetics. Functionally it is
   the same ABI; the `GNUstepObjCCompatibility.mm` runtime shims
   (`objc_readClassPair`, `_objc_realizeClassFromSwift`, …) are shims for
   **libobjc2**, and the user's "the runtime we already ship" covers them.
5. **Keep `swift-corelibs-foundation`** only if you want SwiftPM / `swift test`.
   It is Apache-2.0, not GNUstep, and is used by the Swift *tools*; it is not the
   Foundation Agora programs link against.

The resulting dependency set:

- LLVM/clang (Apache-2.0)
- Swift sources (Apache-2.0)
- **libobjc2 = Agora's** (MIT)
- swift-corelibs-libdispatch with Swift overlay (Apache-2.0)
- Agora's Foundation/CoreFoundation headers + libraries
- *(optional)* swift-corelibs-foundation, for the Swift tools only

No GNUstep beyond libobjc2.

## 4. The libdispatch problem is separate and still real

Agora's `libagora-dispatch` has its Swift support deleted; the Swift stdlib and
concurrency need the `Dispatch` module from a Swift-enabled libdispatch
(`src/swift/CMakeLists.txt` in swift-corelibs-libdispatch). So the toolchain must
build libdispatch with `ENABLE_SWIFT`. That is Apache-2.0 software Agora already
uses, not GNUstep — but Agora currently ships a Swift-stripped copy, so the
Swift-enabled libdispatch and Agora's `libagora-dispatch` must be the same
library at runtime (one dispatch state per process). This is unchanged from the
earlier analysis.

## 5. First check: run, and it found the one Agora-side change

The decisive pre-build check is whether Agora's headers satisfy the ObjC/C++
surface `SwiftObject.mm` needs. Run with clang 19 against `build-prefix/include`:

**a) `NSObject` protocol conformance — passes.** Agora's `@protocol NSObject`
requires `hash`, `description`, `debugDescription`, `isEqual:`, `superclass`,
`class`, `self`, `isProxy`, `isKindOfClass:`, `isMemberOfClass:`,
`conformsToProtocol:`, `respondsToSelector:`, `retain`, `release`, `autorelease`,
`retainCount`, `performSelector:` and its two variants. `SwiftObject.mm`
implements every one. Agora even makes `-superclass` nullable, which is exactly
what the Swift runtime's root class needs.

**b) Objective-C++ cleanliness — fails, and this is the one Agora-side patch.**
The stdlib compiles the ObjC interop sources as Objective-C++ (`.mm`).
`Foundation/Foundation.h` → `NSGeometry.h` → `CoreGraphics/CGBase.h` →
`CoreFoundation/CoreFoundation.h` → `ForSwiftFoundationOnly.h`, and that chain
hits C++-only errors. The **complete** barrier set, found by iteration:

| # | File | Problem | Fix |
|---|---|---|---|
| 1 | `libagora-core/CoreFoundation/ForSwiftFoundationOnly.h` | `_stat_with_btime`'s `(struct stat){…}` C99 designated initializer narrows `__u64`→`off_t`/`blkcnt_t`; an error in C++ | cast `(off_t)` / `(blkcnt_t)`, or a `#ifdef __cplusplus` path |
| 2 | `libagora-base/NSDateFormatter.h` | parameter named `template` (C++ keyword), 2 sites | rename the *parameter* to `aTemplate` — selector and ABI unchanged |
| 3 | `libagora-base/NSRegularExpression.h` | parameter named `template`, 2 sites | same |

With exactly these three applied, Agora's Foundation umbrella compiles clean as
Objective-C++ (`exit 0`). Nothing else in the umbrella conflicts with C++. **That
is the whole port on the Agora side: three headers, all API-preserving.** (For a
first build, `-Wno-c++11-narrowing` covers #1 as a stopgap; #2/#3 need the
rename.)

### Still to verify once a build is attempted

3. **What does libswiftCore link for `NSObject`?** Whether `[NSObject class]`
   becomes a hard `NEEDED` on `libagora-base` or a weak reference — either is
   acceptable, but know which.
4. **The `ObjectiveC` overlay** (`Selector`, `#selector`) is still not built for
   Linux (OpenSwiftProject/swift#1). Unrelated to GNUstep, still open.
5. **Swift-defined `@objc` classes / subclasses** remain outside the fork's
   scope entirely (`docs/GNUstepClassSymbols.md`). The toolchain swap does not
   change that.

## 6. Bottom line

"Build Swift against Agora, with no GNUstep but the runtime" is a **build
re-targeting**, not a port:

- the compiler and stdlib are already Foundation-agnostic through the fork's
  `__has_include` guards;
- the only GNUstep header dependency (`<Foundation/…>`) is satisfied by Agora's
  own headers;
- the only GNUstep artifact that is genuinely load-bearing is libobjc2, which
  Agora ships;
- the remaining non-Agora pieces (Swift-enabled libdispatch, swift-corelibs
  Foundation for the tools) are not GNUstep.

The pre-build check is done (§5): Agora's `NSObject` protocol satisfies
`SwiftObject.mm` completely, and the umbrella is Objective-C++-clean once three
headers are adjusted — two parameter renames and one cast. Everything else is
build plumbing already proven to work.
