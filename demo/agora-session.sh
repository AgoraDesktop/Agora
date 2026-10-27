#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

### The default Agora development session: window server, wallpaper, Workspace, the Dock.
#
#   window-server          nested on the X11 desktop, and it GRABS NOTHING: no XGrabPointer, no XGrabKeyboard
#   Workspace              the desktop, its icons and the application menu bar
#   the Dock               running applications as tiles, in a vertical strip on the right
#   wallpaper client       wallpaper.jpg at kCGDesktopWindowLevel: ONE frame, then it holds
#
# THIS IS THE SESSION, NOT THE DEMO. `agora-demo.sh` adds the controls application to the same scene to show two
# applications fighting over the menu bar; this script is the composition a login session will eventually start.
#
# Usage:  demo/agora-session.sh [WIDTHxHEIGHT]
#         AGORA_DESKTOP=/path demo/agora-session.sh
#         AGORA_WALLPAPER=/path/to/image.jpg demo/agora-session.sh
#         AGORA_DOCK_POSITION=left demo/agora-session.sh     # the Dock's alternative side
#         AGORA_DPI=57.97 demo/agora-session.sh              # force the output scale (dots per inch)
#         AGORA_UI_SCALE=1.25 demo/agora-session.sh          # a comfort factor on top of it (1.0 is the default)
#         AGORA_CURSOR_THEME=/path demo/agora-session.sh     # another Xcursor theme for the pointer
# Ctrl-C stops everything.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SERVER_BIN="$ROOT/window-server/build/window-server"
CLIENT_BIN="$ROOT/window-server/build/tests/window-server-test-client"
# The bundle is laid out per platform and architecture — Contents/<platform>/<arch>/Workspace — and a
# developer's build tree carries exactly one slice, so the glob is exact.
WORKSPACE_BIN="$(ls "$ROOT"/workspace/build/Workspace.app/Contents/*/*/Workspace 2>/dev/null | head -1)"
# **THE DOCK IS A CLIENT OF ITS OWN**, laid out the same way — Contents/<platform>/<arch>/Dock — and started AFTER
# Workspace, because the compositor gives the menu bar to the application that maps first and the bar is Workspace's.
DOCK_BIN="$(ls "$ROOT"/dock/build/Dock.app/Contents/*/*/Dock 2>/dev/null | head -1)"

for b in "$SERVER_BIN" "$CLIENT_BIN" "$WORKSPACE_BIN" "$DOCK_BIN"; do
	if [ ! -x "$b" ]; then
		echo "the session needs $b" >&2
		echo "build it first: window-server, workspace and dock each have a build/ directory" >&2
		exit 1
	fi
done

GEOM="${1:-1280x720}"
W="${GEOM%x*}"
H="${GEOM#*x}"
# **A MULTI-HEAD X SCREEN MAKES THE DERIVED SCALE WRONG, SO THE SESSION CAN FORCE IT.** `DisplayWidth` spans every
# monitor while `DisplayWidthMM` describes one, so the derived dpi is not the panel's. AGORA_DPI states the real
# number and is passed to the compositor as `--dpi`; it applies to the X11 backend only.
#
# **AND AGORA_UI_SCALE IS THE OTHER HALF OF THE QUESTION: NOT "WHAT IS THIS PANEL" BUT "WHAT SUITS THIS PERSON".** It
# is a plain multiplier applied by the compositor AFTER the measured scale and after AGORA_DPI, so 1.25 is everything a
# quarter larger than the panel's honest answer; 1.0 (the default) changes nothing. It needs no line here at all: the
# compositor reads it from its own environment, which this script inherits and passes on, and its startup line in
# /tmp/agora-session-server.log shows the factor whenever it is not 1.
DPI=()
if [ -n "${AGORA_DPI:-}" ]; then
	DPI=(--dpi "${AGORA_DPI}")
fi

export DISPLAY="${DISPLAY:-:1}"
# The AppKit's dependencies live in the install prefix, and DT_RUNPATH is not inherited by a dependency. The build
# trees come first because the prefix also carries installed copies that may predate the tree.
SESSION_BUILD_LIBS=""
for d in "$ROOT"/libagora-*/build; do
	[ -d "$d" ] && SESSION_BUILD_LIBS="${SESSION_BUILD_LIBS}${SESSION_BUILD_LIBS:+:}$d"
done
export LD_LIBRARY_PATH="${SESSION_BUILD_LIBS}${SESSION_BUILD_LIBS:+:}${AGORA_PREFIX:-$ROOT/build-prefix}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export AGORA_ICON_THEME="${AGORA_ICON_THEME:-$ROOT/libagora-iconservices/themes/Frost}"

# **AND THE POINTER'S THEME, FROM THIS CHECKOUT RATHER THAN FROM AN INSTALL.** The compositor compiles in the prefix's
# `share/cursors/Vimix` and falls back to the arrow it draws itself, so a developer who has built the trees and
# never installed one would see that fallback — a pointer that is a session's own, not the desktop's design. Vimix
# lives in the window server's assets, and an explicit AGORA_CURSOR_THEME still wins.
export AGORA_CURSOR_THEME="${AGORA_CURSOR_THEME:-$ROOT/window-server/assets/cursors/Vimix}"

