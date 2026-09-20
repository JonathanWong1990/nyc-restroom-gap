# 311 as an outcome variable — workstream notes

Pulled 2026-09-20. Source: NYC Open Data, `https://data.cityofnewyork.us/resource/erm2-nwe9.json`.
Verdict up front: **YES, a usable outcome variable exists** — "Urinating in Public",
de-duplicated to address-month, aggregated to community board. See caveats.

---

## 1. What is actually in erm2-nwe9

- Dataset now covers **2020-01-01 → 2026-09-19 only**, **22,530,629 rows**, 276 distinct
  `complaint_type` values. It is NOT the 40M-row 2010-onwards file people quote; the
  pre-2020 history has been moved to a separate archive dataset. Anything we write
  about "since 2010" would be wrong.
- Queried with `$select=complaint_type,count(1)&$group=complaint_type` (cheap, no row pull).

### Every complaint type plausibly about human waste / sanitary conditions
| complaint_type | agency | total rows (2020–2026) | verdict |
|---|---|---|---|
| **Urinating in Public** | NYPD | 7,926 | **the outcome.** descriptor always `N/A` |
| **Public Toilet** | DOT | 267 | tiny, but see §5 — 100 are *requests for a new toilet* |
| Dirty Condition | DSNY | 278,069 (2021-06→) | complementary, not substitute (§4) |
| Dirty Conditions | DSNY | 68,224 | **retired mid-2021** — do not mix with above |
| Sanitation Condition | DSNY | 62,768 | **retired mid-2021** |
| Homeless Street Condition | NYPD | 15,583 | **retired 2021** (2020: 14,205 → 2021: 1,378). Dead. |
| UNSANITARY CONDITION | HPD | 705,661 | inside apartments (rodents/mould). Irrelevant. |
| Indoor Air Quality / "Human Feces" | DOHMH | 1,086 | inside buildings. Irrelevant. |
| Sewer, Missed Collection, Litter Basket* | DSNY/DEP | — | service delivery, not restroom need |

Searched all descriptors for `COMFORT|TOILET|RESTROOM|BATHROOM|HUMAN|FECES|URIN`.
**FAILED / negative finding:** Parks (DPR) has *no* comfort-station complaint route in 311.
`Maintenance or Facility` descriptors are Structure-Outdoors / Garbage / Grass / Rodent /
Unsecured Facility / Hours of Operation / Structure-Indoors — none names a restroom. So we
cannot measure complaints *about* Parks restrooms from 311. Only DOT's 10 APT kiosks have
a complaint route.

---

## 2. Geography — good, not a blocker

2023–2024 window, per complaint type:

| type | n | lat/lon NULL | incident_zip NULL | community_board NULL | borough bad |
|---|---|---|---|---|---|
| Urinating in Public | 2,125 | 45 (**2.1%**) | 3 (0.1%) | 0 | 2 |
| Public Toilet | 80 | 1 | 0 | 0 | 0 |
| Dirty Condition | 108,775 | 1,007 (**0.93%**) | 165 (0.15%) | 0 | 157 |

`community_board` is 100% populated but includes non-board codes (`28 BRONX`,
`81 QUEENS`, `64 MANHATTAN`, `0 Unspecified` = parks/airports/unmapped).
**Filter to first-two-digits 01–18.** That keeps 7,736 of 7,926 urination rows (97.6%).
Spatial joins on lat/lon are safe — 98% coverage.

---

## 3. Files written to `data_raw/`

Pull script: `Restroom_Rebuild/pull_311.R` (scipen, `$order=:id`, 25k pages, 1.5s sleep,
exponential backoff, on-disk cache — per CONVENTIONS).

| file | rows × cols | filter |
|---|---|---|
| `nyc311_urination_publictoilet_erm2-nwe9_20260920.csv` | 8,193 × 17 | `complaint_type in('Urinating in Public','Public Toilet')`, 2020-01-01 → 2026-09-20 |
| `nyc311_dirtycondition_erm2-nwe9_20260920.csv` | 108,775 × 17 | `complaint_type='Dirty Condition'`, 2023-01-01 → 2024-12-31 |
| `nyc311_totalvolume_by_cb_erm2-nwe9_20260920.csv` | 79 × 2 | all-311 count per CB, 2020–2026 — the reporting-propensity denominator |

Row counts match the server-side `count(1)` exactly and `unique_key` is unique in both
files → paging did not duplicate or drop. Date ranges verified in-file.

Fields: unique_key, created_date, closed_date, agency, complaint_type, descriptor,
location_type, status, latitude, longitude, incident_zip, incident_address, borough,
community_board, council_district, police_precinct, open_data_channel_type.
(I added `location_type`, `incident_address` and `open_data_channel_type` beyond the brief
— all three turn out to be load-bearing, see §5 and §6.)

**I deliberately widened the urination window to the full 2020–2026 rather than the
suggested 2023–24**, because ~1,000/yr is too thin to spend on two years.

---

## 4. Is the volume enough to model? Yes — at community-board level, not below

`location_type` matters. Of 7,926 urination complaints:
Street/Sidewalk 3,881 · Residential Building/House 2,164 · Store/Commercial 588 ·
Park/Playground 581 · Subway Station 244 · Club/Bar/Restaurant 156.

"Residential Building/House" is someone urinating in a lobby or stairwell — a housing
problem, not a public-restroom-access problem. **Defensible public-space subset =
Street/Sidewalk + Park/Playground + Subway Station = 4,546** on valid CBs, 2020–2026.

