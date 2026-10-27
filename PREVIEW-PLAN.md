# Preview — an Agora application for PDFs and images

**Status: exploratory. No code, no commitments, no stage approved.** This is a design record written to be
argued with. It is grounded in the tree as it stands on 2026-10-22:

- workspace HEAD `553d02b`; `libagora-app` `c3f629c` **plus uncommitted work in `NSWorkspace.{h,m}` and
  `AppKitRefusal.h`**; `libagora-drawing` `2cecdbb`.
- Where this document says "the tree does X", the claim was read out of the source, not out of a plan
  document. The component README is already stale on this subject (`libagora-app/README.md` still lists
  `NSDocument` and `NSTabView` as absent; both exist, and `tests/document.m` drives the former around a real
  file). Trust the source and the tests over the prose.

Working name **Preview**; repository `preview`; bundle identifier `io.github.agoradesktop.preview`;
application, licence GPL-3.0-or-later like Workspace and Dock. The name is a decision, not a placeholder — see
§4.11.

---

## 1. The proposition

Agora has a file manager, a dock, and a controls demonstration. It has no application whose job is *looking at
a document*. Preview is that application: open a PDF or an image, read it comfortably, and (later) mark it up
and hand it back.

It matters out of proportion to its size for three reasons:

1. **It is the first real consumer of Core Graphics' PDF stack.** `CGPDFDocument`, `CGPDFPage` and
   `CGPDFRenderer` exist and are tested, but almost nothing drives them with files made by the rest of the
   world. Preview is the harness that turns "the renderer works" into "the renderer is right", and it makes
   PDF fidelity a platform problem with a user-visible scoreboard instead of a library aspiration.
2. **It is the first real consumer of the document stack.** `NSDocument`, `NSDocumentController`,
   `NSWindowController`, the open/save panels, printing and undo exist; nothing ships that uses them together.
   Preview is where their gaps (unsaved-changes flow, save-without-URL, recents) stop being hypothetical.
3. **It is the shape most future applications will copy.** A repository per application, a bundle built by
   CMake, `Info.plist` as the type contract, tests that need no compositor. Dock already set that shape; Preview
   should prove it generalises beyond a launcher.

### 1.1 What "v1" means

The first shippable slice is **a PDF and image viewer with a real window, real thumbnails, zoom, rotation,
print, and Export** — not an annotation editor, not a format zoo. Concretely:

- Double-click a `.pdf`, `.png` or `.jpg` in Workspace and it opens in Preview, because Launch Services resolves
  the type from the bundle's `Info.plist` and passes the path as `argv[1]`.
- One window per document, a thumbnail sidebar, continuous or single-page scrolling, fit-width/fit-page/actual
  size, rotate left/right, page navigation, and a page counter.
- Print (including "Save as PDF" through the existing print system) and Export a page as PNG.
- Images: view, rotate, flip, crop, resize, save PNG.
- Everything else is staged behind a written feature matrix (§5) and refuses by name where it is not there.

### 1.2 Non-goals for v1 (stated so they are not smuggled in)

Forms, signatures, OCR, PDF text editing, PostScript/EPS *authoring*, HEIC/RAW, iCloud/continuity, camera and
scanner import, sandboxing, multi-user document sharing, and any claim to open every PDF ever made. Encrypted
PDFs are detected and refused (not shown blank). Cross-process clipboard and drag-and-drop are out of our hands
until the window server has a data device (§7).

---

## 2. Where the platform stands today

This is the section to re-read before believing any later sentence. Each row names the evidence.

| Capability | State | Evidence / consequence |
|---|---|---|
| PDF parse, pages, boxes, rotation | **Real** | `libagora-drawing/CGPDFDocument.h`, `CGPDFPage.h`: xref tables and xref streams, object streams, `/Prev` chain; `CropBox`/`BleedBox`/`TrimBox`/`ArtBox` default per spec; `CGPDFPageGetDrawingTransform`. |
| PDF rendering | **Real, with a measured refusal list** | `CGPDFRenderer.c`: paths, state, colour, text, images, forms, shadings. **Not drawn:** Type 3 fonts, named CMaps, inline images, patterns, soft masks, mesh shadings, PostScript calculator functions, JPX/JBIG2/CCITT images. Each prints `CG-REFUSE` once per page. |
| PDF encryption | **Detected, not decrypted** | `CGPDFDocumentIsEncrypted`; an encrypted document opens but its pages are refused. Need a user-facing refusal. |
| PDF annotations (`/Annots`) | **Not read, not drawn** | The renderer walks content streams only; `CGPDFPageGetDictionary` exists, so the data is reachable if we choose to render appearance streams ourselves. |
| PDF text extraction | **Absent** | `CGPDFScanner` can be given an operator table, but nothing maps glyphs to Unicode; `/ToUnicode` is *written* by `CGPDFWriter.c`, never *read*. Selection/search is a platform work item, not an app hack. |
| PDF writing | **Real (fresh documents)** | `CGPDFContext` + `CGPDFWriter.c`: pages, boxes, alpha groups, fonts (with `/ToUnicode`), images. No incremental-update writer and no public header for the writer. |
| Image decode | **PNG and JPEG only** | `NSBitmapImageRep +canInitWithData:` checks 8 bytes (`\x89PNG`, `\xFF\xD8`). `CGImagePNG.c`, `CGImageJPEG.c`. |
| Image encode | **PNG only** | `CGImageDestination.h` refuses every other type by name; `NSBitmapImageRep`'s `-representationUsingType:` likewise. libjpeg is already linked, so JPEG encode is a small, contained addition. |
| Image transforms | **Enough** | `CGImageCreateWithImageInRect` (crop), `CGImageCreateCopyWithColorSpace`, `CGContext` scaling/rotation, `NSBitmapImageRep` for pixels. |
| Image metadata | **Almost none** | `CGImageGetWidth/Height/BitsPerComponent/ColorSpace`; no EXIF, no DPI, no orientation. `NSImageEXIFData` is a name without a reader. |
| Colour management | **Real** | `libagora-drawing` links lcms2; `CGColor.c` converts via ICC profiles; a generic CMYK profile is vendored with provenance. |
| Documents | **Real** | `NSDocument` (data/wrapper read & write, change count, undo integration, print doors) and `NSDocumentController` (types from `CFBundleDocumentTypes`/`NSDocumentClass`/`CFBundleTypeExtensions`, open panel, in-memory recents). `tests/document.m` covers the data round trip and windows; `tests/printing.m` covers its print doors. |
| Unsaved changes | **Not the framework's** | `NSDocumentController.h`: with no alert in the tier, `-closeAllDocuments…` closes none if any document is edited. `NSDocument`'s `-saveDocument:` refuses when there is no URL (that is the save-panel path). **The app builds Save-As and the close/quit confirmation.** |
| Printing | **Real** | `NSPrintOperation` paginates a view into a `CGPDFContext`; `NSPrintPanel` has queue, copies, range and disposition; libcups is optional and a build without it refuses by name. `tests/printing.m` (72 checks). |
| Panels/sheets/menus/toolbar | **Real** | `NSOpenPanel`/`NSSavePanel` (sheet, modal, filters by document types), `NSAlert`, `NSPanel`, sheets, `NSToolbar` (no customisation palette), `NSMenu` + validation. |
| Views | **Enough, with holes** | `NSScrollView`/`NSClipView`/`NSScroller`, `NSSplitView`, cell-based `NSTableView`, `NSMatrix`, `NSTextView`/field editor, `NSTrackingArea`, `NSCursor`. **Absent:** `NSCollectionView` (only the item class), `NSImageView`, `NSPopover`, `NSStackView`, view-based table rows. `NSTabView` exists. |
| Zoom | **App-side** | `NSScrollView` has no magnification; `NSEvent` has a magnify type but the compositor does not synthesise gestures. The app owns a zoom factor and its own layout. |
| HiDPI | **Absent** | `window-server/src/output.c` sends `wl_output.scale = 1`. "Actual size" therefore means 72 points = 72 device pixels, not a physical inch. |
| Clipboard | **Process-local** | `NSPasteboard` is an in-memory store; the compositor has no `wl_data_device`, and the AppKit README records the cross-process drag session as absent. Copy/paste and drag work inside Preview; not to another application. |
| Launch/open documents | **argv, one process per launch** | `LSOpen.c` resolves the default application from the type registry, then `posix_spawn`s it with the document path as an argument. **No activation, no single-instance, no document event to a running instance.** `NSApplicationMain` ignores `argv`, so the app parses it. |
| Application discovery | **Directory scan** | `LaunchServices.c` scans `/Applications`, `/usr/local/Applications`, `~/Applications`, or the colon-separated `AGORA_APPLICATIONS` (a test/development door). Bundles, not `.desktop` files. |
| Window server | **Client-side chrome, layers, activation** | `xdg-shell`, `agora_shell` (activate/close/reopen, levels, reserved edges, Dock menu). No iconify/minimise protocol, no fullscreen door in `NSWindow`. |
| Running applications / Dock | **Real** | `NSWorkspace.runningApplications`, Dock tiles, `activateWithOptions:`. Dock filters itself by bundle id — a pattern Preview should copy for tests. |

