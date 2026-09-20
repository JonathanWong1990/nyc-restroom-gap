# Geography backbone — notes

Pulled **2026-09-20**. All scripts in `R/`, all outputs in `data_raw/`.
Run order: `01_geography.R` → `02_acs_demographics.R` → `03_community_boards_and_outcome_test.R`.
Everything is cache-first; re-running does not re-download.

---

## 1. Recommended unit of analysis

**Primary: residential 2020 NTAs (`ntatype == 0`), n = 197.**
**Inference / robustness anchor: Community Districts, n = 59.**

The decision was made on the *outcome*, not on the geometry. Counts below are the
311 "Urinating in Public" series restricted to public-space `location_type`
(Street/Sidewalk, Park/Playground, Subway Station) and de-duplicated to one count
per address per month — 3,738 events on my reconstruction.

| Unit | n | total | median | mean | zeros | <5 | <10 | max | unit×year non-zero |
|---|---|---|---|---|---|---|---|---|---|
| Community District | 59 | 3,584 | 45 | 60.7 | 0 | 0 | 0 | 145 | 97% |
| NTA — all | 262 | 3,623 | 7 | 13.8 | 43 | 99 | 157 | 99 | 56% |
| **NTA — residential only** | **197** | **3,556** | **10** | **18.1** | **4** | **37** | **93** | **99** | **72%** |
| Census tract | 2,325 | 3,623 | 1 | 1.6 | 1,067 | 2,118 | 2,275 | 44 | — |
| Taxi zone | 260 | — | — | — | — | — | — | — | — |

Raw (un-de-duplicated) series for comparison: CD median 99, NTA-all median 17
(35 zeros, 68 under 5), residential NTA median 22 (1 zero, 8 under 5), tract median 2.

**Why NTA over community district.** 59 observations cannot carry the covariate set
this project needs — restroom supply, subway entries, museums/attractions, taxi
drop-offs, income, poverty, 65+, disability, density is nine predictors before any
borough effect, i.e. ~6 observations per predictor. 197 observations is a real
regression. The sparsity objection to NTA is an artifact of treating this as a
*rate* model: at these counts the correct specification is negative binomial on the
count with `offset(log(pop_total))`, which is built for 4 zeros and a median of 10.
Rates of the form events/100k are what break at low counts, not counts themselves.

**The trade-off I accepted.** NTA-level standard errors will be optimistic because
complaints cluster geographically. The fix is free here: NTA codes nest *exactly*
inside CDTA (the NTA code's first four characters ARE the CDTA code — verified TRUE
for all 262), so cluster NTA standard errors by community district. That buys the
degrees of freedom of 197 with the inference honesty of 59. Run the CD model
(n = 59, median 45, no unit under 10, 97% dense panel) as a pre-committed
robustness spec, and present the CD map to officials, who think in boards.

