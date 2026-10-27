# The default session and the demo

## The default session

```
demo/agora-session.sh [WIDTHxHEIGHT]   # 1280x720 by default; Ctrl-C stops it
```

The default session runs the three pieces a login session needs: the **window server**, the **wallpaper client**,
and **Workspace** (desktop, icons and menu bar). It deliberately does not start the controls application. It uses
the same nested, non-grabbing X11 setup as the demo, defaults the desktop to `$HOME/Desktop`, and accepts
`AGORA_DESKTOP`, `AGORA_WALLPAPER` and `AGORA_SESSION_SOCKET`.

**The pointer is the vendored Vimix cursor theme**, not the arrow the compositor used to draw: the script points
`AGORA_CURSOR_THEME` at `window-server/assets/cursors/Vimix` so a developer running the build trees sees it without
installing anything, and `AGORA_CURSOR_SIZE` makes it larger or smaller (24 points by default). A nested session has
the X server draw the pointer, so what you see over the Agora window is the theme's image handed to the host as the
window's cursor; on a DRM output the compositor composites the same image itself. See `window-server/README.md` §5b.

## The demo

One window server, three clients, and a menu bar that belongs to whichever of them is **active**.

```
demo/agora-demo.sh [WIDTHxHEIGHT]      # 1280x720 by default; Ctrl-C stops it
```

It needs `window-server`, `workspace` and `libagora-app` built (`build/` in each). Nothing is installed and
nothing is grabbed: the compositor runs nested on your X11 desktop with `--input host`, so it receives the input
**your** session gives its window and takes nothing else. It is safe to leave open.

## What you are looking at

| layer | who draws it |
|---|---|
| the wallpaper (`wallpaper.jpg` by default) | `window-server-test-client`, at `kCGDesktopWindowLevel` — the **Dock's** layer, eventually |
| the icons, the menu bar and the file windows | **Workspace**, whose icon window is transparent at `kCGDesktopIconWindowLevel`; **File → New Workspace Window** (or `--file-window`) opens the file window, and **View → as List** (`--list-view`) shows W4's list, and **View → as Columns** (`--column-view`) W5's columns |
| the window full of controls | **`appkit_controls_draw`**, an ordinary window — buttons, checkbox, radio, switch, sliders, a pop-up, a combo box, a text field, a scrolled panel, and a **toolbar** above them all |
| the table and outline window | **`appkit_controls_draw`** again — the **Data → Table & Outline** item (or the toolbar's **Table** item): a real `NSOutlineView` with disclosure and levels beside a real `NSTableView` with columns, a header and alternating rows |
| the GUI gallery | **`appkit_controls_draw`** again — the **Gallery → All Classes** item (or the toolbar's **Gallery** item): one scrollable window with every remaining view and control class — a radio matrix, a form, an image view, a colour well, a bare scroller, a browser, a token field, a rule editor, a predicate editor, a collection view, a ruler and a centred drawer tucked under the window — plus buttons for the alert, save, open, colour, font and print panels |

**The wallpaper is `../wallpaper.jpg` by default**, decoded by the test client with libjpeg and scaled to cover the window; `AGORA_WALLPAPER=/path/to/image.jpg` overrides it, and the flat amber colour is the fallback when the file is absent. **The toolbar is the same acts as the menus.** "Show Grid" toggles the checkbox the View menu validates
against, "Playground" opens the text window, "Table" opens the data views, "Gallery" opens the GUI gallery, and
"Action" prints its own name — so the strip and the menus are not two sets of commands. The separator, flexible
space and greyed "Disabled" item are the rest of what a toolbar has to show.
The **Table** item (or **Data → Table & Outline**) opens the two data views; `--data` does the same at startup when
you run `appkit_controls_draw` directly. `--gallery` opens the gallery at startup, `--gallery-bottom` opens it
scrolled to the panel buttons, and `--gallery-drawer` opens its drawer too. (The menu bar's status item is
Workspace's clock, not this application's.)

**The menu bar has two owners, and that is the demonstration.** A menu bar belongs to the ACTIVE application.
Workspace maps first and therefore owns it: `Workspace · File · Edit · View · Go · Window · Help`. Click the
Controls window and its own menus replace them — because it called `-setMainMenu:` too. Click the desktop and
Workspace's come back.

## Two things it does deliberately, which are worth knowing before changing it

- **Workspace is started first.** The compositor gives the keyboard to the first surface that maps
  (`window-server/src/seat.c`, the initial-focus half of click-to-focus), so the application that should own the
  bar is the one that maps first.
- **`appkit_controls_draw` is given no `--seconds`.** That argument makes it pump its own event loop, and a
  hand-pumped loop cannot drive a menu bar: `NSMenuView` fetches events only while `-[NSApplication isRunning]`.
  With no argument the demo calls `-[NSApplication run]`, which is what its controls and its menus both want.

## The measurements behind its shape

- The wallpaper client redraws on **every frame callback**, so asking it for frames for ever makes it a
  frame-rate generator: MEASURED at **233 composites a second and 86% of a core** for pixels that never change.
  Hence `--frames 1 --hold` — one commit, then listen. The compositor also paces its own composite to 60 Hz, so a
  greedy client cannot do that again. With both, the whole scene idles under 1%.
- The host window is **activated and pinned above** the other host windows at startup (EWMH
  `_NET_ACTIVE_WINDOW` + `_NET_WM_STATE_ABOVE`). A nested window that is buried receives **no clicks at all** —
  they land on whatever the host desktop has there instead, which is what "I click File and nothing happens"
  turned out to be.