# **AND WHERE THE APPLICATIONS ARE, BECAUSE IN A DEVELOPMENT SESSION THEY ARE NOT IN /Applications.** Launch
# Services scans directories for `.app` bundles; the session's bundles live in the components' build trees, so
# without this the Dock can see an application's windows but not its bundle — which is a placeholder tile instead of
# an icon and a name. `AGORA_APPLICATIONS` is the door Launch Services already has for exactly this (it is
# colon-separated, and the code's comment names the case: "a test can point at a fixture tree").
export AGORA_APPLICATIONS="$ROOT/workspace/build:$ROOT/dock/build${AGORA_APPLICATIONS:+:$AGORA_APPLICATIONS}"

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SOCK="${AGORA_SESSION_SOCKET:-agora-session}"
DESK="${AGORA_DESKTOP:-$HOME/Desktop}"
WALLPAPER="${AGORA_WALLPAPER:-$ROOT/wallpaper.jpg}"

# **THE HOME DIRECTORY SET IS A LOGIN'S JOB, SO THE SESSION DOES IT.** A complete Agora installation
# carries the Mac OS X directories at the root (README, "The installation"), and each account's share of
# them — `~/Applications`, `~/Desktop`, `~/Library` and the folders beside them — is created when that
# account logs in. This session is the closest thing this tree has to a login (WORKSPACE-PLAN.md §2,
# W13), so it creates the same list `release/scripts/install-layout.sh --user` writes. THE TRASH IS THE
# ICON THAT MEASURED IT: the Dock draws `~/.Trash` as the can, and a machine that has never thrown
# anything away had no such directory, so the icon lookup fell back to a piece of paper.
for d in Applications Desktop Documents Downloads Movies Music Pictures Public \
         Library "Library/Application Scripts" "Library/Application Support" Library/Autosave \
         Library/Caches Library/Colors Library/Documentation Library/Fonts "Library/Input Methods" \
         Library/PreferencePanes Library/Preferences Library/Printers/PPDs .Trash; do
	mkdir -p "$HOME/$d"
done
mkdir -p "$DESK"
if [ -S "${RUNTIME}/${SOCK}" ]; then
	echo "a session socket already exists at ${RUNTIME}/${SOCK}" >&2
	echo "stop that session, or choose another with AGORA_SESSION_SOCKET=name" >&2
	exit 1
fi
rm -f "${RUNTIME}/${SOCK}.lock"