**Consequence in one sentence: the viewing half is close; the fidelity, text, markup, and cross-process halves
are platform work that this application happens to be the best reason to do.**

---

## 3. Decisions (proposed)

Each decision has a consequence that is easy to forget. They are written to be rejected explicitly, not
silently.

**D1 — Preview is a separate repository and an application, not a Workspace mode.**
Follow Dock: own `CMakeLists.txt`, own bundle, `find_package(AgoraApp CONFIG REQUIRED)`, install
`libexec/Preview.app`. Workspace keeps the file manager; a PDF viewer inside it would die with the desktop and
would repeat the mistake `window-server/DESIGN.md` names for the Dock.
*Consequence:* the parent workspace gains a gitlink and `README.md`/`components.conf` entries (release can
follow later, as it has not yet followed Dock).

**D2 — Documents are `NSDocument`s; one window controller; many documents per process.**
`PVPDFDocument` and `PVImageDocument` subclass a shared `PVDocument`; `PVWindowController` owns the window, the
sidebar, the toolbar and the page view. `NSDocumentController` supplies the type table, open panel, document
list and recents.
*Consequence:* two different open paths exist — several `argv` paths in one process (fine: one document each),
and one process per double-click from Workspace (see D8).

**D3 — The renderer is the in-tree Core Graphics PDF stack; pdfium is not adopted.**
`CGPDFPageGetDrawingTransform` + `CGContextDrawPDFPage` are the only PDF rasterisers. A second PDF engine would
mean two answers to "what does this page look like", would stop Preview from maturing the platform, and would
put a large C++ dependency under an Objective-C stack. `WORKSPACE-PLAN.md` mentions pdfium for a future Quick
Look; that divergence must be reconciled *in favour of one renderer* before either feature ships (open question
Q1).
*Consequence:* Preview inherits the refusal list in §2. PDF fidelity becomes a first-class workstream (§6 P4)
with a corpus-driven census, not an app bug.

**D4 — The bundle's `Info.plist` is the contract, and it only claims what Preview can actually read.**
`CFBundleDocumentTypes` drives both Launch Services and `NSDocumentController`; the app declares `com.adobe.pdf`,
`public.png`, `public.jpeg` and (once implemented) `public.tiff` — never the umbrella `public.image`, because
Launch Services routes by conformance and Preview would then be handed GIFs it cannot decode.
*Consequence:* adding a decoder is what earns the right to a new `LSItemContentTypes` entry, and a fixture test
asserts the two declarations cannot drift from the code's own supported list.

**D5 — Annotations are Preview's own model, drawn by one routine for screen and PDF; Save semantics are
staged.**
There is no PDFKit and no intention of pretending there is. An annotation is a page index, a kind, page-space
geometry, a style and an optional text. One renderer draws it into whatever `CGContext` it is given, so the
screen and the exported PDF cannot disagree.
*Consequence:* v1 PDFs are **read-only**. Annotated PDFs are saved by **flattening to a new file** (Save As /
Export) until an incremental-update writer exists (P7). The fidelity loss is enumerated in §4.8, not discovered
by a user. This is the single most important sequencing decision in the plan: don't offer "Save" on a PDF until
it can be honest.

**D6 — Image editing is whole-image, not layered.**
Rotate/flip/crop/resize produce a new `CGImage`; there is no non-destructive edit stack and no colour-adjust
engine (no Core Image). Export formats are limited to encoders that exist.
*Consequence:* a rotated JPEG cannot be saved back as JPEG until JPEG encoding lands; until then Save is
disabled for formats we cannot re-encode and Export offers PNG. The UI says so.

**D7 — The UI speaks the 10.6 idiom the AppKit implements.**
Cell-based `NSTableView` for thumbnails, `NSMatrix` for a contact sheet, a floating **Tools palette** instead
of a popover, a borderless window instead of fullscreen, a page view as a custom `NSView` inside `NSScrollView`.
*Consequence:* no `NSCollectionView` work is a prerequisite; the thumbnail strip is a one-column table with an
image data cell, and the page view owns its own zoom/layout maths (which is testable without a compositor).

**D8 — One process per launch is accepted for now; the app makes concurrent edits safe rather than pretending
they cannot happen.**
The session/activation component that would route a document to a running Preview does not exist
(`LSOpen.h` says so). Two double-clicks mean two processes.
*Consequence:* saves are atomic (temp + `rename`), the document records size/mtime at read, and a save over a
file that changed underneath prompts **Overwrite / Save As / Cancel**. No private single-instance IPC is
invented; that belongs to the session (Q2).

**D9 — Cross-process clipboard and drag are dependencies, not v1 features.**
In-process copy/paste and drag work today. Copying an image to another app, or dragging a page into
Workspace, waits for a `wl_data_device` in the compositor.
*Consequence:* menu items that would produce no cross-app effect are still implemented honestly (they fill the
pasteboard; the pasteboard is process-local). The plan does not promise what the transport cannot carry.

**D10 — Tests come before chrome.**
The page-layout maths, annotation geometry, save contract and type registration are all testable headless, in
the pattern Workspace and Dock already use (compile the model source into a probe; no compositor). Pixel tests
draw into a bitmap and compare PPMs with Pillow, the way `libagora-app/tests/pdf_app.m` does.
*Consequence:* the window is assembled last in each stage; if the geometry is wrong, a test says so before a
screenshot looks plausible.

