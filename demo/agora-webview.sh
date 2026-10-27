#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# A web page on the Agora desktop: the window server, and one application with a WKWebView in it.
#
#   demo/agora-webview.sh                       # the built-in page
#   demo/agora-webview.sh https://example.org   # a URL, if this machine has a network
#   demo/agora-webview.sh --session             # plus Workspace and the Dock, so the desktop is there too
#
# **THE WINDOW IS 86% OF THE OUTPUT, AND A PAGE CAN WANT MORE THAN THAT.** The application sizes itself to the screen it
# is on; a two-column page — osnews.com is the one this was measured on — lays its sidebar out beside the text and needs
# about 1000 points before it stops. On a small output the sidebar is therefore CLIPPED BY THE PAGE'S OWN LAYOUT, not by
# the view: the engine renders exactly the width it was given, the view draws all of it, and what is missing is width.
# Give the session a bigger output when that matters: `demo/agora-webview.sh 1440x900 <url>`.
#
# Three environment variables exist for looking at the result rather than living in it:
#   AGORA_SCREENSHOT=/tmp/page.ppm   the compositor writes the frame it composited when it stops
#   AGORA_CAPTURE_AFTER=8            how long the page gets before that happens
#   AGORA_WPE_PREFIX=~/Development/wpewebkit/agora/prefix
#                                    use a locally built WPE WebKit (ENABLE_DRAG_SUPPORT=ON): real drags, not shift-clicks
#   AGORA_SECONDS=20                 the application closes itself, so the run ends without a person
#
# **A CAPTURE STOPS THE COMPOSITOR FIRST, AND THAT IS NOT A DETAIL.** The frame is written on the compositor's exit path,
# so an application that has already quit has no window in it — MEASURED as an empty desktop that looked exactly like a
# window that never appeared. With AGORA_SCREENSHOT set, the application runs in the background and the compositor is
# signalled while it is still drawing.
#
# **THIS IS THE SMALLEST SESSION THAT SHOWS THE CLASS WORKING**, and it is deliberately not part of
# `agora-session.sh`: that script is the composition a login will start, and a browser is an application, not furniture.
# What this starts is one application whose window is a page — AppKit paints the engine's frames into a window's buffer
# and the compositor composites them, which is the hop every offscreen test stops short of.
#
# Ctrl-C stops everything.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SERVER_BIN="$ROOT/window-server/build/window-server"
WEBVIEW_BIN="$ROOT/libagora-webview/build/agora-webview"
WORKSPACE_BIN="$(ls "$ROOT"/workspace/build/Workspace.app/Contents/*/*/Workspace 2>/dev/null | head -1)"
DOCK_BIN="$(ls "$ROOT"/dock/build/Dock.app/Contents/*/*/Dock 2>/dev/null | head -1)"

W=960
H=720
WANT_SESSION=0
URL=""

for arg in "$@"; do
	case "$arg" in
	--session)
		WANT_SESSION=1
		;;
	[0-9]*x[0-9]*)
		W="${arg%x*}"
		H="${arg#*x}"
		;;
	--help|-h)
		sed -n '5,15p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		URL="$arg"
		;;
	esac
done

for b in "$SERVER_BIN" "$WEBVIEW_BIN"; do
	if [ ! -x "$b" ]; then
		echo "the session needs $b" >&2
		echo "build it first: window-server and libagora-webview each have a build/ directory" >&2
		exit 1
	fi
done
if [ "$WANT_SESSION" = "1" ] && [ ! -x "$WORKSPACE_BIN" ]; then
	echo "--session needs Workspace at $WORKSPACE_BIN" >&2
	exit 1
fi

export DISPLAY="${DISPLAY:-:1}"
SOCK="agora-webview-session-$$"
export WAYLAND_DISPLAY="$SOCK"

# The AppKit's dependencies live in the install prefix, and DT_RUNPATH is not inherited by a dependency. The build trees
# come first because the prefix also carries installed copies that may predate the tree.
SESSION_BUILD_LIBS=""
for d in "$ROOT"/libagora-*/build; do
	[ -d "$d" ] && SESSION_BUILD_LIBS="${SESSION_BUILD_LIBS}${SESSION_BUILD_LIBS:+:}$d"
