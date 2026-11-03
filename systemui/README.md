# systemui

**The System UI — the menu that drops from the System menu's square, and the About panel it opens.** It is a *client*
of the window server, and that split is the Mac's rather than an accident:

| who | what |
|---|---|
| `window-server` | the strip, the System menu's **square** and the OS mark inside it — furniture no application owns |
| `systemui` (this) | the **menu** itself: its rows, the highlight chip, the tracking loop and the About panel |

A menu is text, a hover chip and a tracking loop, and all three are the AppKit's. So the menu is an ordinary client
window at the pop-up level, composited like any application's, drawn with the same toolkit and therefore the same
measurements (`NSMenuView`, `NSMenuItemCell`) as every other menu on the desktop. The server's half of the bargain is
one forwarded click.

## The one event

```
agora_shell.claim_system_menu            (version 19)  — "I am the system UI"
agora_shell.system_menu_invoked x y w h  (version 19)  — "the square was clicked; open the menu here"
```

The square's click is **consumed** by the server: it is delivered to no surface, and neither is its release. A press
that lands while a menu is already tracking is the menu's own dismissal and is *not* forwarded — a second
`system_menu_invoked` would ask this process to open a menu it is already tracking, which its tracking loop refuses.
See `window-server/src/seat.c` and `src/shell.c`.

One claimant at a time and the last one wins, so a restarted `SystemUI` takes over from the one that died; the claim is
cleared when the claiming client goes away.

## The menu

```
About this Computer…
──────────
System Preferences
──────────
Restart
Shut Down
──────────
Log Out
```

**The four grey rows are deliberate.** "A row with no target is a disabled row" is this tree's convention
(`workspace/src/WSMainMenu.m`): `-[NSMenu update]` enables a row only when its action has a target that answers it.
Restart, Shut Down and Log Out need a session manager the tree has not got; System Preferences needs an application it
has not got. Listing them and showing them unavailable says what the desktop *is*, not only what it can do today.

## About this Computer

A floating, non-activatable panel — this process has no menu bar of its own to put in the strip, so a click that
activated it would empty the bar. It reads the machine rather than asking anyone:

```
Agora <version>              the checkout this session was built from (`git describe`, baked in by the configure)
Debian GNU/Linux 13 (kernel …)   /etc/os-release PRETTY_NAME
Intel(R) Xeon(R) CPU …           /proc/cpuinfo, model name
Memory 62.8 GB                    sysinfo(2)
Graphics nvidia, PCI 10de:1c03    /sys/class/drm/card0/device/uevent — driver and PCI identifier
Display 1280x720, 96 dpi          NSScreen: points and the panel's own dots per inch
```

A line the platform cannot answer is **omitted**, not filled with a zero: a panel that says "0 GB" is worse than one
that says nothing. `--dump-about` prints exactly the lines the panel draws, which is what
`tests/check_about.sh` checks without a session.

**Known limit:** the graphics line names the kernel driver and the PCI identifier, not a marketing name — that needs a
PCI vendor/device table this tree does not carry yet. `lspci -nn` prints the same identifier in brackets.

## Build and run

```sh
cmake -S systemui -B systemui/build -DCMAKE_PREFIX_PATH=$PWD/build-prefix -DCMAKE_INSTALL_PREFIX=$PWD/build-prefix
cmake --build systemui/build -j"$(nproc)"
ctest --test-dir systemui/build --output-on-failure
```

`demo/agora-session.sh` starts it after Workspace and before the wallpaper.