---

## 4. Architecture

### 4.1 Repository and bundle

```
preview/
  CMakeLists.txt            copied in shape from dock/CMakeLists.txt (bundle platform/arch names are
                            libagora-core's vocabulary, not CMake's — do not reinvent)
  Info.plist.in             the type contract (see 4.10)
  src/
    main.m                  argv → queued URLs → NSApplicationMain → delegate opens after launch
    PVApplication.h/.m      delegate: menus, launch, terminate/quit confirmation, open-panel-on-launch
    PVDocument.h/.m         shared document model, undo, change count, close/save policy
    PVPDFDocument.h/.m      PDF source: CGPDFDocument, page count/boxes/rotation, annotations
    PVImageDocument.h/.m    bitmap source: CGImage, transforms, encoder choice
    PVWindowController.h/.m window, split view, toolbar, sidebar, inspector wiring
    PVPageView.h/.m         the document view: layout, drawing, hit testing, selection, annotation editing
    PVPageLayout.h/.m       pure geometry: page frames, zoom modes, page-at-point  (no AppKit drawing)
    PVThumbnailTable.h/.m   cell-based table data source/delegate; lazy thumbnail cache
    PVAnnotation.h/.m       the annotation model and its page-space geometry
    PVAnnotationRenderer.h/.m  one drawing routine, screen or PDF context
    PVToolsPalette.h/.m     floating tool/colour/line-width palette
    PVInspector.h/.m        floating document/page inspector
    PVPrintView.h/.m        -knowsPageRange:/-rectForPage: one sheet per page
    PVSlideshowWindow.h/.m  borderless, screen-sized, arrow keys, Esc
    PVMenu.h/.m             File/Edit/View/Tools/Window/Help, key equivalents, validation
    PVGeometry.h            shared types: PVPageSpaceRect, PVQuarterTurns, PVPageIndex
  tests/
    page_layout.m           zoom/fit/page-at-point/rotation algebra
    annotation_geometry.m   page↔view round trips, crop-box offsets, rotation
    document_save.m         flatten contract, atomic write, staleness, dirty/undo
    render_pixels.m         PDF page + annotation → PPM; screen vs PDF equality
    registration.m          Info.plist declarations vs the app's supported list (and an LS fixture)
    open_argv.m             the argv parser and the queued-open path
    ...                     plus run-*.sh wrappers where a compositor is genuinely needed (opt-in)
  Resources/Preview.icns
  README.md, PROVENANCE.md, COPYING, COPYING.LESSER (match the other apps)
```

Build/install:
`find_package(AgoraApp CONFIG REQUIRED)`; link `AgoraApp::App`; bundle at
`libexec/Preview.app/Contents/{Info.plist,<platform>/<arch>/Preview,Resources/Preview.icns}`. The install-time
`DT_RUNPATH` gap recorded in `workspace/CMakeLists.txt` applies here too: an installed bundle still wants
`LD_LIBRARY_PATH` until the dependencies carry `$ORIGIN`.

**Where Launch Services finds it.** `demo/agora-session.sh` already exports `AGORA_APPLICATIONS` pointing at
the components' build trees, which is how a development Dock sees bundles; P0 adds `preview/build` to that
list. An *installed* Preview is the settled case now: a complete installation carries `/Applications` and
`~/Applications` (README, "The installation"), and an application bundle is installed into one of them
rather than into `libexec/` — the directory Launch Services already scans. That resolves **Q8**, and
"double-click works after install" is a claim an installed Preview can make. The `AGORA_APPLICATIONS` door
stays what it is: the development path for bundles that live in a build tree.

### 4.2 Object graph

```
NSApplication (PVApplication delegate)
  └── NSDocumentController (shared)
        ├── PVPDFDocument ──┬── PVWindowController ──┬── NSSplitView
        │                   │                        │     ├── sidebar: PVThumbnailTable (NSTableView in NSScrollView)
        │                   │                        │     └── NSScrollView → PVPageView
        │                   │                        ├── NSToolbar
        │                   │                        └── PVToolsPalette / PVInspector (optional panels)
        │                   ├── CGPDFDocument (lazy) + NSData source bytes
        │                   └── NSArray<PVAnnotation *> (page-indexed)
        └── PVImageDocument ──── PVWindowController (same controller class)
              └── CGImage + source NSData + transform state
```

`PVDocument` owns the truth. The window controller owns no model. `PVPageView` reads the document through a
small protocol (`-pageCount`, `-pageBoundsAtIndex:`, `-pageRotationAtIndex:`, `-drawPage:inContext:rect:`,
`-annotationsForPage:`) so PDF and image documents share one view and one set of tests.

### 4.3 Coordinate contract (the highest-risk detail)

Write this once, use it everywhere, test it first.

- **Page space** = PDF *default user space* adjusted so the origin is the **crop box's lower-left**, in
  points, y-up, **before** the page's intrinsic `/Rotate`. For a bitmap, page space is the image's natural
  pixel rectangle in points (72 dpi), y-up for symmetry.
  - If `CropBox.origin != (0,0)`, the app subtracts it; when flattening, it adds it back. This is the classic
    off-by-origin bug and gets its own test. `CGPDFPageGetDrawingTransform` already translates the chosen box's
    origin to zero (its header says so), which is why the crop box — not the media box — is the page-space origin.
