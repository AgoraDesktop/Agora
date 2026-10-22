# Cocoa 10.11 — the plan to match the API surface

*Status: **plan.** This document says what "match the API surface of OS X 10.11" means for Agora's four
Objective-C/Cocoa frameworks — Foundation, Core Graphics, Core Text and the Application Kit — measures the
gap against the 10.11 SDK today, chooses the policy for the parts that cannot be implemented, and stages the
work with a gate that makes progress checkable. Nothing here is scheduled; the size classes are
order-of-magnitude, not commitments.*

*"Mac OS X 10.11" in the request is Apple's **OS X 10.11** (El Capitan); the SDK is `MacOSX10.11.sdk`. The
name is used as the user wrote it where a version is being named, and "10.11" everywhere else.*

---

## 0. The verdict

**The target is right; the premise that this is primarily an "update to 10.11" is wrong.** Measured against
the 10.11 headers, the tree is missing **211 classes**, **88 protocols** and **455 C functions** across the
four frameworks. But **137 of those classes, 36 of the protocols and 388 of the functions were already in
10.6.** On classes that already exist, the first pass also finds **1,057 selectors** Apple declares and the
tree does not (Foundation 289, AppKit 768). The largest part of the work is not the 10.7–10.11 delta at all:
it is the **10.6 surface this tree never finished**.

```
                      missing from the four frameworks
      ┌──────────────────────────────────────────────────────────────┐
      │  owed from 10.6            │  new in 10.7–10.11             │
      │  classes      137          │  classes       74              │
      │  protocols     36          │  protocols     52              │
      │  functions    388          │  functions     67              │
      └──────────────────────────────────────────────────────────────┘
```

That split changes the plan in three ways:

1. **"Add 10.11" would produce a façade.** Adding `NSStackView` and `NSCollectionViewLayout` while
   `NSOpenPanel`, `NSSavePanel`, `NSPredicate`, `NSProgress` and `NSDocument` are still absent
   would satisfy a name list and fail every real client. Completeness comes first. (`NSWorkspace`,
   `NSRunningApplication` and `NSDockTile`'s data half are no longer on that list: they landed in
   `libagora-app` over Launch Services, Icon Services and the window server's window list, with the
   deviations `NSRunningApplication.h` states at their doors.)
2. **The work is not uniform across the four frameworks.** Core Text is one 10.6 function away from its old
   baseline and 31 functions from 10.11; Core Graphics is missing 280 functions that 10.6 already had, almost
   all of them the display/event/PDF half rather than drawing. Foundation's gap is dominated by scripting
   (37 classes); AppKit's by panels, documents, controls and accessibility. The plan is shaped by that, not
   by a single "Cocoa 10.11" bucket.
3. **10.11 is a declaration target, not a behavioural promise.** "Surface" means a program written against
   the 10.11 headers compiles, links and reaches a door that either does the documented thing or **refuses by
   name**. Pretending to implement AppleEvents, XPC or OpenGL would be worse than refusing them.

**The plan therefore has two milestones.** **M1 — declared:** every 10.11 macOS public name exists, is annotated,
and is implemented or explicitly refused. **M2 — behavioural:** the doors the applications and the Workspace
actually use do the documented thing, with the remaining refusals documented and tested. M1 is the
commitment of this plan; M2 is staged behind it and is where most of the time goes.

---

## 1. What "match the API surface" means

Five things are part of the surface. Binary compatibility is deliberately not.

| Tier | What it covers | Measured by |
|---|---|---|
| **S1 — declarations** | Headers, classes, protocols, categories, properties, methods, C functions, typedefs, enums, constants, umbrella imports, and the header each name is declared in | name-and-signature ledger against the 10.11 SDK |
| **S2 — annotations** | `NS_AVAILABLE`, `NS_DEPRECATED`, `API_AVAILABLE`, nullability (`nullable`/`nonnull`/`NS_ASSUME_NONNULL`), lightweight generics, `__kindof`, `instancetype`, designated initializers, `NS_UNAVAILABLE`, ownership (`NS_RETURNS_RETAINED`, `CF_RETURNS_RETAINED`, `NS_CONSUMED`), `NS_SWIFT_NAME` | clang AST + a header-compile gate |
| **S3 — runtime shape** | The class exists, has the right superclass and protocols, and answers the selectors it should (including inherited ones); every non-inline C function is an exported symbol | runtime class/selector probe + `nm -D` |
| **S4 — behaviour** | The door does what Apple documents, or refuses by name with a documented failure; a refusal is a supported outcome, silent success is not | per-door tests + the refusal census |
| **S5 — source compatibility** | An Objective-C program written against the 10.11 headers builds against the tree; a Swift importer can see the classes; an ARC client can compile against the headers | compile tests (ObjC, ObjC++, ARC) + a Swift import smoke test |

**Not part of the surface: binary compatibility.** Agora does not reproduce Apple's class layouts, ivars,
ABI, Objective-C runtime version, or dyld behaviour. A binary built against Apple's frameworks will not run
against Agora's. Source compatibility — the property the project README already claims — is the contract.

**Why 10.11, and not 10.6 or 10.13.** 10.11 is the last SDK before the Swift 3 renaming (10.12): its
Objective-C names are the classic Cocoa names this tree's clients already spell, it carries availability
and nullability annotations throughout, and it is the newest point at which the four frameworks' surfaces
are still recognisably the Cocoa surface the tree was built against. 10.12+ adds the Swift 3 names, and
later releases add the Touch Bar, Dark Mode and the rest; that is a separate expansion, not this one.

**Also not in scope:** the iOS-only declarations in the 10.11 headers (`API_UNAVAILABLE(macos)` /
`NS_AVAILABLE_IOS`-only doors), private API, and 10.12+ APIs. The tree already has a handful of post-10.11
classes (`NSDateInterval`, `NSISO8601DateFormatter`, `NSRelativeDateTimeFormatter`,
`NSSecureUnarchiveFromDataTransformer`, …). They stay as **extensions**, annotated with the version they
really arrived in, and a strict 10.11 build can hide them (§4.1).

### 1.1 The four dispositions

Every name in the ledger gets exactly one:

