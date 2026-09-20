# Methods, code and data

Everything behind the analysis. Nothing is hidden and nothing was run that is not here —
including the models that failed.

## Reproduce it

R 4.6.1. Packages: `sf`, `dplyr`, `MASS`, `tidyr`, `leaflet`, `rpart`, `httr`, `jsonlite`.
Scripts run in numeric order from `analysis/R/`, reading from `analysis/data/`.

## The scripts, in the order they were written

| Script | What it does |
|---|---|
| `geo_helpers.R` | Socrata paging (`$order=:id`, retry, disk cache), point-in-polygon join |
| `01_geography.R`, `02_acs_demographics.R` | Boundaries, crosswalks, Census ACS |
| `03_community_boards_and_outcome_test.R` | Unit-of-analysis test: NTA vs community district vs tract |
| `pull_supply.R`, `parse_hours.R` | Restroom inventory; free-text opening hours parser |
| `demand_00/01/02_*.R` | Subway, taxi, hotels, employment, pedestrian counts |
| `10_modelling_table.R` | The modelling table, every join cardinality-checked |
| `11_benchmark.R` | **The one-line benchmark any model must beat** |
| `12–15_did_*.R` | First causal attempt. Abandoned — treatment variable mismeasured |
| `20_regression.R` | The ranking model: negative binomial, offset, clustered errors |
| `30_maps.R`, `31_coverage_validation.R`, `97_svg_map.R` | Spatial outputs |
| `40_logistic.R` | Where NYC actually invests |
| `50_tree_vs_regression.R` | Session 7 comparison — the tree loses, reported as such |
| `60/61_cost_*.R` | Intervention assignment; annualised costs and sensitivity |
| `70_audit_checks.R` | Time-of-day; phone-only reporting-bias test |
| `80_corrections.R` | Fixes from the adversarial audit |
| `90–92_*.R` | Second outcome measure (OATH summonses) — tested and rejected |
| `93_winterization.R` | Second causal attempt. **Fails its own placebo test** |
| `94_breakeven.R` | Switching-value analysis |
| `95_convergent_shortlist.R` | Agreement between the two outcome measures |
| `96_commercial_supply.R` | Does informal (commercial) supply change the ranking? |
| `98_coldread_fixes.R` | Bootstrap stability, Moran's I, accessibility |
| `99_offset_test.R` | Is the shortlist an artifact of the exposure measure? |

## Research notes

`analysis/notes/` — one per workstream, each recording what was pulled, what failed, and why.
`external_evidence.md` carries every external citation with an access date and a "thin ice"
section listing figures that could not be verified and are therefore not used.

## The audit trail

`analysis/WORKLOG.md` is the full record: a 32-item defect list from an adversarial audit of
the code and the numbers, what was fixed, and a "verified correct" list of things that were
checked and held. `00_START_HERE.md` is the project briefing.

## Data

`analysis/data/` holds every pull, named `<source>_<datasetid>_<date>.csv`. Principal sources:
NYC Open Data (restrooms `i7jb-7jku`, 311 `erm2-nwe9`, OATH summonses `hxbk-grd3`, parks
`enfh-gkve`, capital tracker `4hcv-tc5r`, PIP inspections `yg3y-7juh`, DOHMH `43nn-pn8j`,
NTA boundaries `9nt8-h7nd`), data.ny.gov (MTA ridership `ak4z-sape`, stations `39hk-dx4f`),
and the US Census (ACS 5-year, LEHD LODES8).

Excluded: `_hourprofile_parts/`, 45MB of intermediate weekly MTA pulls, regenerable from
`demand_02_hourprofile.R`.

## What failed

Recorded deliberately, because the negative results were as informative as the positive ones:
the inspection-based closure design (treatment variable mismeasured), the winterization design
(fails its placebo), OATH summonses as a ranking outcome (measures enforcement), the cultural
organisations dataset (a grants roster, not attractions), pedestrian counts (114 sites, too
sparse), and two external figures withdrawn after their sources could not be verified.