cleanup() {
	for pid in "${SPID:-}" "${WPID:-}" "${DOCKPID:-}" "${WALLPID:-}"; do
		[ -n "${pid:-}" ] && kill "$pid" 2>/dev/null
	done
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------------------------------------------
# 1. THE COMPOSITOR. `--input host` routes the pointer and keyboard that THIS WINDOW is given, so the session can
#    be left open without taking the host desktop's input away.
# ---------------------------------------------------------------------------------------------------------------
"$SERVER_BIN" --backend x11 --input host --socket "$SOCK" --frames 0 --width "$W" --height "$H" "${DPI[@]}" \
	>/tmp/agora-session-server.log 2>&1 &
SPID=$!
for _ in $(seq 1 60); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${RUNTIME}/${SOCK}" ]; then
	echo "FAIL: the window server never came up; its log follows" >&2
	cat /tmp/agora-session-server.log >&2
	exit 1
fi

# ---------------------------------------------------------------------------------------------------------------
# 2. WORKSPACE FIRST. The compositor gives the keyboard to the first surface that maps, and the menu bar belongs to
#    the active application. The desktop must own the bar; the wallpaper below it must not.
# ---------------------------------------------------------------------------------------------------------------
# `--seconds` IS THE TEST DOOR THAT KEEPS THE ORDINARY RUN LOOP GOING. Without it main.m defaults to
# three seconds and the desktop — the menu bar and the icon window — leaves the session.
AGORA_DESKTOP="$DESK" WAYLAND_DISPLAY="$SOCK" "$WORKSPACE_BIN" --seconds 1000000000 \
	>/dev/null 2>/tmp/agora-session-workspace.log &
WPID=$!
sleep 1.5

# ---------------------------------------------------------------------------------------------------------------
# 2b. THE DOCK, AFTER WORKSPACE AND BEFORE THE WALLPAPER. It is furniture at NSDockWindowLevel (20), below the
#     menu bar's level (24), and it reserves the right edge of the screen so no window is placed under it. It does
#     not own the bar: Workspace mapped first.
# ---------------------------------------------------------------------------------------------------------------
WAYLAND_DISPLAY="$SOCK" "$DOCK_BIN" >/tmp/agora-session-dock.log 2>&1 &
DOCKPID=$!
sleep 0.5

# ---------------------------------------------------------------------------------------------------------------
# 3. THE WALLPAPER: ONE FRAME, THEN HOLD. It redraws on every frame callback, so a still picture asks for one frame
#    rather than becoming a frame-rate generator.
#
#    **AND IT RENDERS AT THE COMPOSITOR'S OWN SCALE, BECAUSE IT IS THE ONE CLIENT THAT DOES NOT SPEAK THE EXTENSION.**
#    An AppKit application hears `agora_output.preferred_scale` — the output's real fraction, whatever produced it —
#    and rasterises at exactly that; the raw test client used as the wallpaper speaks neither that nor `wl_output`,
#    so a 1x wallpaper on a 1.333x output is magnified by the compositor and looks soft. It is given the scale the
#    server just printed, rounded up, and 1 (the client's own default) when the line cannot be read.
#
#    That printed number is the FINAL scale: the panel's own answer times AGORA_UI_SCALE, so a session at 1.25
#    comfort on a 1.333 output asks the wallpaper for 2x and is composited from a big enough buffer either way.
# ---------------------------------------------------------------------------------------------------------------
OUTPUT_SCALE=$(sed -n 's/.*(scale \([0-9.]*\).*/\1/p' /tmp/agora-session-server.log | head -1)
WALLPAPER_SCALE=$(awk -v s="${OUTPUT_SCALE:-1}" 'BEGIN { n = int(s); if (n < s) n++; if (n < 1) n = 1; print n }')
if [ -f "$WALLPAPER" ]; then
	WAYLAND_DISPLAY="$SOCK" "$CLIENT_BIN" --width "$W" --height "$H" --image "$WALLPAPER" --buffer-scale "$WALLPAPER_SCALE" \
		--x 0 --y 0 --level $(( -2147483648 + 20 )) --frames 1 --hold >/dev/null 2>&1 &
else
	WAYLAND_DISPLAY="$SOCK" "$CLIENT_BIN" --width "$W" --height "$H" --colour 48240E --buffer-scale "$WALLPAPER_SCALE" \
		--x 0 --y 0 --level $(( -2147483648 + 20 )) --frames 1 --hold >/dev/null 2>&1 &
fi
WALLPID=$!
sleep 1

echo "server=$SPID  workspace=$WPID  dock=$DOCKPID  wallpaper=$WALLPID"
SCALE_NOTE="output scale ${OUTPUT_SCALE:-1}"
[ -n "${AGORA_UI_SCALE:-}" ] && SCALE_NOTE="${SCALE_NOTE} = panel x ${AGORA_UI_SCALE} UI"
echo "  window server: ${W}x${H} on DISPLAY $DISPLAY (${SCALE_NOTE})"
echo "  Wayland socket: ${RUNTIME}/${SOCK}"
echo "  desktop: ${DESK}"
echo "  wallpaper: ${WALLPAPER}"
echo "  dock: ${AGORA_DOCK_POSITION:-right} (vertical, below the menu bar)"
echo "  menu bar: Workspace"
echo "  logs: /tmp/agora-session-{server,workspace,dock}.log"
echo "Ctrl-C stops the session."

# ---------------------------------------------------------------------------------------------------------------
# 4. PUT THE HOST WINDOW IN FRONT. A buried nested window receives no clicks at all; EWMH's activate request is what
#    a taskbar sends, and the raise is the fallback.
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
    match = re.match(r'\s*(0x[0-9a-f]+)', line)
    if not match:
        continue
    if "mutter-x11-frames" in line or "frame" in line:
        frame = int(match.group(1), 16)
    elif re.search(r'\(\)\s+\d+x\d+', line):
        client = int(match.group(1), 16)
if client is None:
    print("  (no Agora window on the host display to raise)")
    raise SystemExit(0)

A_ACTIVE = x11.XInternAtom(d, b"_NET_ACTIVE_WINDOW", 0)
A_STATE = x11.XInternAtom(d, b"_NET_WM_STATE", 0)
A_ABOVE = x11.XInternAtom(d, b"_NET_WM_STATE_ABOVE", 0)

def send(message_type, l0, l1, l2):
    event = XClientMessageEvent()
    ctypes.memset(ctypes.byref(event), 0, ctypes.sizeof(event))
    event.type = 33; event.send_event = 1; event.display = d; event.window = client
    event.message_type = message_type; event.format = 32
    event.l[0] = l0; event.l[1] = l1; event.l[2] = l2; event.l[3] = 1
    x11.XSendEvent(d, root, 0, 0x180000, ctypes.byref(event)); x11.XFlush(d); time.sleep(0.25)

send(A_ACTIVE, 1, 0, 0)
send(A_STATE, 1, A_ABOVE, 0)
if frame is not None:
    x11.XRaiseWindow(d, frame)
x11.XRaiseWindow(d, client)
x11.XFlush(d)
print(f"  host window {hex(client)} activated and pinned above")
PY

wait "$SPID"
