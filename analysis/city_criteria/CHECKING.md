# How to check this analysis (for a reviewer)

The site's **Walkthrough** and **Limits** tabs (https://jonathanwong1990.github.io/nyc-restroom-gap/) are built from
this folder. The **Deck outline** tab is out of date on purpose (frozen while the walkthrough is finalised) — ignore it.

## Where things are
| What | Local path (under `Final Project/`) | On GitHub (`JonathanWong1990/nyc-restroom-gap`) |
|---|---|---|
| Scripts | `City_Criteria_Model/R/` | `analysis/city_criteria/R/` |
| Outputs (CSV) | `City_Criteria_Model/outputs/` | `analysis/city_criteria/outputs/` |
| Figures | `City_Criteria_Model/outputs/fig/` | `img/plan/` |
| Inputs | `Restroom_Rebuild/data_raw/`, `Build_Plan/prototype/cache/prep.rds`, `Pedestrian_Demand_Test/data/` | most raw files in `analysis/data_raw/`; **prep.rds is not on GitHub** |
| Page text | — | `index.html`, `<div id="plan">` (Walkthrough) and `<div id="plim">` (Limits) |

Scripts use absolute local paths (`BASE <- ".../Final Project"`). To rerun, work in the local folder.

## Run order (R 4.6, packages: sf, data.table, logistf, ggplot2, patchwork)
1. `R/01_features.R` — measures the factors at 5,814 candidate sites + 17 pilot sites -> `cache/features.rds`
2. `R/05_gap.R` — **the current analysis**: pilot model (M7), demand, supply by hour, gap, greedy count, fix per
   location, sensitivity -> `cache/gap.rds`, `outputs/gap_*.csv` (~15 s)
3. `R/06_gap_figures.R` — figures g3–g10 (f1 hours chart and f2 pilot map come from `R/04_figures.R`)

`R/02_*`, `R/02b_*`, `R/03_*` are the superseded "next 50" version (kept for the record; not on the page).

## Where each Walkthrough number comes from
| Step | Numbers | Source |
|---|---|---|
| 1 | 2,120 · 975 · 1,145 | LL58 text (`Restroom_Rebuild/data_raw/ll58_2025_text_20260926.pdf`); register `nycrestrooms_i7jb-7jku_20260920.csv` |
| 2 | 5,814 sites (4,076 / 92 / 1,646) | `Build_Plan/prototype/cache/prep.rds` `$cand` |
| 3 | 17 pilots, 6/7/4 by type | `01_features.R` console; Mayor's release saved as `data_raw/nycgov_mayor_pilot_release_20260923.html` |
| 4 | coefficients, CIs; demand weights 95/5; six-factor check; complaints −0.38 | `05_gap.R` console; `outputs/gap_pilot_model.csv` |
| 5 | LOO median 95, mean 87; AUC 0.91 | `05_gap.R` console; `outputs/gap_leave_one_out.csv` |
| 6 | top third; 1,566 / 189 / 111 / 73 / 0 | `05_gap.R` objects `D0` × borough |
| 7 | 954 / 57; 71% / 16%; pilots 13/17, 1/17 | `05_gap.R` console |
| 8 | 1,249 gap (1,184 / 65); 14 of 17 pilots | `05_gap.R` console |
| 9 | 156; borough 68/36/27/25/0; 378 at top half | `outputs/gap_sites_selected.csv`; `outputs/gap_sensitivity_settings.csv` |
| 10 | 150–225 (median 182); 127 / 131 / 109 of 156; chance 34%; 355 gap / 46 locations if parks open to 10pm | `05_gap.R` console; `outputs/gap_sensitivity_*.csv` |
| 11 | 101 / 27 / 12 / 16 | `outputs/gap_sites_selected.csv` column `first_action` |
| 12 | 29 areas; 3 of 17; 20 of 156 | `Build_Plan/layered/outputs/diagnosis_29_final.csv`; `outputs/gap_overlap_with_29.csv` |

## Things worth probing
- Supply at 9pm rests on the 4pm assumption for 641 Parks restrooms (biggest lever: 156 -> 46).
- Demand is ranked citywide, so the top third is 81% Manhattan.
- Greedy covering is not a guaranteed optimum; the count is an upper-bound-style estimate for full coverage.
- Weights come from 17 sites; equity's CI crosses zero.