- **Document rotation** = the app's quarter-turns (0–3), kept in the model as `NSDocument` change state. The
  page's intrinsic `/Rotate` is separate; the model records both and only combines them at the drawing call
  (the transform's `rotate` argument is the extra turn). Never derive one from the other.
- **View space** = the page view's coordinates: flipped (y-down), points, at zoom factor *z*. One function
  maps page↔view given (page bounds, intrinsic rotation, document rotation, z, page frame). Everything else —
  annotation hit testing, selection handles, text overlays, print — calls it.
- **Drawing rule** (measured, not guessed): a PDF page draws y-up; a flipped AppKit destination draws y-down.
  `NSPDFImageRep.m` states the mirror rule and `tests/pdf_app.m` checks it in both a bitmap and a PDF export.
  `PVPageView` reuses the same rule rather than inventing a second one; `render_pixels.m` asserts page corner
  pixels land in the expected corners after rotation.
- **Annotations are stored in page space only.** No view coordinates, no zoom, no document rotation in the
  model. That is what makes "rotate the document after annotating" not move the ink, and what makes flattening
  reproducible.

### 4.4 Page layout and zoom (pure model, no drawing)

`PVPageLayout` is a value type with no AppKit dependency beyond `NSGeometry`:

- inputs: page bounds array, intrinsic rotations, document rotation, layout mode (single / continuous / two-up),
  zoom mode (fit width / fit page / actual size / custom factor), viewport size, page gutter and margin.
- outputs: `documentSize` (the scrolled canvas), `frameForPage:`, `pageAtPoint:`, `visiblePageRange`.
- zoom arithmetic is computed from the *rotated* page bounds; changing rotation recomputes the fit zoom, which
  is what a user expects from Preview.
- clamping: 5%–3200%; a fit zoom is recomputed on viewport resize but a *custom* zoom is left alone (the Mac's
  behaviour) — pick one and test it.
- two-up puts a spread of equal height; whether the first page sits alone (cover convention) is a decision to
  write down and test, not to discover. Two-up itself is deferred to P8; the layout mode exists in the model so
  the tests can be written early.

Tests: fit-width of a 612×792 page in a 900-point viewport; rotation swaps width/height; page-at-point at
margins and gutters; zoom clamp; document size with 0 pages.

### 4.5 Rendering and caching

- `PVPageView -drawRect:` draws only pages intersecting the dirty rect (plus a small bleed), fills the canvas
  with the desktop's page-grey, draws a one-point border/shadow per page, then page content, then annotations,
  then selection/adornments.
- PDF: `CGPDFPageGetDrawingTransform(page, kCGPDFCropBox, dest, rotate, true)` then
  `CGContextDrawPDFPage`. The `rotate` argument is the *extra* clockwise turn on top of the page's own
  `/Rotate` (the header says so), so the document rotation is passed there rather than composed by hand. Vector,
  at the destination's resolution.
- Bitmap: `CGContextDrawImage` with interpolation quality set; rotation/flip applied by the transform.
- **Cache policy, v1:** an `NSImage`/CGImage thumbnail per page (small, retained) and **no full-page bitmap
  cache** — vector re-draw at window size is cheap enough, and avoids a stale-cache class of bug. Add a
  page-bitmap cache only after measuring a slow case; if added, key it by (page, rotation bucket, zoom bucket,
  annotation revision) and test invalidation explicitly.
- **Invalidation:** annotation changes bump a per-page revision and redraw that page. Zoom/rotation relayouts
  the canvas. Document close releases thumbnails.
- **Refusal surfacing:** `CG-REFUSE` lines are diagnostics, not UI. A first-class "this page used something the
  renderer skipped" marker is a P4 research item (e.g. count refusals per page by scanning the same content
  streams); until then Preview shows what it drew and the console says what it skipped.
- **Performance targets (soft, measured by hand):** first paint of a 50-page text PDF ≤ 250 ms; first ten
  thumbnails ≤ 300 ms; zoom step repaint ≤ 100 ms; thumbnail memory ≤ 100 KB each. If a target fails, the fix
  is a measurement and a cache, not a spinner.

### 4.6 Thumbnails and sidebar

- One-column `NSTableView` in the sidebar's `NSScrollView`; `NSTableColumn`'s data cell is an `NSImageCell`
  (cell-based tables are what this tier has; `NSTableCellView` is absent).
- Thumbnail generation: render the page into a `CGBitmapContext` at ~120 pt wide (aspect preserved, 2× if we
  ever get HiDPI), make an `NSImage` via `-initWithCGImage:size:`, cache it, invalidate on that page's
  annotation revision. Generate lazily as rows are requested; generate the current page first.
- Selection is synchronized both ways: sidebar row ↔ visible page (scroll the page view when the row is
  chosen; update row selection when the user scrolls, without fighting the scroll).
- Sidebar header: a small segmented control (Thumbnails / (later) Bookmarks), a page-count label. Outline and
  search-results modes are P7.
- Collapse/expand via toolbar item and View menu; the split view's own `-setAutosaveName:` remembers the divider
  (the AppKit implements it in its own format, not Apple's private one).

### 4.7 Annotations

Model:

```objc
typedef NS_ENUM(NSInteger, PVAnnotationKind) {
    PVAnnotationNote, PVAnnotationText, PVAnnotationRectangle, PVAnnotationOval,
    PVAnnotationLine, PVAnnotationArrow, PVAnnotationFreehand,
    PVAnnotationHighlight, PVAnnotationUnderline, PVAnnotationStrikeout
};

@interface PVAnnotation : NSObject
@property NSUInteger pageIndex;
@property PVAnnotationKind kind;
@property CGRect bounds;             // page space, y-up, crop-box-relative
@property CGPoint startPoint, endPoint;   // lines/arrows
@property NSArray *points;           // freehand / quad points (page space)
@property NSColor *color;            // retained as components, not as a device colour
@property CGFloat lineWidth, opacity;
@property NSString *text;            // notes and text annotations
@property NSFont *font;              // text annotations
@property NSString *author;
@property NSDate *createdAt, *modifiedAt;
@end
```

- Editing: the page view is the editor. Mouse-down hit-tests annotations top-most first; selected annotations
  get eight handles (move/crop-resize) drawn by the page view; Delete removes; arrow keys nudge; undo via the
  document's `NSUndoManager` (register add/remove/geometry changes). Text annotations edit through a transient
  `NSTextView` positioned over the page using the page↔view transform; commit on click-away/Escape.
- Tools palette (floating `NSPanel`, not a popover): a radio `NSMatrix` of tools, an `NSColorWell` (which opens
  the existing `NSColorPanel`), a line-width slider, and the current tool's options. A cursor change
  (`crosshair` for drawing, `IBeam` for text, `openHand` for pan, resize cursors on handles) makes the mode
  legible.
- `PVAnnotationRenderer` draws the model into a `CGContext` already in **page space**. The page view sets up
  page space (so screen drawing is just another destination); the flattener sets up page space with the
  crop-box offset. Same code, same geometry, different target — that is the design.
- **Text markup is staged after text extraction.** Highlight/underline/strikeout need text ranges and
  quad points, which need the glyph→Unicode work in P6. P5 ships note/text/shapes/freehand; the markup tools
  exist in the palette but are disabled (grey, with a reason in the tool tip) until P6. That is more honest
  than drawing highlights as arbitrary rectangles over glyphs.

### 4.8 Save, export, print

**The contract.** For a PDF, the source bytes are the master copy. Preview never writes a PDF in place until it
can append an incremental update. Until then:

| Document state | ⌘S (Save) | Save As… | Export… |
|---|---|---|---|
| PDF, unmodified | no-op (disabled) | byte-for-byte copy | page → PNG (P3) |
| PDF + annotations (P5) | disabled | **flattened** PDF (new file) | page → PNG with annotations |
| PNG | re-encode PNG (lossless) | new PNG | PNG |
| JPEG/TIFF (read-only until encoder) | disabled | copy | PNG |
| Image + edits | re-encode if encoder exists, else disabled | new file | PNG |

**Flattening** (the P5 save path): create a `CGPDFContext`; for each page begin a page with the original
MediaBox/CropBox (and the app rotation baked), draw the original page with the same transform the screen uses,
draw annotations with `PVAnnotationRenderer`, end page. Result: one content stream per page, no `/Annots`.
**What is lost, stated in the Save-As dialog's accessory text or the README:** bookmarks/outlines, links,
form fields, metadata, tagged structure, attachments, optional content groups, and the editability of any
annotations that were already in the file (which we do not draw today either). What is preserved: page count,
page sizes, crop boxes, visible page content at the renderer's fidelity, and our own annotations as marks.

**Incremental append** (P7) is the honest fix: keep the original bytes verbatim, append annotation objects and
appearance streams, append a copied page dictionary with `/Annots`, a copied page-tree and catalog, and a new
xref with `/Prev`. Everything the flattener loses survives. It needs parser internals (object numbers, xref
offsets) exposed by `libagora-drawing`; the app must not grow a second PDF parser (Q3).

**Images.** Saving re-encodes the whole image, so EXIF/ICC chunks and unknown metadata are lost unless we write
them. v1 only claims PNG; JPEG is a one-day platform addition (libjpeg is already linked); TIFF/GIF/BMP come
with decoders in P8. Crop uses `CGImageCreateWithImageInRect`, which **integralises the rect outward**
(`CGRectIntegral`) and requires byte-aligned pixels — so the app stores the integral rect it actually got, or the
selection UI and the saved pixels will disagree by a fraction of a pixel. Resize draws into a new bitmap with
interpolation quality; rotate/flip are transforms into a new bitmap at natural pixel size.

**Printing** uses `PVPrintView`: `-knowsPageRange:` answers the 1-based, inclusive range `{1, pageCount}` (a
length of 0 means every page the view has); `-rectForPage:` returns `NSZeroRect` after the last; each page draws
into the print graphics context with the same page transform at print scale, annotations included. `NSPrintPanel`
supplies range/copies/queue and "Save as PDF"; "Print Current Page" is a File menu item that sets the
**`NSPrintOperation`'s** page range to `{currentPage, 1}` (the range lives on the operation, not on
`NSPrintInfo`).

