# The NYC Restroom Gap

Where should New York site the ~1,150 public restrooms implied by its own 2035 target,
and which of them need building at all?

**Read it: https://jonathanwong1990.github.io/nyc-restroom-gap/**

An independent analysis built from primary sources — NYC Open Data, MTA, TLC, NYPD OATH
summonses, US Census ACS and LEHD. Every figure was re-derived from source in an adversarial
audit; corrections from that audit are marked in the text.

- `index.html` — the write-up (summary view, with a toggle for the full report)
- `maps/unmet-need.html` — interactive choropleth of modelled unmet need
- `maps/coverage-gap.html` — five-minute-walk coverage against subway ridership

Prepared for PMBA6093 Analytics for Managers, HKU MBA.

## Code, data and audit trail

- `analysis/R/` — all 35 scripts, in order, including the models that failed
- `analysis/notes/` — research notes per workstream, with sources and access dates
- `analysis/data/` — every dataset pulled
- `analysis/WORKLOG.md` — the full audit trail: 32 defects found, fixed, and verified
- [`METHODS.md`](METHODS.md) — how to reproduce it