**Interpretability.** NTAs are named neighbourhoods ("Greenpoint", "Mott Haven-Port
Morris") — a city official reads them without a legend. Tracts fail this badly.

**Why not census tract.** 2,325 observations but median 1 event and 1,067 zeros:
finer geography buys observations and destroys the outcome. Confirmed, not assumed.

**Why not taxi zones or a hex grid.** No demographics attach natively to either, so
every per-capita denominator would itself be an apportionment.

---

## 2. Boundary files pulled

All EPSG:4326 (WGS84), MULTIPOLYGON, verified loading with `sf::st_read()`.
Use EPSG:2263 (NAD83 / New York Long Island ftUS) for any area or distance work —
`NYC_CRS_FEET` in the helpers.

| File | Dataset ID | Rows | Note |
|---|---|---|---|
| `nycopendata_63ge-mke6_tracts2020_20260920.geojson` | `63ge-mke6` | 2,325 | shoreline-clipped; carries `nta2020` + `cdta2020` |
| `nycopendata_9nt8-h7nd_nta2020_20260920.geojson` | `9nt8-h7nd` | 262 | 197 residential, 65 park/airport/cemetery/Rikers |
| `nycopendata_8meu-9t5y_taxizones_20260920.geojson` | `8meu-9t5y` | 263 rows → **260** zones | see multipart defect below |
| `nycopendata_5crt-au7u_communitydistricts_20260920.geojson` | `5crt-au7u` | 71 → **59** real boards | 12 "joint interest areas" (cd_num > 18) dropped |
| `nycopendata_xn3r-zk6y_cdta2020_20260920.geojson` | `xn3r-zk6y` | 71 | tract-built approximation of the boards |

Total tract land area 302.1 sq mi — matches NYC's published 302.6, so the clip is sane.

### Defect found: the taxi zone file has 263 rows but only 260 LocationIDs
Zone **56** (Corona) is 2 separate rows; zone **103** (Governors/Ellis/Liberty
Island) is 3. IDs **57, 104, 105** exist in TLC's lookup table but have no geometry
in the shapefile. **Any join on `locationid` without dissolving first will duplicate
trips 2–3× for those zones.** `01_geography.R` dissolves with `st_union` before use.
Separately, **LocationID 1 = Newark Airport is in New Jersey** and has zero overlap
with any NYC polygon — drop it. IDs 264/265 ("Unknown"/"N/V") in TLC trip data have
no geometry at all. **259 usable NYC zones.**

---

## 3. Crosswalks (all in `data_raw/`)

Exact, attribute-based (no geometry needed — these nest by construction):
- tract → NTA → CDTA. `lookup_tract_to_nta_20260920.csv`, 2,325 rows.
  Every NTA in the tract file exists in the NTA file and vice versa (262 ↔ 262).

Areal, because these layers genuinely do not nest:

| Crosswalk | File | units | exactly one target | biggest ≥95% | median max weight |
|---|---|---|---|---|---|
| taxi zone → tract | `crosswalk_taxizone_to_tract_20260920.csv` | 259 | 10 (4%) | — | 0.245 |
| taxi zone → NTA | `crosswalk_taxizone_to_nta_20260920.csv` | 259 | 93 (36%) | 157 (61%) | — |
| taxi zone → CD | `crosswalk_taxizone_to_cd_20260920.csv` | 257 | 154 (60%) | 197 (77%) | 1.000 |
| tract → CD | `crosswalk_tract_to_cd_20260920.csv` | 2,318 | 2,086 (90%) | 2,167 (93%) | 1.000 |
| NTA → CD | `crosswalk_nta_to_cd_20260920.csv` | 256 | 166 (65%) | 218 (85%) | 1.000 |

**How badly do taxi zones and NTAs nest? Badly.** Only 36% of taxi zones sit inside
a single NTA; the median zone touches 2. Against tracts it is worse — median 8
tracts per zone, and the largest tract holds a median of just 24.5% of the zone.

**Apportionment recommendation: population weights, not area weights.** Taxi trips
track people, not acreage. `crosswalk_taxizone_to_tract` carries both `w_from`
(area share) and `w_pop` (area share re-weighted by ACS tract population,
renormalised to 1 per zone). **Use `w_pop`** (verified to sum to 1.0 per zone to 1.7e-15). They disagree by more than 0.10 on the
top tract for **120 of 259 zones** — this choice materially changes the answer, and
area weighting would spread airport and park-zone trips onto empty land.
Caveat to state in the write-up: disaggregating a zone total to sub-units assumes
uniform demand within the zone, which is an assumption, not a measurement. If taxi
data is only needed as a demand proxy, **aggregate up** (zone → CD, 60% clean) rather
than disaggregating down; upward aggregation needs no within-zone assumption.

### CDTA is a safe stand-in for the real community boards
98.3% of events assigned to a CDTA land in that CDTA's modal real community district.
CDTA-based vs CD-based event counts across the 59 boards: correlation **0.995**,
mean absolute difference 1.8 events, median difference 1.4%. So tract/NTA-built
measures can be rolled to CDTA and read as community-board numbers.

### Join correctness spot-check (not just yield)
Spatially assigned community district vs 311's own `community_board` text field:
**7,897 of 7,960 agree (99.21%)**. The 63 disagreements are near-boundary addresses
(e.g. 13 cases 311 calls MN04 that fall in MN05). The geocoding is trustworthy.

Point-in-polygon yield for the 311 extract: 8,193 rows in, 157 with no coordinates,
161 outside all NTA polygons → **98.0% matched** (97.2% against tracts, which are
shoreline-clipped and so reject a few waterfront points).

---

## 4. Demographics

**`api.census.gov` FAILED.** As of 2026-09-20 every request without an API key
returns `HTTP 302 → /missing_key.html` with header `X-DataWebAPI-KeyError: 1`,
including small ones. The old "no key needed for low volume" behaviour is gone.

**Fallback used, and it works with no key:** the table-based Summary File flat
files at `https://www2.census.gov/programs-surveys/acs/summary_file/2024/table-based-SF/`.
One pipe-delimited file per table, all US geographies, ~18 MB each; `02_acs_demographics.R`
filters to `1400000US36{005,047,061,081,085}`. **ACS 2020–2024 5-year** (latest).

Tables: `B01003` population · `B19013` median household income · `B17001` poverty ·
`B01001` sex by age (65+) · `B18101` disability · `B11001` households.

`census_acs5_2024_tract_demographics_20260920.csv` — **2,327 tracts.**
(Two more than the boundary file: `36047990100` and `36081990100` are water-only
tracts absent from the shoreline-clipped shapefile. Drop them.)

Validation against published NYC figures:

| Measure | Computed | Expected |
|---|---|---|
| Population | 8,483,844 | ~8.3–8.5M |
| Poverty rate | 17.91% | ~17–18% |
| 65+ share | 16.55% | ~16% |
| Disability rate | 12.42% | ~11–12% |
| Median of tract median HH income | $82,676 | plausible |

84 tracts have zero population, 105 under 200 — parks, airports, cemeteries,
industrial. They must be excluded before any per-capita rate.

### Bug found and fixed: `ifelse` in the population-weighted crosswalk
`w_pop` summed to as much as 7.4 for a zone instead of 1.0. `ifelse()` returns a
value shaped like its *test*, so a scalar test (`sum(pop_in_piece) > 0`) recycled a
single number across the whole group. Replaced with `if/else` and guarded by a
`stopifnot`. Worth knowing in every other workstream: this silently corrupts any
group-normalised weight.

### Bug found and fixed: the income aggregation
`med_hh_income` was NA for **259 of 262 NTAs**. Cause was not the ACS sentinel
(`-666666666` was already handled — tract-level income has 128 NAs and no negative
values). It was a dplyr scoping trap: the weighted mean was written inside the same
`summarise()` that creates `pop_total`, so `pop_total` resolved to the newly created
scalar sum rather than the tract vector, and the weight collapsed. Weights are now
built before the `summarise()`, and the weight is **households (B11001)**, not
people — B19013 is a median over households, so households is the correct weight.

Missingness after the fix:

| Variable | NTA, all 262 | NTA, 197 residential | CD, 59 |
|---|---|---|---|
| `med_hh_income_hhwtd` | 62 | **0** | **0** |
| `poverty_rate` | 50 | **0** | **0** |
| `pct_65plus` | 48 | **0** | **0** |
| `disability_rate` | 50 | **0** | **0** |
| `pop_total` | 0 | 0 | 0 |

Every remaining NA is a non-residential NTA. All 65 of them hold **8,090 people
combined** — they are not observations and excluding them costs nothing.

### Analysis-ready files
- `nta_analysis_base_20260920.csv` — 262 rows, `is_residential` flag, demographics,
  `events_311` (cleaned, sums to 3,623), `events_311_raw` (8,032), `events_per_100k`.
- `cd_analysis_base_20260920.csv` — 59 rows, area-weighted demographics, land area,
  density, events, events per 100k (min 10.0, median 30.6, max 236.9).
  Population sums to 8,483,828 against a tract total of 8,483,844 — a 16-person
  rounding gap, so the areal apportionment is not leaking.
- `tract_events311_20260920.csv` — 2,325 rows, for anyone who wants the fine grid.

---

## 5. Helper file `R/geo_helpers.R`

Source it; other workstreams should not re-implement any of this.

- `socrata_get(dataset_id, cache_file=, ...)` — paged JSON pull. Sets
  `options(scipen=999)`, always sends `$order=:id`, 25k pages, 1.5s sleep,
  exponential backoff over 5 attempts, reads the `.rds` cache if present.
  **Tested:** pulled `hm78-6dwm` in 2 pages → 2,327 rows, 2,327 unique geoids;
  second call served from cache.
- `socrata_geojson(dataset_id, out_path)` — boundary download straight to disk,
  same rules. Used for all five boundary files.
- `load_geo(path)` — `st_read` + force EPSG:4326 + `st_make_valid`.
- `points_to_area(df, areas, lon_col, lat_col, area_id)` — `st_join` point tagging.
  Returns a plain data frame (not sf), drops border double-matches, reports
  match rate, attaches `unmatched` / `no_coords` attributes.
  **Tested:** used five times on the real 311 extract, 98.0% match.
- `areal_crosswalk(from, to, from_id, to_id)` — overlap weights in EPSG:2263,
  `w_from` sums to ~1 per source unit. Built all five areal crosswalks.
- Constants `NYC_CRS_WGS84` (4326), `NYC_CRS_FEET` (2263).

`sf_use_s2(FALSE)` is set and restored inside the spatial functions — S2 rejects
some of the city's polygons.

---

## 6. Open issues for other workstreams

1. **My de-dup gives 3,738 events; the 311 workstream reports 3,603 (+3.7%).**
   My recipe is: `complaint_type == "Urinating in Public"`, `location_type ∈
   {Street/Sidewalk, Park/Playground, Subway Station}`, `distinct(incident_address,
   year-month)`. The residual is an unknown de-dup detail. Reconcile before
   anything is published; the geographic conclusions are unaffected at this margin.
2. **Use `w_pop`, not `w_from`, for taxi apportionment.** It changes 120 of 259 zones.
3. **Dissolve taxi zones on `locationid` before joining** or zones 56 and 103
   double- and triple-count.
4. **Drop LocationID 1 (Newark), IDs 264/265, the 12 joint interest areas, the 65
   non-residential NTAs, and tracts `36047990100` / `36081990100`.**
5. The disability rate uses B18101's universe (civilian non-institutionalised),
   which is smaller than total population — do not divide it by `pop_total`.