**Atomicity and staleness.** Every write goes to a temp file in the destination directory, `fsync` optional,
then `rename`. Before writing, compare `stat` size+mtime against the values recorded at read; on mismatch show
an `NSAlert` with Overwrite / Save As / Cancel. Tests: write to a read-only directory (error surfaces), modify
the file between read and save (prompt path), and a save that is interrupted before rename (original intact).

### 4.9 Window, toolbar, menus, inspector, slideshow

- **Window:** titled, resizable, `-setContentMinSize:` (e.g. 480×360), frame autosave per document kind,
  `-setDocumentEdited:` for the close dot, `-setRepresentedURL:` **for storage only** — this tier's chrome has no
  document icon button and no path popup, as `NSWindow.h` states, so no UI can hang off it. One window per
  document; closing the last window does not quit (Preview's behaviour) —
  `applicationShouldTerminateAfterLastWindowClosed:` returns NO.
- **Toolbar:** sidebar toggle, previous/next page, zoom out, zoom in, actual-size/fit segmented control,
  rotate left/right, annotate (opens the Tools palette), search field (P6), action menu (Share/Export/Print).
  `NSToolbarItem` images come from the existing item/cell vocabulary; no customisation palette.
- **Menus:** see Appendix A. Rows with no implementation have no target and are drawn disabled by
  `-[NSMenu update]` — the Workspace convention. Shortcuts always set their modifier mask explicitly (a
  measured AppKit behaviour recorded in `WSMainMenu.m`).
- **Inspector:** floating `NSPanel`, toggled by ⌘I, showing file facts (name, path, kind, size, dates) and
  document facts that actually exist: PDF version, page count, encrypted/allows-printing/allows-copying,
  current page size and rotation; image pixel size, bits/component, colour space. DPI/EXIF appear only when a
  metadata reader exists — do not print a guessed 72.
- **Slideshow:** a borderless `NSWindow` at the screen's frame, black background, one page centred, arrow/space
  advance, Esc or click exits, no animation. Edge case: no fullscreen API, so this is the era's own technique;
  restore the previous key/main window on exit.
- **Open with no document:** show `NSOpenPanel` at launch (Preview's behaviour), filtered by the bundle's
  document types. Quit/close confirmation is the app's (`applicationShouldTerminate:` + `windowShouldClose:`),
  with Save / Don't Save / Cancel per edited document; save failures keep the document open and show the error.

### 4.10 `Info.plist` and the type contract

Sketch (the real file is `@PROJECT_VERSION@`-configured, like Workspace's):

```xml
<key>CFBundleIdentifier</key><string>io.github.agoradesktop.preview</string>
<key>CFBundleName</key><string>Preview</string>
<key>CFBundleExecutable</key><string>Preview</string>
<key>CFBundleIconFile</key><string>Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key><string>PDF Document</string>
    <key>CFBundleTypeRole</key><string>Editor</string>       <!-- Viewer until P5; Editor once flattening is honest -->
    <key>NSDocumentClass</key><string>PVPDFDocument</string>
    <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
    <key>CFBundleTypeExtensions</key><array><string>pdf</string></array>   <!-- what NSDocumentController actually reads -->
  </dict>
  <dict>
    <key>CFBundleTypeName</key><string>PNG Image</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>NSDocumentClass</key><string>PVImageDocument</string>
    <key>LSItemContentTypes</key><array><string>public.png</string></array>
    <key>CFBundleTypeExtensions</key><array><string>png</string></array>
  </dict>
  <!-- public.jpeg (Editor once JPEG encode exists), public.tiff (Viewer, when the decoder exists) -->
</array>
```

Notes:
- `NSDocumentController` reads **`CFBundleTypeExtensions`**, not `LSItemContentTypes`; Launch Services reads the
  UTIs. Both must be present and must agree, and a test asserts that every declared type maps to a document
  class that can actually read it.
- `CFBundleTypeRole` must not claim Editor for a format we cannot write honestly. Viewer for TIFF/GIF until
  their encoders exist.
- The classes named in `NSDocumentClass` must be linked into the executable (a document class the linker drops
  cannot be found by name). A test that opens one URL per declared type catches this, and is the cheapest guard
  against a plist that looks right and opens nothing.
- Declaring narrow UTIs (not `public.image`) is what keeps Launch Services from routing unsupported images to
  us; the test uses `AGORA_APPLICATIONS` pointing at the built/fixture bundle and asks
  `LSGetApplicationForURL` for a `.pdf` and a `.png`.
- Icons are read from `Contents/Resources/Preview.icns`; Icon Services and the Dock need one representation at
  every size.

### 4.11 Name, identity, icon

`Preview` is chosen for parity: a user coming from the reference desktop should find the same verb in the same
place. The alternative (an Agora-specific name such as Vellum or Loupe) is a one-line change to the bundle id,
the repo name and the application menu title; if the project wants distance from Apple's naming, decide now,
not after the icon exists.

The icon cannot be a borrowed Mac icon and should not be a generic theme glyph for an application this central.
**Proposal:** a small in-house mark (two sheets, a lens/eyepiece, or a page with a folded corner) drawn with
Core Graphics by a `tools/make-icon` program in the repo, rendered at the `.icns` sizes, and committed with a
`PROVENANCE.md` note saying it is original art for Agora. Until then, a placeholder derived from the Frost
theme's document/image glyph, documented as temporary. (Workspace's icon derivation recipe is the precedent for
provenance, not for the art.)

---

## 5. Feature parity matrix (reference: the 10.6-era Preview)

Verdicts: **Now** = buildable on today's stack; **Work** = needs a named platform addition; **Later** = staged,
not v1; **No** = deliberate refusal with a reason.

| Reference capability | Verdict | Stage | Note / dependency |
|---|---|---|---|
| Open PDF from Finder/Workspace | Now | P0 | LS doc types + argv; process per launch |
| One window per document, title, edited dot | Now | P0 | NSDocument + NSWindowController |
| Continuous / single-page scrolling | Now | P1 | custom page view + layout |
| Thumbnails sidebar, click to navigate | Now | P1 | cell-based NSTableView + lazy renders |
| Fit width / fit page / actual size / zoom in-out | Now | P1 | app-side zoom (no NSScrollView magnification) |
| Page navigation (keys, toolbar, menu) | Now | P1 | |
| Rotate left/right | Now | P1 | document rotation; baked on export |
| Two-page/spread view | Later | P8 | layout mode; first-page-alone rule |
| Open images (PNG/JPEG) | Now | P2 | NSImageRep registry |
| Image rotate/flip/crop/resize | Now | P2 | CGImage/CGContext |
| Image Save in native format | Work (partial) | P2 | PNG now; JPEG encode is a platform addition; TIFF later |
| Print, page range, Save as PDF | Now | P3 | NSPrintOperation; CUPS optional |
| Export page as PNG | Now | P3 | bitmap render + PNG destination |
| PDF fidelity over real-world files | **Work** | P4 | corpus + refusal census; top gaps drive libagora-drawing |
| Text selection and copy | Work | P6 | glyph→Unicode (ToUnicode/CMap/encodings) |
| Find in PDF | Work | P6 | depends on extraction |
| Links (URL / internal) | Work | P7 | page `/Annots` `/Link`; NSWorkspace.openURL |
| Outline / bookmarks sidebar | Work | P7 | catalog `/Outlines`; parser reachable via `CGPDFDocumentGetCatalog` |
| Notes / text / shapes / freehand annotations | Now | P5 | app model + one renderer |
| Highlight / underline / strikeout | Work | P6 | needs text ranges/quad points |
| Save annotated PDF | Work | P5 (flatten) → P7 (append) | see §4.8; never silently lossy |
| Draw annotations that already exist in a PDF | Work | P7 | appearance streams (`/AP`) via page dictionary; not content streams |
| Annotate an image | Later | P8 | same model, single page space |
| Encrypted PDFs | No (v1) | — | refuse with an explanation; password + decryption is a security-sensitive platform project |
| AcroForm fill / signatures | No | — | no PDFKit, no form model; not the era's core |
| Adjust Colour (brightness/contrast/saturation) | Work | P8 | needs an image-filter path in libagora-drawing (no Core Image) |
| Instant Alpha | No / optional | — | colour-key alpha; low value, high surprise |
| Contact sheet printing | Later | P8 | NSMatrix layout + print view |
| Slideshow | Now | P8 | borderless window |
| Metadata inspector (PDF facts, image pixels) | Now | P1/P2 | DPI/EXIF only when a reader exists |
| Open Recent menu | Now (session) | P2 | NSDocumentController recents are in-memory; persist later |
| Cross-app copy/drag of an image/page | Work | — | blocked by compositor data device |
| Fullscreen | No | — | no `NSWindow` fullscreen; slideshow covers the use |
| Scanner/camera import, iCloud, Continuity | No | — | out of scope |

---

## 6. Stages

Each stage ends with something a person can use without hand-holding, and with tests that do not need a
compositor unless stated. Ordering rationale: **viewing before editing, fidelity before markup, extraction
before text markup, append before in-place save.**

### P0 — Skeleton, registration, one window (≈ smallest useful)

**Goal:** launching `Preview file.pdf` (or double-clicking in Workspace) opens a window; the type contract is
real; the repository builds and tests like Dock.

Deliverables:
- new repo/bundle, CMake copied in shape from Dock, install rules, `Info.plist.in`, placeholder icon.
- `main.m` argv queue; `PVApplication` delegate opens queued URLs after launch; `applicationShouldTerminate:`
  and `windowShouldClose:` stubs that do not lose edits.
- `NSDocumentController` type table verified against `Info.plist`; `PVPDFDocument`/`PVImageDocument` stubs that
  read bytes and validate the magic (`%PDF-`, PNG, JPEG).
- `PVWindowController` with a titled window and an empty page view; `-makeWindowControllers` returns exactly one;
  menus built (Appendix A) with most rows disabled; application menu correct.
- Error sheets: not-a-PDF, unreadable file, encrypted PDF (refuse), unknown type.

Acceptance:
- `ctest` runs `open_argv` (parse/queue), `registration` (Info.plist ↔ supported formats, and `AGORA_APPLICATIONS`
  fixture → `LSGetApplicationForURL` for a `.pdf` returns Preview), and `document_stub` (read + dirty state).
- A headless test drives the bundle's executable with a path and a short-lived run loop (the pattern
  `workspace/tests` uses with its own bundle) — or, if the run loop proves awkward without a compositor, the
  argv/open path is tested as a model and the launch is verified manually once.
- `ldd` shows the build-tree AppKit first (`LD_LIBRARY_PATH` via `agora-env.sh`), not the prefix copy.

### P1 — PDF viewing, properly

**Goal:** a PDF is comfortable to read.

Deliverables: `PVPageLayout` + `PVPageView` (continuous/single), zoom modes and clamping, rotation, thumbnail
sidebar with lazy cache, page navigation, window title, page counter, inspector v1 (PDF facts), View/Window
menus, scroll/selection synchronisation.

Acceptance: `page_layout` (fit/rotate/clamp/page-at-point); `render_pixels` (a generated 2-page PDF with a
known coloured rectangle per page: corner pixels, crop-box offset, rotation 90/180/270, zoom 0.5/1/4); a
thumbnail test asserting count and invalidation; a manual nested-demo checklist.

### P2 — Image viewing and the safe edits

**Goal:** PNG/JPEG open, rotate/flip/crop/resize, Save/Export honestly.

Deliverables: `PVImageDocument` decode and transform, image inspector, Save policy per encoder (PNG only),
Export PNG, Open Recent (session-only), rectangular selection for crop (the UI primitive, not yet the Tools
palette), drag-to-open inside Preview if the in-process drag path is usable.

Acceptance: `image_ops` (rotate/flip/crop dimensions and corner pixels; crop offset; resize resampling
determinism); save/export round trip reads back with the same pixel dimensions; a JPEG rotate shows Save
disabled and Export PNG enabled; a read-only destination surfaces an error, not a silent no-op.

### P3 — Print and export

**Goal:** the document leaves the screen.

Deliverables: `PVPrintView` (one page per sheet, rotation-aware, annotations-aware), page-range defaults,
Print Current Page, Export Page as PNG, Save a Copy for PDFs.

Acceptance: `printing`-style probe with `NSPrintOperation` headless (the AppKit's printing tests already answer
without a queue): page count = document page count, `-rectForPage:` sequence terminates, the produced PDF
re-parses with `CGPDFDocument` and has the right boxes. CUPS-absent spool path refuses by name.

### P4 — PDF fidelity drive (no new UI)

**Goal:** know, numerically, what Preview cannot draw, and fix the three worst things.

Deliverables:
- A corpus of PDFs (hand-built fixtures for each feature plus public-domain documents) and a `refusal_census`
  test that scans pages, collects `CG-REFUSE` reasons, and prints a per-feature matrix. This is the scoreboard.
- Platform fixes in `libagora-drawing` chosen by the census, in order of user impact (candidates: inline
  images, named CMaps/Type 3 fonts for CJK, patterns, soft masks; JPX/JBIG2/CCITT need codecs and are likely
  out of scope). Each fix lands with its own drawing test, not an app workaround.
- A visible, non-fatal notice in the inspector (e.g. "2 pages used unsupported features") once the census API
  exists; never a silent blank page.

Acceptance: the census runs in CI on the fixtures; the top three gaps have before/after pixel tests; no
app-level special cases in `preview/`.

### P5 — Annotations v1 (shapes, notes, text, freehand)

**Goal:** mark up a PDF and hand back a flattened copy, with undo and no surprises.

Deliverables: `PVAnnotation`, selection/move/resize/delete, transient text editing, Tools palette, undo,
per-page invalidation, flatten-to-Save-As, Export with annotations, "flattening loses X" disclosure.

Acceptance: `annotation_geometry` (page↔view round trips under crop offsets and rotation; hit testing at
edges); `document_save` (flattened PDF re-parses to the same page count/boxes; annotation ink appears at the
expected pixel; original file bytes unchanged); undo restores geometry and change count; closing with edits
prompts and can cancel.

### P6 — Text extraction, selection, find

**Goal:** read text, select it, copy it, find it; then enable text markup.

Deliverables: platform text extraction (`libagora-drawing`) with encodings, `/ToUnicode` CMaps, simple-font
differences, Type0/CID basics, and glyph positions; `PVTextPage` with line runs in page space; selection
rectangles and copy (in-process pasteboard); Find with match highlighting and next/previous; then highlight/
underline/strikeout annotations built on text ranges/quads.

Acceptance: extraction on fixtures with WinAnsi, MacRoman, Identity-H + ToUnicode, and a ligature; search finds
a known phrase on the right page and selects the expected quads; copy produces the expected string; a markup
annotation saves flattened exactly over the glyphs it highlighted. **This stage is the plan's largest unknown;
estimate it after a spike, not before.**

### P7 — Incremental append, existing annotations, links, outline

**Goal:** annotate a PDF in place without flattening, and read the things a real PDF carries.

Deliverables: `libagora-drawing` incremental-update API (append objects + new page/catalog/xref with `/Prev`),
app-side annotation serialisation + appearance streams, re-open verification, page `/Annots` rendering for
existing annotations, clickable links (external via `NSWorkspace`, internal page jumps), outline sidebar.

Acceptance: append preserves the original byte prefix exactly; a diff shows only appended objects and a new
xref/trailer; our parser re-opens the file and sees the old and new annotations; links hit-test under rotation;
outline entries navigate. A PDF written by Preview must open in an independent reader (manual acceptance; use
a permissively licensed one, not a linked GPL tool).

### P8 — Breadth and polish

Formats (TIFF via libtiff, GIF via giflib, WebP via libwebp, BMP via a small in-tree decoder),
image annotations, two-up, contact-sheet print, slideshow, Adjust Colour (image filter path), recents
persistence, accessibility labels, keyboard map completion, performance work driven by measurements.

---

## 7. Changes below the app (who owns what)

| Component | Change | Why / blocking |
|---|---|---|
| **`libagora-drawing`** | JPEG **encode** in `CGImageDestination` (libjpeg already linked) | P2 honest image Save; also Export JPEG later |
| | Glyph→Unicode text extraction: `/ToUnicode` CMap reader, encodings, Type0/CID basics, glyph positions | P6; the largest platform item in the plan |
| | Incremental PDF update writer (append objects, `/Prev` xref) | P7; avoids a lossy flatten and a second parser |
| | Optional: render `/Annots` appearance streams; PDF soft masks/patterns/inline images driven by the census | P4/P7 fidelity |
| | Optional: TIFF/GIF/WebP decoders over system libs (libtiff/giflib/libwebp; licences checked) and a small in-tree BMP decoder | P8; keep them in the drawing library, not the app |
| **`libagora-app`** | Nothing required for v1. Possible small fixes found while building: document close/save ergonomics, `NSOpenPanel` multi-select details, toolbar item behaviour. Do **not** add `NSCollectionView` for this app. | Keep the app honest; prefer the app-level workaround until a second consumer proves a framework gap |
| **`window-server`** | `wl_data_device` (clipboard + drag between clients); iconify if the Dock wants minimised windows; output scale for HiDPI | D9 / Q5; not v1 |
| **`libagora-launchservices` / session** | Single-instance activation and a document-open event to a running app | D8 / Q2; belongs to the session component |
| **`workspace`** | Optional: "Open With" submenu using `LSCopyApplicationURLsForURL` (API exists, UI does not) | Nice-to-have; not on Preview's critical path |
| **`release`** | Add `preview` to `components.conf` / pins once it is in the workspace | Release follows Dock's precedent, which it has not yet done |
| **parent workspace** | gitlink, `README.md` component row, `.gitmodules` entry | Federation bookkeeping |

---

## 8. Testing

Follow the existing patterns rather than inventing a harness:

- **Model tests need no compositor.** Compile `PVPageLayout.m`, `PVAnnotation.m`, `PVGeometry.m`,
  `PVDocument` save-policy code directly into a probe (Dock's `dock_layout`, Workspace's `desktop_layout`).
  These are the tests that must be green on every commit.
- **Pixel tests** draw into a `CGBitmapContext`/`NSBitmapImageRep`, write PPM, and compare with Pillow
  (`libagora-app/tests/pdf_app.m` is the template). They assert page corners after rotation, crop-box offsets,
  annotation ink, and **screen-versus-flatten equality** for annotations.
- **Registration tests** use `AGORA_APPLICATIONS` pointed at the built bundle (or a fixture bundle) and ask
  `LSGetApplicationForURL`/`LSCopyApplicationURLsForURL`; additionally assert the plist's declared formats
  equal the app's supported list, so the contract cannot rot.
- **Document tests** drive `NSDocumentController` against temp directories: open, edit, undo, save/export,
  staleness prompt, read-only destination, close-with-edits, quit-with-edits. No UI: use the AppKit's own
  headless panel guard style where a panel is unavoidable.
- **One nested/headless integration test** for the real window path (screenshot of a rendered page in a real
  window with the compositor) — opt-in, like the existing nested runners, because it can grab the host pointer.
- **Manual checklist** per stage: double-click from Workspace, open panel, multi-file argv, Dock activation,
  print dialog, slideshow escape, sidebar sync.

The rule from the skill applies: a test that passes for the wrong reason is worse than one that fails. Every
runtime-visible claim should state which library was loaded (`ldd` / `LD_LIBRARY_PATH` ordering) and which
suite ran.

---

## 9. Risks and open questions, ranked

1. **PDF fidelity ceiling.** The refusal list (§2) covers things real documents use (inline images, Type 3,
   named CMaps, patterns, soft masks). If P4 cannot move the common cases, Preview will look correct on simple
   files and wrong on professional ones. Mitigation: census first, fixtures per feature, no app-level hacks,
   honest inspector notice. This is the project risk, not an app risk.
2. **Annotation save semantics.** Flattening is lossy; incremental append is real work. The plan sequences
   read-only → flatten-to-copy → append. If P7 slips, users can still mark up and export, but "Save" on a PDF
   remains disabled — acceptable and honest, but must be designed into the UI from P5.
3. **Text extraction.** CMaps, encodings, CID fonts, ligatures, RTL, rotated text and vertical writing are a
   deep well. Scope P6 to "horizontal, simple and Identity-H with ToUnicode" first, and refuse the rest
   visibly. Estimate only after a spike on three real PDFs.
4. **Process-per-document and no activation.** Two processes on one file are normal. Atomic writes + mtime
   checks make it safe, not pleasant. A real fix is a session/LaunchServices feature (Q2).
5. **No cross-process clipboard or drag.** Copy a page and paste into another app does not work. Say so in the
   README and do not build UI that implies otherwise.
6. **No HiDPI.** Artwork and thumbnails are 1×; `wl_output.scale` is hard-coded 1. Do not print "actual size"
   claims about physical inches.
7. **No `NSCollectionView` / `NSImageView` / popover / view-based tables.** Costs are small (a table cell and a
   custom view), but every "we'll just use the modern control" instinct is wrong here.
8. **Large-document performance.** Vector redraw at high zoom and hundreds of thumbnails. Measure before
   caching; if caching, test invalidation (annotation revision, rotation, zoom bucket).
9. **Encrypted PDFs.** Detected and refused, which is a visible parity gap (the Mac asks for a password).
   Decryption is a security-sensitive platform project; do not start it by accident.
10. **Icon, name and federation.** Decide the name now; produce original art with provenance; add the gitlink
    and README row in the same change that makes the repo build (the tree's federation is hand-maintained).
11. **Quick Look divergence (Q1).** `WORKSPACE-PLAN.md` proposes pdfium for Quick Look while this plan insists
    on the in-tree renderer. One of the two must change. Recommended: Quick Look uses the same `CGPDFRenderer`
    and inherits Preview's fidelity work.
12. **Licence choices for format decoders.** libtiff (BSD-like), giflib (MIT), libwebp (BSD-3) are acceptable;
    HEIC is out (patents); nothing GPL/AGPL gets linked. Record each in `THIRD-PARTY.md`.
13. **Installed-bundle discovery (Q8).** The development session works because `AGORA_APPLICATIONS` names build
    trees; a real install has no such guarantee today. If the release keeps installing bundles under `libexec`,
    the type-association story is a demo, not a feature.

**Open questions that need a decision, not more code:**

- **Q1** Quick Look/pdfium: one renderer or two? (Recommend one.)
- **Q2** Does the session own single-instance/activation, and when? Preview documents the limitation meanwhile.
- **Q3** Does the incremental PDF writer live in `libagora-drawing` (recommended) or in a new
  `libagora-pdf`? The app must never parse PDF itself.
- **Q4** Is text extraction a Core Graphics-shaped door on `CGPDFPage` (so Quick Look and accessibility share
  it) or a lower-level scanner helper the app assembles? Pick one and keep the parser knowledge in the drawing
  library, not in `preview`.
- **Q5** HiDPI and gesture support: are they prerequisites for a "1.0" or explicitly post-1.0? The plan assumes
  post-1.0.
- **Q6** Save/Export policy wording: does "Save" on an annotated PDF ever appear before incremental append?
  (Recommend no.)
- **Q7** Naming: `Preview` for parity, or a distinct Agora name? Decide before the icon and the docs.
- **Q8** *Resolved:* an installed application bundle is installed into `/Applications` (or `~/Applications`
  for a single user), and a complete installation creates both — the Mac OS X directory set is part of the
  installation (README, "The installation"), so the Launch Services scan roots are no longer empty on a
  machine that has Agora on it. Workspace's current `libexec/Workspace.app` is the development arrangement.

---

## 10. First moves (if this direction is approved)

1. **A one-week spike, not a stage:** create the `preview` repo skeleton from Dock's CMake, a bundle with the
   proposed `Info.plist`, argv parsing, and a `PVPageView` that draws page 1 of a PDF through
   `CGPDFPageGetDrawingTransform` + `CGContextDrawPDFPage` into a bitmap. One headless pixel test, one
   `AGORA_APPLICATIONS` registration test. This proves the whole vertical slice: bundle → LS → argv → document →
   Core Graphics → pixels.
2. **Build the refusal census next.** Collect PDFs (fixtures plus a handful of public-domain documents), run
   the renderer over every page, and count `CG-REFUSE` reasons by feature. Choose the top three platform fixes
   from data. Do this before promising "PDF support".
3. **Write the save contract** (the table in §4.8) into the repo's README *before* annotation code exists, and
   make the UI match it. A lossy "Save" is the one mistake this application cannot walk back.

Only then start P1 properly. The temptation to build the toolbar first should be resisted; the toolbar is the
cheapest part and the least likely to be wrong.

---

## Appendix A — proposed menu map (10.6 idiom)

| Menu | Rows (bold = v1) | Shortcut |
|---|---|---|
| **Preview** (application menu, inserted by `-setMainMenu:`) | About Preview, Hide, Hide Others, Show All, Quit Preview | ⌘Q |
| **File** | **Open…**, **Open Recent ▸**, **Close**, **Save**, **Save As…**, **Export…**, **Print…**, **Print Current Page** | ⌘O, ⌘W, ⌘S, ⇧⌘S, ⌘P |
| **Edit** | **Undo/Redo**, Cut/Copy/Paste (P2 images, P6 text), Delete, Select All, Find ▸ (Find…, Find Next, Find Previous) *(P6)* | ⌘Z/⇧⌘Z, ⌘X/C/V, ⌘F, ⌘G |
| **View** | **Thumbnails** (toggle sidebar), **Toolbar** (toggle), **Zoom In/Out**, **Actual Size**, **Fit to Window**, **Continuous Scroll**, Two Pages *(P8)*, **Rotate Left/Right**, Enter Slideshow *(P8)* | ⌘0, ⌘9, ⌘+/⌘-, ⌘L/⌘R |
| **Tools** | **Rectangular Selection** (crop), Elliptical Selection, Lasso, Note, Text, Rectangle, Oval, Line, Arrow, Freehand, Highlight, Underline, Strikeout *(all annotation tools P5/P6)*, **Show Inspector**, Show Colors, Show Fonts *(P5)* | ⌘I |
| **Window** | Minimise *(disabled until the window server has an iconify)*, **Zoom**, **Bring All to Front** | ⌘M |
| **Help** | Preview Help (a single window with the README's user section, or disabled until written) | |

Rows for unimplemented features have no target and are disabled by `-[NSMenu update]`, the Workspace
convention. **Bold marks the v1 slice (P0–P3), not a wish list**; where a row's stage matters it is named in
the text. Markup tools stay disabled until P5/P6; disabled rows carry a tool tip naming the dependency.

## Appendix B — what this app deliberately will not do in 1.0

Encrypted PDFs, forms, signatures, OCR, PDF text editing, EPS/PostScript authoring, HEIC/RAW, cross-application
clipboard/drag, physical-inch "actual size", fullscreen UI, iCloud/continuity, scanner/camera import, and any
promise that every PDF renders exactly as its author intended. Each refusal should be visible and specific —
the project's own style — rather than a blank canvas or a silent no-op.
