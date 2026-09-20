# DEMAND workstream — measures of human presence by area

Pulled 2026-09-20. Independent rebuild; nothing here was taken from the
teammates' `Restroom Gap and ROI (CHOSEN TOPIC)/` folder.

Scripts: `R/demand_00_helpers.R` (Socrata transport + paging, obeys
CONVENTIONS.md), `R/demand_01_pull.R` (the straightforward pulls),
`R/demand_02_hourprofile.R` (the 44.9M-row server-side aggregation).
All outputs in `data_raw/`.

One transport note that applies to the whole project: **`demand_00_helpers.R`
shells out to system `curl` rather than using `httr::GET`.** On the heavy
aggregation queries httr reported connection failures well inside its own
`timeout(300)`, which sent the retry loop chasing a phantom network problem.
curl surfaces the real cause (`curl 52 Empty reply from server` = the server's
own 60s budget), which is what made the problem diagnosable. Note that
`system2()` passes arguments through a shell, so every one must be `shQuote()`d
or SoQL's parentheses become shell syntax errors.

"Demand" = people present in an area who cannot use their own bathroom.
Ranked below by how much of that signal I think each measure actually carries.

---

## Ranked summary

| # | Measure | Dataset | Host | Rows | Geography | Time grain | Strength |
|---|---|---|---|---|---|---|---|
| 1 | Subway hourly profile | `5wq4-mkjj` | data.ny.gov | see below | station lat/lon | hour × day-of-week | **strong** |
| 2 | Subway monthly ridership | `ak4z-sape` | data.ny.gov | 48,255 / 426 stations | station lat/lon (0 missing) | month, 2017-02→2026-07 | **strong** |
| 3 | Taxi/FHV pickups+dropoffs | `c5iv-bn4s` | data.cityofnewyork.us | 138,706 / 3.99B trips | taxi zone (264) | month, 2019-01→2026-07 | **strong** |
| 4 | Workplace jobs (LODES WAC) | LODES8 ny wac 2023 | lehd.ces.census.gov | 25,445 blocks / 4.59M jobs | census block → 2,304 tracts | annual, 2023 | **strong** |
| 5 | Hotels | `tjus-cn27` | data.cityofnewyork.us | 14,010 (1,225 bldgs in 2025) | lat/lon (NTA col is EMPTY) | tax year 2021–2025 | **moderate** |
| 6 | Subway station master | `39hk-dx4f` | data.ny.gov | 496 | lat/lon | static | support |
| 7 | Cultural organizations | `u35m-9t32` | data.cityofnewyork.us | 2,535 (267 ungeocoded) | lat/lon + NTA | static | **weak** |
| 8 | Pedestrian counts | `cqsj-cfgu` | data.cityofnewyork.us | 114 | screenline geom | 2× per year, 2007→2026 | **too sparse** |

---

## 1. Subway — the single best demand measure we have

### What is actually published
The MTA splits hourly ridership across three tables, all on **data.ny.gov**
(not data.cityofnewyork.us — that was the first thing to get right):

- `t69i-h2me` — Hourly ridership 2017–2019
- `wujg-7c2s` — Hourly ridership 2020–2024
- `5wq4-mkjj` — Hourly ridership **beginning 2025** ← the current one

`5wq4-mkjj` verified live: **44,937,246 rows**, covering
**2025-01-01 00:00 → 2026-09-10 23:00**, totalling 2,216,217,173 rides.
Broken out by `transit_mode`: subway 44,607,055 / staten_island_railway
174,353 / tram 155,838. Each row is station-complex × hour × payment_method ×
fare_class_category.

### Coordinates — answering the question directly
Coordinates are **real CSV columns**, not JSON-only. Both `5wq4-mkjj` and
`ak4z-sape` carry flat `latitude` and `longitude` fields alongside a
`georeference` point object. Only the `georeference` object is awkward (it
serialises through R as `c(-73.91203, 40.775036)` text and is unusable) — the
`latitude`/`longitude` columns are clean and are what we use. No geocoding
step needed.

### The server-side aggregation trick (the important bit)
We never download 44.9M rows. Socrata executes `sum()` + `$group` on its side
and returns only the aggregate. The working call shape:

