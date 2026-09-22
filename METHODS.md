# Methods, code and data

Everything behind the analysis, including the models that failed and the claims that were
withdrawn.

## Reproduce it

```bash
git clone https://github.com/JonathanWong1990/nyc-restroom-gap
cd nyc-restroom-gap/analysis
Rscript R/11_benchmark.R        # scripts resolve data_raw/ relative to this directory
```

R 4.6.1. Packages: `sf`, `dplyr`, `MASS`, `tidyr`, `leaflet`, `htmlwidgets`, `htmltools`,
`rpart`, `data.table`, `httr`, `jsonlite`.

Scripts read `data_raw/` relative to the working directory. To run from elsewhere, set
`RESTROOM_PROJ` to the `analysis/` directory.

## The scripts

| Script | What it does |
|---|---|
| `geo_helpers.R` | Socrata paging (`$order=:id`, retry, disk cache), point-in-polygon join |
| `01_geography.R`, `02_acs_demographics.R` | Boundaries, crosswalks, Census ACS |
| `03_community_boards_and_outcome_test.R` | Unit-of-analysis test: NTA vs community district vs tract |
| `pull_supply.R`, `parse_hours.R` | Restroom inventory; free-text opening-hours parser |
| `demand_00_helpers.R`, `demand_01_pull.R` | Subway, taxi, hotels, employment, pedestrian counts |
| `demand_02_hourprofile.R` | **Orphaned — do not run.** An hour-plus of live network pulls for an hour-of-day profile that no other script consumes and that never produced its final output. Kept for the record only. |
| `10_modelling_table.R` | The modelling table, every join cardinality-checked |
| `11_benchmark.R` | **The one-line benchmark any model must beat** |
| `12–15_did_*.R` | First causal attempt. Abandoned — treatment variable mismeasured. These run and report their own negative results |
| `20_regression.R` | The ranking model: negative binomial, offset, clustered errors |
| `30_maps.R`, `31_coverage_validation.R`, `97_svg_map.R` | Spatial outputs |
| `40_logistic.R` | Where NYC actually invests |
| `50_tree_vs_regression.R` | Session 7 comparison — the tree loses, reported as such. **This is the script the site's 0.793 / 0.709 figures come from** |
| `60_cost_layer.R`, `61_cost_annualised.R` | Intervention assignment; annualised costs and sensitivity |
| `70_audit_checks.R` | Time-of-day; phone-only reporting-channel test |
| `80_corrections.R` | Fixes from the first adversarial audit |
| `90–92_*.R` | Second outcome measure (OATH summonses) — tested and rejected |
| `93_winterization.R` | Second causal attempt. **Fails its own placebo test** |
| `94_breakeven.R` | Switching-value analysis |
| `95_convergent_shortlist.R` | Agreement between the two outcome measures |
| `96_commercial_supply.R` | Does informal (commercial) supply change the ranking? |
| `98_coldread_fixes.R` | Time-of-day on genuine hours, accessibility, Moran's I |
| `99_offset_test.R` | Is the shortlist an artifact of the exposure measure? |
| `A1_noise_floor.R` | **Parametric bootstrap: can the ranking be told apart from noise?** |

`A5_null_comparison.R` — runs the noise floor against BOTH nulls. The negative binomial's overdispersion IS between-area rate variation, so simulating from it does not represent "nothing is wrong"; a Poisson null does. Against Poisson the observed spread is 2.5x chance (p=0.002); against NB the count of extremes matches the estimated spread, i.e. the extremes are a continuum, not a category.
`A6_empirical_bayes.R` — per-neighbourhood posteriors. The fitted NB is already a Poisson-gamma model, so P(true rate > 1.5x expected) is conjugate. Seven neighbourhoods exceed 0.95, all surviving leave-one-out re-estimation of model and prior. Addresses sparse counts only, not reporting validity.
| `A2_cost_bands.R` | Valuing the banded capital projects excluded from an earlier median |
`A7_repair_vs_build.R` — separates restroom capital projects into build-new vs reconstruct-existing vs component work, valuing banded costs as A2 does. Build new median $4.0M (n=68); reconstruct $1.66M (n=108). Component work is n=5 and too thin to quote.
`A8_condition_trend.R` — Parks Inspection Program comfort-station condition, 31,768 inspections, matched Jan-Jun window. Failure rate 8.5% (2024) -> 20.1% (2026); facility fixed effects +11.4pp (SE 2.0pp). Internal placebo: litter and graffiti flat while structural triples. Rules out new inspectors and a step-change rule revision.
| `A3_seed_stability.R` | The out-of-sample result across six random seeds |
| `A4_reporting_channel.R` | Reporting-channel correlations, raw vs de-duplicated series |

`20_regression.R` prints 0.790 / 0.710 from its own random splits; the site quotes
`50_tree_vs_regression.R` at 0.793 / 0.709. Same model, different splits, same conclusion.

## Notes, audit trail and data

`analysis/notes/` — one file per workstream, recording what was pulled and what failed.
`external_evidence.md` carries every external citation with an access date and a "thin ice"
section of figures that could not be verified and are therefore unused.

`analysis/WORKLOG.md` — the full defect log across three rounds of adversarial review, what
was fixed, and what was checked and held.

`analysis/data_raw/` — every dataset pulled, named `<source>_<datasetid>_<date>.csv`.
Principal sources: NYC Open Data (restrooms `i7jb-7jku`, 311 `erm2-nwe9`, OATH summonses
`hxbk-grd3`, parks `enfh-gkve`, capital tracker `4hcv-tc5r`, PIP inspections `yg3y-7juh`,
DOHMH `43nn-pn8j`, NTA boundaries `9nt8-h7nd`), data.ny.gov (MTA `ak4z-sape`, `39hk-dx4f`),
and the US Census (ACS 5-year, LEHD LODES8).

## What failed

The inspection-based closure design (treatment variable mismeasured), the winterization
design (fails its placebo), OATH summonses as a ranking outcome (measures enforcement),
the cultural-organisations dataset (a grants roster, not attractions), pedestrian counts
(114 sites, too sparse), and two external figures withdrawn after their sources could not
be verified.