Then de-duplicate to **one count per address per month** (§6): **3,603 events, 79.3% retained.**

Distribution across the 59 real community boards:
- **all 59 CBs have ≥ 10**; median 46; min 10 (03 Bronx); max 143 (05 Manhattan)
- 52 CBs ≥ 20, 43 CBs ≥ 30 → clean Poisson / negative-binomial territory with a
  population-or-footfall offset. No zero-inflation problem.
- Panel: **400 of 413 CB-year cells non-zero**, median cell = 7. Supports CB fixed effects.

At ZIP level (2023–24 only) it is thinner: 176 ZIPs, median 9, 46 ZIPs with < 5.
Workable but noisy. **At census-tract level it would be mostly zeros — do not go there.**

---

## 5. The second candidate: DSNY "Dirty Condition" — complementary, not better

107,583 rows on valid CBs; median 1,712 per CB (min 497, max 4,245) — enormous power.
But descriptors are Trash 96,323 · Dog Waste 4,770 · Broken Glass 2,117 · Dirt/Gravel 2,056 ·
Syringes 1,462 · Debris 855. **Nothing about human waste.**
Correlation with public-space urination counts across the 59 CBs:
**Pearson 0.168, Spearman 0.329.** Weak. It is measuring DSNY street-cleaning service
levels, not restroom need.

Use: a **control variable** for "this is a dirty, high-footfall, complain-y district",
which is exactly the confounder we need to hold constant. Not the outcome.

**Sleeper asset:** DOT `Public Toilet` / descriptor `New Automatic Public Toilet Request`
= **100 unsolicited requests for a new public toilet**, 2020–2026, geocoded. That is
*revealed demand stated in the citizen's own words*. Too small to regress on, but a superb
face-validity check and a killer slide: do the places that asked for a toilet line up with
the places our model flags?

---

## 6. The reporting-bias problem — honest answer

311 measures **propensity to complain**, not need. Three diagnostics run on the data:

**(a) Is it just total complaint volume?** No. Across the 59 CBs,
`cor(urination count, total 311 volume) = 0.027` raw, `0.201` in logs. Urination complaints
are essentially orthogonal to how much a board calls 311 overall. This is the single best
defence we have, and `nyc311_totalvolume_by_cb_...csv` lets us include log(total 311) as an
explicit control so a professor can see the adjustment.

**(b) Serial complainants — the real problem, and it is severe.**
The **top 1% of addresses generate 22.6% of all public-space urination complaints.**
Worked examples in the raw counts:
- `14 QUEENS` (Rockaways) ranked #2 with 327 — but 286 of those are three adjacent
  addresses on Bayport Place. One site.
- `11 MANHATTAN` (East Harlem) ranked #1 with 384 — 223 of those are five adjacent
  addresses on East 122nd Street. One block.
Raw counts therefore rank *"where one angry neighbour lives next to one nuisance site"*,
not *"where restrooms are missing."*

Fix: collapse to **distinct (address, month)**. Costs 20.7% of rows and the rank
correlation with raw is 0.966 overall — but it demolishes both false hotspots. The
de-duplicated top ten becomes 05/07/04/02/08/01 Manhattan, 04 and 03 Queens, 01 Queens,
02 Brooklyn — i.e. Midtown, Upper West, Chelsea/Clinton, Village, UES, FiDi, Elmhurst,
Jackson Heights, Astoria, Downtown Brooklyn. High-footfall commercial and transit
districts. That is face-valid in a way the raw count is not.
**Always model the de-duplicated series; show the raw one only as a robustness check.**

**(c) Residual bias we can diagnose but not fully fix.**
`cor(CB complaint count, share of complaints filed ONLINE) = 0.597`. Boards that complain
more about urination also file more through the app rather than by phone — an app-using
population skews younger, higher-income, English-speaking. So some of the Manhattan
signal is plausibly *reporting capacity*, not *need*. `open_data_channel_type` is in the
extract, so we can at minimum report this, control for it, or run the model on
phone-only complaints as a sensitivity test. We cannot eliminate it. **Say so out loud in
the deck — do not let the professor find it first.**
The direction of the bias is the dangerous one for our policy conclusion: it pushes
investment toward Manhattan and away from the outer-borough and low-income areas that
may have equal need and lower voice.

---

## 7. Time dimension — yes, a real one

- `created_date` is timestamped to the second, 2020-01-02 → 2026-09-18.
- Strong, face-valid seasonality: Aug 585 / Jun 558 / Sep 525 vs Feb 157 / Jan 205.
  Summer footfall drives it, exactly as a restroom-demand story predicts.
- Annual public-space counts: 2020 536 · 2021 796 · 2022 470 · 2023 520 · 2024 684 ·
  2025 792 · 2026 (partial) 748. The 2022 trough and the recovery are usable variation.
- 400/413 CB-year cells populated → a CB fixed-effects panel is feasible, and a
  difference-in-differences around a facility opening/closing is feasible **provided
  another workstream supplies dated open/close events**. 311 supplies the outcome side of
  a DiD cleanly; it does not supply the treatment dates.

## 8. What failed
- No DPR/Parks comfort-station complaint route exists in 311 (§1).
- `Homeless Street Condition`, `Dirty Conditions`, `Sanitation Condition` all return **0 rows
  for 2023–2024** — they were retired in 2021, not missing. A 2023–24 pull on those names
  would have silently returned nothing.
- Pre-2020 data is not in this dataset at all.