```
$select = station_complex_id,
          date_extract_hh(transit_timestamp)  AS hh,
          date_extract_dow(transit_timestamp) AS dow,
          sum(ridership) AS rides, sum(transfers) AS xfers, count(*) AS n_rows
$where  = transit_mode='subway' AND borough='Brooklyn'
          AND transit_timestamp >= '2025-10-13' AND transit_timestamp < '2025-10-20'
$group  = station_complex_id, date_extract_hh(transit_timestamp),
          date_extract_dow(transit_timestamp)
$order  = station_complex_id
$limit  = 50000
```

**data.ny.gov enforces a hard ~60-second gateway timeout**, and — this is the
trap — a query that exceeds it does **not** return an HTTP error. It returns
`curl 52 Empty reply from server` / an httr connection error, which looks like
a flaky network and invites pointless retrying. It is not flaky; it is a
deterministic budget. Five retries with backoff will fail five times.

The cost driver turned out to be **the size of the time window**, not the
grouping. Measured directly:

| Query | Result |
|---|---|
| Full-year window, grouped station × hh × dow | **timeout at 60s** |
| One-month window | **timeout at 60s** |
| One-month window + `borough=` filter | **timeout at 60s** |
| **One-week window + `borough=` filter** | **~8s. Works.** |

So the shipped pull (`R/demand_02_hourprofile.R`) walks **52 consecutive weeks
× 4 boroughs = 208 small queries**, each comfortably inside the budget. It
covers **2025-09-01 → 2026-08-30**, a genuine full year — not a sample.

Four more findings worth keeping, each of which cost a failed run:

1. **`$group` must repeat the whole `date_extract_*()` expression**, not the
   `hh`/`dow` aliases. Grouping by the alias returns HTTP 400
   `query.soql.column-not-in-group-bys`.
2. **Never put a computed expression in `$where`.** Splitting the day with
   `date_extract_hh(transit_timestamp) < 12` to halve the result size blew the
   60s budget on its own. Filter only on plain indexed columns
   (`transit_mode`, `borough`, `transit_timestamp`); compute only in
   `$select`/`$group`.
3. **Never alias an aggregate onto its source column.** `sum(ridership) AS
   ridership` shadows the real column; use `AS rides`.
4. **`$order` must be a plain grouped column.** `$order=station_complex_id, hh,
   dow` forces a sort over the full aggregate and re-triggers the timeout;
   `$order=station_complex_id` alone is fine. Because that is not a unique
   sort, the design deliberately **avoids `$offset` paging altogether** — each
   borough-week returns under the 50,000-row page limit (Brooklyn, the biggest,
   yields ~25.8k), so there is never a second page to mis-order. This also
   dodges a real cost trap: `$offset` on an aggregate makes Socrata **re-run
   the entire aggregation** for every page.

Borough split verified live: Bronx 68 · Brooklyn 156 · Manhattan 121 ·
Queens 79 = **424 station complexes**. (Staten Island has no subway; SIR and
the Roosevelt Island tram are excluded by `transit_mode='subway'`.)

Each week is checkpointed to `data_raw/_hourprofile_parts/wk_YYYYMMDD.csv`, so
a mid-run failure costs one week rather than the whole pull, and the run is
resumable. The 52 checkpoints are then summed into one
station × borough × hh × dow table.

This directly supports the "what's open at 11pm" question: `hh` 0–23 crossed
with `dow` 0–6 per station separates late-night demand from commuter peak, and
weekend from weekday.

### Monthly table
`ak4z-sape` (Feb 2017 → Jul 2026, 48,255 rows) is station-complex × month with
lat/lon already attached. Verified on disk: **426 distinct stations, 114
months, zero missing coordinates**, and calendar-2025 ridership sums to
**1,299,195,857**. Note 426 stations here vs 445 complexes in `39hk-dx4f` —
that gap must be reconciled before joining, not assumed away. Small enough to take whole, and it gives us a
**9-year trend and seasonality** — useful for showing demand is structural, not
a one-year artefact. Use this for annual totals; use `5wq4-mkjj` for the
within-day profile.

### Station master
`39hk-dx4f` — 496 stop rows resolving to **445 distinct `complex_id`**.
Cardinality check run as CONVENTIONS requires (`count(key) |> count(n)`):
410 complexes have 1 stop, 24 have 2, 7 have 3, 3 have 4, and 1 has 5.
**163 of the 496 stops are flagged `ada = 1`.**
Note the cardinality: this is **many-to-one** at the complex level, so it must
NOT be joined naively to the ridership tables, which are keyed on
`station_complex_id`. Per CONVENTIONS join rules, collapse to complex first and
check the count. Carries `ada`, `ada_northbound`, `ada_southbound`, `structure`
and `cbd` flags — ADA status is directly relevant to a restroom-siting argument.

