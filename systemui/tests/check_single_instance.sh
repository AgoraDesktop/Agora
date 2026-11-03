#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# ONE SYSTEM UI PER SESSION, PROVED BY THE TWO REFUSALS BEING DIFFERENT ONES.
#
# With the lock held by another process, the binary must refuse because the System UI is already running — and, with the
# lock free and no display, it must refuse for the OTHER reason. A test that only asserted the first would pass for a
# process that refused everything.
set -u

BINARY="${1:?usage: check_single_instance.sh SYSTEMUI}"
RUNTIME="$(mktemp -d)"
failures=0

check() {
	printf '  %s   %s\n' "$([ "$1" = 1 ] && echo 'ok  ' || echo 'FAIL')" "$2"
	[ "$1" = 1 ] || failures=$((failures + 1))
}

cleanup() {
	[ -n "${HOLDER:-}" ] && kill "${HOLDER}" 2>/dev/null
	rm -rf "${RUNTIME}"
}
trap cleanup EXIT

export XDG_RUNTIME_DIR="${RUNTIME}"
unset WAYLAND_DISPLAY

# THE HOLDER TAKES THE SAME LOCK THE PROGRAM TAKES — `flock(LOCK_EX)` on the session's own file.
python3 - "${RUNTIME}/agora-systemui.lock" <<'PY' &
import fcntl, sys, time
lock = open(sys.argv[1], "w")
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
time.sleep(10)
PY
HOLDER=$!
for _ in $(seq 1 50); do [ -s "${RUNTIME}/agora-systemui.lock" ] && break; sleep 0.1; done
sleep 0.2

OUT="$("${BINARY}" 2>&1)"; STATUS=$?
check "$([ "${STATUS}" = 0 ] && echo 1 || echo 0)" "a second launch exits 0 — being already running is not an error"
check "$(printf '%s' "${OUT}" | grep -q 'another System UI is running' && echo 1 || echo 0)" \
      "and says why: ${OUT}"

kill "${HOLDER}" 2>/dev/null; wait "${HOLDER}" 2>/dev/null; HOLDER=

# AND WITH THE LOCK FREE, THE SAME BINARY REFUSES FOR THE OTHER REASON — there is no compositor in this test.
OUT="$("${BINARY}" 2>&1)"; STATUS=$?
check "$([ "${STATUS}" = 1 ] && echo 1 || echo 0)" "with no System UI running it gets past the lock"
check "$(printf '%s' "${OUT}" | grep -q 'no window server' && echo 1 || echo 0)" \
      "and fails on the missing compositor instead: ${OUT}"

printf '%d failure(s)\n' "${failures}"
[ "${failures}" = 0 ]
