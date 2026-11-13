# Facts

Engine and library facts that briefs rely on, each with the probe that showed it. Read here before probing again.

## Fonts (Next.js 16.4.6)

- Next.js ships the Geist and Geist Mono variable fonts (weight axis 100 to 900, the Google Fonts `latin` and `latin-ext` subsets) for its dev overlay at `node_modules/next/dist/next-devtools/server/font/` (`geist-latin.woff2`, `geist-latin-ext.woff2`, `geist-mono-latin.woff2`, `geist-mono-latin-ext.woff2`). Probe: `fc-scan --format "%{family} | %{weight} | variable=%{variable}\n" <file>` prints `weight=[0 210] | variable=True` (fontconfig 0 = 100, 210 = 900). (#2)
- `next/font/local` takes `src` relative to the calling file, `weight: "100 900"` for a variable font and `variable` for the CSS variable name. Probe: `node_modules/next/dist/docs/01-app/03-api-reference/02-components/font.md`. (#2)
- No copy of the OFL licence text is under `node_modules/`; Geist's is `OFL.txt` in github.com/vercel/geist-font. (#2)
