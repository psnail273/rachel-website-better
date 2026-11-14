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

- A small-lane red test (no seam) loads a page that doesn't exist yet once, at the file's top level: `const pages = import.meta.glob<PageModule>("./page.tsx"); const page = await pages["./page.tsx"]?.();`, each test asserting `expect(page).toBeDefined()` first. It typechecks (top-level await: `module` esnext, `target` ES2017), and with no page every test fails on that assertion, not an import error. Probe: the bio test with `page.tsx` moved aside, `pnpm exec vitest run` (5 × `expected undefined to be defined`) and `pnpm exec tsc --noEmit -p .` (errors only in the stale `.next/types/validator.ts`). (#13; top level: amend stryker-survivors)
- Why the mutate step reported module-level constants as survivors (#12-#17's `metadata`): Stryker's Vitest runner records coverage per test from a `beforeEach`, so a module first loaded inside a test (a lazy `import.meta.glob` loader, or `await import()`) has its top-level code counted as covered by that one test, not as static code; each such mutant then runs against that test alone (`testFilter`), and the metadata test never runs on it. The module is reloaded per run; it's the test filter. `coverageAnalysis: "all"` doesn't help: the runner still reports per-test coverage and Stryker core uses it. Loaded at the file's top level, the constants are static mutants, run against every test and killed. Probe: the mutate step (`FACTORY_MUTATE_BASE` a commit without `src/app/(upcoming)/performing/bio/page.tsx`) gave 3 survivors on lines 7, 8, 10, each `coveredBy` only "shows the Bio heading and the four bio paragraphs" in Stryker's JSON report; with the test loading at its top level, the same 3 were `static` and killed by "has its own title and meta description" (killed 6, survived 0). (amend stryker-survivors)
- The other glob-loaded page tests (`src/app/therapy/{about,services,education-and-training}`, `src/app/contact`, `src/app/(upcoming)/performing/media`) still load inside their tests: their `metadata` mutants survive falsely until each moves its load to the top level. (amend stryker-survivors)

## Driver's checks (Next.js 16.4.6)

- `next build` (`bash tools/verify/playtest`) empties `.next/`, `.next/factory/` included: keep a Driver's check's logs, PIDs and screenshots outside `.next/` (the scratchpad), or create `.next/factory/` after the build. `setsid pnpm exec next start` exits its wrapper at once; stop the server by the PID `ss -ltnp` shows on its port. Probe: #12's Driver's check. (#12)

## Revalidation and the events strip (Next.js 16.4.6, `cacheComponents: true`)

- The route segment `revalidate` export is removed under Cache Components (`node_modules/next/dist/docs/01-app/03-api-reference/03-file-conventions/02-route-segment-config/index.md:25`); a `"use cache"` scope sets its lifetime with `cacheLife`. The `hours` profile: stale 5 minutes, revalidate 1 hour, expire 1 day (`.../04-functions/cacheLife.md`, Preset cache profiles). Each cached scope keeps its own lifetime: `next build` shows `/` at Revalidate 15m (the footer's default-profile scope) while an `hours` scope inside it is refreshed hourly. (#11)
- `node:sqlite` bundles in a Server Component under Turbopack, and a `"use cache"` function may open the events cache, `fetch` the feed with `AbortSignal.timeout(10_000)` and call `new Date()`: `next build` prerenders it static; an unroutable feed waits the timeout, then renders the fallback. Probe: scratch build. (#11)
- Under Vitest, `vi.mock("next/cache", () => ({ cacheLife: vi.fn() }))` lets a test import a file calling `cacheLife`; `"use cache"` is an inert string there. happy-dom's global `AbortSignal` has `timeout`. Probe: scratch Vitest file. (#11)
- Moving a page into a route group: its test must move in the same commit or `next build`'s typecheck fails (`Cannot find module './page'`). The red gate diffs `--no-renames`, so a moved test file's passing tests count as new (`red-unnamed`): move it in the green phase, with `asserts <old file> <func> <n> 0` lines in the brief. A route group holding only a layout builds. (#11)

## Pages in the Upcoming group (Next.js 16.4.6, Vitest 5.1.0)

- `next/link`'s `Link` renders as a plain `<a href>` inside `prerender` from `react-dom/static` under Vitest (happy-dom), with no router; JSX `&quot;`, `&apos;` and `&amp;` read back as `"`, `'` and `&` in `textContent`. Probe: scratch test in the #15 worktree. (#15)
- A page test inside `src/app/(upcoming)/<segment>/` can show the strip by importing the group's layout (`../../layout` from two levels down) and rendering `await UpcomingLayout({ children: <Page /> })`, with `vi.mock("next/cache", () => ({ cacheLife: vi.fn() }))`, `EVENTS_CACHE_PATH` and `CALENDAR_FEED_URL` stubbed and `fetch` rejecting: the body's children are the page's root, then `SECTION` with `h2` "Upcoming" and the fallback `p`s. Render the page alone for its own `p`/`a` counts, since the strip adds its own. Probe: scratch test in the #15 worktree. (#15)

## Click-to-play video (happy-dom 21.0.4, YouTube)

- happy-dom 21 loads no iframe page unless `enableIframePageLoading` is set (default `false`, `lib/browser/DefaultBrowserSettings.js`): an `<iframe src="https://www.youtube-nocookie.com/...">` that React mounts after `fireEvent.click` stays in the DOM with its `src`, `title`, `allow` and `allowfullscreen` attributes readable, nothing reaches the network, and happy-dom prints `DOMException [NotSupportedError]: Failed to load iframe page "<src>". Iframe page loading is disabled.` to stderr while the test passes. Probe: a scratch RTL test in #16's worktree (`render`, `fireEvent.click`, `pnpm exec vitest run`), removed after. (#16)
- `next/image` renders under RTL's `render` (react-dom/client, happy-dom) as well as under `prerender`: an `.svg` `src` gives a plain `<img>` with `src`, `alt`, `width` and `height` unchanged. Probe: the same scratch test. (#16)
- The two Media videos' YouTube titles, from `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=<id>&format=json` (2026-11-14): `VdwOjCyVsSE` is `“Passacaille” by Jacques-Martin Hotteterre`, `DZA9Wi6KzWY` is `“Aria sopra La Bergamasca” by Marco Uccellini` (curly quotes U+201C/U+201D), both on the Early Music Missouri channel. (#16)

## Link prefetch (Next.js 16.4.6)

- Under Vitest, `next/link` resolves to `node_modules/next/dist/client/link.js` and renders `prefetch={false}` and the default identically (`<a href="/contact">C</a>`); its `onMouseEnter`/`onTouchStart` prefetch ignores the prop, and `prefetchEnabled` gates only the viewport prefetch, which runs only in production with a router. So no rendered output under Vitest shows the prop: a test of it reads the component's source. In a production build (`next start`), loading `/` fetches `/contact?_rsc=...` for an in-viewport Link. Probe: scratch Vitest file, `link.js:145`, `:309-330`, `:356-375`; Playwright on `next start`. (#20)
