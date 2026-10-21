#!/bin/bash
### The Agora demo: one window server, Workspace's desktop and menu bar, and the AppKit controls window.
#
#   window-server          nested on the X11 desktop, and it GRABS NOTHING: no XGrabPointer, no XGrabKeyboard
#   Workspace              the desktop, its icons and the application menu bar
#   appkit_controls_draw   the control layer, in a window of its own, with its own menu bar
#   test client            the wallpaper (wallpaper.jpg by default), at the desktop level: ONE frame, then it holds
#
# TWO APPLICATIONS, ONE MENU BAR, WHICH IS THE POINT OF THE SCENE: a menu bar belongs to the ACTIVE application.
# Workspace maps first and so it owns the bar; click the controls window and ITS menus replace it. That is the
# Mac's behaviour, and it is the thing this demo exists to show.
#
# Usage:  demo/agora-demo.sh [WIDTHxHEIGHT]
# Ctrl-C stops everything.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SERVER_BIN="$ROOT/window-server/build/window-server"
CLIENT_BIN="$ROOT/window-server/build/tests/window-server-test-client"
# The bundle is laid out per platform and architecture — Contents/<platform>/<arch>/Workspace — and a
# developer's build tree carries exactly one slice, so the glob is exact where a hand-written mapping
# (Linux/FreeBSD/MacOS × amd64/arm64) would be a second copy of libagora-core's vocabulary.
WORKSPACE_BIN="$(ls "$ROOT"/workspace/build/Workspace.app/Contents/*/*/Workspace 2>/dev/null | head -1)"
CONTROLS_BIN="$ROOT/libagora-app/build/tests/appkit_controls_draw"

for b in "$SERVER_BIN" "$CLIENT_BIN" "$WORKSPACE_BIN" "$CONTROLS_BIN"; do
	if [ ! -x "$b" ]; then
		echo "the demo needs $b" >&2
		echo "build it first: window-server, workspace and libagora-app each have a build/ directory" >&2
		exit 1
	fi
done

GEOM="${1:-1280x720}"
W="${GEOM%x*}"
H="${GEOM#*x}"

export DISPLAY="${DISPLAY:-:1}"
# The AppKit's own dependencies live in the install prefix, and DT_RUNPATH is not inherited by a dependency.
#
# **AND THE BUILD TREES COME FIRST, BECAUSE THE PREFIX ALSO CARRIES AN INSTALLED COPY OF EVERY ONE OF THEM.**
# Without this the scene loads whatever was last installed and misses everything the build has moved on from —
# MEASURED, two ways in one run: the controls window died with "undefined symbol ._OBJC_REF_CLASS_NSSplitView"
# because the installed AppKit predated the class it was built to show, and Workspace's destroy request was read by
# the server as `set_pointer_capture` ("message too short") because the installed library still spoke the older
# protocol. A build tree is the thing this script is running FROM; the prefix is what it falls back to.
DEMO_BUILD_LIBS=""
for d in "$ROOT"/libagora-*/build; do
	[ -d "$d" ] && DEMO_BUILD_LIBS="${DEMO_BUILD_LIBS}${DEMO_BUILD_LIBS:+:}$d"
done
export LD_LIBRARY_PATH="${DEMO_BUILD_LIBS}${DEMO_BUILD_LIBS:+:}${AGORA_PREFIX:-$ROOT/build-prefix}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# **THE ICON THEME IS THE VENDORED FROST, EVEN UNINSTALLED.** The library's compiled default is the install
# prefix's share/icons/Frost; a developer running the build trees may never have installed it. An explicit
# AGORA_ICON_THEME still wins, and an absent directory falls back to Icon Services' drawn generics.
export AGORA_ICON_THEME="${AGORA_ICON_THEME:-$ROOT/libagora-iconservices/themes/Frost}"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SOCK="agora-demo"
DESK="/tmp/agora-demo-desktop"
# **THE WALLPAPER IS AN IMAGE NOW, TEMPORARILY.** `AGORA_WALLPAPER` overrides it; a missing file falls back to the
# colour the server tests use, so the demo still runs in a tree without the picture.
WALLPAPER="${AGORA_WALLPAPER:-$ROOT/wallpaper.jpg}"

pkill -f "Workspace.app/Contents/" 2>/dev/null
pkill -f "backend x11" 2>/dev/null
pkill -f "appkit_controls_draw" 2>/dev/null
pkill -f "window-server-test-client" 2>/dev/null
sleep 1
rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"

rm -rf "$DESK"
mkdir -p "$DESK/Photos" "$DESK/Projects"
for n in hello.txt Notes.txt report.pdf README.txt Archive.zip Music; do printf 'x\n' > "$DESK/$n"; done

