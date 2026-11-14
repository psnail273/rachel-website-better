# Facts

Engine and library facts that briefs rely on, each with the probe that showed it. Read here before probing again.

## Fonts (Next.js 16.4.6)

- Next.js ships the Geist and Geist Mono variable fonts (weight axis 100 to 900, the Google Fonts `latin` and `latin-ext` subsets) for its dev overlay at `node_modules/next/dist/next-devtools/server/font/` (`geist-latin.woff2`, `geist-latin-ext.woff2`, `geist-mono-latin.woff2`, `geist-mono-latin-ext.woff2`). Probe: `fc-scan --format "%{family} | %{weight} | variable=%{variable}\n" <file>` prints `weight=[0 210] | variable=True` (fontconfig 0 = 100, 210 = 900). (#2)
- `next/font/local` takes `src` relative to the calling file, `weight: "100 900"` for a variable font and `variable` for the CSS variable name. Probe: `node_modules/next/dist/docs/01-app/03-api-reference/02-components/font.md`. (#2)
- No copy of the OFL licence text is under `node_modules/`; Geist's is `OFL.txt` in github.com/vercel/geist-font. (#2)
- `next/font/local` is empty at runtime outside Next's compiler (`node_modules/next/font/local/index.js` is empty), so a Vitest test that imports a file calling `localFont` must `vi.mock("next/font/local", ...)`. (#6)
- Weight axes: Fraunces 100 to 900, Source Sans 3 200 to 900 (`fc-scan`: `[0 210]` and `[40 210]`); `localFont({ src: [{ path, style: "normal" }, { path, style: "italic" }], weight: "<min> <max>", variable })` builds four `@font-face` rules from the four `.ttf` files. (#6)

## Calendar feed (2026-11-14)

- Rachel's public Google Calendar ICS feed (the basic.ics URL in `WEBSITE_SPEC.md`) uses CRLF line ends and `X-WR-TIMEZONE:America/Chicago`; every DTSTART/DTEND is a UTC `...Z` date-time, LOCATION values carry `\,` escapes and folded lines, there is no RRULE, and the Harry Potter nights are separate VEVENTs whose titles differ only in case. Probe: `curl` of the feed, then `grep -E '^(DTSTART|DTEND|LOCATION|SUMMARY|RRULE)'` and `od -c | head`. (#9)
- Node v26.13.1 has full ICU: `new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", month: "short", day: "numeric" }).format(new Date("2026-11-08T00:30:00Z"))` prints `Nov 7`. (#9)

## Tests (Vitest 5.1.0)

- The project had no `vitest.config.ts` or `stryker.config.json` until #9; the adapter's templates are `factory/adapters/nextjs/new/vitest.config.ts.txt` and `stryker.config.json.txt`. Copied unchanged, the Vitest one runs `src/**/*.test.ts` (`pnpm exec vitest run`) and typechecks. (#9)

## Cache Components (Next.js 16.4.6, `cacheComponents: true`)

- `new Date()` in a Client Component fails `next build` (blocking-prerender-current-time-client). An async Server Component whose body starts with `"use cache"` may call it and builds static (Revalidate 15m by default). `cacheLife` from `next/cache` throws outside Next (Vitest). Probe: scratch `next build` and `vitest run`. (#6)

## Tests (Vitest 5.1.0, React 19.3.0)

- Component tests use `happy-dom` 21.0.4 with `@testing-library/react` 16.3.3 and `@testing-library/dom` 10.4.2 (exact devDependencies, added by #6). A file opts in with a first line `// @vitest-environment happy-dom`; RTL's auto-cleanup needs Vitest globals (off), so call `cleanup()` in `afterEach`. `next/link` renders there without a router. (#6)
- `prerender` from `react-dom/static` renders trees holding async Server Components; its HTML puts `<!-- -->` between adjacent text nodes, so read `textContent` from `new DOMParser().parseFromString(html, "text/html")`. `vi.useFakeTimers({ toFake: ["Date"] })` with `vi.setSystemTime` drives `new Date()`. (#6)
- Vitest 5.1.0 defaults `clearMocks: true`: a `vi.fn` called at module import (e.g. a mocked `localFont` called when the layout is imported) has empty `mock.calls` by the time a test body runs; snapshot the calls at import. (#6, Editor's red round)
- Vite rewrites a literal `new URL("./x", import.meta.url)` into a served path, and under happy-dom the global `URL` is happy-dom's, which `fileURLToPath` rejects: build file paths with `join(import.meta.dirname, ...)` in tests. (#6, Editor's red round)

## Images (Next.js 16.4.6, Tailwind 4.3.3)

- `next/image` renders under Vitest (happy-dom, `prerender` from `react-dom/static`) with no Next runtime: an `.svg` `src` passes through unoptimized and unchanged as a plain `<img>` with `width`/`height` attributes, and `preload` adds a `<link rel="preload" as="image">` ahead of the tree. `priority` is deprecated for `preload` in 16. Probe: scratch Vitest file; `node_modules/next/dist/docs/01-app/03-api-reference/02-components/image.md` (`preload`, `dangerouslyAllowSVG`). (#8)
- happy-dom's `DOMParser` parses an SVG file as `image/svg+xml`; the root's `tagName` is `svg` and `getAttribute` reads `width`, `height` and `viewBox`. Probe: scratch Vitest file. (#8)
- Tailwind 4 puts utilities in `@layer utilities`; `src/app/globals.css`'s unlayered `h1, h2, h3 { color: var(--heading) }` beats any colour utility on a heading unless it uses the important modifier (`text-background!`). Probe: `node_modules/tailwindcss/index.css:1`. (#8)

## Loading a module that doesn't exist yet (Vitest 5.1.0, StrykerJS 10.1.1)

- A small-lane red test (no seam) can load a page that doesn't exist yet with `const pages = import.meta.glob<{ default: () => ReactElement; metadata: Metadata }>("./page.tsx")`: it typechecks, `pages["./page.tsx"]` is `undefined` until the file exists, so `expect(load).toBeDefined()` fails on an assertion, not an import error. Probe: a scratch test in the #13 worktree, `pnpm exec vitest run` and `pnpm exec tsc --noEmit -p .`. (#13)
- Stryker's mutate step reports a module's top-level constants (metadata, arrays, strings) as survivors when the tests load the module through that lazy glob: it doesn't reload the module between mutants. Applied by hand, 31 of #13's 33 "survivors" each failed a test; only the two Tailwind class strings truly survived. Probe: `sed` each mutant into a copy, `vitest run` on the page test. (#13, Driver and Verifier)