---

## 2. Taxi / rideshare — pre-aggregated, and it is the right choice

`c5iv-bn4s` "Pickups and Drop-offs by Taxi Zone and Industry" — **verified
live on data.cityofnewyork.us**. 138,706 rows. This is the pre-aggregate the
brief hoped existed, and it is genuinely much better than the raw trip tables
(which run to tens of millions of rows *per year* — `4b4i-vvec`, `u253-aew4`
etc. all exist but there is no reason to touch them).

Schema: `metric_month`, `industry`, `pickup_dropoff`, `locationid`, `borough`,
`zone`, `trip_count`.

- Coverage: **2019-01-01 → 2026-07-01**, summing to **3,989,493,475 trips**.
- `industry`: `FHV - High Volume` (Uber/Lyft), `Yellow Taxi`, `Green Cab` —
  each split `Pick-up` / `Drop-off`. All 6 combinations present, ~21k–24k rows each.
- Geography: **taxi zone `locationid`**, which joins to the taxi-zone polygons.

**Dimensional limit, stated plainly: there is NO hour-of-day here.** Month is
the finest grain. So taxi/FHV can tell us *where* the churn of arriving and
departing people is, and how it changed across years, but it cannot tell us
about 11pm on its own. The subway hourly profile has to carry the time-of-day
story.

Why this matters for restrooms specifically: a **drop-off** is a person
arriving somewhere away from home. That is conceptually much closer to
"needs a restroom soon" than a pickup is. Keeping the pickup/dropoff split
rather than summing them is the useful modelling choice.

Geography join: `data_raw/crosswalk_taxizone_to_nta_*.csv`,
`crosswalk_taxizone_to_cd_*.csv` and `crosswalk_taxizone_to_tract_*.csv`
already exist from the geography workstream, so this is joinable to whatever
unit the final model uses. Verified on disk: the TLC file covers **264 distinct
`locationid` values over 91 months**, summing to 3,989,493,475 trips.

A flat `locationid → zone → borough` lookup was also pulled from `8meu-9t5y`
as `nyc_8meu-9t5y_taxizonelookup_20260920.csv` (**263 zones**). Warning worth
recording: pulling `8meu-9t5y` *with* its `the_geom` column through R/jsonlite
produces a corrupt CSV — the MultiPolygon serialises as R `c(...)` text
containing newlines, which inflated the file to 7,035 apparent lines for 260
zones. That file was deleted. **Use the geometry-free lookup above, or the
`nycopendata_8meu-9t5y_taxizones_*.geojson` the geography workstream already
pulled — never a Socrata geometry column via `read.csv`.**



### Join check, run properly (not just "did it resolve")

`crosswalk_taxizone_to_nta_*.csv` is **one-to-many with areal weights**
(`locationid`, `nta2020`, `w_from`), 565 rows. Cardinality
(`count(key) |> count(n)`): 93 zones map to exactly 1 NTA, 78 to 2, 54 to 3,
21 to 4, 9 to 5, 3 to 6, 1 to 7. **`w_from` sums to exactly 1.000 for every
zone** (min = max = 1), so it is a clean apportionment.

**This must be applied as a weighted split, not a "biggest/first NTA wins"
collapse** — that would silently move up to 100% of a zone's trips into one
NTA. This is exactly the tie-break CONVENTIONS forbids.

Join yield: **258 of 264 TLC zones match (97.7%)**. I checked *what* the six
misses are rather than just counting them, and they are all correct exclusions:

| id | zone | trips | share |
|---|---|---|---|
| 265 | Outside of NYC | 65,965,606 | 1.653% |
| 1 | Newark Airport (New Jersey) | 11,071,749 | 0.278% |
| 264 | N/A / Unknown | 2,968,914 | 0.074% |
| 57 | Corona | 730,082 | 0.018% |
| 105 | Governor's/Ellis/Liberty Island | 1,387 | ~0% |
| 104 | Governor's/Ellis/Liberty Island | 60 | ~0% |

