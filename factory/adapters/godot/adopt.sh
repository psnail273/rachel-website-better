#!/usr/bin/env bash
# The Godot adapter's part of adoption; factory/core/adopt.sh runs it from the
# project root once tools/verify/ is seeded:
#   bash factory/adapters/godot/adopt.sh [--new]
#
# With --new (a new project, from the skeleton in new/), it first vendors gdUnit4
# under addons/gdUnit4, at the version tools/verify/pins pins, the way the tests
# step expects it. It copies the addon folder $FACTORY_GDUNIT4 names (another
# project's addons/gdUnit4, say) when set; otherwise it downloads the pinned
# release's source archive from GitHub (curl and unzip), checked against the
# archive's sha256 pinned below before it is unpacked; a pin of another
# gdUnit4 version needs FACTORY_GDUNIT4. Either way the copy's plugin.cfg
# must carry the pinned version. An addons/gdUnit4 already there is kept.
#
# The seeded tools/verify/ holds a .gd (the arch probe) and lies outside the scope,
# so prepare's scope cross-check needs every export preset to leave it out: this
# adds `tools/*` to each preset's exclude_filter that lacks it. A project with no
# export_presets.cfg is left alone; CRLF line endings are kept.
set -u

# The gdUnit4 release the adapter's pins name, and the sha256 of its source
# archive, checked before the archive is unpacked.
GDUNIT4_ARCHIVE='https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/tags/v%s.zip'
GDUNIT4_VERSION=6.2.2
GDUNIT4_SHA256=ddb44730ffb9cd77fd70d283753450759b00c5016143d7572bf63625f64d5433

case "$#:${1:-}" in
	0: | 1:--new) ;;
	*)
		echo "usage: bash factory/adapters/godot/adopt.sh [--new]" >&2
		exit 2
		;;
esac

# gdunit_version <plugin.cfg>: the version it declares.
gdunit_version() {
	tr -d '\r' < "$1" | sed -n 's/^version="\(.*\)"$/\1/p'
}

# sha256_of <file>: the file's sha256, in hex.
sha256_of() {
	if command -v sha256sum > /dev/null 2>&1; then
		sha256sum "$1"
	else
		shasum -a 256 "$1"
	fi | awk '{ print $1 }'
}

# vendor_gdunit: put the pinned gdUnit4 under addons/gdUnit4.
vendor_gdunit() {
	local pin src tmp status=0
	if [ -e addons/gdUnit4 ]; then
		echo "adopt: kept addons/gdUnit4" >&2
		return 0
	fi
	pin="$(tr -d '\r' < tools/verify/pins | sed -n 's/^gdunit4 \([^ ]*\)$/\1/p')"
	[ -n "$pin" ] || {
		echo "adopt: tools/verify/pins pins no gdunit4" >&2
		return 1
	}
	tmp="$(mktemp -d)"
	src="${FACTORY_GDUNIT4:-}"
	if [ -z "$src" ] && [ "$pin" != "$GDUNIT4_VERSION" ]; then
		echo "adopt: tools/verify/pins pins gdUnit4 $pin, and the adapter knows the archive checksum of $GDUNIT4_VERSION only; set FACTORY_GDUNIT4 to a copy of $pin's addons/gdUnit4" >&2
		status=1
	elif [ -z "$src" ]; then
		# shellcheck disable=SC2059
		echo "adopt: downloading gdUnit4 $pin from $(printf "$GDUNIT4_ARCHIVE" "$pin")" >&2
		# shellcheck disable=SC2059
		if curl -fsSL -o "$tmp/gdunit4.zip" "$(printf "$GDUNIT4_ARCHIVE" "$pin")"; then
			if [ "$(sha256_of "$tmp/gdunit4.zip")" != "$GDUNIT4_SHA256" ]; then
				echo "adopt: the downloaded gdUnit4 $pin archive isn't the one pinned (sha256 $GDUNIT4_SHA256); nothing was unpacked" >&2
				status=1
			elif unzip -q "$tmp/gdunit4.zip" -d "$tmp/x"; then
				src="$(find "$tmp/x" -mindepth 3 -maxdepth 3 -type d -path '*/addons/gdUnit4' | head -n 1)"
			fi
		fi
		[ "$status" -ne 0 ] || [ -n "$src" ] || {
			echo "adopt: could not download gdUnit4 $pin; set FACTORY_GDUNIT4 to a copy of its addons/gdUnit4" >&2
			status=1
		}
	fi
	if [ "$status" -eq 0 ]; then
		if [ ! -f "$src/plugin.cfg" ]; then
			echo "adopt: $src has no plugin.cfg; FACTORY_GDUNIT4 names gdUnit4's addons/gdUnit4 folder" >&2
			status=1
		elif [ "$(gdunit_version "$src/plugin.cfg")" != "$pin" ]; then
			echo "adopt: $src is gdUnit4 $(gdunit_version "$src/plugin.cfg"), but tools/verify/pins pins $pin" >&2
			status=1
		else
			mkdir -p addons && cp -R "$src" addons/gdUnit4 || status=1
		fi
	fi
	rm -rf "$tmp"
	return "$status"
}

if [ "${1:-}" = --new ]; then
	vendor_gdunit || exit 1
fi

presets=export_presets.cfg
[ -f "$presets" ] || exit 0

eol='\n'
grep -qU $'\r$' "$presets" && eol='\r\n'
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
tr -d '\r' < "$presets" | awk -v eol="$eol" '
	/^exclude_filter="/ {
		value = $0
		sub(/^exclude_filter="/, "", value)
		sub(/"$/, "", value)
		n = split(value, part, /[ \t]*,[ \t]*/)
		has = 0
		for (i = 1; i <= n; i++) if (part[i] == "tools/*") has = 1
		if (!has) value = (value ~ /^[ \t]*$/) ? "tools/*" : value ", tools/*"
		$0 = "exclude_filter=\"" value "\""
	}
	{ printf "%s" eol, $0 }
' > "$tmp" || exit 1
cmp -s "$tmp" "$presets" || cp "$tmp" "$presets"
