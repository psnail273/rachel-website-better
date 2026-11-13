# Architecture

<!-- What this Godot project is, in one paragraph. Keep this file under ~150 lines: structure and rules only; history goes in ADRs, terms in the glossary. These are the Godot adapter's default rules: amend them to fit. -->

## Scene tree

```
Main                          main/main.tscn
```

## Modules

| Folder | Owns | Public seam |
|---|---|---|
| `main/` | The main scene | none |
| `addons/` | Third-party code | none |

## Layers

`main` → `config`

A script may depend only on folders to its right. Script edges count: `class_name` use, `preload`/`load` and `extends`. Data edges are exempt, such as a `.tres` listing scenes or a `.tscn` instancing another scene.

## Rules

Each rule has a stable number that is never reused. `Enforced by:` is `arch:<id>` (a check in the arch step), `typecheck`, `lint:<rule>`, `deviation` or `review`. Findings print as `file:line R<n> message`.

**R1.** The project has no autoloads.
Enforced by: `arch:no-autoloads`
Source: convention

**R2.** A plain model (each class the arch step's `PLAIN_MODELS` names, and every product script under a folder its `PLAIN_MODEL_DIRS` names) is a `RefCounted` with no Node fields, `get_tree`, `await` or preloads.
Enforced by: `arch:model-plain`
Source: convention

**R3.** Script dependencies go only down the layer line.
Enforced by: `arch:layers`
Source: convention

**R4.** A signal connection's target is the emitter or one of its ancestors, with no exceptions.
Enforced by: `arch:signals-up`
Source: convention

**R5.** No script reaches up the tree: no `get_parent`, `owner.`, `../`, `get_tree().root`, `/root/` or `current_scene`, and no allowlist.
Enforced by: `arch:no-reach-up`
Source: convention

**R6.** No warning is suppressed.
Enforced by: `arch:no-warning-ignore`
Source: convention

**R7.** Every product script has a test at `tests/<path>/<name>_test.gd` (a strict mirror); allowlisted `@tool` scripts are exempt.
Enforced by: `arch:mirrored-tests`
Source: convention

**R8.** Files and folders are snake_case, and nodes are PascalCase.
Enforced by: `arch:naming`
Source: convention

**R9.** Third-party code lives only under `addons/`.
Enforced by: `arch:third-party`
Source: convention

**R10.** `@tool` scripts come from the tracked allowlist, keep editor logic behind `Engine.is_editor_hint()` and never write scene data they don't own; adding one is a declared Deviation, not an amend.
Enforced by: `arch:tool-allowlist`, `review`
Source: convention

**R11.** No `@export` or `node_paths` reference points at a node outside the scene's own subtree.
Enforced by: `arch:no-sideways-refs`
Source: convention

**R12.** Tunables and colours are `@export`ed on a config resource or a scene node, never a script `const`, except a const marked `## invariant`.
Enforced by: `arch:no-tunable-consts`
Source: convention

**R13.** Fixed layout lives in `.tscn` scenes, and runtime-spawned things are instanced from their own scenes, with no `.new()` on a visual node type outside the allowlist.
Enforced by: `arch:no-visual-new`, `review`
Source: convention

**R14.** Product code never checks how it is run: no command-line arguments, environment variables, or build, editor, debugger or display-server checks outside the allowlist; a `@tool` script may call `Engine.is_editor_hint()`. Tests and smoke runs steer the game through config and seams.
Enforced by: `arch:run-mode`, `review`
Source: convention (a game that knows it is under test hides what its tests check)

## Ratchet files

These are tracked and may only shrink; the `deviation` step fails when one grows.

- `tools/verify/ratchet/tool_scripts.txt`: the `@tool` allowlist.
- `tools/verify/ratchet/visual_new.txt`: the `.new()` allowlist.
- `tools/verify/ratchet/run_mode.txt`: the run-mode allowlist.
- `tools/verify/ratchet/format_exclude.txt`: files the formatter skips.
- `tools/verify/ratchet/baseline.txt`: the Baseline, the findings that existed at adoption.

## Keeping it true

An amend lands as one change: the rule text, its check and any ratchet file. The arch step's sync check fails on an `arch:<id>` tag with no check, a check no rule cites, or a reused rule number. The `review`-tagged rules make up the verifier's rubric.
