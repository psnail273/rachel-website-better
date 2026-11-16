#!/usr/bin/env bash
# Prime a pnpm store with the Next.js skeleton's packages, and a folder with the
# browsers its smoke step runs, for the adapter's tests:
#   bash factory/adapters/nextjs/tests/prime-store.sh <dir> [<browsers dir>]
# then set FACTORY_PNPM_STORE=<dir> and FACTORY_PLAYWRIGHT_BROWSERS=<browsers
# dir> (in the workspace's local.env). The one command of the adapter's tests
# that uses the network: it installs the
# skeleton's package.json, exactly as its pnpm-lock.yaml locks it, into a
# throwaway folder with <dir> as pnpm's store (and fetches the pnpm version
# packageManager pins, when the machine lacks it). It then proves the store is
# enough: a second install, offline, with no registry. With <browsers dir>, it
# then installs Chromium's headless shell, Firefox and WebKit there, at the
# builds the skeleton's Playwright pins (as bootstrap does), and proves each
# starts. Rerun it after the skeleton's lockfile changes; an existing store or
# folder keeps what it has and gains what it lacks. It installs no system
# libraries: when a browser won't start without some, it says so, naming the
# engine, and pnpm exec playwright install-deps <engine> (as root) installs them.
#
# Needs Node and pnpm (NODE_BIN and PNPM_BIN, else on PATH). pnpm's output goes
# to stderr; stdout is a line FACTORY_PNPM_STORE=<dir, absolute>, then with a
# browsers folder FACTORY_PLAYWRIGHT_BROWSERS=<it, absolute>.
# Exits 0 primed, 1 failed, 2 usage.
set -u

{ [ "$#" -eq 1 ] || [ "$#" -eq 2 ]; } && [ -n "$1" ] && [ -n "${2-x}" ] || {
	echo "usage: bash factory/adapters/nextjs/tests/prime-store.sh <dir> [<browsers dir>]" >&2
	exit 2
}
adapter="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$1" || exit 1
store="$(cd "$1" && pwd)"
browsers=""
if [ "$#" -eq 2 ]; then
	mkdir -p "$2" || exit 1
	browsers="$(cd "$2" && pwd)"
fi
for bin in "${PNPM_BIN:-}" "${NODE_BIN:-}"; do
	case "$bin" in */*) PATH="$(dirname "$bin"):$PATH" ;; esac
done
pnpm="${PNPM_BIN:-pnpm}"
command -v "$pnpm" > /dev/null 2>&1 || {
	echo "prime-store: no pnpm (PNPM_BIN, or pnpm on PATH)" >&2
	exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# install <folder> [pnpm option...]: the skeleton's packages into <folder>.
install() {
	local dir="$1"
	shift
	mkdir -p "$dir" &&
		sed 's/<project>/prime-store/g' "$adapter/new/package.json.txt" > "$dir/package.json" &&
		cp "$adapter/new/pnpm-lock.yaml.txt" "$dir/pnpm-lock.yaml" || return 1
	(cd "$dir" && pnpm_config_store_dir="$store" "$pnpm" install --frozen-lockfile "$@" >&2)
}

if ! install "$tmp/online"; then
	echo "prime-store: pnpm install into the store $store failed (above)" >&2
	exit 1
fi
if ! pnpm_config_offline=true pnpm_config_registry=http://127.0.0.1:9/ install "$tmp/offline"; then
	echo "prime-store: the store $store doesn't install the skeleton offline (above)" >&2
	exit 1
fi
echo "FACTORY_PNPM_STORE=$store"
[ -n "$browsers" ] || exit 0
if ! (cd "$tmp/online" && PLAYWRIGHT_BROWSERS_PATH="$browsers" node_modules/.bin/playwright install --only-shell chromium firefox webkit >&2); then
	echo "prime-store: playwright install --only-shell chromium firefox webkit into $browsers failed (above)" >&2
	exit 1
fi
for engine in chromium firefox webkit; do
	if ! (cd "$tmp/online" && PLAYWRIGHT_BROWSERS_PATH="$browsers" node --input-type=module -e "import { $engine } from \"@playwright/test\"; await (await $engine.launch()).close();" >&2); then
		echo "prime-store: $engine in $browsers doesn't start (above); when it names missing system libraries, install them as root: pnpm exec playwright install-deps $engine" >&2
		exit 1
	fi
done
echo "FACTORY_PLAYWRIGHT_BROWSERS=$browsers"