Unmatched is **2.02% of all trips, and 1.93pp of that is "Outside of NYC" plus
Newark, which we want dropped anyway.** Genuine unexplained loss is ~0.09%
(zone 264 Unknown, a deprecated duplicate Corona zone 57, and the harbour
islands, which have no NTA). Materially complete.

### Face validity
Top drop-off zones over the full period, as a sanity check that the measure
means what we think it means:
JFK Airport 35.2M · LaGuardia 34.9M · Midtown Center 29.9M ·
Upper East Side South 26.7M · Times Sq/Theatre District 26.5M ·
Upper East Side North 26.5M · East Village 26.0M.
Airports, Midtown and Times Square at the top is exactly the ranking a
"people arriving away from home" measure should produce. This one passes.

---

## 3. Employment / daytime population — the underrated one

**Census LEHD LODES8, `ny_wac_S000_JT00_2023.csv.gz`** from
`lehd.ces.census.gov/data/lodes/LODES8/ny/wac/`. Verified the directory lists
2002 → **2023**; 2023 is the newest vintage available.

WAC = Workplace Area Characteristics: jobs counted **at the workplace**, at
**census-block** resolution, which is finer than anything else in this project.
Filtered to the five NYC counties (Bronx 005, Kings 047, New York 061,
Queens 081, Richmond 085) and a `tract` key (first 11 chars of `w_geocode`)
added for joining.

