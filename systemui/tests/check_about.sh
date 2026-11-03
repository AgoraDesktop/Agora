#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# The About panel's lines, as the panel would draw them.
set -u

BINARY="${1:?usage: check_about.sh SYSTEMUI}"
failures=0

check() {
	printf '  %s   %s\n' "$([ "$1" = 1 ] && echo 'ok  ' || echo 'FAIL')" "$2"
	[ "$1" = 1 ] || failures=$((failures + 1))
}

LINES="$("${BINARY}" --dump-about 2>/dev/null)"
TITLE="$(printf '%s\n' "${LINES}" | head -1)"

check "$([ -n "${LINES}" ] && echo 1 || echo 0)" "--dump-about answers at least one line"
check "$(printf '%s' "${TITLE}" | grep -q '^Agora ' && echo 1 || echo 0)" "the title names the desktop: ${TITLE}"
check "$([ "$(printf '%s\n' "${LINES}" | wc -l)" -ge 2 ] && echo 1 || echo 0)" "and the machine follows the title"

printf '%s\n' "${LINES}" | sed 's/^/       /'
printf '%d failure(s)\n' "${failures}"
[ "${failures}" = 0 ]