done
export LD_LIBRARY_PATH="${SESSION_BUILD_LIBS}${SESSION_BUILD_LIBS:+:}${AGORA_PREFIX:-$ROOT/build-prefix}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# **A LOCALLY BUILT WPE WEBKIT, WHEN ONE IS NAMED, AND THE DRAG THAT GOES WITH IT.** The system library is built with
# `ENABLE_DRAG_SUPPORT=OFF`, so the view emulates a text selection with shift-clicks; a fork with it ON (see
# `~/Development/wpewebkit`) selects the way a browser does. The library and the instruction have to travel together:
# a real drag sent to the system library selects NOTHING — MEASURED, 0 characters where the emulation selects 29.
if [ -n "${AGORA_WPE_PREFIX:-}" ]; then
	export LD_LIBRARY_PATH="${AGORA_WPE_PREFIX}/lib:$LD_LIBRARY_PATH"
	export AGWEBVIEW_REAL_DRAG=1
fi
export AGORA_ICON_THEME="${AGORA_ICON_THEME:-$ROOT/libagora-iconservices/themes/Frost}"
export AGORA_CURSOR_THEME="${AGORA_CURSOR_THEME:-$ROOT/window-server/assets/cursors/Vimix}"

cleanup() {
	# **THE SERVER IS KILLED AND WAITED FOR, IN THAT ORDER.** The screenshot is written on the server's ordinary exit
	# path, so a cleanup that signalled it and went on to delete the socket would race the write it was waiting for.
	for pid in "${APP_PID:-}" "${WS_PID:-}" "${DOCK_PID:-}"; do
		[ -n "$pid" ] && kill "$pid" 2>/dev/null
	done
	[ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
	for pid in "${APP_PID:-}" "${WS_PID:-}" "${DOCK_PID:-}" "${SERVER_PID:-}"; do
		[ -n "$pid" ] && wait "$pid" 2>/dev/null
	done
	rm -f "${XDG_RUNTIME_DIR:-/tmp}/${SOCK}" "${XDG_RUNTIME_DIR:-/tmp}/${SOCK}.lock"
}
trap cleanup EXIT INT TERM

DPI=()
if [ -n "${AGORA_DPI:-}" ]; then
	DPI=(--dpi "${AGORA_DPI}")
fi
SHOT=()
if [ -n "${AGORA_SCREENSHOT:-}" ]; then
	SHOT=(--screenshot "${AGORA_SCREENSHOT}")
fi
APP_ARGS=()
if [ -n "${AGORA_SECONDS:-}" ]; then
	APP_ARGS=(--seconds "${AGORA_SECONDS}")
fi

"$SERVER_BIN" --backend x11 --input host --socket "$SOCK" --frames 0 --width "$W" --height "$H" "${DPI[@]}" "${SHOT[@]}" \
	>"$ROOT/demo/.agora-webview-server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 100); do
	[ -S "${XDG_RUNTIME_DIR:-/tmp}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${XDG_RUNTIME_DIR:-/tmp}/${SOCK}" ]; then
	echo "the window server never came up; see demo/.agora-webview-server.log" >&2
	exit 1
fi

# **WORKSPACE MAPS FIRST WHEN IT IS ASKED FOR**, because the compositor gives the menu bar to the application that maps
# first and the bar is Workspace's.
if [ "$WANT_SESSION" = "1" ]; then
	"$WORKSPACE_BIN" --seconds 1000000 >/dev/null 2>&1 &
	WS_PID=$!
	sleep 1
	if [ -x "$DOCK_BIN" ]; then
		"$DOCK_BIN" >/dev/null 2>&1 &
		DOCK_PID=$!
		sleep 0.5
	fi
fi

run_app() {
	if [ -n "$URL" ]; then
		"$WEBVIEW_BIN" "$URL" "${APP_ARGS[@]}"
	else
		"$WEBVIEW_BIN" "${APP_ARGS[@]}"
	fi
}

if [ -n "${AGORA_SCREENSHOT:-}" ]; then
	run_app &
	APP_PID=$!
	sleep "${AGORA_CAPTURE_AFTER:-8}"
	# **THE COMPOSITOR GOES FIRST, SO ITS FRAME HAS A WINDOW IN IT.** Then the application, which has nothing left to do.
	kill -TERM "$SERVER_PID" 2>/dev/null
	wait "$SERVER_PID" 2>/dev/null
	SERVER_PID=""
	kill "$APP_PID" 2>/dev/null
	wait "$APP_PID" 2>/dev/null
	APP_PID=""
	echo "the frame the compositor stopped on is ${AGORA_SCREENSHOT}"
else
	run_app
fi
