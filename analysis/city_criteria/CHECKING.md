# How to check this analysis (for a reviewer)

The site's **Walkthrough** and **Limits** tabs (https://jonathanwong1990.github.io/nyc-restroom-gap/) are built from
this folder. The **Deck outline** tab is out of date on purpose (frozen while the walkthrough is finalised) — ignore it.

## Where things are
| What | Local path (under `Final Project/`) | On GitHub (`JonathanWong1990/nyc-restroom-gap`) |
|---|---|---|
| Scripts | `City_Criteria_Model/R/` | `analysis/city_criteria/R/` |
| Outputs (CSV) | `City_Criteria_Model/outputs/` | `analysis/city_criteria/outputs/` |
| Figures | `City_Criteria_Model/outputs/fig/` | `img/plan/` |
| Inputs | `Restroom_Rebuild/data_raw/`, `Build_Plan/prototype/cache/prep.rds`, `Pedestrian_Demand_Test/data/` | most raw files in `analysis/data_raw/`; prep.rds is on GitHub at `analysis/city_criteria/cache/prep.rds` |
| Page text | — | `index.html`, `<div id="plan">` (Walkthrough) and `<div id="plim">` (Limits) |

Scripts use absolute local paths (`BASE <- ".../Final Project"`). To rerun, work in the local folder.

## Run order (R 4.6, packages: sf, data.table, logistf, ggplot2, patchwork)
1. `R/01_features.R` — measures the factors at 5,814 candidate sites + 17 pilot sites -> `cache/features.rds`
2. `R/05_gap.R` — **the current analysis**: pilot model (M7), demand, supply by hour, gap, two-stage cover
   (existing restrooms, then new units), sensitivity -> `cache/gap.rds`, `outputs/gap_*.csv` (~2 min)
3. `R/06_gap_figures.R` — figures g3–g10 (f1 hours chart and f2 pilot map come from `R/04_figures.R`)
4. `R/07_private_supply.R` — chain outlets as supply (scenarios A–D) -> `outputs/private_supply_scenarios.csv`, `PRIVATE_SUPPLY_FINDINGS.md`
5. `R/08_citywide.R` — two-stage cover at wider demand cut-offs -> `outputs/citywide_coverage.csv`, `citywide_resident_coverage.csv`
6. `R/09_resident_coverage.R` — residents covered at 9pm; existing restrooms then new units anywhere residents live -> `outputs/resident_coverage_*.csv`
7. `R/10_extra_figures.R` — g2c candidate-site map, g12 resident-coverage curve

`R/02_*`, `R/02b_*`, `R/03_*` are the superseded "next 50" version (kept for the record; not on the page).

## Where each Walkthrough number comes from
| Step | Numbers | Source |
|---|---|---|
| 1 | 2,120 · 975 | LL58 text (`Restroom_Rebuild/data_raw/ll58_2025_text_20260926.pdf`); register `nycrestrooms_i7jb-7jku_20260920.csv` |
| 2 | law quote; factor table | LL58 text; `01_features.R` |
| 3 | 5,814 sites (4,076 / 1,646 / 92) | `Build_Plan/prototype/cache/prep.rds` `$cand`; `10_extra_figures.R` |
| 4 | 17 pilots, 6/7/4 by type | `01_features.R` console; `data_raw/nycgov_mayor_pilot_release_20260923.html` |
| 5 | coefficients, CIs; weights 95/5; six-factor check; complaints −0.38 | `05_gap.R` console; `outputs/gap_pilot_model.csv` |
| 6 | LOO median 95, mean 87; in-sample AUC 0.91 | `05_gap.R` console; `outputs/gap_leave_one_out.csv` |
| 7 | top third 1,939; 1,570 / 185 / 111 / 73 / 0 | `cache/gap.rds` `D0` × borough |
| 8 | 954 / 57 (scheduled); 873 working at 2pm; 641; 20.1%; 34 / 47 / 41; 70% / 16%; pilots 13/17, 1/17 | `05_gap.R` console; `prep.rds` `$sup` flags |
| 9 | 1,247 gap (1,182 / 65); 14 of 17 | `05_gap.R` console |
| 10 | 154 existing (103/35/16), 1,183 covered; 24 new; boroughs; 56/74/89% | `outputs/gap_existing_facilities.csv`, `outputs/gap_new_units.csv` |
| 11 | park-hours table; private-toilet table; threshold/radius/hour; random weights; 103/154, 13/24 | `outputs/gap_sensitivity_*.csv`; `outputs/private_supply_scenarios.csv` |
| 12 | 72% / 4% / 73%; 761 (457/207/97); 38 / 171 / 296 / 830 | `outputs/resident_coverage_summary.csv` |
| 13 | 29 areas; 3/17, 24/154, 2/24 | `Build_Plan/layered/outputs/diagnosis_29_final.csv`; `outputs/gap_overlap_with_29.csv` |

## Things worth probing
- Supply at 9pm rests on the 4pm assumption for 641 Parks restrooms (154 -> 29 existing restrooms; new units unchanged).
- Demand is ranked citywide, so the top third is 81% Manhattan.
- Greedy covering is not a guaranteed optimum. Stage 1 keeps adding existing restrooms while any adds coverage.
- Weights come from 17 sites; equity's CI crosses zero.