cleanup() {
	for pid in "${SPID:-}" "${WPID:-}" "${CPID:-}" "${WALLPID:-}"; do
		[ -n "${pid:-}" ] && kill "$pid" 2>/dev/null
	done
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------------------------------------------
# 1. THE COMPOSITOR. `--input host` routes the pointer and keyboard that THIS WINDOW is given, which is why the
#    scene can be left open without taking the host desktop's input away.
# ---------------------------------------------------------------------------------------------------------------
"$SERVER_BIN" --backend x11 --input host --socket "$SOCK" --frames 0 --width "$W" --height "$H" \
	>/tmp/agora-demo-server.log 2>&1 &
SPID=$!
for _ in $(seq 1 60); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${RUNTIME}/${SOCK}" ]; then
	echo "FAIL: the window server never came up; its log follows" >&2
	cat /tmp/agora-demo-server.log >&2
	exit 1
fi

# 2. **WORKSPACE FIRST, BECAUSE THE MENU BAR BELONGS TO THE ACTIVE APPLICATION.** The compositor gives the keyboard
#    to the first surface that maps (seat.c's initial-focus half of click-to-focus), so the desktop must map first
#    or its menus have nothing to sit on.
AGORA_DESKTOP="$DESK" WAYLAND_DISPLAY="$SOCK" "$WORKSPACE_BIN" --seconds 1000000000 \
	>/dev/null 2>/tmp/agora-demo-workspace.log &
WPID=$!
sleep 1.5

# 3. **THE CONTROLS DEMO, WITH NO `--seconds`.** That argument makes it pump its OWN loop, and a hand-pumped loop
#    cannot drive a menu bar — `NSMenuView` fetches events only while the application is running. With no argument
#    it calls `-[NSApplication run]`, which is what its controls and its menus both want.
WAYLAND_DISPLAY="$SOCK" "$CONTROLS_BIN" >/dev/null 2>/tmp/agora-demo-controls.log &
CPID=$!
sleep 1.5

# 4. **THE WALLPAPER: ONE FRAME, THEN HOLD.** This client redraws on every frame callback, so asking it for frames
#    for ever makes it a frame-rate generator — MEASURED at 233 composites a second and 86% of a core for pixels
#    that never change. A wallpaper is a still picture: one commit, and the buffer stays.
if [ -f "$WALLPAPER" ]; then
	WAYLAND_DISPLAY="$SOCK" "$CLIENT_BIN" --width "$W" --height "$H" --image "$WALLPAPER" --x 0 --y 0 \
		--level $(( -2147483648 + 20 )) --frames 1 --hold >/dev/null 2>&1 &
else
	WAYLAND_DISPLAY="$SOCK" "$CLIENT_BIN" --width "$W" --height "$H" --colour 48240E --x 0 --y 0 \
		--level $(( -2147483648 + 20 )) --frames 1 --hold >/dev/null 2>&1 &
fi
WALLPID=$!

sleep 1
echo "server=$SPID  workspace=$WPID  controls=$CPID  wallpaper=$WALLPID"
echo "  window server: ${W}${H:+x}${H} on DISPLAY $DISPLAY, socket ${RUNTIME}/${SOCK}"
echo "  wallpaper: ${WALLPAPER}"
echo "  menu bar: Workspace (active) — click the Controls window to give ITS menus the bar"

# ---------------------------------------------------------------------------------------------------------------
# 5. **AND THE HOST WINDOW IS PUT IN FRONT.** A nested window that is buried receives NO CLICKS AT ALL — they land
#    on whatever the host desktop has at that point instead, which is exactly what "I click File and nothing
#    happens" was. EWMH's activate request is what a taskbar sends; the raise is the fallback for a WM without it.
# ---------------------------------------------------------------------------------------------------------------
python3 - <<'PY' || true
import ctypes, re, subprocess, time

class XClientMessageEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
                ("format", ctypes.c_int), ("l", ctypes.c_long * 5), ("pad", ctypes.c_char * 96)]

x11 = ctypes.CDLL("libX11.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p; x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XDefaultRootWindow.restype = ctypes.c_ulong; x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x11.XInternAtom.restype = ctypes.c_ulong; x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
x11.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long,
                           ctypes.POINTER(XClientMessageEvent)]
x11.XRaiseWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XFlush.argtypes = [ctypes.c_void_p]
d = x11.XOpenDisplay(None)
if d is None:
    raise SystemExit(0)
root = x11.XDefaultRootWindow(d)

tree = subprocess.run(["xwininfo", "-root", "-tree"], capture_output=True, text=True).stdout
client = frame = None
for line in tree.splitlines():
    if '"Agora Window Server"' not in line:
        continue
    m = re.match(r'\s*(0x[0-9a-f]+)', line)
    if not m:
        continue
    if "mutter-x11-frames" in line or "frame" in line:
        frame = int(m.group(1), 16)
    elif re.search(r'\(\)\s+\d+x\d+', line):
        client = int(m.group(1), 16)
if client is None:
    print("  (no Agora window on the host display to raise)")
    raise SystemExit(0)

A_ACTIVE = x11.XInternAtom(d, b"_NET_ACTIVE_WINDOW", 0)
A_STATE = x11.XInternAtom(d, b"_NET_WM_STATE", 0)
A_ABOVE = x11.XInternAtom(d, b"_NET_WM_STATE_ABOVE", 0)

def send(message_type, l0, l1, l2):
    ev = XClientMessageEvent()
    ctypes.memset(ctypes.byref(ev), 0, ctypes.sizeof(ev))
    ev.type = 33; ev.send_event = 1; ev.display = d; ev.window = client
    ev.message_type = message_type; ev.format = 32
    ev.l[0] = l0; ev.l[1] = l1; ev.l[2] = l2; ev.l[3] = 1
    x11.XSendEvent(d, root, 0, 0x180000, ctypes.byref(ev)); x11.XFlush(d); time.sleep(0.25)

send(A_ACTIVE, 1, 0, 0)
send(A_STATE, 1, A_ABOVE, 0)
if frame is not None:
    x11.XRaiseWindow(d, frame)
x11.XRaiseWindow(d, client)
x11.XFlush(d)
print(f"  host window {hex(client)} activated and pinned above")
PY

echo "Ctrl-C stops the demo."
wait "$SPID"
