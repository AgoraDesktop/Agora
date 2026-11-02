# Builder

*An interface builder for Agora: it edits a design file, shows the design as the real AppKit views it is, and writes the
text back exactly as it was written.*

The role is Apple's **Interface Builder** and GNUstep's **Gorm** — a visual editor for a serialised object graph with
connections. What it is not: a code generator, a runtime framework, a skin over somebody else's format, or an
implementation of Apple's nib schema. The format is Agora's own, it lives in the Application Kit (`NSNib` and
`NSNibSource`), and this repository is the EDITOR over it. See `DEVELOPMENT-TOOLS.md` at the workspace root for the role's
place in the plan — this is tier 3, and tiers 0–2 (the format, `ibtool`, the project layer) are what made it possible.

## The division

Three files, and the boundary between them is the point:

| File | What it is | What it must not do |
|---|---|---|
| `src/AGDesign.{h,m}` | **the model** — the source property list, plus the `id` → live object table the AppKit's compiler built | hold a window, a screen or a pixel |
| `src/AGBuilderDocument.{h,m}` | **the document** — an `NSDocument` over the text source: read, write, one window | know what a property list is |
| `src/AGBuilderWindowController.{h,m}` | **the window** — the object outline, the canvas, the status line, the shield | invent semantics the model does not have |

`AGDesign` is two things at once, and that is what makes the window a view of the file rather than a drawing of it. The
tree is what a save writes, so every `id`, every property's spelling and the key order are the person's. The live objects
are what the canvas shows and what an inspector writes through, so moving a view moves the thing you see. They cannot
disagree, because the tree is parsed and the objects are made from that same parse by
`+[NSNibSource objectsFromPropertyList:objectsByID:error:]`.

**Design mode is a mode.** The canvas hosts the real views and puts a transparent shield above them, so a designed button
cannot fire while it is being arranged. Test mode will remove the shield; it will not add a second event path.

## The file

A design is TEXT: OpenStep-shaped property list syntax with typed bare words and three object literals, as
`libagora-app/NSNibSource.h` documents. Extension `.agnib`. The compiled `.nib` is a build artifact — `ibtool compile`
makes it, and a document writes it only when the interface is being tested.

```
{
  version = 1;
  objects = (
    {
      id = root;
      class = NSView;
      properties = { frame = "0 0 480 320"; };
      subviews = (
        { id = title; class = NSTextField; properties = { toolTip = "press me"; }; }
      );
    }
  );
  connections = (
    { source = title; action = "go:"; destination = owner; }
  );
}
```

## Build

The tree's usual way, from the workspace root:

```sh
cmake -S builder -B builder/build \
  -DCMAKE_C_COMPILER=/usr/bin/clang-19 -DCMAKE_OBJC_COMPILER=/usr/bin/clang-19 \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++-19 \
  -DCMAKE_PREFIX_PATH="$PWD/build-prefix" -DCMAKE_BUILD_TYPE=Release
cmake --build builder/build -j"$(nproc)"
ctest --test-dir builder/build --output-on-failure
```

Dependents are the installed prefix: `AgoraApp` must be built and installed first (`libagora-app`), which carries the
format.

**Builder is not yet in `release/components.conf` or `.gitmodules`.** It is a component in the only sense that matters —
its own build, its own tests, its own bundle — and registering it waits on a repository to pin, exactly as `forge/` does.

## Run

```sh
source "$HOME/.agents/skills/agora-desktop/scripts/agora-env.sh"
"$AGORA_ROOT/builder/build/Builder.app/Contents/Linux/amd64/Builder" [--seconds N] [design.agnib]
```

`examples/Panel.agnib` is a small design to open: a view with a label, a button and a slider, and one action. **It also
records a rule of the format that looks like a bug the first time**: a control states its CELL as an object, so a button
without `cell = { class = NSButtonCell; … }` is a real `NSButton` with nothing to draw — the palette will build the pair
together, because the file has to.

It needs a compositor: nested (`window-server --backend x11`) or a session. `--seconds N` pumps events for N seconds and
leaves, which is how a session script can prove it started.

## What runs today

- A document that reads and writes `.agnib` through the AppKit's own parser and emitter; a save of an unedited design is
  byte-identical.
- The canvas: the design's real top-level views, at their real frames, on a grid, behind a shield — the whole window, until
  the object list draws (below).
- A status line that counts objects and connections.
- `builder-design-model`: the model, both directions of the id table, the child walk, the compile of a save, the refusals,
  and the document's doors — with no window and no compositor.

## One defect is measured and open: an object list will not draw its rows

The tree of objects is the window's left half and it is **not in the window yet**, because both routes to it were measured
and both fail:

1. **`NSOutlineView` in an `NSScrollView` paints no rows.** The table answers the right row count, `-rowsInRect:` answers
   the right row, the data source is asked for the right string, `preparedCellAtColumn:` builds the cell and draws it with
   `-drawWithFrame:inView:` — and no pixels appear. The same table placed directly in a pane paints its background
   (black, its default) and still no rows. Two contributing facts: the dirty rectangle handed to a view's `-drawRect:` is
   the WINDOW's (`0,-22 900x622` for a `324x578` table), i.e. `fn_draw_view` does not convert it per level; and a
   `NSTextFieldCell` prepared by the table answers a **nil** `-textColor`, so its text is drawn in whatever colour the last
   drawing left set.
2. **A hand-drawn replacement places its rows off-screen.** With rows laid out from the top of the bounds, only the last
   two of seven land inside the pane — the rest are above its top edge — so the vertical mapping between the list's
   coordinates and the pane's is not what its frame says either.

Both are the same class of defect (a view's own coordinate space versus the one it is drawn in) and both want one focused
pass in the view walk, not another workaround in this application. The canvas holds the whole width until then.

## What does not, yet

In the order the next slices take them:

0. **The object list.** A tree that draws its rows, selects one, and reports it — the defect above, then disclosure
   triangles, drag-reorder and the row-to-canvas selection they share.
1. **Selection on the canvas, move and resize, undo.** The shield becomes a selection surface; the document's
   `NSUndoManager` gets the edits.
2. **The palette** — the classes a design may contain, dragged onto the canvas — and the inspector, which is KVC over the
   selected object.
3. **Connections** — drawn source to destination, with the legal outlets and actions read from the file's-owner class by
   `libagora-app/tools/nib-outlets` (clang's AST, so a connect list is exact rather than guessed).
4. **Test Interface** — instantiate the graph with a stub owner and drop the shield.
5. **Windows on the canvas** — a top-level `NSWindow` is a designed object with a title, a style and a content view, and it
   is skipped today rather than mis-drawn.
6. Resources (images, fonts, colours as document content), alignment and distribution, drag-reorder in the outline,
   scrolling for a design larger than the window.

## Licence

MIT (see `LICENSE`). The format this program edits is the Application Kit's, licensed LGPL-3.0-or-later; Builder links it
as a shared library and owns no part of it.
