# Build plan prototype: coverage-based siting (25 Sep 2026)

Prototype. Run `R/01_prep.R`, `R/02_greedy.R`, `R/03_maps.R` (~1 minute).

## Method
- **Coverage rule:** a demand point counts as covered if an open restroom is within 500 m in a straight line (EPSG:2263). Times tested: Wednesday 2pm and 9pm. Hours follow `C2_hub_open_access.R`. The 641 restrooms with placeholder hours are assumed to close at 16:00 (20:00 in the in-season sensitivity). New sites are assumed open 7am to 10pm.
- **Four separate objectives, never weighted together:**
  - residents (ACS tracts)
  - workers (LODES 2023 block data, summed to tracts)
  - subway entries (424 station complexes, 2025)
  - metres of DOT Global and Regional street

  Residents and workers are spread over a 150 m grid within each tract, with parks excluded.
- **Supply:** the base set is restrooms that are operational and open at the hour. The strict set also drops register rows within 30 m of Parks properties that are either long-term closed (34 rows) or repeatedly failing (47 rows). Repeatedly failing means at least 2 Unacceptable inspections making up at least 50% of rated inspections since 2025.
- **Candidates (5,814):** 150 m grid points on eligible Parks land, DOT plazas, or within 30 m of busy streets, plus points every 150 m along busy streets.
- **Greedy maximal covering:** for each objective, hour and supply set, add the site that newly covers the most demand, and repeat up to 1,145 sites.
- **Consensus:** for each NTA (residential, with park NTAs snapped to the nearest residential one), count how many of the 8 primary runs place one of their first 100 sites there. The 8 runs are 4 objectives × 2pm/9pm, on base supply.

> **Corrected 25 Sep after an independent number check** (`../checks/prototype_check.md`): the DOT street file repeated 3,966 rows, now removed (busy-street length 124 km, not 176 km); the extend-to-10pm column now uses all 641 placeholder restrooms. Other figures unchanged.

## Headline numbers (Wednesday)
| Objective | 2pm | 9pm | 9pm with 100 new sites | 9pm with placeholders open to 10pm |
|---|---|---|---|---|
| Residents | 72.4% | 4.4% | 31.1% | 61.7% |
| Workers | 80.4% | 21.6% | 64.1% | 63.2% |
| Subway entries | 87.4% | 12.7% | 81.9% | 63.2% |
| Busy streets | 97.0% | 35.1% | 100% | 76.0% |

- **Open restrooms:** 954 are open at 2pm and 57 at 9pm. At 9pm the in-season close and strict supply change nothing; the script checks this.
- **Fixing vs building at 2pm (strict supply):** reopening long-term-closed restrooms adds 2.8 points of resident coverage, fixing failing ones adds 1.7, and 100 new builds add 7.2.
- **City pilot vs greedy first 17 (9pm, points added):** residents +3.2 vs +7.2; subway +6.8 vs +37.9; streets +3.8 vs +44.0.
- **Consensus:** 4 NTAs appear in all 8 runs: Upper East Side–Carnegie Hill, Park Slope, Elmhurst and Upper West Side (Central). 47 NTAs appear in at least 4.
- **Validation (complaints are not used for selection):** 2 of the six high-complaint NTAs are in the consensus top 20: East Harlem (North) at #7 and Midtown–Times Square at #16. The Spearman correlation with the complaint-model residual ratio is −0.04.
- **Radius sensitivity:** of the top 20 NTAs at 500 m, 15 stay in the top 20 at 400 m and 9 at 750 m. There are 3–4 ties at 20th place.

## Caveats
- Straight-line distance (walks ~1/3 longer); posted hours from a 15-month-old register; placeholder closes assumed.
- Street demand is DOT's modelled pedestrian demand, not counted footfall.
- Candidates are grid points, not verified sites. Because they are limited to public land, the maximum achievable coverage for residents at 9pm is 67%.
- At 2pm, the subway and street objectives are fully covered after 34 and 14 sites.
- The closed and failing matches rely on proximity, and ambiguous matches were skipped.
- The "extend to 10pm" column extends all 641 placeholder sites on the full listed supply (`gain_extend_all641_placeholder_to_22_pts`); it has not been costed.

## Outputs (`outputs/`)
- `coverage_curves.csv` and `.png`: coverage against the number of new sites.
- `first100_sites_<objective>.csv`: the first 100 sites for each run.
- `consensus_nta.csv`: NTA scores, with complaint columns included for reference only.
- `radius_sensitivity.csv`, `validation.txt`, `fix_hours_vs_build.csv`, `pilot_vs_greedy17.csv`, `build_plan_map.html`/`.png`
