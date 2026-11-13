# Architecture

<!-- What this project is, in one paragraph. Keep this file under ~150 lines: structure and rules only; history goes in ADRs, terms in the glossary. -->

## Modules

| Folder | Owns | Public seam |
|---|---|---|

## Layers

<!-- The layer line: folders in backticks joined by →, top to bottom. A script may depend only on folders to its right. -->

## Rules

Each rule has a stable number that is never reused. `Enforced by:` is `arch:<id>` (a check in the arch step), `typecheck`, `lint:<rule>`, `deviation` or `review`. Findings print as `file:line R<n> message`.

## Ratchet files

These are tracked and may only shrink; the `deviation` step fails when one grows.

- `tools/verify/ratchet/baseline.txt`: the Baseline, the findings that existed at adoption.
