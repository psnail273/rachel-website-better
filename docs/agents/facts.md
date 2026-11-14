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
