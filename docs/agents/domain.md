# Domain docs

Single-context layout: one app, one glossary.

- `CONTEXT.md` at the repo root: the glossary of the domain's terms (the site, its pages, its content).
- `docs/adr/`: architecture decision records, one file per decision (`NNNN-title.md`).
- `WEBSITE_SPEC.md`: the product spec for the redesign.

Before exploring an area, read `CONTEXT.md` and the ADRs touching it. Name things with the glossary's terms. When your output contradicts an ADR, say so plainly rather than quietly diverging.

Neither file exists yet; that is fine. `CONTEXT.md` is created when a term is first settled, and `docs/adr/` when a decision is first recorded.
