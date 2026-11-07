#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

### install.sh — build and install the testing Agora, and leave `agora-session` on the PATH.
#
#   ./install.sh                      # install into ~/.local
#   ./install.sh --prefix /opt/agora  # somewhere else
#   ./install.sh --jobs 8             # parallel builds (default: every CPU)
#   ./install.sh --only-prefix        # install only; assume the components are built
#
# **THIS IS THE TESTING INSTALLER, AND IT INSTALLS A SESSION.** A complete Agora installation is every component in
# `release/components.conf`, packaged by `release/`; this script builds the set a *desktop session* actually starts —
# the Cocoa stack the applications are written against, the window server, and the four shell components — into one
# prefix, without root, and puts the one command a person types on their PATH. The pieces it leaves out are named at
# the end of the run rather than hidden.
#
# **NOTHING IS INSTALLED SYSTEM-WIDE AND NOTHING IS ASSUMED TO BE PRESENT.** The prefix defaults to `~/.local`, which
# needs no privileges and is already on most accounts' `PATH`; `~/.local/bin` is the directory the launcher lands in, so
# a session is `agora-session` from any shell once this returns.
#
# **IT IS A BUILD, SO IT TAKES AS LONG AS A BUILD DOES** — tens of minutes from an empty tree on a fast machine. What it
# does not do is ask a person to work out an order: each component is configured against this prefix, built, and
# installed, in the one order that lets the next one find it with `find_package()`.
#
# Requirements: clang-19 (or clang), cmake ≥ 3.24, pkg-config, and the system libraries the components name in their
# READMEs — wayland-server/client, wayland-protocols, xkbcommon, pixman, libdrm, gbm, libinput, libudev, libX11/Xext/
# Xrender, EGL/GLESv2, lcms2, libpng, libjpeg, freetype, harfbuzz, ICU, OpenSSL and zlib. A missing one stops the
# component that wants it with the library's name, and the log says which component.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$root"

prefix="$HOME/.local"
jobs=$(nproc 2>/dev/null || echo 4)
build_only=0
do_install=1

while [ $# -gt 0 ]; do
	case $1 in
		--prefix)      prefix=$2; shift 2 ;;
		--jobs)        jobs=$2; shift 2 ;;
		--build-only)  do_install=0; shift ;;
		--only-prefix) build_only=1; shift ;;
		-h|--help)     sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "install: unknown option: $1 (try --help)" >&2; exit 1 ;;
	esac
done

prefix=${prefix%/}
[ -n "$prefix" ] || { echo "install: an empty prefix is not a place to install into" >&2; exit 1; }

die() { echo "install: $*" >&2; exit 1; }

# ------------------------------------------------------------------ toolchain --
first_of() { for c in "$@"; do p=$(command -v "$c" 2>/dev/null) && { printf '%s' "$p"; return 0; }; done; return 1; }
cc=$(first_of clang-19 clang) || die "no C compiler found (tried clang-19, clang)"
cxx=$(first_of clang++-19 clang++) || die "no C++ compiler found (tried clang++-19, clang++)"
command -v cmake >/dev/null 2>&1 || die "cmake is not on the PATH"
command -v pkg-config >/dev/null 2>&1 || die "pkg-config is not on the PATH"

echo "install: prefix $prefix"
echo "install: cc $cc — $jobs jobs"

