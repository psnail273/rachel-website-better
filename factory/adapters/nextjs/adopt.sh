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
(
	if [ -f tools/verify/local.env ]; then
		set -a
		. ./tools/verify/local.env
		set +a
	fi
	bash tools/verify/bootstrap
) || echo "adopt: tools/verify/bootstrap failed (above); prepare says what is missing: fix it, run bash tools/verify/bootstrap, then bash factory/core/adopt.sh nextjs again" >&2
exit 0
