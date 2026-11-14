#!/usr/bin/env bash
# The Next.js adapter's part of adoption; factory/core/adopt.sh runs it from the
# project root once tools/verify/ is seeded:
#   bash factory/adapters/nextjs/adopt.sh [--new]
#
# It runs the seeded bootstrap (tools/verify/bootstrap: pnpm install
# --frozen-lockfile, then the smoke step's browser; the one step allowed the
# network), with the machine's
# tools/verify/local.env when there is one, so the prepare step and the Baseline
# that adoption runs next find the project's packages installed. With --new they
# are the skeleton's (new/package.json, locked by new/pnpm-lock.yaml).
#
# First it seeds the test configs from the skeleton, new/vitest.config.ts.txt and
# new/stryker.config.json.txt, as vitest.config.ts and stryker.config.json,
# unless the project has its own (with --new, the skeleton's): any
# vitest.config.* or vite.config.* (Vitest reads them in that order, so ours
# would win), or any stryker.config.*, stryker.conf.* or .stryker.conf(ig).*.
#
# A bootstrap that fails stops nothing here: prepare, next, reports what is
# missing (no pnpm-lock.yaml, a package its store lacks) and adoption stops
# there, keeping what it seeded. Fix it, run bash tools/verify/bootstrap, then
# bash factory/core/adopt.sh nextjs again, which resumes at the Baseline.
set -u

case "$#:${1:-}" in
	0: | 1:--new) ;;
	*)
		echo "usage: bash factory/adapters/nextjs/adopt.sh [--new]" >&2
		exit 2
		;;
esac

if [ ! -f tools/verify/bootstrap ]; then
	echo "adopt: no tools/verify/bootstrap; seed tools/verify/ first (factory/core/adopt.sh does)" >&2
	exit 1
fi
new_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/new"
# seed_config <file> <glob...>: copy new/<file>.txt to <file>, unless a config
# matching a glob is there: the tool would read the project's own, or ours first.
# Either way $config_in_use names the config the tool reads. A seeded Stryker
# config's vitest.configFile names $vitest_config, the Vitest config in use.
seed_config() {
	local config="$1" glob
	shift
	for glob in "$@"; do
		config_in_use="$(compgen -G "$glob" | head -n 1)"
		if [ -n "$config_in_use" ]; then
			echo "adopt: kept $config_in_use" >&2
			return 0
		fi
	done
	config_in_use="$config"
	sed "s#\"configFile\": \"vitest\.config\.ts\"#\"configFile\": \"$vitest_config\"#" "$new_dir/$config.txt" > "$config" || {
		echo "adopt: could not write $config" >&2
		exit 1
	}
}
# Vitest reads the first of these, in this order; Stryker its config's names.
vitest_config=vitest.config.ts
seed_config vitest.config.ts {vitest,vite}.config.{ts,mts,cts,js,mjs,cjs}
vitest_config="$config_in_use"
seed_config stryker.config.json 'stryker.config.*' 'stryker.conf.*' '.stryker.config.*' '.stryker.conf.*'
(
	if [ -f tools/verify/local.env ]; then
		set -a
		. ./tools/verify/local.env
		set +a
	fi
	bash tools/verify/bootstrap
) || echo "adopt: tools/verify/bootstrap failed (above); prepare says what is missing: fix it, run bash tools/verify/bootstrap, then bash factory/core/adopt.sh nextjs again" >&2
exit 0