# **THE ORDER IS THE DEPENDENCY ORDER**, and it is the same rule `release/components.conf` states: a component appears
# only after every component it resolves with `find_package()`. `release/` is authoritative and carries the whole
# desktop; this list is the session subset of it, and the two differ only in what a session does not need:
#
#   libagora-webview   takes the system WPE WebKit (2.48+), a heavy optional dependency; the session embeds no page
#   terminal, forge     applications, not shell furniture; nothing the desktop starts needs them
#   viewer, music      likewise — the Dock draws a tile for an application it can find in the prefix, and these are
#                      not in it, so a session installed by this script has no picture viewer and no music player
#   widget-zoo         an empty repository
#
# **AND `window-server` IS BUILT WITH THE NESTED BACKEND ON**, because this is the testing install and a nested X11
# window is what a person can start on top of an existing desktop. `release/components.conf` keeps it OFF: the shipping
# compositor is DRM-only, and that decision is the release's to make, not this script's.
components="
libagora-objc -DLIBOBJC_INSTALL_BLOCK_COMPATIBILITY_HEADERS=OFF
libagora-dispatch
libagora-lcms2 -DLCMS2_BUILD_TOOLS=OFF
libagora-tsm
libagora-core
libagora-drawing
libagora-text
libagora-base
libagora-audio
libagora-data
libagora-launchservices
libagora-watch
libagora-iconservices
libagora-app
window-server -DAWS_WITH_X11=ON
workspace
dock
systemui
"

if [ "$build_only" -eq 0 ]; then
	while read -r name extra; do
		[ -n "$name" ] || continue
		src="$root/$name"
		bld="$src/build"
		log="/tmp/agora-install-$name.log"

		[ -f "$src/CMakeLists.txt" ] || die "$name has no CMakeLists.txt — is this a complete checkout (git submodule update --init)?"

		# **A FRESH TREE IS A RELEASE-SHAPED TREE; AN EXISTING ONE KEEPS WHAT A DEVELOPER CHOSE.** `BUILD_TESTING=OFF` is
		# what an install wants — no test executable is built, compiled or installed — but stating it unconditionally would
		# reconfigure a developer's tree and throw away the suites they had. The absence of the build tree is the honest
		# test for "nobody has configured this yet".
		testing=(-DBUILD_TESTING=OFF)
		[ -d "$bld" ] && testing=()

		echo "install: $name — configure"
		# shellcheck disable=SC2086  # `extra` is a list of cmake arguments, split on purpose
		if ! cmake -S "$src" -B "$bld" \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" -DCMAKE_OBJC_COMPILER="$cc" \
			-DCMAKE_PREFIX_PATH="$prefix" \
			-DCMAKE_INSTALL_PREFIX="$prefix" \
			"${testing[@]}" $extra >"$log" 2>&1; then
			echo "install: $name FAILED to configure — $log" >&2
			tail -20 "$log" >&2
			exit 1
		fi

		echo "install: $name — build"
		if ! cmake --build "$bld" --parallel "$jobs" >>"$log" 2>&1; then
			echo "install: $name FAILED to build — $log" >&2
			tail -20 "$log" >&2
			exit 1
		fi

		if [ "$do_install" -eq 1 ]; then
			echo "install: $name — install"
			cmake --install "$bld" --prefix "$prefix" >>"$log" 2>&1 || {
				echo "install: $name FAILED to install — $log" >&2
				exit 1
			}
		fi
	done <<< "$components"
fi

if [ "$do_install" -eq 1 ]; then
	# **THE SESSION ITSELF IS THE LAST THING INSTALLED, AND IT IS THE POINT OF THE EXERCISE.** The launcher is one script
	# that finds its prefix by being in it; installing it here rather than from a component is what keeps any single
	# component from having to know about its siblings.
	echo "install: agora-session"
	install -d "$prefix/bin" "$prefix/libexec" "$prefix/share"
	install -m755 "$root/release/scripts/agora-session" "$prefix/bin/agora-session"
fi

echo
echo "install: done"
echo "  session:  $prefix/bin/agora-session 1280x720"
case ":$PATH:" in
	*":$prefix/bin:"*) ;;
	*) echo "  NOTE: $prefix/bin is not on your PATH — run it by full path, or add that directory to PATH" ;;
esac
echo "  The session runs nested on an X11 desktop (DISPLAY is required), starts the window server, Workspace,"
echo "  the Dock and the System UI, and draws the wallpaper itself: the amber ramp, or AGORA_WALLPAPER=/path/to/a.jpg."
echo "  Not installed, by design: the web view (needs WPE WebKit), Terminal, Forge, Viewer, Music."
