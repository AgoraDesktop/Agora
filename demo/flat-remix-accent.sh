#!/usr/bin/env bash
# Render the Flat-Remix icon theme into the PNG layout libagora-iconservices reads, with its folders in
# Agora's accent colour, and say where the result is.
#
# Flat-Remix is GPL-3, so neither its SVG sources nor the PNGs rendered from them are committed — the sources
# are the checkout beside this script and the theme is built into the gitignored install prefix, exactly as
# theme-greybird is read at run time and never versioned. Nothing in this script is Flat-Remix's: it runs
# upstream's own recolouring (`color-folder/generate-colors.sh` swaps these same two folder literals).
#
# The accent is NSColor's `+cg_accentColor`: 164/154/255, the second tone 70% of it, the ratio upstream's own
# violet uses. The theme reader asks for `<size>x<size>[@2x]/<context>/<name>.png` at the sizes Frost ships.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:-$ROOT/flat-remix-master/Flat-Remix-Violet-Light}
OUT=${2:-$ROOT/build-prefix/share/icons/Flat-Remix-Accent}

SIZES=(16 22 24 32 48 64 96 128 256)
ACCENT='#a49aff'       # 164,154,255
ACCENT_DARK='#736cb3'  # 70% of it: the folder's second tone

SIZES_STR=${SIZES[*]}
export SRC OUT SIZES_STR ACCENT ACCENT_DARK

# One icon: recolour once, render it at every size and scale. The colour-variant folders (folder-blue-*,
# user-red-*) are other themes' art here and are skipped.
render_one () {
	local svg=$1 rel=${1#"$SRC"/} ctx name size scale px dir
	ctx=${rel%%/*} name=${rel##*/} name=${name%.svg}
	case $name in
		black-*|blue-*|brown-*|cyan-*|green-*|grey-*|magenta-*|orange-*|red-*|teal-*|violet-*|yellow-*) return 0 ;;
		*-black-*|*-blue-*|*-brown-*|*-cyan-*|*-green-*|*-grey-*|*-magenta-*|*-orange-*|*-red-*|*-teal-*|*-violet-*|*-yellow-*) return 0 ;;
	esac
	for size in $SIZES_STR; do
		for scale in 1 2; do
			px=$((size * scale))
			dir=$OUT/${size}x${size}$([ "$scale" = 2 ] && echo @2x)/$ctx
			mkdir -p "$dir"
			sed "s/#8c42ab/$ACCENT/g; s/#622e78/$ACCENT_DARK/g" "$svg" |
				rsvg-convert -w "$px" -h "$px" -o "$dir/$name.png" -
		done
	done
}
export -f render_one

# `places` and `mimetypes` are the contexts Icon Services looks in for a folder and for a file type; `actions`
# and `apps` are the UI's symbols (Tabler answers those, beside this theme) and application art (a bundle's
# own .icns), so neither is rendered.
find "$SRC/places/scalable" "$SRC/mimetypes/scalable" -name '*.svg' -print0 |
	xargs -0 -P "$(nproc)" -n 1 bash -c 'render_one "$1"' _

echo "built $(find "$OUT" -name '*.png' | wc -l) PNGs in $OUT"
echo "use it:  AGORA_ICON_THEME=$OUT demo/agora-demo.sh"
