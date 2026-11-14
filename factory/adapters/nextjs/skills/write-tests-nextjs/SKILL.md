---
name: write-tests-nextjs
description: Write Vitest tests for a Build Brief's red phase in a Next.js app: public seams, hand-written expected values, typed stubs, fakes for the network, no fixed waits. Use when writing or fixing tests.
---

Tests written first, from a Build Brief, before the code exists. Each one pins a criterion of the brief so that only a correct implementation turns it green. The Verifier reads your tests against the **rubric** below, and the gates check the **gate rules** by script, so every item here is one you control.

## Red phase

The red commit holds the brief's named tests plus **typed stubs** of its named seams, and nothing else. It becomes the **Lock**: after it, any edit to those tests is a Deviation.

1. **Beside the code.** Each module `<path>/<name>.ts` (or `.tsx`) gets its tests in `<path>/<name>.test.ts` (`.test.tsx` for one that renders), importing from `vitest` explicitly: `import { describe, expect, it, vi } from "vitest";`. Add to the test file when it exists. Tests that span modules go under `tests/`.
2. **Names.** Name each test (`it("<behaviour>", ...)`) exactly as the brief lists it, character for character. The gate reads each result as `<file> > <describe> > <title>` (`lib/cart.test.ts > total > adds the prices`), so a test keeps the file and `describe` blocks the brief gives it, and no two tests in a file share a name.
3. **Typed stubs.** Each seam the brief names exists with its real signature: typed parameters, a typed return, exported under the name the brief gives. Its body returns the empty value of its type (`0`, `false`, `""`, `[]`, `null` where the type allows it, a fresh object) and does nothing else; a route handler returns `new Response(null, { status: 501 })`. The stub typechecks, so every test reaches its assertion.
4. **A module with no stub** (a small-lane page) loads once, at the file's top level, never inside a test or hook:

   ```tsx
   const pages = import.meta.glob<PageModule>("./page.tsx");
   const page = await pages["./page.tsx"]?.();
   ```

   Each test first asserts `expect(page).toBeDefined()`: red there until the file exists, and it typechecks (`import("./page")` doesn't). Stryker credits a module's top-level code (`metadata`) only to the test that first loads it, so a load inside a test lets those mutants survive falsely.
5. **Red for the assertion.** Run the file: `pnpm exec vitest run <file>`. Done when every named test fails on an `expect`. A pass means the test checks nothing the stub lacks; a thrown error or a failed import means it never reached its assertion. Rework the test or the stub until each one is red for its assertion.

## Rubric

Every item holds for every test.

- **Public seam.** Drive the code through what callers use: the module's exports, a route handler called with a `Request` (`await GET(new Request("http://test/api/items?id=3"))`), a server action called with its arguments. Leave unexported functions and internal state untouched.
- **Hand-written expected values.** Work each expected value out from the brief and write it as a literal or a named constant in the test. The code under test never computes its own expected value.
- **Exact assertions.** `expect(total).toBe(150)`, `expect(body).toEqual({ id: 3, name: "Ada" })`, `expect(response.status).toBe(404)`. Floats use `toBeCloseTo(x, digits)` with the digits named. Assert a thrown error's message or type (`await expect(load()).rejects.toThrow(NotFoundError)`), not only that something threw.
- **Boundaries and negatives.** Each criterion gets its edge cases (zero, empty, the limit and one past it, a missing field) and the case where nothing should happen: the request that is refused, the call that is never made (`expect(save).not.toHaveBeenCalled()`), the state left unchanged.
- **Fakes at seams only.** Use a double only for a seam the brief names, and prefer a small hand-written fake passed in (a handler factory's client argument, a repository object) over `vi.mock` of a module. Assert what the code did with the fake's value, never the value you put into it.
- **Straight-line.** Arrange, act, assert, with no branches or loops that decide what gets asserted. Give every number a name or derive it from the input the test built. Every assertion runs on every run: none sits under an `if`, in a `try`/`catch`, or in a callback that may never be called (count it with `expect.assertions(n)` when you must).
  - **Many recorded calls.** Assert the count, then each call: `expect(send).toHaveBeenCalledTimes(2)`, `expect(send).toHaveBeenNthCalledWith(1, "ada@example.com")`.
  - **Every item of a collection.** Collect what is wrong in the loop and assert once after it, `expect(problems).toEqual([])`, with the item named in each entry; or use `it.each` with one case per item.
- **Property tests match the invariants.** A generated-input test checks an invariant the brief states, over a fixed seed or a fixed table of inputs, never `Math.random()` unseeded.
- **Fewer checks is a Deviation.** The deviation step counts each test's assertion calls (`expect` and its members, an `assert` or `expect…` helper), named by its `describe` titles and its own joined by `.`, other characters `_` (`total.adds_the_prices`). A rewrite that leaves a test fewer than the base, or removes it, fails `assert-drop` unless the brief declares it (`asserts <file> <name> <from> <to>`).
- **No special-casing.** In the green phase, product code treats test inputs like any others: no branch on a test's values, names, `NODE_ENV` or `process.env.VITEST`.

## Gate rules

The lint step fails a test that breaks these, beside ESLint's own rules (typescript-eslint's strict type-aware set: `no-floating-promises`, the `no-unsafe-*` rules and the rest).

- **An assertion in every test.** Each `it(...)` or `test(...)` with a function calls `expect`, `expect.soft`, `expect.poll`, `expectTypeOf`, `assert`, or a helper whose name starts with `expect` or `assert` (`expectValidOrder(order)`); otherwise `assertion-free`. `it.todo("...")` declares a test with no body and passes.
- **No fixed waits.** `fixed-wait` fails a sleep in a test file: `setTimeout` inside `new Promise(...)` with a delay above 0, an awaited `setTimeout` from `node:timers/promises`, an awaited `sleep(...)` or `delay(...)`, `scheduler.wait`, Playwright's `waitForTimeout` and `Atomics.wait`. A file that calls `vi.useFakeTimers()` may use the timer forms, which then wait for no real time. A wait that has to be fixed (a check that something does *not* happen within a time) gives its reason: `// fixed-wait: <why>`, on its line or alone on the line above.
- **No disabled rules.** The lint step runs ESLint with `--no-inline-config`, so an `eslint-disable` comment changes nothing: fix the finding.
- **Promises handled.** Every `expect(...).resolves` / `.rejects` and every async call is awaited (`no-floating-promises`); an un-awaited one passes whatever happens.
- **Typed.** Tests typecheck under `strict` like the product code. Read a response body as `unknown` and narrow it, or assert it whole with `toEqual`, rather than casting.
- **Same verdict twice.** The red verdicts must match on a second run, which the durable rules below make true.

## Arch and smoke

The arch and smoke steps judge the code your tests and stubs add, by the rules in `ARCHITECTURE.md`.

- **Client stays client.** A `"use client"` file, and every file it imports, never imports a server-only module: one under `server/`, a route handler, or one that imports `server-only`. An `import type` is fine. Test server code from its own test file, not through a client component.
- **Next stays in `app/`.** A module outside `app/` imports nothing from `next` or `next/*`, so its tests run without Next: a stub under `lib/` takes plain values (a `URL`, a body), not a `NextRequest`. Tests themselves may import `next/server`.
- **Fonts** come from `next/font/local`; `next/font/google` fails arch.
- **Smoke** builds the app, starts it and loads `/` in a headless browser. A console error, an uncaught error, or a response other than 2xx for the page or any request it makes (a redirect is followed, and its target judged) fails the gate, so a stub that `/` reaches returns its empty value and never throws.

## Durable tests

A durable test gives the same verdict on a machine ten times slower, under a loaded CPU, and in any test order. Its verdict depends only on the code under test.

1. **No network.** A test never reaches a real server, the internet or a real database. Hand the code a fake at its seam (a `fetch` function, a client object) that returns a fixed `Response` (`new Response(JSON.stringify({ id: 3 }), { status: 200 })`) or rejects, and assert on the request it was given. Stub the global only when the code has no seam: `vi.stubGlobal("fetch", fake)`, with `vi.unstubAllGlobals()` in `afterEach`.
2. **The test drives time.** `vi.useFakeTimers()`, then `vi.advanceTimersByTime(ms)` or `await vi.runAllTimersAsync()`, and `vi.useRealTimers()` in `afterEach`. Make delays config values a test can set to zero.
3. **Await a condition.** `await vi.waitFor(() => { expect(store.items).toHaveLength(2); })` or `await expect.poll(() => job.state).toBe("done")`. Their timeouts are hang guards, many times longer than the work, and the assertion never depends on them.
4. **Inject dates and randomness.** `vi.setSystemTime(new Date("2026-01-01T00:00:00Z"))` under fake timers, or pass the date, the id or the random value in.
5. **Isolate shared state.** Each test builds its own inputs and fakes (`beforeEach`, not module-level objects that tests mutate), restores what it stubbed (`vi.restoreAllMocks()`), and writes files only under a fresh temporary folder (`mkdtemp`) it removes.

**Audit** the changed test files for `setTimeout`, `setInterval`, `sleep`, `delay`, `Date.now()`, `new Date()` with no argument, `Math.random()`, `fetch(` against a real URL, and shared module-level state. Done when each hit is rewritten to the rules above or carries a one-line comment saying why its verdict can't depend on timing.

A test that failed once and then passed breaks one of these rules: find which and fix it, or delete it when a pure-seam test covers its behaviour. A retry or a longer wait leaves the bug in place.
