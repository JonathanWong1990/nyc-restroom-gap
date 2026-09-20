# Supply-side data — NYC Restroom Gap & ROI (independent rebuild)

Pulled **2026-09-20**. Scripts: `R/pull_supply.R` (pull), `R/parse_hours.R` (hours parser).
All pulls follow CONVENTIONS: `scipen=999`, `$order=:id`, 25k paging, 1.5s sleep, disk cache.

## Datasets pulled

| # | Dataset | ID | Rows | Source rows updated | File |
|---|---|---|---|---|---|
| 1 | Public Restrooms | `i7jb-7jku` | 1,066 | **2025-06-27 (stale, 15 mo)** | `nycrestrooms_i7jb-7jku_20260920.csv` |
| 2 | Parks Properties | `enfh-gkve` | 2,061 | 2026-09-16 | `parksprops_enfh-gkve_20260920.csv` + `.geojson` + `_sf_.rds` |
| 3 | Capital Project Tracker | `4hcv-tc5r` | 2,787 | 2026-09-19 | `capitaltracker_4hcv-tc5r_20260920.csv` |
| 4 | Parks Closure Status COVID: Comfort Stations | `i5n2-q8ck` | 672 | 2021-11-22 (frozen) | `csclosurecovid_i5n2-q8ck_20260920.csv` |
| 5 | PIP – Public Restrooms (closure flags) | `9byw-znpj` | 736 | 2026-09-03 | `pipRestrooms_9byw-znpj_20260920.csv` |
| 6 | NYC Parks Structures | `n8q6-i44s` | 2,857 | 2026-09-17 | `parkstructures_n8q6-i44s_20260920.csv` |
| 7 | PIP – Public Restroom Inspections | `mp8v-wjtf` | 31,768 | 2026-09-03 | `pipInspections_mp8v-wjtf_20260920.csv` |
| 8 | **PIP – Inspections (master, DATED)** | `yg3y-7juh` | 152,484 | 2026-09-03 | `pipInspectionsMaster_yg3y-7juh_20260920.csv` |
| 9 | PIP – All Sites (MAPPED) | `buk3-3qpr` | 6,406 | 2026-08-22 | `pipAllSites_buk3-3qpr_20260920.csv` |

All three candidate IDs in the brief verified live. **Caveat on #1:** the catalog page
says modified 2025-11-05 but `rowsUpdatedAt` is 2025-06-27 — the *data* is 15 months old.
Treat the inventory as a mid-2025 snapshot, not current.

## 1. Restroom inventory (`i7jb-7jku`, n=1,066)

Status: **Operational 975**, Not Operational 73, Closed for Construction 17, Closed 1.
Seasonality: Year Round 855, Seasonal 132, Future 6, blank 73.
**Operational AND year-round = 843** — this is the real denominator, not 1,066.

Type: Park 824, Library 216, POPS 14, Public Plaza 7, Transit 5.
Operator: NYC Parks 728, NYPL 91, Parks Concessionaire 71, QPL 63, BPL 62, rest small.

Lat/lon: **1,066 / 1,066 (100%) usable**, all within the NYC bbox. No geocoding needed.
Borough (spatial join of points to Parks borough polygons):
B 216 · M 157 · Q 209 · R 57 · X 151 · outside any park polygon 276.
The 276 are the library/POPS/plaza/transit facilities — consistent with 824 park sites.

Missingness: additional_notes 93% blank, website 79%, accessibility 16%,
restroom_type 14%, hours 8.7%, changing_stations 8.1%. Core fields are complete.

## 3. Accessibility fields

Two usable fields:
- `accessibility`: Fully Accessible 619, Not Accessible 218, Partially Accessible 53,
  Limited Accessibility 1, **blank 175 (16.4%)**. Free-text-ish but effectively a
  4-level ordinal; "Limited"/"Partially" are redundant labels for the same idea.
- `changing_stations`: Yes 659, No 174, blank 86, plus 8 free-text variants
  (`"Yes, in men's restroom only"`, `"N/A, restrooms closed"` etc.) — needs cleaning.

**Operational AND Fully Accessible = 577 of 975 (59%).** 198 operational restrooms are
flagged Not Accessible. No ADA-standard field (no door width, grab bars, etc.).

## 2. Hours parser (`R/parse_hours.R`)

Output: `data_raw/parsed_hours_20260920.csv`, **7,462 rows = 1,066 facilities x 7 days**.
Columns: `facility_id, facility_name, day_of_week (1=Sun), open_hour, close_hour,
is_open, parsed, parse_method, dusk_assumed, multi_range, ampm_repaired, day_implied_closed`.
`close_hour` may exceed 24 for past-midnight closes (6am–1am → 6.0, 25.0).

**Parse rate: 965 / 1,066 facilities = 90.5% overall; 99.2% of the 973 with non-blank hours.**

