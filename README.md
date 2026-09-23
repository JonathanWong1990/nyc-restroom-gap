# The NYC Restroom Gap

New York must plan for 2,120 public restrooms by 2035 (Local Law 58), and its siting strategy
is due on 1 Nov 2026. This project answers the City's four decisions: where to put restrooms,
when they must be open, what to do first, and how to measure the 17-unit pilot it has just started.

**Read it: https://jonathanwong1990.github.io/nyc-restroom-gap/** · plain text: [`llms.txt`](llms.txt)

Built from primary sources: NYC Open Data, MTA, TLC, NYPD OATH summonses, US Census ACS and LEHD.
Prepared for PMBA6093 Analytics for Managers, HKU MBA.

## Files

- `index.html` is the write-up, with three tabs: Walkthrough, Limits, Data & code.
- `llms.txt` is **generated** from `index.html` by `python3 tools/build_llms.py`. Do not edit it by hand.
- `img/hub_open_access.png` is the hub-by-hour chart, made by `analysis/R/C2_hub_open_access.R`.
- `maps/` holds two interactive maps: unmet need, and coverage gap.
- `analysis/` is a copy of the analysis folder, refreshed by `tools/sync_analysis.sh`:
  - `R/` has all 49 scripts, including the models that failed.
  - `outputs/headline_numbers.json` holds **every number on the site**, written by `R/Z0_headline_numbers.R`. `R/Z1_check_site.R` checks that the site quotes those numbers and none of the known-wrong ones.
  - `notes/` has the research notes for each workstream, with sources and access dates.
  - `data_raw/` has every dataset, exactly as pulled.
- [`METHODS.md`](METHODS.md) explains how to reproduce the analysis.

## Tag convention

Anything that came from teammates' research is marked on the page with a small
**Team research** pill. Hovering over the pill shows its source. In `llms.txt` the same
items appear as `[Team research: <source>]`. Each tagged item was checked against its primary
source before it went in. The Data & code tab lists every tagged item with its source link.

## Before publishing a change

```bash
python3 tools/build_llms.py                       # regenerate llms.txt
cd <analysis folder> && Rscript R/Z1_check_site.R  # must print RESULT: PASS
```
