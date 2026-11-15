# Architecture

<!-- What this Next.js app is, in one paragraph. Keep this file under ~150 lines: structure and rules only; history goes in ADRs, terms in the glossary. These are the Next.js adapter's default rules: amend them to fit. -->

## Routes

```
/                 app/page.tsx              page
/api/health       app/api/health/route.ts   route handler (GET)
```

## Modules

| Folder | Owns | Public seam |
|---|---|---|
| `app/` | Pages, layouts and route handlers (the App Router), and the components that use Next's runtime (`app/_components/`) | the URLs above |
| `lib/` | Code with no Next.js in it, used by client and server alike | each file's exports |
| `server/` | Server-only code: secrets, the database, the file system | each file's exports, to server code only |
| `node_modules/` | Third-party code, as `pnpm-lock.yaml` locks it | each package's exports |

## Layers

`app` → `server` → `lib`

A module may import only from folders to its right, and from packages. Route segments in `app/` don't import one another; code two of them share moves into `app/_components/` when it uses Next's runtime (R9), else into `lib/`.

## Rules

Each rule has a stable number that is never reused. `Enforced by:` is `arch:<id>` (a check in the arch step), `typecheck`, `lint:<rule>`, `deviation` or `review`. Findings print as `file:line R<n> message`.

**R1.** The code typechecks under `strict`, and `tsconfig.json` turns none of strict's checks back off.
Enforced by: `typecheck`
Source: convention

**R2.** No promise is left floating: each is awaited, returned or handled.
Enforced by: `lint:@typescript-eslint/no-floating-promises`
Source: convention

**R3.** No `any` flows unchecked: values from `JSON.parse`, `response.json()` and other untyped sources are checked or narrowed before use.
Enforced by: `lint:@typescript-eslint/no-unsafe-assignment`, `lint:@typescript-eslint/no-unsafe-member-access`, `review`
Source: convention

**R4.** No lint rule is turned off in code: the lint step ignores `eslint-disable` comments; a rule that doesn't fit is changed in `eslint.config.mjs` by an amend.
Enforced by: `review`
Source: convention

**R5.** Every test asserts, and no test waits a fixed time.
Enforced by: `lint:assertion-free`, `lint:fixed-wait`
Source: convention (a sleep passes on a quiet machine and fails on a busy one)

**R6.** Client code never imports a server-only module. Client code is each `"use client"` file and everything it imports, on down; a server-only module is a file under `server/`, a route handler (`app/**/route.ts`), a file that imports the `server-only` package, and that package. A `"use server"` file of server actions is neither, and an import of types alone doesn't count. Secrets stay out of client code too.
Enforced by: `arch:client-server`, `review`
Source: convention (what a client module imports ships to the browser)

**R7.** Product code never checks how it is run: no test-only branches on `NODE_ENV`, `process.env.VITEST` or similar. Tests steer the app through config and seams (a handler's arguments, an injected client).
Enforced by: `review`
Source: convention (an app that knows it is under test hides what its tests check)

**R8.** Third-party code comes only from packages that `package.json` names with an exact version and `pnpm-lock.yaml` locks.
Enforced by: `review`
Source: convention

**R9.** Only `app/` (and a Pages Router's `pages/`) imports Next's runtime (`next` and `next/*`): code outside it is plain TypeScript, so a test runs it without Next. Tests and the files Next wants at the root (`middleware.ts`, `proxy.ts`, `instrumentation.ts`, `instrumentation-client.ts`, `next.config.ts`) are exempt.
Enforced by: `arch:next-in-app`
Source: convention

**R10.** Fonts come from `next/font/local` and files in the repo, never `next/font/google`, which `next build` downloads: the gates run offline.
Enforced by: `arch:fonts-local`
Source: convention

## Ratchet files

These are tracked and may only shrink; the `deviation` step fails when one grows.

- `tools/verify/ratchet/format_exclude.txt`: files the formatter skips.
- `tools/verify/ratchet/baseline.txt`: the Baseline, the findings that existed at adoption.

## Keeping it true

An amend lands as one change: the rule text, its check and any ratchet file. The arch step's sync check fails on an `arch:<id>` tag with no check, a check no rule cites, or a reused rule number; its lint-tags check fails on a `lint:<rule>` tag whose rule the lint step doesn't run (an ESLint rule off in `eslint --print-config`). The `review`-tagged rules make up the verifier's rubric.