| method | facilities | meaning |
|---|---|---|
| uniform | 744 | one range applied to all 7 days (`6:00am-11:00pm`, `24 Hours`) |
| labeled | 145 | per-day lines (`Sunday: Closed \n Monday: 9:00 am - 7:00 pm`) — libraries |
| dayprefixed | 76 | day ranges (`M-F 10:30am-5:15pm S-S 12:00pm-8:00pm`, `Monday to Friday: …`) |
| **blank** | **93** | field empty — the single biggest failure |
| **unparseable** | **8** | `Open by permit`, `Park Hours`, `Temp Closed`, `Concession Operating Hours`, `Tuesday-Saturday`, a bare URL |

Known limitations, all flagged in the output so they can be dropped:
- `dusk_assumed` (3 facilities): `"6am - dusk"` has no clock time. Substituted
  **DUSK_HOUR = 20.0**. Not a measurement — drop these for any night-time analysis.
- `multi_range` (9 facilities): text held >1 range (`"6am - 12am, 8am - 11pm"` =
  summer/winter; `"7am-7pm, with a one-hour closure for cleaning 12-1pm"`).
  **We keep the FIRST range**, so midday cleaning closures are not represented.
- `ampm_repaired` (53 rows / 27 facilities): the **source data** contains am/pm typos —
  e.g. a library listed `"Tuesday: 10:00 pm - 6:00 pm"`. A pm open producing a >14h day
  is treated as a typo and flipped to am. This is a repair of NYC's data, not ours.
- `day_implied_closed` (7 rows): a day never mentioned in a per-day listing is set closed.
- Holidays, seasonal park schedules and winterisation are **not** in this field at all.

Bugs found and fixed during the audit (yield alone was misleading):
1. `"7 a.m."` — the `m` in `a.m.` matched the Monday alias, so 5 transit facilities
   parsed as Monday-only. Day tokens now require word boundaries; single-letter codes
   are only honoured inside an explicit range (`M-F`, `S-S`).
2. `"Monday to Friday"` / `"Monday to Saturday"` were unmatched (only `-` was handled).
3. `"Friday 4:00-10:00pm"` parsed as 04:00. An unsuffixed open now inherits the close's
   meridiem when that yields a sane interval → 16:00.

Sanity: 0 rows with close<=open, 0 open>24, 0 close>26, exactly 7 rows per facility.
Median open day = 8.0 hours. **Only 9 facilities are 24-hour; only 21 are open at
11pm on a Saturday.** The late-night gap is real and it is the headline supply fact.

## 4. Parks Properties (`enfh-gkve`, n=2,061)

**The JSON API returns the `multipolygon` column empty** (flattened to
`multipolygon.type`/`.coordinates`, both blank). Geometry must come from the GeoJSON
export endpoint — `pull_supply.R` now does this automatically.

`sf` load: 2,061 MULTIPOLYGON features, CRS WGS 84, bbox correct for NYC.
2,047 valid on load, **2,061 after `st_make_valid()`** — cached as
`parksprops_sf_20260920.rds`. Fully usable.

Acreage: numeric for all 2,061, total **30,455 acres**; median 0.70, max 2,771.7
(Pelham Bay). Geometry-derived acreage totals 28,928 and correlates **r = 0.991** with
the stated field — the two agree, use `acres`.
`gispropnum` is a clean unique key (2,061 distinct / 2,061 rows).
Borough: B 628 · Q 478 · X 399 · M 396 · R 160.

## 5. Cost evidence (`4hcv-tc5r`)

Filter `title`+`summary` on `restroom|comfort station|bathroom|lavator` → **247 rows**.

**Cardinality (checked before aggregating, per CONVENTIONS):** 247 rows are only
**191 distinct projects**. 21 projects are multi-park bundles repeating the SAME
`totalfunding` on each park row (one appears 5x at $19,393,000; another 10x).
**Summing the raw rows overstates capital spend by ~2.4x.** Always dedup on `trackerid`.
Funding is constant within a `trackerid` — 0 trackerids disagree.

**`totalfunding` is FREE TEXT, and mixed.** 128 of 191 projects parse to a number after
stripping `$` and commas. The other **63 (33%) are banded strings** that cannot be made
numeric: "Between $3 million and $5 million" (23), "Between $5M and $10M" (18),
"Greater than $10 million" (12), "Less than $1 million" (6), "Between $1M and $3M" (4).
Any cost model must either drop a third of projects or impute band midpoints — say which.

**Project-level cost (n=128 numeric):** min $45,000 · p25 $830,250 · **median $1,559,000**
· p75 $3,637,750 · p90 $4,850,200 · max $30,096,000 (Freshkills North Park).

**Per-site cost** (project funding / number of parks in the bundle), the figure an ROI
model actually needs: min $43,000 · p25 $485,750 · **median $1,397,000** · p75 $2,651,083.
Split by scope:
- **New build** (n=59): median **$3,793,000** per site.
- **Reconstruction / renovation** (n=130): median **$1,152,500** per site.
- Component work (roof, HVAC, electrical): **$45,000–$76,000** — the cheap-fix tail.