| Disposition | Meaning | Allowed when |
|---|---|---|
| **implemented** | The documented behaviour, tested | the subsystem exists or can be backed |
| **adapted** | The documented contract through a different backing, with the deviation written down | the platform equivalent is not the same mechanism (e.g. `NSWorkspace` over Agora's launch services, not Launch Services) |
| **refused** | Declared, annotated, and calling it produces a named, documented failure | the backing is genuinely absent (XPC, AppleScript execution, OpenGL, physical printers) |
| **unavailable** | Declared `NS_UNAVAILABLE` / `API_UNAVAILABLE` and not callable | the declaration is iOS-only or has no meaning on Agora |

An **omitted** 10.11 macOS name is a bug, not a disposition. The only omissions allowed are names that are
not part of the macOS surface of that SDK (iOS-only declarations), and the ledger carries the exemption with
the reason.

---

## 2. The reference and the measurement

### 2.1 Reference

The 10.11 headers are fetched from the same mirror the tree already uses for 10.6
(`phracker/MacOSX-SDKs`), and **the headers are not committed** — the SDK is not redistributable. What is
committed is the recipe and the generated **name manifest**, which is a list of facts (names, versions,
selectors), not Apple's expression of them.

The tree's own reference today is 10.6: `libagora-text`'s README says it is "written from scratch against
Apple's own 10.6 headers", and `libagora-app`'s era pins are 10.2/10.5/10.6. The 10.11 SDK is therefore a
**new** reference, not a replacement for an existing 10.11 one, which is why the 10.6 debt shows up in the
measurement.

```
BASE=https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.11.sdk/System/Library/Frameworks
# Foundation and AppKit are Versions/C/Headers; Core Graphics and Core Text are Versions/A/Headers.
# CoreGraphics.framework/Headers and CoreText.framework/Headers are symlinks in the 10.11 SDK, so a
# GitHub contents listing of them returns one entry ("Headers"); request Versions/A/Headers directly.
```

Measured on 2026-10-19, the 10.11 SDK's four frameworks carry:

| Framework | Headers fetched | Classes | Protocols | C functions | Notes |
|---|---:|---:|---:|---:|---|
| Foundation | 156 | 217 | 40 | 191 | includes the scripting/AppleEvents, URLSession, XPC, metadata and notification families |
| Core Graphics | 44 | 0 | 0 | 636 | includes display, event, PDF, window and display-stream headers |
| Core Text | 21 | 0 | 0 | 186 | includes the 10.7+ font-collection/manager/ruby surface |
| AppKit | 233 | 216 | 100 | 92 | includes accessibility, OpenGL, printing, documents, cells and the 10.11 collection-view stack |

`NSObject` and `NSProxy` live in the Objective-C runtime headers imported by Foundation, not in Foundation's
own headers. The ledger must attribute them to `libagora-objc`, or it will report a false Foundation gap.

### 2.2 The instrument (Phase 0)

The numbers in this document are a **first pass from a regex extractor** (`@interface`, `@protocol`,
method-looking lines, exported C declarations). It is good enough to size the work and it is **not good
enough to be the gate**: it misses inline functions, merges categories into classes inconsistently, and
cannot see inheritance. Phase 0 replaces it with four instruments, all checked in:

| Instrument | Job | Why it cannot be a regex |
|---|---|---|
| **`tools/api-ledger`** | Extract declarations + signatures + annotations from a header tree; emit a normalized manifest | needs a real parser for nullability, generics, property attributes, `instancetype`, block types and availability |
| **`api-check`** | Diff local vs 10.11 manifest **in both directions**, per header and in total | catches a door quietly disappearing as well as one quietly appearing |
| **`runtime-surface`** | For every 10.11 class: `NSClassFromString`, superclass, adopted protocols, and every selector answered (including inherited) | inheritance and class clusters are invisible in headers |
| **`symbol-check`** | Every non-inline C function declared is exported (`nm -D --defined-only`) | a declaration without a definition is a linker error waiting for a client |

The ledger is built with clang (libclang or `-Xclang -ast-dump=json`) for the local headers. The reference
side is normalized from the fetched 10.11 headers with the same declaration grammar; where the reference
cannot be parsed cleanly, the name is listed for manual review rather than silently dropped. The manifest
records, per name: kind, header, signature, introduced version, deprecated version, nullability, and
ownership. **It is committed; the reference headers are not.**

**Measured caveat, so the numbers are read correctly.** The first-pass counts include a few artifacts:
`size_t` and `void` from a malformed CG declaration, `NSMakeRange`/`NSMaxRange` (inline in 10.11 and
macros here), and some functions declared in a header different from the one the name was attributed to.
The ledger's first job is to remove those from the count, not to preserve them. The class and protocol
counts are the reliable part of the measurement; the function counts are ±a few.

### 2.3 The baseline, measured today

| Framework | Unit | 10.11 | local | missing | **owed from 10.6** | **new in 10.7–10.11** |
|---|---|---:|---:|---:|---:|---:|
| Foundation | classes | 217 | 154 | 73 | **46** | 27 |
| Foundation | protocols | 40 | 29 | 13 | **3** | 10 |
| Foundation | functions | 191 | 201 | 33 | **31** | 2 |
| Core Graphics | functions | 636 | 333 | 309 | **280** | 29 |
| Core Text | functions | 186 | 154 | 32 | **1** | 31 |
| AppKit | classes | 216 | 84 | 138 | **91** | 47 |
| AppKit | protocols | 100 | 27 | 75 | **33** | 42 |
| AppKit | functions | 92 | 16 | 81 | **76** | 5 |
| **Total** | classes | — | — | **211** | **137** | **74** |
| **Total** | protocols | — | — | **88** | **36** | **52** |
| **Total** | functions | — | — | **455** | **388** | **67** |

Selectors on classes the tree already has, and categories (first pass; see §2.4):

| Framework | Unit | 10.11 | local | missing |
|---|---|---:|---:|---:|
| Foundation | declared method selectors | 2612 | 3065 | 289 on shared classes |
| Foundation | categories | 157 | 28 | 129 |
| AppKit | declared method selectors | 4066 | 2729 | 768 on shared classes |
| AppKit | categories | 231 | 10 | 221 |

**These are first-pass numbers.** The function counts include the parser artifacts documented in §2.2 and
Appendix A.3 (the largest is Foundation's seven inline/macro hits and Core Graphics' two malformed
declarations); the class and protocol counts are the reliable part. The ledger in Phase 0 replaces this table
and the totals are re-derived from it.

The local function count for Foundation exceeds 10.11 because it includes Agora's private `fn_*` and
`plist_*` helpers; the ledger excludes non-public names. The local class count includes Agora's
`NSOwnedString` and `NSTinyString` (extensions) and is therefore not a coverage measure by itself.

**Headers missing entirely** (name-level; some local headers combine several Apple headers and some Apple
headers are umbrella/split files, so this table is about API families, not file count):

| Framework | 10.11 headers | present locally | missing | what the missing headers are |
|---|---:|---:|---:|---|
| Foundation | 156 | 112 | 44 | scripting/AppleEvents, URLSession, XPC, metadata, notifications, predicates, item providers/extensions, progress, formatters, plus `NSRange.h`, `NSZone.h`, `NSDebug.h`, `NSPathUtilities.h` and the XML/plist/error split headers |
| Core Graphics | 44 | 18 | 26 | display (4), display stream (1), events (3), PDF (12), window/session (2), PS converter (1), Metal (1), palette/error/umbrella (3) |
| Core Text | 21 | 17 | 4 | `CTDefines.h`, `CTRubyAnnotation.h`, `SFNTLayoutTypes.h`, `SFNTTypes.h` |
| AppKit | 233 | 80 | 153 | 11 accessibility, 19 document/controller, 18 panel/print, 16 collection/layout, 14 text/typesetter, 13 gesture/appearance, 12 legacy/OpenGL, and the rest controls, fonts, images and scripting categories |

### 2.4 Selectors and categories

**The class-level counts are not the whole surface.** A 10.11 client also expects the methods a class already
has, and Apple declares many of them in categories rather than on the class. The first pass finds **289
missing selectors on Foundation classes the tree already has and 768 on AppKit classes** — a figure larger
than the class gap and much more evenly spread. The largest AppKit examples are `NSTextView` (100
Apple selectors, 12 declared locally, 100 names differ — the local class inherits most of its editing
surface from `NSText`), `NSLayoutManager` (111/34, 93 differ), `NSResponder` (156/92, 74), `NSView`
(184/235, 62 — the local class declares more, so raw counts are not a coverage measure), and `NSWindow`
(137/248, 34). Foundation's are smaller but real: `NSObject` (98/98, 84 differ), `NSMutableCharacterSet`
(26/7, 19), `NSOrderedSet` (57/44, 13), and the XML classes.

**These numbers are a warning, not a work list.** The regex method extractor does not resolve inheritance,
does not merge a class's categories into the class, and treats a method declared in a category as missing
when it is declared on the class elsewhere. The Phase 0 ledger must:

- union every class and its categories into one selector set before diffing;
- run the selector probe at runtime (`respondsToSelector:` on an instance and the class object), so an
  inherited method counts as present;
- record the selector's full signature, not just its name, because `-initWithFrame:` and
  `-initWithFrame:flag:` are different doors.

**Categories are also headers.** Apple's 10.11 AppKit has 231 categories against 10 here, and Foundation 157
against 28. Many are partitions of methods the tree already declares on the class (e.g.
`NSString(NSStringCreation)`), and merging them into the class before diffing is correct. But the
*behavioural* categories — the scripting categories (`NSApplicationScripting`, `NSDocumentScripting`,
`NSWindowScripting`, `NSTextStorageScripting`), the accessibility categories, the deprecated-method
categories, and the `NSFileWrapper`/`NSBundle`/`NSNib` additions — are separate headers a client imports.
The plan creates or folds them per the Foundation and AppKit waves; the ledger records the category name and
its selector set, not just the class.

### 2.5 The annotation gap, which is part of the surface

10.11 is the last classic-Objective-C SDK, and its headers carry the availability and nullability facts
that make the surface usable by clang, ARC and Swift:

| Annotation | Foundation 10.11 | Foundation local | AppKit 10.11 | AppKit local |
|---|---:|---:|---:|---:|
| `NS_AVAILABLE` | 1214 | 5 | 1757 | **0** |
| `NS_DEPRECATED` | 206 | 5 | 569 | **0** |
| `nullable` | 1372 | 1522 | 1950 | 1228 |
| `__kindof` | 3 | 1 | 67 | **0** |
| `NS_DESIGNATED_INITIALIZER` | 182 | **0** | 49 | **0** |
| `NS_UNAVAILABLE` | 12 | 1 | 4 | **0** |

The local availability macros are **inert by design** (`NSObjCRuntime.h`, D12: "the bodies do nothing").
That was a defensible choice while there was no reference version; at 10.11 it is no longer one, because a
client cannot tell a 10.11 door from a 10.0 door and the Swift importer cannot see availability at all.
Tested on this host: clang 19 accepts `__attribute__((availability(macosx,introduced=10.11)))` on Linux,
records it in the AST, and emits no warning; it also accepts the attribute on methods and properties. The
plan therefore makes the attributes real and checks them in the AST, rather than leaving them empty.

---

## 3. The shape of the gap

This is the section that decides the order of the work.

### 3.1 Foundation — dominated by scripting, then networking

The 73 missing classes fall into these piles:

| Pile | Classes | 10.6 or new | Disposition |
|---|---:|---|---|
| Scripting / AppleEvents (`NSScript*`, `NS*Command`, `NS*Specifier`, `NSAppleEvent*`, `NSAppleScript`, `NSClassDescription`, `NS*Test`, `NSUser*ScriptTask`) | 37 | 10.6 | **refused** (data types implemented where useful; execution refuses) |
| URLSession / networking (`NSURLSession*`, `NSURLComponents`, `NSURLQueryItem`, `NSNetServiceBrowser`) | 10 | new | implemented; URLSession is the largest subsystem |
| XPC (`NSXPC*`) | 4 | new | **refused** on Linux; no Mach services, no launchd |
| Metadata (`NSMetadata*`) | 4 | 10.6 | implemented over a metadata provider (Spotlight is absent; see §6.1 F3) |
| Predicates (`NSPredicate`, `NSExpression`, `NSComparisonPredicate`, `NSCompoundPredicate`) | 4 | 10.6 | implemented; they gate metadata and AppKit's predicate editor |
| Notifications (`NSUserNotification*`), extensions/item providers, progress, formatters, `NSCondition`, `NSFileAccessIntent`, `NSSimpleCString`, `NSGarbageCollector` | 14 | mixed | implemented or declared/refused individually |

`NSProgress` and `NSCondition` are small, but `NSProgress` is the reporting spine that several other
subsystems (URLSession, FileCoordinator, extension requests) name. `NSPredicate` is the query language that
`NSMetadataQuery` and `NSPredicateEditor` need. Those two are early.

### 3.2 Core Graphics — the drawing core is nearly done; the screen half is not

309 missing functions, grouped by header:

| Header | Missing | What it is | 10.6 or new |
|---|---:|---|---|
| `CGDirectDisplay.h` | 49 | display enumeration, modes, capture, cursor, transfer tables | 10.6 (2 new: pixel width/height) |
| `CGDisplayConfiguration.h` | 33 | display configuration, mirroring, reconfiguration callbacks | 10.6 |
| `CGEvent.h` / `CGEventSource.h` / `CGEventTypes.h` | 30 + 17 | event creation, posting, fields, taps, event sources | 10.6 (2 new: post-to-pid, tap-for-pid) |
| `CGRemoteOperation.h` | 28 | cursor warping, synthetic posting, screen refresh callbacks, window-server ports | 10.6 |
| `CGPDF*` (11 headers) | ~92 | PDF documents, pages, objects, arrays, dictionaries, strings, streams, scanners, content streams, operator tables, PDF context | 10.6 (1 new: document metadata) |
| `CGDisplayStream.h` | 11 | 10.8+ display capture stream | new |
| `CGDisplayFade.h` | 6 | fade reservations and configuration | 10.6 |
| `CGWindow.h` | 5 | window-list enumeration and images | 10.6 |
| `CGFont.h` | 8 | PostScript subset/encoding, variations, table access | 10.6 |
| `CGPath.h` | 11 | path adding/copying/transforming, arcs, rounded rects | 10.6 (8 new) |
| `CGContext.h` | 3 | PDF drawing, rendering intent | 10.6 |
| `CGColor.h` / `CGImage.h` / `CGGeometry.h` | 1 + 1 + 4 | color matching, UTType, vector/inline geometry | mixed |
| `CGPSConverter.h` | 5 | PostScript conversion | 10.6 |
| `CGSession.h`, `CGShading.h`, `CGDirectDisplayMetal.h`, `CoreGraphics.h` | 5 | session dictionary, one artifact, Metal (new), umbrella duplicate | mixed |

**The drawing core — path, context, color, image, font, geometry — is about 30 functions from complete.**
The rest is the window-server-facing half (display, event, window, session) and PDF. That is not a reason to
skip it: `CGDisplay*` and `CGEvent*` are the public face of what Kestrel already does, and `CGPDF*` is what
`NSPDFImageRep` and print-to-PDF need. But it is a reason to split Core Graphics into **G1 drawing**,
**G2 PDF** and **G3 screen/events**, with different backings and different gates.

### 3.3 Core Text — the smallest gap, almost all of it new

| Header | Missing | What it is |
|---|---:|---|
| `CTFontCollection.h` | 9 | mutable collections, query/exclusion descriptors, matching with options/family/callback, copying font attributes |
| `CTRubyAnnotation.h` | 7 | the whole ruby-annotation type (10.10) |
| `CTFont.h` | 5 | default cascade list, draw glyphs, ligature carets, optical bounds, QuickDraw instance (the one 10.6 debt) |
| `CTFontManager.h` | 3 | register/unregister graphics fonts, descriptor from data |
| `CTFontDescriptor.h` | 3 | copy with family, copy with symbolic traits, match with progress handler |
| `CTLine.h` | 2 | bounds with options, enumerate caret offsets |
| `CTTypesetter.h` | 3 | line creation and suggestion with an offset |
| `CTRunDelegate.h` | 3 | the parser missed `CTRunDelegateCreate/GetRefCon/GetTypeID`; they exist locally and the first-pass count is an artifact |

31 of the 32 are new since 10.6, and the one 10.6 function is `CTFontCreateWithQuickdrawInstance`, which is
declared and refused (QuickDraw does not exist here). Core Text is therefore the **cheapest** framework to
bring to 10.11 and the best place to prove the ledger and annotation gates before AppKit.

### 3.4 AppKit — the largest gap, and 91 of its missing classes are 10.6 debt

| Pile | Classes (or units) | 10.6 or new | Why it matters |
|---|---:|---|---|
| Controls and cells (`NSBox`, `NSMatrix`, `NSForm`, `NSDatePicker`, `NSStepper`, `NSLevelIndicator`, `NSImageView`, `NSSearchField`, `NSSecureTextField`, `NSTokenField`, `NSTabView`, color wells/panels, `NSPathControlItem`) | 29 | 10.6 (1 new) | every windowed application needs them; the tree is cell-based already |
| Text system (`NSATSTypesetter`, `NSTypesetter`, `NSGlyphGenerator`, `NSGlyphInfo`, `NSSpellChecker`, ruler views, `NSInputManager`, `NSTextAlternatives`, `NSStringDrawingContext`) | 14 | mixed | the layout manager exists; these are its public facade and the spell/input machinery |
| Documents and controllers (`NSDocument`, `NSDocumentController`, `NSPersistentDocument`, the controller family, `NSTreeController`, nib connectors) | 16 | 10.6 | the reference applications are document applications |
| Panels, printing and images (`NSOpenPanel`, `NSSavePanel`, `NSPrint*`, `NSPageLayout`, `NSPDF*`, `NSPICTImageRep`, `NSEPSImageRep`, `NSCachedImageRep`, `NSCustomImageRep`, `NSCIImageRep`, `NSDrawer`, `NSHelpManager`, `NSSound`, speech) | 21 | 10.6 | a desktop without open/save/print is not a desktop |
| Workspace (`NSWorkspace`, `NSRunningApplication`, `NSDockTile`, `NSStatusBarButton`, media library) | 4 | 10.6 + new | the Workspace plan assumes it; its backing is launch/icon/file-watch services |
| Collections, layout and modern view controllers (`NSCollectionView` + the 10.11 layout stack, `NSTableCellView`, `NSTableRowView`, `NSTableViewRowAction`, `NSStackView`, `NSSplitViewController`, `NSTabViewController`, `NSTitlebarAccessoryViewController`, `NSLayoutGuide`, `NSPageController`, `NSPopover`) | 21 | 10.7–10.11 | the modern application shape; the 10.11 collection view is a different API from 10.6's |
| Appearance, animation and gestures (`NSAppearance`, `NSVisualEffectView`, `NSAnimation*`, `NSGradient`, `NSShadow`, the gesture-recognizer family, haptics, pressure, alignment feedback) | 17 | mixed | visual polish and input; some need server support |
| Sharing, storyboards and assets (`NSSharingService*`, `NSStoryboard*`, `NSDataAsset`, `NSDraggingImageComponent`) | 7 | new | modern app features; storyboards can be declared/refused |
| Accessibility (`NSAccessibilityElement` + 20 protocols + 13 functions) | 1 class + 20 protocols | mixed | a cross-cutting contract every view participates in |
| Legacy/OpenGL (`NSOpenGL*`, `NSMovie*`, `NSQuickDrawView`) | 8 | 10.6 | deprecated even at 10.11; declare + refuse unless a client needs GL |

Two sequencing consequences:

- **Open/save panels, documents and `NSWorkspace` are not late polish.** They are 10.6 debts and they gate
  the reference applications and Workspace. They come early in AppKit, after the core view/window method
  fill and before the modern collection-view work.
- **Accessibility is a cross-cutting wave, not a class wave.** It touches every view and control; doing it
  before the control set stabilises would mean doing it twice.

---

## 4. Policy decisions

### 4.1 10.11 is a floor, not a ceiling

The tree already ships APIs that postdate 10.11. They stay, because removing a working door to satisfy an
older reference is a regression. They are marked as **extensions** (`AGORA_EXTENSION`) and annotated with
the version they actually arrived in. A build with `AG_TARGET_OS_X_10_11` defined hides them from the
surface check; the normal build keeps them. The ledger treats them as "extra, explained", not as missing.

### 4.2 Deprecated API is still API

10.11 still declares `NSOpenGLView`, `NSMovie`, `NSQuickDrawView`, `NSDrawer`, the zone functions and the
legacy alert-panel functions. Declaring them is part of matching 10.11; removing them would make the tree
*less* compatible. They get their `NS_DEPRECATED` annotation and a disposition (usually refused). A client
that compiles with `-Wdeprecated-declarations` sees the same kind of warning it would see on the Mac.

### 4.3 Refusal is a contract, not a stub

A refused door:

- is declared with the 10.11 signature and annotation;
- has a single documented reason (no backing, no platform equivalent, deliberately not implemented);
- logs one `APPKIT-REFUSE` / `FOUNDATION-REFUSE` / `CG-REFUSE` / `CT-REFUSE` line naming itself and the
  reason, the way the AppKit already does;
- returns a documented failure (`nil`/`NO`/`0`/`kCGErrorFailure`) rather than a success that a caller cannot
  distinguish from the real thing;
- has a test that asserts the refusal, and is counted in the refusal census.

**A refusal is never allowed to silently succeed, and a "temporary" stub that returns success is worse than
an absent declaration.** The census is a file-level count in both directions (already built for AppKit:
129 `APPKIT-REFUSE` sites over 24 files); the same mechanism extends to the other three frameworks.

### 4.4 Behaviours that get a documented adaptation

| Area | Apple's mechanism | Agora's backing | Deviation to document |
|---|---|---|---|
| `NSWorkspace` | Launch Services, Icon Services, FSEvents | `libagora-launchservices`, `libagora-iconservices`, `libagora-watch` (the Workspace plan's components) | Agora bundles only; no foreign applications; no `open`-with-arbitrary-binary |
| `NSOpenPanel`/`NSSavePanel` | the system panel | AppKit panels over the file system and the Workspace model | no sandbox powerbox; no iCloud; no tags column unless the metadata provider exists |
| `NSUserNotification` | notification center | the shell/notification service (a window-server client) | delivery depends on the shell; the in-process center keeps its state even when delivery is refused |
| `NSSpellChecker` | system spell service | the tree's `NSSpellServer`/`FNSpellServerDispatch` and a dictionary | language coverage is the dictionary's, not Apple's |
| `NSPrintOperation` | CUPS/print system | render to PDF via `CGPDFContext`; physical printers refused | "print to PDF" works; "print to printer" refuses by name |
| `NSTypesetter`/`NSATSTypesetter` | ATSUI/Core Text | facade over `NSLayoutManager`/Core Text | the facade must not become a second layout engine |
| `NSAppearance`/`NSVisualEffectView` | Core Animation materials | server-side blur if the compositor supports it, flat fallback otherwise | material names round-trip; pixels may differ |
| `NSAccessibility` | the macOS accessibility API | AT-SPI bridge (later) | the protocol surface is complete; the bridge is a separate deliverable |

### 4.5 What is permanently refused unless a decision changes

- **XPC** (`NSXPCConnection` and friends): no Mach services, no launchd. A Unix-socket substitute that calls
  itself XPC would be a lie. Refuse; point at `NSConnection` or a future Agora IPC component.
- **AppleScript / OSA / AppleEvents execution**: no OSA. `NSAppleEventDescriptor` is still implemented as a
  descriptor data type (it is useful and testable); `NSAppleScript`, script commands and coercion refuse.
- **OpenGL / CGL**: no GL dependency is introduced for a deprecated API. `NSOpenGL*` refuses; if a client
  needs GL, that is a separate component decision (Mesa/EGL), not an AppKit stub.
- **Physical printing**: PDF output is implemented; `NSPrinter`/CUPS is refused.
- **PostScript interpretation**: `CGPSConverter` (PostScript to PDF) and `NSEPSImageRep` need a PostScript
  interpreter and stay absent, while EPS **production** is implemented in `libagora-drawing`'s `CGEPSContext` (an
  Agora extension) and reaches AppKit through `-dataWithEPSInsideRect:` and `-writeEPSInsideRect:toPasteboard:`.
- **QuickDraw**: `NSQuickDrawView`, `CTFontCreateWithQuickdrawInstance`, `NSPICTImageRep`'s QuickDraw
  decoder, and the QuickDraw-era packed-glyph function either refuse or are reimplemented over CG where the
  format is still readable.
- **Storyboards**: declared and refused until a storyboard compiler/runtime exists; nibs remain the supported
  path. This is a deliberate scope cut, recorded at the header.

### 4.6 The annotation policy

Every public declaration gets the 10.11 annotation facts:

- `NS_AVAILABLE`/`NS_CLASS_AVAILABLE`/`NS_ENUM_AVAILABLE` with the **introduction version from the 10.11
  header**, not the version the tree happened to add it.
- `NS_DEPRECATED`/`NS_CLASS_DEPRECATED` with Apple's deprecation version and, where Apple gives one, the
  replacement.
- Nullability: every header is inside `NS_ASSUME_NONNULL_BEGIN/END`, and every pointer that can be nil is
  `nullable` in the same place Apple puts it. This is a mechanical but large sweep; it is checked by a
  compile with `-Wnullability-completeness` on the public headers once the sweep for that header is done.
- Ownership: `NS_RETURNS_RETAINED`/`CF_RETURNS_RETAINED` where the function returns a +1 object;
  `NS_CONSUMED`/`CF_CONSUMED` where it consumes; `NS_RETURNS_INNER_POINTER` for borrowed interior pointers.
- `NS_DESIGNATED_INITIALIZER`, `NS_UNAVAILABLE`, `NS_REQUIRES_SUPER`, `NS_NOESCAPE`, `__kindof`,
  lightweight generics, and `NS_SWIFT_NAME`/`NS_REFINED_FOR_SWIFT` where 10.11 has them.
- Availability is checked in the clang AST, because Linux clang records the attribute but does not warn on
  it. A declaration with the wrong introduction version is a ledger failure, not a warning.

---

## 5. Phase 0 — the instrument and the prerequisites

**Goal: make the surface measurable before adding to it.** No public API changes in this phase.

### 5.1 The tooling

| Deliverable | Acceptance |
|---|---|
| `tools/api-ledger` | Parses a header tree with clang; emits kind, header, signature, availability, nullability, ownership per name; deterministic output |
| `api/10.11/{foundation,coregraphics,coretext,appkit}.txt` | Committed name manifests, generated from the fetched 10.11 headers; no Apple header text |
| `tools/api-check` | Both-direction diff against the manifests; per-header; an `exemptions.txt` with a reason per line; exits non-zero on any unexempted difference |
| `tools/runtime-surface` | Loads the four libraries; reports missing classes, wrong superclasses, unimplemented required protocols, and unanswered selectors (including inherited); exits non-zero |
| `tools/symbol-check` | `nm -D` against the C-function manifest; inline functions are compiled and called, not looked for in the symbol table |
| `tools/header-compile` | Every public header compiles standalone as ObjC and ObjC++; the umbrella header compiles once; an ARC `-fsyntax-only` pass over the public headers |
| `tools/availability-check` | Dumps the clang AST and verifies the expected availability/deprecation attributes; no reliance on warnings |
| `tools/swift-import` | A small Swift file imports all four modules (module maps added here if needed) and references one class/function from each |

The first run of `api-check` will not be clean. That is the point: it produces the **M1 work list** per
header, and the exemptions file is where deliberate differences are argued rather than hidden.

### 5.2 The macro prerequisites

These live in `libagora-core` and `libagora-base`, not in the four frameworks, but every framework needs
them:

- **Core Foundation** (`CFAvailability.h`): `API_AVAILABLE`, `API_DEPRECATED`, `API_UNAVAILABLE`,
  `CF_AVAILABLE`, `CF_DEPRECATED`, `CF_SWIFT_NAME`, `CF_REFINED_FOR_SWIFT`, `CF_ASSUME_NONNULL_BEGIN/END`,
  `CF_RETURNS_RETAINED`, `CF_RETURNS_NOT_RETAINED`, `CF_CONSUMED`, `CF_WARN_UNUSED_RESULT`.
- **Foundation** (`NSObjCRuntime.h`): make the availability spellings real; add the missing
  `NS_DESIGNATED_INITIALIZER`, `NS_PROTOCOL_REQUIRES_EXPLICIT_IMPLEMENTATION` (find the correct clang
  spelling or record why it stays empty), `NS_SWIFT_UNAVAILABLE`, `NS_REFINED_FOR_SWIFT`, `NS_NOESCAPE`,
  `NS_HEADER_AUDIT_BEGIN/END`, `NS_DIRECT` (if the compiler supports it), and the full `NS_TYPED_ENUM` /
  `NS_ERROR_ENUM` / `NS_STRING_ENUM` family. The current `NS_ENUM`/`NS_OPTIONS` bodies are simplified; they
  must produce the same clang enum attributes (extensibility, flag enum) as 10.11's.
- **Objective-C runtime** (`libagora-objc`): confirm blocks, `instancetype`, `__kindof`, class properties,
  designated-initializer checking and `objc_requires_super` work under this runtime; add a compile test for
  each. If a feature is a compiler feature (most are), the test proves the header spelling, not the runtime.
- **Modules**: add `module.modulemap` for the four frameworks if the Swift import gate needs it. The Swift
  overlay plan already has a phase for the Clang module; this plan depends on it, it does not replace it.

### 5.3 The gate

Phase 0 is done when:

1. The ledger reproduces the baseline in §2.3 (within the documented parser artifacts) and the artifacts are
   removed or explained.
2. `api-check`, `runtime-surface`, `symbol-check`, `header-compile` and `availability-check` run in CI and
   fail on a deliberate one-name perturbation (the instrument is proved to bite, the way the AppKit refusal
   census was).
3. The existing suites still pass: `libagora-base` 3 tests, `libagora-drawing` 2, `libagora-text` 2, and the
   AppKit suite (the README records 70/70 in 107 s at the time of writing; the CMake list is larger now).
   Install before `ctest`, because the suites test the installed library.
4. The Swift import smoke test passes, or its module-map blocker is recorded as a named dependency.

**Estimated size: 2–3 engineer-weeks.** It is the cheapest phase and the one that keeps every later claim
honest.

---

## 6. Foundation — the plan

### 6.1 Waves

| Wave | Scope | Classes/protocols | Disposition | Depends on |
|---|---|---|---|---|
| **F1 — core and annotations** | Availability/nullability/ownership sweep over the existing headers; fill the 10.6 methods on `NSObject`, `NSArray`, `NSDictionary`, `NSSet`, `NSString`, `NSData`, `NSDate`, `NSURL`, `NSRunLoop`, `NSThread`, `NSOperation`, `NSNotification`, `NSFileManager`; resolve the `NSMakeRange`/`NSMaxRange` inline-vs-macro and `NSClassFromString`/`NSStringFromClass` declaration gaps; `CFBridgingRetain`/`CFBridgingRelease` if ARC bridging is in scope (otherwise declare as unavailable) | 0 new classes | implemented / annotated | Phase 0 |
| **F2 — predicates and expressions** | `NSPredicate`, `NSExpression`, `NSComparisonPredicate`, `NSCompoundPredicate` (the predicate family; `NSSpecifierTest` and the scripting tests are F10) | 4 | implemented | F1 |
| **F3 — metadata** | `NSMetadataItem`, `NSMetadataQuery`, `NSMetadataQueryAttributeValueTuple`, `NSMetadataQueryResultGroup`, `NSMetadataQueryDelegate`; query evaluation over `NSPredicate`; a provider seam (`libagora-metadata` in the Workspace plan) | 4 + 1 protocol | adapted (in-tree provider) or refused if no provider is chosen | F2 |
| **F4 — file access** | `NSFileAccessIntent`; finish the `NSFileCoordinator`/`NSFilePresenter` 10.6 method surface; `NSFileVersion` and `NSFileSecurity` method fills (the existing `NSFileProviderService` is a post-10.11 extension and stays one) | 1 | implemented | F1 |
| **F5 — progress and condition** | `NSProgress`, `NSProgressReporting`, `NSCondition` | 2 + 1 protocol | implemented | F1 |
| **F6 — URLs, sessions and net services** | `NSURLComponents`, `NSURLQueryItem`; the `NSURLSession` family (task, data/upload/download/stream, configuration, five delegate protocols) over the existing `NSURLConnection`/libcurl stack and dispatch; `NSNetServiceBrowser` (+ browser and service delegates) | 10 + 7 protocols | implemented (URLSession is the largest single subsystem) | F1, F5; dispatch; TLS |
| **F7 — user notifications** | `NSUserNotification`, `NSUserNotificationAction`, `NSUserNotificationCenter`, `NSUserNotificationCenterDelegate`; a delivery seam to the shell | 3 + 1 protocol | implemented in-process; delivery adapted or refused | F1; window server/shell |
| **F8 — extensions and item providers** | `NSExtensionContext`, `NSExtensionItem`, `NSExtensionRequestHandling`, `NSItemProvider`, `NSBundleResourceRequest` | 4 + 1 protocol | declared/implemented for item providers; extension host refused if no host exists | F6, F7 |
| **F9 — XPC** | `NSXPCConnection`, `NSXPCInterface`, `NSXPCListener`, `NSXPCListenerEndpoint`, `NSXPCListenerDelegate`, `NSXPCProxyCreating` | 4 + 2 protocols | **refused** | none (deliberate) |
| **F10 — scripting and AppleEvents** | The `NSScript*`/`NS*Command`/`NS*Specifier`/`NSAppleEvent*`/`NSAppleScript`/`NSClassDescription`/`NSUser*ScriptTask` family; `NSAppleEventDescriptor` as a data type | 37 | **refused** (data types implemented where testable) | F2 (predicate-shaped tests) |
| **F11 — the small remainder** | `NSByteCountFormatter`, `NSPersonNameComponentsFormatter`, `NSSimpleCString` (declare; it is a class cluster detail), `NSGarbageCollector`, the `NSZone.h`/`NSHashTable.h`/`NSMapTable.h` zone functions, `NSCountFrames`, `NSUncaughtExceptionHandler` | 4 + functions | implemented or refused (zone functions are mostly legacy) | F1 |

### 6.2 The order and why

**F1 → F2 → F5 → F6** is the spine. Predicates are the query language that metadata and AppKit's predicate
editor need; progress is the reporting object URLSession, file coordination and extension requests name;
URLSession is the modern networking surface and the gateway to `NSWorkspace`/sharing/notification backings.
**F3** follows F2 because a metadata query is a predicate over a provider, and the provider is a real
dependency (the Workspace plan's `libagora-metadata` is only proposed; if it is not built, F3's disposition
must be *refused with a named provider requirement*, not a fake in-memory index that silently returns
nothing). **F4** is small and can run beside F2. **F7/F8** can follow once the shell has a delivery seam.
**F9/F10** are declaration-first and can be done by a second worker at any point after the ledger, because
they block nothing else.

### 6.3 The Foundation gates

- **Ledger:** all 73 classes, 13 protocols and 33 functions present or exempted; the 44 missing headers
  either created or folded into an existing header with the names re-exported.
- **Signatures:** `NSURLSession`'s block types, nullability and `NS_NOESCAPE` are part of the surface; the
  AST check, not a name check, is the gate.
- **Runtime:** every class resolves; `NSURLSession`'s delegate protocols are adopted by the session; the
  refused XPC/scripting classes exist and their initializers refuse.
- **Behaviour:** a URLSession test against a local HTTP server, a predicate/expression test against a table
  of expressions, a progress test through a URLSession task, a metadata test over the chosen provider, and a
  notification test through the in-process center.
- **No bridge regressions:** the toll-free bridge suite (`tests/bridges.m`, 76 cases) stays green, and the
  new classes do not get a second reference count.

**Estimated size: 30–45 engineer-weeks for M1 + core behaviour, excluding a real XPC/AppleScript
implementation (which this plan does not undertake).** URLSession alone is 6–10; scripting declarations are
2–3 because the data types are many but shallow.

---

## 7. Core Graphics — the plan

### 7.1 Waves

| Wave | Scope | Functions | Disposition | Depends on |
|---|---|---|---|---|
| **G1 — drawing core** | `CGPath` additions (`AddLines`, `AddPath`, `AddRects`, `CreateWithRect`, `CreateWithEllipseInRect`, `CreateWithRoundedRect`, `AddRelativeArc`, `CreateCopyByDashingPath`, `CreateCopyByStrokingPath`, `CreateCopyByTransformingPath`, `CreateMutableCopyByTransformingPath`), `CGContextSetRenderingIntent`, `CGColorCreateCopyByMatchingToColorSpace`, `CGImageGetUTType`, `CGVectorMake`, `CGFont` table/variation/PostScript-subset family | ~30 | implemented | existing CG drawing core |
| **G2 — PDF** | `CGPDFDocument`, `CGPDFPage`, `CGPDFObject`, `CGPDFArray`, `CGPDFDictionary`, `CGPDFString`, `CGPDFStream`, `CGPDFContentStream`, `CGPDFScanner`, `CGPDFOperatorTable`, `CGPDFContext`, `CGPSConverter`, `CGPDFContextAddDocumentMetadata` | ~92 | implemented over a PDF backend (pdfium BSD-3, or an in-tree reader/writer) or refused per door if the backend cannot | G1 |
| **G3 — screen and events** | `CGDirectDisplay`, `CGDisplayConfiguration`, `CGDisplayFade`, `CGDisplayStream`, `CGWindow`, `CGSession`, `CGRemoteOperation`, `CGEvent`, `CGEventSource`, `CGEventTypes` | ~180 | adapted over the window-server protocol; capture/fade/transfer doors refused until the server grows the operation | Kestrel protocol; G1 |
| **G4 — legacy/absent** | `CGWindowServerCFMachPort`, `CGWindowServerCreateServerPort`, `CGDirectDisplayCopyCurrentMetalDevice`, `CGShieldingWindowID`, `CGShieldingWindowLevel`, `CGPostKeyboardEvent`/`CGPostMouseEvent`/`CGPostScrollWheelEvent` (PSN-era) | ~8 | refused (Mach ports, Metal, synthetic posting) | none (deliberate) |
| **G5 — verification** | `nm -D` symbol parity, inline-call compile tests, a display/event conformance probe against a headless server, PDF round-trip tests | — | gate | G1–G4 |

### 7.2 The decisions

- **PDF backend.** `pdfium` (BSD-3) is the candidate in the Workspace plan; it supplies the object model,
  page rendering and metadata. `CGPDFContext` (writing) may be easier to build in-tree over the existing
  `CGDataConsumer`/`CGImageDestination` machinery than to pull from a reader-only library. **Decide in G2's
  first week**: if pdfium's object model is exposed only through its own API, do not wrap it as `CGPDFObject`
  and pretend it is Apple's; build the reader in-tree over a small PDF parser, or refuse the scanner/operator
  half and implement document/page/context. This is the biggest fork in the plan.
- **Display/events are the server's public face.** `CGDisplayBounds`, `CGMainDisplayID`, the mode list,
  `CGWindowListCopyWindowInfo`, `CGEventPost` and the event-source state must be answered from the same
  state Kestrel uses, not by opening a second connection to the compositor. The protocol extension is a
  deliverable of G3, not an implementation detail.
- **Capture, fade and gamma tables are refused until the server supports them.** `CGCaptureAllDisplays`,
  `CGDisplayFade`, `CGSetDisplayTransferBy*` and `CGDisplayStream` must not return success while doing
  nothing. A headless server has no fade; the refusal is the honest answer.
- **Inline geometry is not a symbol gap.** `CGPointEqualToPoint`, `CGRectEqualToRect`, `CGSizeEqualToSize`
  and `CGVectorMake` are inline in 10.11; the symbol check must not demand them and the compile test must
  call them.

### 7.3 The gate

- Every one of the 309 names present or exempted; the 26 missing headers created or folded.
- `nm -D` exports every non-inline function; the inline ones compile and behave.
- A headless display/event probe: display list, main display, mode list, window list, event create/post and
  event-source round-trip against the server; a capture/fade refusal test.
- A PDF round-trip: create a context, draw, close, reopen, count pages, read metadata, render a page into a
  bitmap and compare a pixel; the scanner/operator half only if the backend choice keeps it.
- Existing drawing tests (`tests/drawing.c`, `tests/window_levels.c`) stay green.

**Estimated size: 25–40 engineer-weeks.** PDF is 10–15, display/events 10–15, the drawing core 4–6.

---

## 8. Core Text — the plan

### 8.1 Waves

| Wave | Scope | Functions | Disposition | Depends on |
|---|---|---|---|---|
| **T1 — font collections** | `CTFontCollectionCreateMutableCopy`, `SetQueryDescriptors`, `SetExclusionDescriptors`, `CopyQueryDescriptors`, `CopyExclusionDescriptors`, `CopyFontAttribute`, `CopyFontAttributes`, `CreateMatchingFontDescriptorsWithOptions`, `CreateMatchingFontDescriptorsForFamily` | 9 | implemented over the existing collection/matching layer | existing `CTFontCollection` |
| **T2 — font manager and descriptors** | `CTFontManagerRegisterGraphicsFont`, `UnregisterGraphicsFont`, `CreateFontDescriptorFromData`; `CTFontDescriptorCreateCopyWithFamily`, `CopyWithSymbolicTraits`, `MatchFontDescriptorsWithProgressHandler` | 6 | implemented; the progress handler uses a block, no `NSProgress` dependency | T1, font service |
| **T3 — font drawing and metrics** | `CTFontDrawGlyphs`, `GetOpticalBoundsForGlyphs`, `GetLigatureCaretPositions`, `CopyDefaultCascadeListForLanguages`; the QuickDraw instance (refused) | 5 | implemented (4) / refused (1) | existing `CTFont`/CG glyph path |
| **T4 — line and typesetter** | `CTLineGetBoundsWithOptions`, `CTLineEnumerateCaretOffsets`; `CTTypesetterCreateLineWithOffset`, `SuggestLineBreakWithOffset`, `SuggestClusterBreakWithOffset` | 5 | implemented | existing `CTLine`/`CTTypesetter` |
| **T5 — ruby annotations** | `CTRubyAnnotationCreate`, `CreateCopy`, `GetAlignment`, `GetOverhang`, `GetSizeFactor`, `GetTextForPosition`, `GetTypeID` | 7 | implemented as a type + attributes; layout integration is a follow-up | existing attributed-string/line layer |
| **T6 — verification** | symbol parity, a font-collection mutation/matching probe, a graphics-font registration probe, an optical-bounds/caret probe, a ruby attribute round-trip | — | gate | T1–T5 |

### 8.2 The decisions

- **Core Text stays plain C over Core Foundation and Core Graphics.** No Objective-C, no Foundation
  dependency, as the README's two rules require. The block-taking descriptor matcher is a C block
  (`CTFontDescriptorProgressHandler`), which the runtime already supports.
- **Font registration is a real file operation.** `CTFontManagerRegisterGraphicsFont` takes a `CGFontRef`;
  the font service already owns the file/directory model. The registration state must be visible to
  `CTFontCollection` matching and to the existing fallback path, or the two will disagree.
- **Ruby is a type first.** The 10.10 ruby annotation is an attributed-string attribute and a run property;
  the seven functions are a small data model. Do not hold them hostage to a full ruby layout implementation.
- **The one 10.6 debt is a refusal.** `CTFontCreateWithQuickdrawInstance` has no QuickDraw; declare it and
  refuse it by name.

### 8.3 The gate

- All 32 functions present or exempted; the 4 missing headers created (the SFNT headers are data/type
  vocabulary, not new behaviour).
- `nm -D` exports all of them; `owed_symbols.cmake` is replaced by the 10.11 ledger check.
- A collection test that creates a mutable copy, sets query/exclusion descriptors, matches with options and
  family, and copies the attributes; a registration test that registers a font from data, sees it in a
  collection, unregisters and sees it leave; an optical-bounds/caret test on a shaped line; a ruby attribute
  round-trip.
- Existing text suite stays green.

**Estimated size: 5–7 engineer-weeks.** This is the best first framework for the new gates: small, mostly
behavioural, and it exercises C declarations, blocks, availability and symbol parity.

---

## 9. AppKit — the plan

### 9.1 The organizing principle

AppKit is not one wave; it is a dependency graph. The order is:

```
A1 core method fill + annotations
   ├── A2 controls ──────────────┐
   ├── A3 text system ───────────┤
   ├── A4 documents/controllers ─┤
   ├── A5 panels/printing/images ┤
   └── A6 workspace ─────────────┘
                                  ├── A7 collections/layout/view controllers
                                  ├── A8 appearance/animation/gestures
                                  ├── A9 sharing/storyboard/assets
                                  ├── A10 accessibility
                                  └── A11 legacy/OpenGL/refusals
```

A2–A6 can proceed in parallel once A1 lands. A7 depends on A1 and benefits from A2/A4. A10 must come after
the controls and views it annotates. A11 is declaration-only and can be done by a second worker at any time.

### 9.2 Waves

| Wave | Scope | Classes/protocols | Disposition | Depends on |
|---|---|---|---|---|
| **A1 — core method fill and annotations** | Availability/nullability/ownership over the existing headers; fill the 10.6 methods on `NSResponder`, `NSView`, `NSWindow`, `NSApplication`, `NSControl`, `NSCell`, `NSMenu`, `NSEvent`, `NSGraphics`, `NSImage`, `NSColor`, `NSFont`, `NSBezierPath`, `NSPasteboard`, `NSTableView`, `NSOutlineView`; `NSOpenGL*` declarations are A11, not here | 0 new classes | implemented / annotated | Phase 0 |
| **A2 — controls and cells** | `NSBox`, `NSMatrix`, `NSForm`/`NSFormCell`, `NSImageView`/`NSImageCell`, `NSLevelIndicator`/`Cell`, `NSStepper`/`Cell`, `NSDatePicker`/`Cell`, `NSSearchField`/`Cell`, `NSSecureTextField`/`Cell`, `NSTokenField`/`Cell`, `NSTabView`/`NSTabViewItem`, `NSColorWell`, `NSColorSpace`, `NSColorList`, `NSColorPanel`, `NSColorPicker`, `NSPathControlItem`, `NSPredicateEditor`/`RowTemplate`, `NSRuleEditor`; the delegate/data-source protocols they need | ~29 | implemented (the cell-based engine exists) | A1 |
| **A3 — text system** | `NSATSTypesetter`, `NSTypesetter`, `NSSimpleHorizontalTypesetter` (legacy), `NSGlyphGenerator`, `NSGlyphInfo`, `NSSpellChecker`, `NSRulerView`/`NSRulerMarker`, `NSInputManager`/`NSInputServer` (legacy), `NSTextAlternatives`, `NSStringDrawingContext`; `NSTextViewDelegate`, `NSTextAttachmentContainer`, `NSTextLayoutOrientationProvider`, `NSTextFinder`/its protocols; finish the `NSLayoutManager`/`NSTextView` 10.11 method surface | ~14 + 8 protocols | facade over the existing layout manager / Core Text; spell checker over the existing server; input-manager legacy refused if the new input path covers it | A1, CT T1–T4 |
| **A4 — documents and controllers** | `NSDocument`, `NSDocumentController`, `NSPersistentDocument`, `NSController`, `NSObjectController`, `NSArrayController`, `NSDictionaryController`/`KeyValuePair`, `NSTreeController`/`NSTreeNode`, `NSUserDefaultsController`, `NSNibConnector`/`ControlConnector`/`OutletConnector`; `NSWindowRestoration`, `NSUserInterfaceItemIdentification` | ~16 + 2 protocols | implemented (documents are the reference apps' model) | A1, F4/F5 |
| **A5 — panels, printing and images** | `NSOpenPanel`, `NSSavePanel`, `NSOpenSavePanelDelegate`; `NSPrintInfo`, `NSPrintOperation`, `NSPrintPanel`, `NSPrinter`, `NSPageLayout`, `NSPDFInfo`, `NSPDFPanel`; `NSPDFImageRep`, `NSPICTImageRep`, `NSEPSImageRep`, `NSCachedImageRep`, `NSCustomImageRep`, `NSCIImageRep`; `NSDrawer`, `NSHelpManager`, `NSSound`, `NSSpeechRecognizer`, `NSSpeechSynthesizer` + delegates | ~21 + 6 protocols | open/save implemented; print-to-PDF implemented, physical printers refused; image reps implemented over CG/ImageIO or refused per format; speech/drawer/help refused or adapted | A1, G1, G2 |
| **A6 — workspace and desktop** | `NSWorkspace`, `NSRunningApplication`, `NSDockTile`, `NSDockTilePlugIn`, `NSStatusBarButton`, `NSMediaLibraryBrowserController`; `NSWorkspace` notifications | 5 + 1 protocol | adapted over `libagora-launchservices`, `libagora-iconservices`, `libagora-watch` (the Workspace plan's components) | A1, A5, the three service components |
| **A7 — collections, layout and view controllers** | `NSCollectionView` + `NSCollectionViewItem` + the layout stack (`NSCollectionViewLayout`, `LayoutAttributes`, `LayoutInvalidationContext`, `FlowLayout`, `FlowLayoutInvalidationContext`, `GridLayout`, `TransitionLayout`, `UpdateItem`), the data-source/delegate protocols; `NSTableCellView`, `NSTableRowView`, `NSTableViewRowAction`; `NSStackView` + delegate; `NSSplitViewController`/`NSSplitViewItem`, `NSTabViewController`, `NSTitlebarAccessoryViewController`; add `NSLayoutGuide` and the 10.11 `NSLayoutConstraint` anchor properties (the `NSLayoutAnchor` family itself already exists); `NSPageController` + delegate; `NSPopover` + delegate; `NSViewControllerPresentationAnimator` | ~21 + 7 protocols | implement the 10.11 collection-view shape (not the 10.6 item-prototype API); extend the existing Auto Layout solver for `NSLayoutGuide`; transition layout may be refused | A1, A2/A4 where relevant |
| **A8 — appearance, animation and gestures** | `NSAppearance`, `NSAppearanceCustomization`, `NSVisualEffectView`, `NSAnimation`, `NSAnimationContext`, `NSViewAnimation`, `NSAnimationDelegate`, `NSGradient`, `NSShadow`, the six gesture-recognizer classes + delegate, `NSHapticFeedbackManager`/`Performer`, `NSPressureConfiguration`, `NSAlignmentFeedbackFilter`/`Token`, `NSTouch` | ~20 + 5 protocols | appearance names implemented with a flat fallback; visual effect uses server blur when available; gestures over the event stream; haptics/pressure/alignment feedback refused if the server has no device | A1, window server |
| **A9 — sharing, storyboards and assets** | `NSSharingService`, `NSSharingServicePicker` + delegates, `NSServicesMenuRequestor`, `NSSeguePerforming`, `NSStoryboard`, `NSStoryboardSegue`, `NSDataAsset`, `NSDraggingImageComponent`, `NSPasteboardItem` | ~7 + 5 protocols | sharing adapted over the services menu; storyboards declared/refused; data assets implemented; dragging image components implemented over the existing drag session | A1, A6 |
| **A10 — accessibility** | `NSAccessibilityElement`; the 20 `NSAccessibility*` protocols; the 13 accessibility functions (`NSAccessibilityPostNotification`, `RoleDescription`, `Unignored*`, `FrameInView`, `PointInView`, …) | 1 + 20 protocols + 13 functions | protocols declared and adopted by the view/control hierarchy; functions implemented as tree utilities; the AT-SPI bridge is a separate deliverable, and unsupported attributes refuse | A2–A8 (the classes must exist first) |
| **A11 — legacy, OpenGL and refusals** | `NSOpenGLContext`, `NSOpenGLPixelFormat`, `NSOpenGLPixelBuffer`, `NSOpenGLView`, `NSOpenGLLayer`; `NSMovie`, `NSMovieView`, `NSQuickDrawView`; the deprecated alert-panel functions, `NSDrawer` (if not in A5), `NSInputManager`/`NSInputServer` (if not in A3) | ~8 + functions | **refused** (no GL, no QuickDraw, no movie decoder, no legacy alert panels), with the deprecated annotations | A1 |

### 9.3 The specific decisions

- **`NSOpenPanel`/`NSSavePanel` come early in A5, not last.** They are 10.6 debts and every document
  application needs them. The panel is a real AppKit panel over the file system and the Workspace model;
  the sandbox powerbox/iCloud behaviours are refused and documented.
- **`NSDocument` is the application model.** Implement the document/controller pair before the modern
  collection view. The reference applications (document, text, grid, presentation, canvas, image) are
  document applications, and `NSDocument` is what makes them portable.
- **`NSWorkspace` is adapted, not reimplemented.** The launch/icon/watch services are separate components in
  the Workspace plan; `NSWorkspace` is their AppKit face. If they are not ready, `NSWorkspace`'s file
  operations can use `NSFileManager` and its launch operations refuse by name. Do not build a second
  application registry inside AppKit.
- **The 10.11 collection view replaces the 10.6 one.** 10.11's `NSCollectionView` is the layout-based API;
  the 10.6 item-prototype API is deprecated in 10.11. Implement the 10.11 shape and declare the deprecated
  10.6 methods where 10.11 still has them, with adapters where they can be expressed. Do not implement the
  10.6 shape and call it 10.11.
- **Auto Layout is extended, not replaced.** The existing solver already handles constraints, anchors,
  priorities and intrinsic sizes. `NSLayoutGuide` is a view-like node in the same solver; the existing
  `NSLayoutAnchor` comparisons are reused, and the 10.11 constraint anchor properties are accessors over the
  same attributes. Do not introduce a second layout engine.
- **Text typesetter classes are facades.** `NSLayoutManager` and Core Text already own layout. `NSTypesetter`
  and `NSATSTypesetter` are public facades over that path; `NSGlyphGenerator`/`NSGlyphInfo` are data types.
  A second typesetter would be a correctness risk and a performance regression.
- **Visual effect and appearance are allowed to degrade.** `NSAppearance` names round-trip and the
  `NSVisualEffectView` draws a translucent material when the compositor can, a flat colour when it cannot.
  The deviation is documented at the class, not hidden.
- **Accessibility is a tree, then a bridge.** The protocols and functions can be implemented as a real
  accessibility tree over the view hierarchy without AT-SPI. The bridge to the Linux accessibility bus is a
  separate component and can lag; the AppKit surface is complete before it does.
- **Storyboards and OpenGL are refused.** Both are large subsystems whose absence is a scope decision, not
  an oversight. Nib loading remains the supported path; a GL client is a separate component decision.

### 9.4 The gate

- All 138 classes, 75 protocols and 81 functions present or exempted; the 153 missing header names either
  created or folded into a documented header with the names re-exported.
- Runtime probe: every class resolves with the right superclass and protocols; every required selector
  answers (including inherited); the refused classes refuse at init.
- Header compile: every public header as ObjC and ObjC++; ARC syntax pass; umbrella header.
- Behaviour per wave: a control test for each new control, a text test for the typesetter/spell facade, a
  document open/save/undo test, an open/save panel test, a workspace launch/reveal test, a collection-view
  flow-layout test, an appearance/visual-effect test, an accessibility-tree test, and a refusal test for
  OpenGL/QuickDraw/storyboards.
- The refusal census is updated deliberately (per file and in total); a door that silently acquires or loses
  an implementation fails the build.
- The existing 88-ish AppKit tests stay green (the README records 70/70 in 107 s at the time of writing).

**Estimated size: 80–120 engineer-weeks for M1 + core behaviour.** A2–A6 are roughly half; A7 is 15–20; A10
is 10–15; A8/A9 are 8–12; A11 is 2–3. A full behavioural implementation of every class (including
storyboards, OpenGL and physical printing) is explicitly not in this estimate.

---

## 10. Cross-component dependencies

The four frameworks do not stand alone. The plan names the dependencies rather than discovering them in a
wave:

| Dependency | Needed by | Owner | Notes |
|---|---|---|---|
| Availability/nullability macros, `CF_SWIFT_NAME`, ownership attributes | all four | `libagora-core`, `libagora-base` | Phase 0 |
| Blocks, `instancetype`, `__kindof`, designated initializers, class properties | Foundation (URLSession, progress), AppKit (animation, completion handlers), Core Text (descriptor matching) | `libagora-objc` | compile tests, not new runtime work unless a feature is missing |
| Dispatch sources and queues | URLSession, file coordination, display stream, notification delivery | `libagora-dispatch` | existing |
| TLS/HTTP backing | URLSession, `NSWorkspace` sharing, notifications | libcurl/OpenSSL (existing Foundation link) | no new dependency if the current stack is reused |
| Window-server protocol: display list/modes, window list, event post/tap, output stream, blur/material, notification delivery, dock/status item | CG G3, AppKit A6/A7/A8, `NSUserNotification` | `window-server` (Kestrel) | protocol extensions are deliverables, not assumptions |
| Launch services, icon services, file watch | `NSWorkspace`, open/save panels, Workspace | `libagora-launchservices`, `libagora-iconservices`, `libagora-watch` | the Workspace plan's components |
| Metadata provider | `NSMetadataQuery` | proposed `libagora-metadata` | if absent, F3 refuses with a named provider requirement |
| PDF backend | `CGPDF*`, `NSPDFImageRep`, print-to-PDF | pdfium or in-tree | decide in G2 |
| Shared file lists | `NSWorkspace` favorites, sidebar | proposed `libagora-sharedfilelist` | not required for the surface |
| Swift module maps / overlay | Swift import gate, Foundation overlay parity | `swift-toolchain` | the overlay plan's Phase 0 is a sibling dependency |
| Accessibility bus (AT-SPI) | A10 bridge | new component | the AppKit protocols do not wait for it |

**The window server is the largest external dependency.** A `CGDisplay*` function that opens its own
compositor connection would create a second source of truth; the plan requires the server to expose the
state and the CG functions to be a client of it. The same rule applies to `CGEventPost` and to
`NSWorkspace`'s launch/watch operations.

---

## 11. Sequencing and gates

### 11.1 The order

| Stage | Work | Why here | Exit gate |
|---|---|---|---|
| **P0** | Instrument, macros, header/symbol/runtime checks, Swift import | every later claim depends on it | §5.3 |
| **P1** | Foundation F1, AppKit A1, Core Text T1–T2, Core Graphics G1 | annotation/core completion, and the three small frameworks prove the gates | ledgers clean for the touched headers; suites green |
| **P2** | Foundation F2/F5/F6; Core Text T3–T5; CG G2 | predicates/progress/URLSession and PDF are the next dependencies | F2/F5/F6 behaviour tests; G2 round-trip; CT complete |
| **P3** | AppKit A2/A3/A5; Foundation F4 | controls, text, open/save/print and file access are the application floor | control/text/panel tests; document-ready |
| **P4** | AppKit A4/A6; Foundation F3/F7/F8; CG G3 | documents, workspace, metadata/notifications, display/events | document/workspace tests; display/event probe |
| **P5** | AppKit A7/A8/A9; Foundation F9/F10/F11; CG G4 | modern layout/collection/gesture/share; declaration-only refusals | collection/appearance tests; refusal census |
| **P6** | AppKit A10/A11; final annotation sweep; docs/release | accessibility and legacy/refusals last; the sweep catches drift | full ledger, runtime probe, docs, release notes |

### 11.2 The rules that keep the order honest

- **Do not start A7 before A1/A2/A4.** A collection view on a half-annotated view hierarchy will be rewritten
  when the view methods land.
- **Do not start F4 (URLSession) before F5 (progress) and the dispatch/TLS check.** A session without
  progress and cancellation is a different API from Apple's.
- **Do not start G3 before the window-server protocol extension is agreed.** The alternative is a second
  compositor client that will be deleted.
- **Do not start A10 before A2–A8 have stable class surfaces.** Accessibility is a cross-cutting adoption;
  doing it early doubles the work.
- **Declaration-only waves (F9, F10, A11) can run in parallel with anything.** They do not block behaviour
  and they shrink the ledger, which makes the remaining work visible.

### 11.3 Effort, order of magnitude

| Area | M1 (declared) | M2 (core behaviour) |
|---|---:|---:|
| Phase 0 | 2–3 ew | — |
| Foundation | 12–18 ew | 18–27 ew |
| Core Graphics | 8–12 ew | 17–28 ew |
| Core Text | 3–4 ew | 2–3 ew |
| AppKit | 25–35 ew | 55–85 ew |
| Conformance/docs/release | 8–12 ew | — |
| **Total** | **~58–84 ew** | **~92–143 ew** |

The total is **150–230 engineer-weeks** (roughly 3–4.5 engineer-years) for M1 plus core behaviour. The
estimate excludes a real XPC/AppleScript/OpenGL/storyboard implementation and physical printing. It is an
order of magnitude, not a schedule, and it should be re-measured after Phase 0 and after each wave.

---

## 12. Definition of done

### 12.1 M1 — the 10.11 surface is declared

1. **Ledger:** zero unexempted missing names in all four frameworks; zero unexempted extra names that are
   not marked `AGORA_EXTENSION` with an introduction version. The exempt file has one line per exemption
   with a reason, and the total is checked in both directions.
2. **Headers:** every 10.11 public header is present or its names are re-exported from a documented combined
   header; every public header compiles standalone as ObjC and ObjC++; the umbrella headers compile.
3. **Annotations:** every declaration carries the 10.11 introduction/deprecation version, nullability and
   ownership, verified in the clang AST. `-Wnullability-completeness` is clean for the swept headers.
4. **Runtime:** every 10.11 class resolves with the right superclass and protocols; every required selector
   answers, including inherited ones; every protocol is adopted by at least the class Apple says adopts it
   (or the exemption names why not).
5. **Symbols:** every non-inline C function is exported; every inline function compiles and behaves.
6. **Dispositions:** every name is implemented, adapted, refused or unavailable, and a refusal has a test,
   a named reason and a census entry.
7. **Suites:** the existing four suites pass; the install-then-`ctest` rule is followed; the Swift import
   smoke test passes or its blocker is named.
8. **Docs:** each component's README records the 10.11 reference, the M1/M2 distinction, the disposition
   counts and the deviations. The plan document's appendices are replaced by the generated ledger, not
   maintained by hand.

### 12.2 M2 — the core behaves

1. Every door a reference application or Workspace calls is implemented or refused with a documented
   replacement; the list is generated from the applications' call sites, not guessed.
2. The behaviour tests per wave exist and pass: controls, text, documents, panels, workspace, collection,
   appearance, accessibility, PDF, display/events.
3. The deviations in §4.4 are written at the class/function that carries them, not only in this plan.
4. The refusal census and the owed census are current, and adding or removing a refusal is a deliberate
   diff.

---

## 13. Risks and open decisions

| Risk / decision | Why it matters | Recommendation |
|---|---|---|
| **Scope: 211 classes is multi-year** | A name-only M1 is achievable; a full behavioural M2 is not a quarter's work | Commit to M1 first; make M2 a per-wave decision with a gate, not one big promise |
| **"Surface" ambiguity** | A client can compile against declarations that refuse at runtime and call that a failure | Use the four dispositions; publish the refusal list; never let a stub return success |
| **Availability on Linux** | `availability(macosx,...)` is recorded but not warned on Linux; a client cannot see the version in a warning | Make the attribute real and check it in the AST; do not rely on compiler warnings |
| **Nullability sweep changes warnings** | Turning on nullability and `NS_ASSUME_NONNULL` can break existing local call sites | Sweep per header; build the tree's own apps with the new warnings; fix or annotate, never silence globally |
| **Post-10.11 APIs** | The tree has 10.12+ classes; a naive ledger calls them "extra" and a naive strict mode removes them | Mark `AGORA_EXTENSION`, annotate the real version, hide only under `AG_TARGET_OS_X_10_11` |
| **PDF backend fork** | pdfium is a reader/renderer; `CGPDFContext` is a writer; wrapping one as the other may leak the backend's model | Decide in G2 week 1; allow a split (in-tree writer, pdfium reader) and refuse the scanner half if the model cannot be honoured |
| **Window-server dependency** | CG display/events and AppKit workspace/notification/accessibility need server operations that do not exist yet | Make the protocol extension a deliverable of each wave; refuse the door until it exists |
| **Metadata provider** | `NSMetadataQuery` without Spotlight is a fake if it silently returns nothing | Choose a provider (in-tree index) or refuse F3 with a named requirement |
| **XPC/AppleScript/OpenGL/storyboards** | These are the largest "surface without backing" temptations | Refuse them; document the replacement or the scope cut; do not build a misleading substitute |
| **NSCollectionView 10.6 vs 10.11** | The two APIs are different; implementing the old one and calling it 10.11 fails the target | Implement the 10.11 layout API; keep deprecated 10.6 methods only as adapters |
| **Accessibility scope** | 20 protocols + a bridge is a subsystem, not a class | Declare the protocols in A10; implement the tree; treat AT-SPI as a separate component |
| **Test-suite runtime** | The app suite is already ~107 s and will grow; a slow gate stops being run | Tag slow/headless tests; keep the default suite under a few minutes; run the full set nightly |
| **SDK licence** | Apple's headers are not redistributable | Commit only the recipe and the generated name manifest; never the headers |
| **ABI expectations** | A reader may expect Apple binaries to run | State source-only compatibility in the README and in this plan's §1; no ABI promise |
| **Swift overlay** | The Swift Foundation overlay has its own parity plan; this plan's new ObjC classes need Swift names | Treat the overlay as a sibling dependency; do not duplicate its work in the four frameworks |

### 13.1 Open decisions to settle in Phase 0

1. **PDF backend:** pdfium reader + in-tree writer, or a single in-tree implementation? (G2)
2. **Metadata provider:** build `libagora-metadata` or refuse `NSMetadataQuery` with a named requirement? (F3)
3. **Notification delivery:** does the shell grow a notification service in P4, or is F7 in-process only? (F7)
4. **XPC:** permanent refusal, or a future `libagora-xpc` over a Unix socket with a different name? (F9)
5. **OpenGL:** permanent refusal, or a separate Mesa/EGL component? (A11)
6. **Storyboards:** permanent refusal, or a minimal reader after A4? (A9)
7. **Swift module maps:** does the four-framework Swift import gate land in Phase 0 or with the overlay's
   Phase 0? (Phase 0)
8. **Accessibility bridge:** is AT-SPI a deliverable of this plan or of the shell? (A10)

---

## 14. Immediate next actions

These are the first concrete cuts, in order:

1. **Commit the instrument, not just the plan.** Add `tools/api-ledger` (or the first version of it), the
   committed manifests under `api/10.11/`, and the `api-check` both-direction check. Prove it bites by
   deleting one declaration and restoring it.
2. **Make the availability macros real.** Change `NSObjCRuntime.h` (and `CFAvailability.h` if needed) from
   inert bodies to `__attribute__((availability(macosx,...)))`, verify with a clang AST dump, and confirm
   the existing build is warning-free. This is a small diff with a large effect on every later header.
3. **Add the header-compile and symbol-check targets** to the four CMake projects. A header that cannot
   compile standalone is already a bug; the gate makes it visible.
4. **Freeze the baseline in the plan's terms.** Replace the first-pass numbers in §2.3 with the ledger's
   numbers, or record the delta and why. The plan's counts are a measurement, not a permanent truth.
5. **Start the three cheap waves in parallel:** Foundation F1 (annotations/core methods), AppKit A1
   (annotations/core methods), Core Text T1–T2 (font collection/manager). Core Text is the proof that the
   gates work; Foundation and AppKit are the long poles.
6. **Settle the two forks that block the most work:** the PDF backend (G2) and the metadata provider (F3).
   A wrong choice here is expensive to unwind.
7. **Update the four READMEs** to name 10.11 as the declaration reference, state the M1/M2 distinction, and
   point at the ledger. The READMEs currently describe 10.6-era pins; leaving them unchanged would make the
   plan and the components disagree.

---

## Appendix A — Foundation, missing surface

### A.1 Classes (73), by wave

**F2 — predicates (4):** `NSPredicate`, `NSExpression`, `NSComparisonPredicate`, `NSCompoundPredicate`.

**F3 — metadata (4 + delegate):** `NSMetadataItem`, `NSMetadataQuery`, `NSMetadataQueryAttributeValueTuple`,
`NSMetadataQueryResultGroup`; `NSMetadataQueryDelegate`.

**F4 — file access (1):** `NSFileAccessIntent`.

**F5 — progress and condition (2 + protocol):** `NSProgress`, `NSCondition`; `NSProgressReporting`.

**F6 — URLs, sessions, net services (10 + 7 protocols):** `NSURLComponents`, `NSURLQueryItem`,
`NSURLSession`, `NSURLSessionConfiguration`, `NSURLSessionTask`, `NSURLSessionDataTask`,
`NSURLSessionUploadTask`, `NSURLSessionDownloadTask`, `NSURLSessionStreamTask`, `NSNetServiceBrowser`;
`NSURLSessionDelegate`, `NSURLSessionTaskDelegate`, `NSURLSessionDataDelegate`, `NSURLSessionDownloadDelegate`,
`NSURLSessionStreamDelegate`, `NSNetServiceBrowserDelegate`, `NSNetServiceDelegate`.

**F7 — notifications (3 + protocol):** `NSUserNotification`, `NSUserNotificationAction`,
`NSUserNotificationCenter`; `NSUserNotificationCenterDelegate`.

**F8 — extensions and item providers (4 + protocol):** `NSExtensionContext`, `NSExtensionItem`,
`NSItemProvider`, `NSBundleResourceRequest`; `NSExtensionRequestHandling`.

**F9 — XPC (4 + 2 protocols):** `NSXPCConnection`, `NSXPCInterface`, `NSXPCListener`,
`NSXPCListenerEndpoint`; `NSXPCListenerDelegate`, `NSXPCProxyCreating`.

**F10 — scripting and AppleEvents (37):** `NSAppleEventDescriptor`, `NSAppleEventManager`, `NSAppleScript`,
`NSClassDescription`, `NSCloneCommand`, `NSCloseCommand`, `NSCountCommand`, `NSCreateCommand`,
`NSDeleteCommand`, `NSExistsCommand`, `NSGetCommand`, `NSIndexSpecifier`, `NSLogicalTest`,
`NSMiddleSpecifier`, `NSMoveCommand`, `NSNameSpecifier`, `NSPositionalSpecifier`, `NSPropertySpecifier`,
`NSQuitCommand`, `NSRandomSpecifier`, `NSRangeSpecifier`, `NSRelativeSpecifier`,
`NSScriptClassDescription`, `NSScriptCoercionHandler`, `NSScriptCommand`, `NSScriptCommandDescription`,
`NSScriptExecutionContext`, `NSScriptObjectSpecifier`, `NSScriptSuiteRegistry`, `NSScriptWhoseTest`,
`NSSetCommand`, `NSSpecifierTest`, `NSUniqueIDSpecifier`, `NSWhoseSpecifier`, `NSUserScriptTask`,
`NSUserAppleScriptTask`, `NSUserAutomatorTask`.

**F11 — the small remainder (4):** `NSByteCountFormatter`, `NSPersonNameComponentsFormatter`,
`NSSimpleCString`, `NSGarbageCollector`.

### A.2 Protocols (13)

Core 10.6: `NSMetadataQueryDelegate`, `NSNetServiceBrowserDelegate`, `NSNetServiceDelegate`.

New: `NSExtensionRequestHandling`, `NSProgressReporting`, the five `NSURLSession*` delegates,
`NSUserNotificationCenterDelegate`, `NSXPCListenerDelegate`, `NSXPCProxyCreating`.

### A.3 Functions (33, with parser artifacts called out)

The real gaps are the `NSZone.h` family (`NSAllocateCollectable`, `NSAllocateMemoryPages`,
`NSCopyMemoryPages`, `NSCreateZone`, `NSDeallocateMemoryPages`, `NSDefaultMallocZone`, `NSRecycleZone`,
`NSSetZoneName`, `NSZoneCalloc`, `NSZoneFree`, `NSZoneFromPointer`, `NSZoneMalloc`, `NSZoneName`,
`NSZoneRealloc`), the hash/map-table zone variants (`NSCopyHashTableWithZone`, `NSCreateHashTableWithZone`,
`NSCopyMapTableWithZone`, `NSCreateMapTableWithZone`), the object-allocation legacy
(`NSAllocateObject`, `NSCopyObject`, `NSDeallocateObject`, `NSShouldRetainWithZone`), `NSCountFrames`,
`NSUncaughtExceptionHandler`, and `CFBridgingRetain`/`CFBridgingRelease` (new in 10.7, ARC bridging).

The parser's `NSClassFromString`, `NSStringFromClass`, `NSSelectorFromString`, `NSStringFromSelector`,
`NSStringFromRange`, `NSMakeRange` and `NSMaxRange` hits are **declaration/inline artifacts**, not real
gaps: the first four are declared in `NSObject.h` here, and the last three are inline/macro spellings. The
ledger must resolve them rather than carry them as work.

---

## Appendix B — AppKit, missing classes and protocols by wave

### B.1 Classes (138)

**A2 — controls (29):** `NSBox`, `NSMatrix`, `NSForm`, `NSFormCell`, `NSImageView`, `NSImageCell`,
`NSLevelIndicator`, `NSLevelIndicatorCell`, `NSStepper`, `NSStepperCell`, `NSDatePicker`,
`NSDatePickerCell`, `NSSearchField`, `NSSearchFieldCell`, `NSSecureTextField`, `NSSecureTextFieldCell`,
`NSTokenField`, `NSTokenFieldCell`, `NSTabView`, `NSTabViewItem`, `NSColorWell`, `NSColorSpace`,
`NSColorList`, `NSColorPanel`, `NSColorPicker`, plus `NSPathControlItem`, `NSPredicateEditor`,
`NSPredicateEditorRowTemplate`, `NSRuleEditor` (the last four are controls/editors assigned here).

**A3 — text (14):** `NSATSTypesetter`, `NSTypesetter`, `NSSimpleHorizontalTypesetter`, `NSGlyphGenerator`,
`NSGlyphInfo`, `NSSpellChecker`, `NSRulerView`, `NSRulerMarker`, `NSInputManager`, `NSInputServer`,
`NSTextAlternatives`, `NSStringDrawingContext`; `NSFontCollection`, `NSMutableFontCollection` (the
font-collection classes are grouped with the text/font system).

**A4 — documents and controllers (16):** `NSDocument`, `NSDocumentController`, `NSPersistentDocument`,
`NSController`, `NSObjectController`, `NSArrayController`, `NSDictionaryController`,
`NSDictionaryControllerKeyValuePair`, `NSTreeController`, `NSTreeNode`, `NSUserDefaultsController`,
`NSNibConnector`, `NSNibControlConnector`, `NSNibOutletConnector`; `NSFontManager`, `NSFontPanel` (font
management is a panel/document concern and is owned here).

**A5 — panels and printing (21):** `NSOpenPanel`, `NSSavePanel`, `NSPageLayout`, `NSPrintInfo`,
`NSPrintOperation`, `NSPrintPanel`, `NSPrinter`, `NSPDFInfo`, `NSPDFPanel`, `NSPDFImageRep`,
`NSPICTImageRep`, `NSEPSImageRep`, `NSCachedImageRep`, `NSCustomImageRep`, `NSCIImageRep`, `NSDrawer`,
`NSHelpManager`, `NSSound`, `NSSpeechRecognizer`, `NSSpeechSynthesizer`, `NSMediaLibraryBrowserController`.

**A6 — workspace (4):** `NSWorkspace`, `NSRunningApplication`, `NSDockTile`, `NSStatusBarButton`.

**A7 — collections, layout and view controllers (21):** `NSCollectionView`, `NSCollectionViewItem`,
`NSCollectionViewLayout`, `NSCollectionViewLayoutAttributes`, `NSCollectionViewLayoutInvalidationContext`,
`NSCollectionViewFlowLayout`, `NSCollectionViewFlowLayoutInvalidationContext`, `NSCollectionViewGridLayout`,
`NSCollectionViewTransitionLayout`, `NSCollectionViewUpdateItem`, `NSTableCellView`, `NSTableRowView`,
`NSTableViewRowAction`, `NSStackView`, `NSSplitViewController`, `NSSplitViewItem`, `NSTabViewController`,
`NSTitlebarAccessoryViewController`, `NSLayoutGuide`, `NSPageController`, `NSPopover`.

**A8 — appearance, animation and gestures (17):** `NSAppearance`, `NSVisualEffectView`, `NSAnimation`,
`NSAnimationContext`, `NSViewAnimation`, `NSGradient`, `NSShadow`, `NSGestureRecognizer`,
`NSClickGestureRecognizer`, `NSPanGestureRecognizer`, `NSPressGestureRecognizer`,
`NSMagnificationGestureRecognizer`, `NSRotationGestureRecognizer`, `NSHapticFeedbackManager`,
`NSPressureConfiguration`, `NSAlignmentFeedbackFilter`, `NSTouch`.

**A9 — sharing, storyboards and assets (7):** `NSSharingService`, `NSSharingServicePicker`, `NSStoryboard`,
`NSStoryboardSegue`, `NSDataAsset`, `NSDraggingImageComponent`, `NSPasteboardItem`.

**A10 — accessibility (1):** `NSAccessibilityElement` (plus the 20 protocols in B.2).

**A11 — legacy/OpenGL (8):** `NSOpenGLContext`, `NSOpenGLPixelFormat`, `NSOpenGLPixelBuffer`,
`NSOpenGLView`, `NSOpenGLLayer`, `NSMovie`, `NSMovieView`, `NSQuickDrawView`.

The lists are disjoint and sum to 138; each class has exactly one owning wave. The ledger, not this
appendix, is the source of truth, and `api/10.11/appkit-owners.txt` records the owner.

### B.2 Protocols (75)

**10.6 debt (33):** `NSAlertDelegate`, `NSAnimatablePropertyContainer`, `NSAnimationDelegate`,
`NSChangeSpelling`, `NSCollectionViewDelegate`, `NSColorPickingCustom`, `NSColorPickingDefault`,
`NSComboBoxCellDataSource`, `NSComboBoxDataSource`, `NSComboBoxDelegate`, `NSDatePickerCellDelegate`,
`NSDockTilePlugIn`, `NSDrawerDelegate`, `NSGlyphStorage`, `NSIgnoreMisspelledWords`,
`NSInputServerMouseTracker`, `NSInputServiceProvider`, `NSMatrixDelegate`, `NSMenuDelegate`,
`NSOpenSavePanelDelegate`, `NSPasteboardItemDataProvider`, `NSPasteboardReading`, `NSPasteboardWriting`,
`NSPrintPanelAccessorizing`, `NSRuleEditorDelegate`, `NSSoundDelegate`, `NSSpeechRecognizerDelegate`,
`NSSpeechSynthesizerDelegate`, `NSTabViewDelegate`, `NSTextViewDelegate`, `NSTokenFieldCellDelegate`,
`NSTokenFieldDelegate`, `NSUserInterfaceItemSearching`.

**New in 10.7–10.11 (42):** the 20 `NSAccessibility*` protocols (`NSAccessibility`,
`NSAccessibilityButton`, `NSAccessibilityCheckBox`, `NSAccessibilityContainsTransientUI`,
`NSAccessibilityElement`, `NSAccessibilityGroup`, `NSAccessibilityImage`, `NSAccessibilityLayoutArea`,
`NSAccessibilityLayoutItem`, `NSAccessibilityList`, `NSAccessibilityNavigableStaticText`,
`NSAccessibilityOutline`, `NSAccessibilityProgressIndicator`, `NSAccessibilityRadioButton`,
`NSAccessibilityRow`, `NSAccessibilitySlider`, `NSAccessibilityStaticText`, `NSAccessibilityStepper`,
`NSAccessibilitySwitch`, `NSAccessibilityTable`); `NSAlignmentFeedbackToken`, `NSAppearanceCustomization`,
`NSCollectionViewDataSource`, `NSCollectionViewDelegateFlowLayout`, `NSGestureRecognizerDelegate`,
`NSHapticFeedbackPerformer`, `NSPageControllerDelegate`, `NSPopoverDelegate`, `NSSearchFieldDelegate`,
`NSSeguePerforming`, `NSServicesMenuRequestor`, `NSSharingServiceDelegate`, `NSSharingServicePickerDelegate`,
`NSSpringLoadingDestination`, `NSStackViewDelegate`, `NSTextAttachmentContainer`,
`NSTextFinderBarContainer`, `NSTextFinderClient`, `NSTextLayoutOrientationProvider`,
`NSUserInterfaceItemIdentification`, `NSViewControllerPresentationAnimator`, `NSWindowRestoration`.

### B.3 Functions (81)

**10.6 debt (76):**

- **Graphics/rect drawing (36):** `NSBeep`, `NSCopyBits`, `NSCountWindows`, `NSCountWindowsForContext`,
  `NSDisableScreenUpdates`, `NSDottedFrameRect`, `NSDrawButton`, `NSDrawColorTiledRects`, `NSDrawDarkBezel`,
  `NSDrawGrayBezel`, `NSDrawGroove`, `NSDrawLightBezel`, `NSDrawTiledRects`, `NSDrawWhiteBezel`,
  `NSDrawWindowBackground`, `NSEnableScreenUpdates`, `NSEraseRect`, `NSFrameRect`, `NSFrameRectWithWidth`,
  `NSFrameRectWithWidthUsingOperation`, `NSGetWindowServerMemory`, `NSHighlightRect`, `NSReadPixel`,
  `NSRectClip`, `NSRectClipList`, `NSRectFill`, `NSRectFillList`, `NSRectFillListUsingOperation`,
  `NSRectFillListWithColors`, `NSRectFillListWithColorsUsingOperation`, `NSRectFillListWithGrays`,
  `NSRectFillUsingOperation`, `NSSetFocusRingStyle`, `NSShowAnimationEffect`, `NSWindowList`,
  `NSWindowListForContext`.
- **Accessibility (9):** `NSAccessibilityActionDescription`, `NSAccessibilityPostNotification`,
  `NSAccessibilityRaiseBadArgumentException`, `NSAccessibilityRoleDescription`,
  `NSAccessibilityRoleDescriptionForUIElement`, `NSAccessibilityUnignoredAncestor`,
  `NSAccessibilityUnignoredChildren`, `NSAccessibilityUnignoredChildrenForOnlyChild`,
  `NSAccessibilityUnignoredDescendant`.
- **Application/services (7):** `NSApplicationMain`, `NSPerformService`, `NSRegisterServicesProvider`,
  `NSSetShowsServicesMenuItem`, `NSShowsServicesMenuItem`, `NSUnregisterServicesProvider`,
  `NSUpdateDynamicServices`.
- **Alert panels (13):** `NSBeginAlertSheet`, `NSBeginCriticalAlertSheet`, `NSBeginInformationalAlertSheet`,
  `NSGetAlertPanel`, `NSGetCriticalAlertPanel`, `NSGetInformationalAlertPanel`, `NSReleaseAlertPanel`,
  `NSRunAlertPanel`, `NSRunAlertPanelRelativeToWindow`, `NSRunCriticalAlertPanel`,
  `NSRunCriticalAlertPanelRelativeToWindow`, `NSRunInformationalAlertPanel`,
  `NSRunInformationalAlertPanelRelativeToWindow`.
- **Pasteboard/types (4):** `NSCreateFileContentsPboardType`, `NSCreateFilenamePboardType`, `NSGetFileType`,
  `NSGetFileTypes`.
- **Fonts/cells (3):** `NSConvertGlyphsToPackedGlyphs`, `NSDrawNinePartImage`, `NSDrawThreePartImage`.
- **OpenGL (3):** `NSOpenGLGetOption`, `NSOpenGLGetVersion`, `NSOpenGLSetOption`.
- **Key-value binding (1):** `NSIsControllerMarker`.

**New in 10.7–10.11 (5):** `NSAccessibilityFrameInView`, `NSAccessibilityPointInView`,
`NSAccessibilityPostNotificationWithUserInfo`, `NSAccessibilitySetMayContainProtectedContent`,
`NSEdgeInsetsMake`.

---

## Appendix C — Core Graphics, missing functions grouped

The exact list is in the generated manifest. The groups are:

| Group | Headers | Count | Backing |
|---|---|---:|---|
| Display enumeration and modes | `CGDirectDisplay.h`, `CGDisplayConfiguration.h` | 82 | window server |
| Display capture/fade/transfer | `CGDirectDisplay.h`, `CGDisplayFade.h`, `CGDisplayStream.h` | 17 | server, or refused until supported |
| Events and event sources | `CGEvent.h`, `CGEventSource.h`, `CGEventTypes.h` | ~47 | window server input |
| Remote operation / cursor / posting | `CGRemoteOperation.h` | 28 | server input, or refused |
| PDF | 11 `CGPDF*` headers + `CGPSConverter.h` | ~97 | pdfium or in-tree |
| Window list | `CGWindow.h` | 5 | window server |
| Path | `CGPath.h` | 11 | existing CG path engine |
| Font | `CGFont.h` | 8 | existing font service |
| Context/color/image/geometry | `CGContext.h`, `CGColor.h`, `CGImage.h`, `CGGeometry.h` | 9 | existing CG core |
| Session/Metal/legacy | `CGSession.h`, `CGDirectDisplayMetal.h`, `CGShading.h`, `CoreGraphics.h` | 5 | refused or artifact |

The 29 functions new in 10.7–10.11 are:

- **`CGPath` (8):** `CGPathAddRelativeArc`, `CGPathCreateCopyByDashingPath`,
  `CGPathCreateCopyByStrokingPath`, `CGPathCreateCopyByTransformingPath`,
  `CGPathCreateMutableCopyByTransformingPath`, `CGPathCreateWithEllipseInRect`, `CGPathCreateWithRect`,
  `CGPathCreateWithRoundedRect`.
- **`CGDisplayStream` (11):** `CGDisplayStreamCreate`, `CGDisplayStreamCreateWithDispatchQueue`,
  `CGDisplayStreamGetRunLoopSource`, `CGDisplayStreamGetTypeID`, `CGDisplayStreamStart`,
  `CGDisplayStreamStop`, `CGDisplayStreamUpdateCreateMergedUpdate`, `CGDisplayStreamUpdateGetDropCount`,
  `CGDisplayStreamUpdateGetMovedRectsDelta`, `CGDisplayStreamUpdateGetRects`,
  `CGDisplayStreamUpdateGetTypeID`.
- **Display modes (2):** `CGDisplayModeGetPixelWidth`, `CGDisplayModeGetPixelHeight`.
- **Events (2):** `CGEventPostToPid`, `CGEventTapCreateForPid`.
- **Singles (6):** `CGColorCreateCopyByMatchingToColorSpace`, `CGImageGetUTType`,
  `CGPDFContextAddDocumentMetadata`, `CGDirectDisplayCopyCurrentMetalDevice`,
  `CGWindowServerCreateServerPort`, `CGVectorMake` (inline).

The first-pass count of 31 included two parser artifacts (`size_t`, `void`); those are removed here.

---

## Appendix D — Core Text, missing functions (32)

| Header | Functions | Disposition |
|---|---|---|
| `CTFontCollection.h` | `CTFontCollectionCreateMutableCopy`, `SetQueryDescriptors`, `SetExclusionDescriptors`, `CopyQueryDescriptors`, `CopyExclusionDescriptors`, `CopyFontAttribute`, `CopyFontAttributes`, `CreateMatchingFontDescriptorsWithOptions`, `CreateMatchingFontDescriptorsForFamily` | implemented |
| `CTFontManager.h` | `CTFontManagerRegisterGraphicsFont`, `CTFontManagerUnregisterGraphicsFont`, `CTFontManagerCreateFontDescriptorFromData` | implemented |
| `CTFontDescriptor.h` | `CTFontDescriptorCreateCopyWithFamily`, `CTFontDescriptorCreateCopyWithSymbolicTraits`, `CTFontDescriptorMatchFontDescriptorsWithProgressHandler` | implemented |
| `CTFont.h` | `CTFontDrawGlyphs`, `CTFontGetOpticalBoundsForGlyphs`, `CTFontGetLigatureCaretPositions`, `CTFontCopyDefaultCascadeListForLanguages`; `CTFontCreateWithQuickdrawInstance` | implemented (4); refused (1) |
| `CTLine.h` | `CTLineGetBoundsWithOptions`, `CTLineEnumerateCaretOffsets` | implemented |
| `CTTypesetter.h` | `CTTypesetterCreateLineWithOffset`, `CTTypesetterSuggestLineBreakWithOffset`, `CTTypesetterSuggestClusterBreakWithOffset` | implemented |
| `CTRubyAnnotation.h` | `CTRubyAnnotationCreate`, `CreateCopy`, `GetAlignment`, `GetOverhang`, `GetSizeFactor`, `GetTextForPosition`, `GetTypeID` | implemented (type/attributes) |

The 10.6→10.11 addition count is 34, not 32: `CTRunDelegateCreate`, `CTRunDelegateGetRefCon` and
`CTRunDelegateGetTypeID` were added in that window, but this tree already declares them. They are therefore
not part of the 32-name gap; the ledger records them as present.

---

*This plan is a measurement and a sequence. Its first deliverable is the instrument that can disagree with
it; if the ledger's numbers replace the ones above, the plan has done its job.*
