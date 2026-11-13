#!/usr/bin/env bash
# The done check: the factory's gate runner (factory/core/verify.sh). Run from the
# project root:
#   bash tools/verify.sh [--twice] [--keep-going] [--red] [--reuse] [step...]
exec bash "$(dirname "${BASH_SOURCE[0]}")/../factory/core/verify.sh" "$@"