**Can costs be geolocated below borough? YES — this is better than expected.**
`latitude`/`longitude` are present on **248/248 (100%)** of restroom project rows, and
`parkid` on 248/248. `parkid` matches Parks Properties `gispropnum` for **202 of 203
distinct ids (99.5%)**. Costs join at the individual park level, not borough.
(The `borough` field itself is dirty — concatenations like `"BronxManhattan"` and
`"Brooklyn, Queens, Manhattan, Bronx"` — another symptom of bundling. Use `parkid`.)

**Dates: yes, and they are good.** Phase: completed 175, proposed 41, design 16,
construction 12, procurement 3. On restroom projects: `designstart` 207/248,
`constructionstart` 185, **`constructionactualcompletion` 175**, spanning **2013–2026**
(peak 2019, n=35). **173 projects have both an actual completion date and a cost.**
Median design-start → construction-completion = **5.25 years** (p25 3.7, max 13.0) —
a first-order ROI finding on its own.

## 6. Closure / status-change events — what exists

**(a) COVID comfort-station closures `i5n2-q8ck` — dated, but a weak experiment.**
672 comfort stations; 431 have `approx_date_closed`, 420 `approx_date_reopened`,
**381 have both**. Median closure 40 days. BUT there are only **8 distinct close dates
(all 2020-05-12 → 2020-06-02) and 8 distinct reopen dates (2020-06-19 → 2020-07-06)**.
Treatment timing is effectively simultaneous and citywide, perfectly confounded with
lockdown — **no staggered adoption, no clean control, so this will not support a DiD.**
`editdate` is 2020-08-12 for every row: a frozen Aug-2020 snapshot despite the catalog
claiming a 2026 update. Status: Reopened 425, Active 201, UnderConstruction 37, COVID
Closure 9. `gispropnum` present on all 672, so it joins.

**(b) PIP long-term closures `9byw-znpj` — undated.** 80 of 736 restrooms are flagged
`long_term_closure = Yes` (reasons: Repairs 46, Permanently Closed 15, Capital 8,
No Power 6). 130 of 736 are `winterized`. **No date column at all** — a current-state
snapshot only, useless as an event study but good as a cross-sectional outage measure.

**(c) Parks Structures `n8q6-i44s` — dated openings.** 759 of 2,857 structures are
`public_restroom = TRUE`. `featurestatus`: Active 715, Inactive 27, Removed 9,
Closed Temporarily 7. `construction_year` on 671 (range 1869–2025), **53 built since
2010**; `alteration_year` on 113; `demolition_year` on 2. Geometry included.

**(d) ⭐ PIP inspections master `yg3y-7juh` — THE find. A real dated panel.**
31,768 restroom inspections join to the master on `inspectionid` = `inspection_id` at
**100.0%**, giving a date for every one. Range **2004-05-20 → 2026-06-28**,
~1,000–2,000 inspections/year, **961 distinct restroom sites**, median 43 inspections
per site. **733 sites have ≥8 inspections spanning ≥4 years.** The master carries
`closed`, `overall_condition`, `cleanliness`, `safety_condition`, `structural_condition`
and `visitorcount` per visit, and **584 sites change `closed` status across their
history** (Closed/No Construct. 151, Under Construction 202, Partial Construction 1,703).

This is the natural experiment the brief asked for: pair the 173 capital projects that
have a dated completion and a cost with the inspection panel at the same park, and you
can estimate before/after condition and closure effects per dollar spent.

**Join key warning:** PIP `prop_id` matches Parks `gispropnum` for only **502/961 (52%)**
raw, because PIP uses zone-level ids (`M010-ZN16`, `X136-01`). Stripping the suffix
(`sub("-.*$","",prop_id)`) lifts it to **940/961 (98%)** — but this is **many-to-one**:
961 inspection sites collapse to 608 parent parks. Do not aggregate on it without
deciding how to handle multiple restrooms in one park. 21 ids still fail (`Q510`, `BT15`,
`M391`, `Q468_temp` — temporary/borough-wide codes).

## Failures / caveats to carry forward
1. Restroom inventory data is **15 months stale** (rows updated 2025-06-27).
2. **33% of restroom capital projects have no numeric cost** — banded text only.
3. Raw capital rows **double-count**; dedup on `trackerid` or overstate spend ~2.4x.
4. Hours: 93 facilities blank + 8 unparseable = **101 facilities (9.5%) have no hours**.
5. `multipolygon` is empty via the JSON API — geometry needs the GeoJSON endpoint.
6. The COVID closure file is dated but **not usable as a DiD** (simultaneous treatment).
7. PIP↔Parks join needs suffix stripping and is many-to-one.