**Verified on disk: 25,445 NYC blocks carrying 4,585,129 jobs**, spread over
**2,304 distinct census tracts** (NYC has ~2,325, so coverage is near-total;
the WAC file only lists blocks that actually contain jobs, which is why the
block count is below NYC's ~38k). Jobs by county:
Manhattan 2,504,522 · Brooklyn 883,243 · Queens 728,370 · Bronx 340,785 ·
Staten Island 128,209.

This is the measure nobody thinks to include, and it should be a strong
predictor: it is the only one that captures **weekday daytime population** —
office workers, retail staff, construction, hospital staff — people who are
away from home for 8–10 hours and structurally cannot use their own bathroom.
Subway ridership partly proxies this but attributes everyone to a station, not
to where they actually spend the day. Segment columns (`CNS01`–`CNS20` by
industry, `CE01`–`CE03` by earnings) are retained, so we can distinguish e.g.
accommodation/food-service jobs from finance jobs.

The file has **55 columns**. Verified NYC 2023 segment totals:

| Segment | Jobs |
|---|---|
| `C000` All jobs | 4,585,129 |
| `CNS12` Professional / scientific / technical | 453,200 |
| `CNS15` Health care & social assistance | 439,969 |
| `CNS10` Finance & insurance | 366,524 |
| `CNS18` **Accommodation & food service** | 330,725 |
| `CNS07` Retail trade | 301,482 |
| `CNS09` Information | 251,789 |
| `CNS17` Arts / entertainment / recreation | 88,450 |

Two things make this variable unusually useful here:

- **The skew is enormous, which is what we want from a discriminator.** The
  median NYC tract has **541 jobs**; the top six tracts (all Manhattan,
  `36061...`) carry 52,070–78,023 each. No tract has zero. A demand index built
  only on residential population would flatten exactly the places where the
  restroom problem is worst.
- **`CNS18` Accommodation & food service cuts both ways and should be modelled
  carefully.** Restaurants, bars and hotels generate demand, but they are also
  NYC's de facto informal restroom supply. A high `CNS18` tract may have a
  large *latent* gap that only appears at night when those businesses close —
  which ties straight back to the subway hour-of-day profile. Worth a deliberate
  interaction term rather than treating it as just another job count.

Annual only — no within-year variation. That is fine; it is a structural
baseline, not a temporal signal.

---

## 4. Tourist / visitor attractors — one usable, one not

### Hotels — worth having (`tjus-cn27`, 14,010 rows)
"Hotels Properties Citywide", derived from the property tax roll. Carries
`latitude`/`longitude`, `nta`, `bbl`, `bin`, `bldg_class`, `taxyear`.

Verified structure (counts re-derived from the file on disk, not from metadata):
- `taxyear` runs **2021–2025**: 2,731 / 2,788 / 2,798 / 2,835 / 2,858 rows.
  **It is a panel, not a snapshot** — you must filter to one tax year or you
  will count every hotel five times. This is exactly the many-to-one trap
  CONVENTIONS warns about.
- Within taxyear 2025: **2,858 rows collapse to only 1,225 distinct `bbl` and
  1,167 distinct `bin`.** So rows overstate buildings by ~2.3x even inside a
  single year. Use `n_distinct(bin)`. Of the 2,858, **1,121 are non-`RH`**
  (i.e. actual hotel building classes rather than hotel-condo units).
- **The `nta` column is 100% empty — all 2,858 rows blank. Do not rely on it.**
  Geocode from `latitude`/`longitude` instead; only **8 rows** are missing
  coordinates, so point-in-polygon gives essentially full coverage.
- Borough distribution for taxyear 2024 is itself informative and is the
  reason this is a *tourist* proxy rather than a population proxy:
  Manhattan 2,310 / Queens 225 / Brooklyn 195 / Bronx 83 / Staten Island 16.
- `bldg_class`: **`RH` is the largest class (8,462 rows across all years)** and
  is hotel *condominium units*, so row counts inflate buildings. `H1`–`H9`,
  `HB`, `HR`, `HS`, `HH` are the actual hotel building classes. Recommend
  counting **distinct `bin` or `bbl`**, not rows, and reporting H-classes
  separately from `RH`.

Caveat to state honestly: this is hotel *properties*, not room counts and not
occupancy. A 2,000-room Midtown hotel and a 20-room Queens motel count the
same. Room count would be better; it is not in this dataset.

### Cultural organizations — pulled, but weak (`u35m-9t32`, 2,535 rows)
This is precisely the dataset the brief warned about, and the warning is
correct. Discipline breakdown, verified:

Theater 429 · Music 403 · Multi-Discipline Perf & Non-Perf 315 ·
Multi-Discipline Performing 244 · Dance 235 · Visual Arts 168 ·
(blank) 121 · Multi-Discipline Non-Perf 120 · Film/Video/Audio 115 ·
**Museum 99** · Literature 63 · Other 50 · Folk Arts 44 · Humanities 34 ·
Architecture/Design 33 · New Media 20 · Photography 14 · Science 13 ·
Botanical 6 · Crafts 6

Geocoding is also incomplete: **267 of 2,535 (10.5%) have no
latitude/longitude**, and the same 267 have no NTA. Borough split is
Manhattan 1,508 · Brooklyn 576 · Queens 257 · Bronx 127 · Staten Island 64.

**This is a grants-administration list of small community arts nonprofits, not
a measure of tourist footfall.** A 30-seat Bushwick theatre collective and the
Met are one row each. Recommendation: **do not use the 2,535 as a density
variable.** If it is used at all, use only the
`Museum` + `Botanical` + `Science` subset (**118 organisations**) as a rough
major-attraction indicator, and even then it will miss non-DCLA destinations
entirely (Times Square, the High Line, Central Park, Statue of Liberty ferry
terminal are not "cultural organizations" in this file).

### Evaluated and rejected
- **`kcrm-j9hh` "Museums and galleries"** — looked promising; it is a
  **non-tabular** map asset. Every API call returns
  `no row or column access to non-tabular tables`. Unusable. **FAILED.**
- **`mzbd-kucq` "Places"** — 96 rows, no column metadata, last updated 2013.
  Dead. **FAILED.**
- **`buis-pvji` "Individual Landmark Sites"** — 1,532 polygons, but LPC
  designation tracks architectural merit, not visitor volume; a landmarked
  brownstone row is not an attractor. Same failure mode as the DCLA list.
  Deliberately **not pulled**.

Honest overall verdict on tourism: **hotels are the only defensible
tourist-presence variable we found.** Everything else on NYC Open Data that
sounds like tourism is either an arts-grants roster or a preservation registry.
The subway hourly profile and TLC drop-offs will end up carrying the visitor
signal better than any "attractions" list would have.

---

## 5. Pedestrian counts — coverage is too sparse. Say so.

`cqsj-cfgu` "Bi-Annual Pedestrian Counts". **114 rows = 114 screenline
locations for the entire city.** For scale, NYC has ~2,300 census tracts and
~260 taxi zones; 114 points cannot support a citywide demand surface. There is
no imputation that rescues this.

What it *is* good for, and the only way it should be used: **out-of-sample
validation.** Verified on disk: 114 rows, of which **113 have a May 2026 reading**, so the
series is current rather than abandoned. Locations break down as
Manhattan 36 · Brooklyn 26 · Queens 25 · Bronx 8 · Harlem River Bridges 9 ·
East River Bridges 5 · Staten Island 5 — note that 14 of the 114 are *bridges*,
which are not neighbourhood footfall at all.
It is wide-format — `may_07_am/pm/md` through `may26_am/md/pm`,
i.e. AM / midday / PM screenline counts twice a year from 2007 to **May 2026**.
That is a genuine 19-year time series at the locations it does cover. If our
modelled demand index correlates well with observed pedestrian volume at those
114 points, that is a real credibility check on the whole index. Pulled for
that purpose only.

Also seen but not pulled: `6fi9-q3ta` (Brooklyn Bridge automated pedestrian
counts — one location, high frequency), `ct66-47at` / `6up2-gnw8` (bike +
pedestrian sensors, bike-dominated).

---

## Things that failed or were rejected

| Thing | Outcome |
|---|---|
| `c5iv-bn4s` on data.ny.gov | 404 — it is a **NYC Open Data** dataset, not state. Confirmed on data.cityofnewyork.us. |
| `kcrm-j9hh` Museums and galleries | Non-tabular map asset, no API row access. Unusable. |
| `mzbd-kucq` Places | 96 rows, no schema, stale since 2013. |
| `buis-pvji` Landmark Sites | Valid data, wrong construct — designation ≠ footfall. Not pulled. |
| Grouping by SoQL alias | HTTP 400 `column-not-in-group-bys`. Must repeat the full expression in `$group`. |
| `sum(x) AS x` aliasing | Shadows the source column; rename the aggregate. |
| Raw TLC trip tables | Tens of millions of rows per year. Never attempted — the aggregate is strictly better. |
| DOT pedestrian counts as a predictor | 114 locations citywide. Demoted to validation-only. |

## Files on disk (`data_raw/`), pulled 2026-09-20

| File | Dataset ID | Host | Rows |
|---|---|---|---|
| `mta_5wq4-mkjj_hourprofile_20260920.csv` | `5wq4-mkjj` | data.ny.gov | ~71k (station x hh x dow, summed over 52 weeks) |
| `mta_ak4z-sape_monthly_20260920.csv` | `ak4z-sape` | data.ny.gov | 48,255 |
| `mta_39hk-dx4f_stations_20260920.csv` | `39hk-dx4f` | data.ny.gov | 496 |
| `tlc_c5iv-bn4s_zonemonth_20260920.csv` | `c5iv-bn4s` | data.cityofnewyork.us | 138,706 |
| `nyc_8meu-9t5y_taxizonelookup_20260920.csv` | `8meu-9t5y` | data.cityofnewyork.us | 263 |
| `census_lodes8_nywac2023_20260920.csv` | LODES8 ny wac 2023 | lehd.ces.census.gov | 25,445 |
| `nyc_tjus-cn27_hotels_20260920.csv` | `tjus-cn27` | data.cityofnewyork.us | 14,010 |
| `nyc_u35m-9t32_cultural_20260920.csv` | `u35m-9t32` | data.cityofnewyork.us | 2,535 |
| `nyc_cqsj-cfgu_pedcounts_20260920.csv` | `cqsj-cfgu` | data.cityofnewyork.us | 114 |
| `_hourprofile_parts/wk_*.csv` | — | — | 52 weekly checkpoints, ~70k rows each |

Reproduce with `R/demand_01_pull.R` then `R/demand_02_hourprofile.R`.
Both are cache-aware: delete the target file to force a re-pull.

---

## Join warnings for whoever builds the model

- `39hk-dx4f` is **496 stops → 445 complexes**. Many-to-one. Collapse to
  `complex_id` before joining to ridership, and check `count(key) |> count(n)`.
- `tjus-cn27` is a **5-year panel** (2021–2025). Filter to one `taxyear`
  first or hotel counts inflate ~5×. Within a year, `RH` rows are condo units,
  so count distinct `bin`/`bbl`.
- `c5iv-bn4s` is keyed on **taxi zone**, subway on **lat/lon**, LODES on
  **census block**. Three different geographies. The crosswalks already in
  `data_raw/` from the geography workstream handle taxi-zone → NTA / CD / tract;
  subway stations and hotels need a point-in-polygon step.
