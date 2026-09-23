> Frozen 21 Sep 2026 — current figures are in outputs/headline_numbers.json and the site.

# START HERE — NYC Restroom project, independent rebuild
**Status date: 2026-09-20.** Read this file completely before touching anything.
You can be productive in ~5 minutes from this file alone.

> **Then open `WORKLOG.md` — it is mandatory, not optional.**
> This file tells you what is TRUE. `WORKLOG.md` tells you what is HAPPENING,
> who is working right now, and what the last sessions did. Claim your work there
> on pickup and log it before you finish. Durable facts you learn belong in BOTH:
> the log is history, this file is the briefing.

---

## 1. What this folder is, and why it exists separately

The group's chosen final-project topic is NYC public restroom access. A proposal
for it already existed, written by teammates, in the sibling folder
`../Restroom Gap and ROI (CHOSEN TOPIC)/`.

**That proposal was reviewed and judged not salvageable as analysis** (detail in
§7). The human's instruction was: keep the *concept*, discard the execution,
rebuild from scratch, and only afterwards decide what of theirs survives —
preparing reasons to communicate back to the team either way.

Every dataset in `data_raw/` here was pulled and verified independently by agents
explicitly instructed NOT to read the teammates' folder. Where our numbers agree
with theirs, that is genuine corroboration, not reuse.

**That embargo has now served its purpose and is lifted for a human-directed
comparison step.** Do not silently import their files into the analysis; if you
compare, say which folder a number came from.

---

## 2. The concept and the decision it serves

Where is NYC's public restroom access weakest relative to real demand, and what
is the cheapest intervention that closes the biggest gap?

**The decision hook (this is the spine of the whole project):**
**Local Law 58 of 2025 legally commits NYC to 2,120 public restrooms by 2035**,
half publicly owned. The baseline today is **973 operational, 8 open 24/7,
49.42% of residents within a 5-minute walk** (NYC Council, Dec 2025).

So the city must site roughly **1,150 new restrooms in ten years and has no
published method for deciding where they go.** We are not arguing the city should
care. We are handing them the allocation rule for a commitment already made.

Audience: NYC Mayor's Office of Operations, NYC Parks, DOT Public Realm, MTA.

**Supporting argument — it is not a money problem, it is a siting problem.**
The Automatic Public Toilet program promised 20 units, installed 5, and left 15 in
a Queens warehouse for over a decade. NYC pays $875K-$5M+ per traditional comfort
station (~$5,000/sq ft) and ranks **93rd of the 100 largest US cities** in comfort
stations per capita (NYC Comptroller audit, "Discomfort Stations").

---

## 3. Status: what is done, what is not

| Workstream | Status | Notes file |
|---|---|---|
| External evidence (costs, law, literature, method precedent) | **Done** | `notes/external_evidence.md` |
| Outcome variable (311) | **Done** | `notes/311_outcome.md` |
| Geography backbone, crosswalks, ACS demographics | **Done** | `notes/geography.md` |
| Supply (restrooms, hours parser, parks, costs, natural experiment) | **Done** | `notes/supply.md` |
| Demand (subway, taxi, hotels, employment, pedestrians) | **Done** (hour-profile pull stopped early on purpose — 15 weeks is enough) | `notes/demand.md` (445 lines) |
| **Modelling** | **NOT STARTED** | — |
| Deck / visuals | **NOT STARTED** | — |

**Nothing has been modelled yet.** Not one regression has been run. Every number
below is descriptive or a data-readiness fact. Do not let the volume of research
here fool you into thinking the analysis exists.

---

## 3b. LATE-BREAKING, 2026-09-20 — read this before trusting §5 below

An adversarial audit (5 agents) and a brainstorm round (3 agents) landed after most of this
file was written. Two things changed materially.

**A SECOND, INDEPENDENT OUTCOME MEASURE NOW EXISTS.**
`data_raw/nypd_oath_urination_hxbk-grd3_20260920.csv` — NYPD OATH summonses,
`law_desc = 'PUBLIC URINATION'`, **27,384 rows, a clean CODED field, 100% geocoded**,
2023-01 to 2026-06. De-duplicated to coordinate-month: **14,534 events across the 197
residential NTAs (median 30)** versus 311's 2,033 (median 6) over the same window —
**7.1x the density**. It is an independent MECHANISM: 311 is a citizen calling, OATH is an
officer writing a summons, so the online-filing bias that broke half the 311 ranking cannot
touch it. Agreement is moderate (Spearman 0.499, top-25 overlap 10/25) — **that is the point**:
two oppositely-biased instruments bracket the truth.
- **NEVER model the raw summons count** — it tracks enforcement (Spearman 0.892 with ALL OATH
  summonses by precinct). Use the share, or control for `log(all OATH summonses)`.
- **A placebo outcome ships with it:** `UNLAWFUL CONSUMPTION/POSSESSION OF ALCOHOLIC BEVERAGES`,
  163,329 rows — same officers, same blocks, not restroom-dependent. This is the answer to
  "your data measures policing, not behaviour."
- **Convergent top-25 (high on BOTH):** Jackson Heights, East Harlem (North), Elmhurst,
  Bedford-Stuyvesant (West), Midtown-Times Square, Hell's Kitchen, Bushwick (West), Corona,
  Jamaica, Chelsea-Hudson Yards. These are STREET/transit/nightlife districts — which may
  resolve the thesis-vs-ranking tension, since the 311-only list was outer-borough residential.

**THE EFFECTIVENESS QUESTION IS NO LONGER HOPELESS.**
- **Winterization triple-difference on the summons outcome: MDE ±9.3%** (~132 seasonal
  restrooms close each winter; 843 year-round facilities are the control). The old 311-based
  DiD could only detect ±20%.
- First run is **wrong-signed and CONFOUNDED, not null**: park acreage x winter is -0.225
  (p=0.002) and conditioning on it collapses the effect to p=0.20. **Winterized restrooms sit
  in parks that empty in winter.** Fix: narrow the catchment to 200-250m around the facility so
  park interior and street are not pooled.
- **Published precedent now exists** (we previously believed it did not): Amato et al.,
  *BMC Public Health* 2022 — SF Pit Stop toilets, 27 sites, 500m buffers, **-12.47 feces
  reports/week** (verified directly). And *PLOS One* 2025 "Privy by the Bay" qualifies it:
  76.1% of citywide hotspots kept worsening, suggesting a **minimum effective density**
  threshold. Use BOTH — the honest claim is "restrooms work where deployed densely enough."
- **Break-even / switching-value analysis** replaces the missing ROI: UK Treasury Green Book
  endorses it exactly when benefits resist quantification. Ask "how many avoided incidents per
  year would justify $1.2M?" rather than inventing a benefit. See `notes/methods_alternatives.md`.

**CASUALTY:** the "10 neighbourhoods just need longer hours" line does NOT survive as an
empirical claim — 641 of 975 facilities carry the `8am-4pm, Open later seasonally` boilerplate
and the 202 with genuine variation give a wrong-signed result. It survives only as a COST
argument.

**See `WORKLOG.md` for the full 32-defect audit list. Several numbers in §5 below are
superseded there.**

## 4. The design decision that is OPEN (do not resolve this alone)

Three routes exist. The human has NOT yet chosen. Present options; do not silently pick.

**Route A — Fit the index.** Keep the teammates' "Relief Gap Index" framing but
estimate its weights by regressing 311 complaints on the components instead of
asserting them. Lowest team friction, weakest analytically.

**Route B — Published accessibility method.** Apply **Gaussian Two-Step Floating
Catchment Area (G2SFCA)** — peer-reviewed, *ISPRS Int. J. Geo-Information* 2025,
applied to public toilets in Kunming, using walking-time thresholds that map
directly onto NYC Council's own 5-minute-walk metric. Citable rather than invented.
Implementable with `sf`.

**Route C — Causal (strongest, and newly available).** The supply workstream found
a real natural experiment. See §5 "PIP". Estimate the *effect* of a restroom on
street conditions via staggered difference-in-differences, then use that effect to
price interventions. This is the only route that produces a causal claim, and
DiD is taught in this course (Sessions 5 and 8).

**Current recommendation:** C as the headline with B as the need-ranking layer, and
A demoted to a communication device if the team insists on a single ranked score.
Routes B and C are complementary, not competing.

**Validation discipline (non-negotiable, the human insists on it):** whatever is
built must beat a one-line benchmark before being recommended — e.g. "rank areas by
subway ridership with no operational restroom within 400m." If the model does not
beat the one-liner, say so.

---

## 5. Key verified numbers (use these; they are checked)

**Outcome variable — 311 "Urinating in Public"**
- Dataset `erm2-nwe9` covers **2020-01-01 to 2026-09-19, 22.5M rows**. NOT the
  "40M rows since 2010" figure that is widely repeated — pre-2020 is a separate archive.
- Working count: **3,629 events** (public-space location types, de-duplicated to one
  per address per month, coordinates required). See `notes/outcome_count_reconciliation.md`
  for the full filter ladder (3,738 / 3,629 / 3,593) — they are all defensible, do not
  "fix" the discrepancy, it is already settled.
- **THE key analytical finding:** the top 1% of addresses produce **22.6%** of complaints.
  Raw ranking puts East Harlem #1 (223 of its 384 from five adjacent E 122nd St addresses)
  and the Rockaways #2 (286 of 327 from three Bayport Place addresses). De-duped, the top
  ten becomes Midtown / UWS / Chelsea / Village / UES / FiDi / Elmhurst / Jackson Heights /
  Astoria / Downtown Brooklyn. **Naive 311 analysis sends the restrooms to the wrong place.**
  Show both rankings — the contrast is the best slide available.
- Known bias to disclose before being asked: complaints correlate **0.597** with share
  filed online (app-using boards over-report → biases investment toward Manhattan).
  `open_data_channel_type` is in the extract, so a phone-only sensitivity test is possible.
  Reassuringly, correlation with *total* 311 volume per board is only **0.027**.

**Unit of analysis — DECIDED**
- **Residential 2020 NTAs, n = 197** (median 10 events, 4 zeros), with
  **negative binomial + `offset(log(pop_total))`**, standard errors **clustered by
  community district**.
- This works because **NTA codes nest exactly inside CDTA** — the first 4 characters of
  an NTA code ARE the CDTA code (verified for all 262). 197 degrees of freedom, the
  inference honesty of 59.
- Community District (n=59, median 45) is the **pre-committed robustness spec** and the
  mapping unit for officials. Census tract (n=2,325, median 1) is unusable.
- Demographics are complete at the 197: income, poverty, 65+, disability all **0 missing**.

**Demand (see `notes/demand.md` for the full ranking)**
- **Strong:** subway monthly ridership `ak4z-sape` (48,255 rows / 426 stations, 2017-02 to
  2026-07, zero missing coordinates) · taxi+FHV `c5iv-bn4s` (138,706 rows summarising
  **3.99 BILLION trips**, 2019-01 to 2026-07) · **workplace jobs, LODES8 WAC 2023**
  (25,445 blocks, **4.59M jobs**) — the underrated one nobody's proposal included.
- **Moderate:** hotels `tjus-cn27` — **the ONLY defensible tourist-presence variable found.**
- **WEAK, do not use as density:** cultural orgs `u35m-9t32`. It is a grants-administration
  roster of small community arts nonprofits — 429 Theater, 403 Music, but only **99 Museum**.
  A 30-seat Bushwick theatre collective and the Met are one row each. If used at all, use only
  the Museum+Botanical+Science subset (**118 orgs**), and note it misses Times Square, the
  High Line, Central Park and the Statue of Liberty ferry entirely.
- **Validation only:** pedestrian counts `cqsj-cfgu` — **114 screenlines citywide** (14 are
  bridges), far too sparse to model. But it is a genuine 19-year series (2007 to May 2026), so
  use it as an **out-of-sample credibility check**: if our modelled demand correlates with
  observed footfall at those 114 points, that is real external validation.

**Supply**
- **843** facilities are operational AND year-round — the real denominator, not the
  headline 1,066 or the Council's 973.
- **Only 9 facilities are 24-hour; only 21 are open at 11pm Saturday.** Median open day
  8.0 hours. (Council independently says 8 open 24/7 — near-exact corroboration.)
- Only **577 of 975** operational restrooms (59%) are Fully Accessible.
- Hours parser `R/parse_hours.R` succeeds on **99.2%** of facilities with non-blank hours;
  101 facilities unparseable (93 blank + 8 genuinely malformed). Flags are preserved, not
  hidden — including 27 facilities where **NYC's own data has AM/PM typos**
  (a library listed "Tuesday: 10:00 pm - 6:00 pm").

**Cost ladder (for the intervention stage)**
- Per-site median **$1,397,000**. New build **$3,793,000**. Reconstruction **$1,152,500**.
- **Component work (roof / HVAC / electrical): $45k-$76k** — the cheap-fix tail, and
  probably where the actionable recommendation lives.
- Costs geolocate to **park level** via `parkid` -> Parks `gispropnum` (202/203 match),
  not merely borough.

**PIP — the natural experiment (Route C's engine)**
- `yg3y-7juh` Park Inspection Program master, **152,484 rows**; 31,768 restroom inspections
  join **100%** on `inspectionid`. Dates facility status **2004-2026**, 961 sites,
  733 with >=8 inspections over >=4 years, **584 sites that switch `closed` status**.
- Pair with **173 capital projects having both a completion date and a cost** for staggered
  treatment timing. Median design-start to completion: **5.25 years**.
- Design: treatment = a restroom closes/reopens at a known date and place; outcome =
  311 complaints within a radius, before vs after; controls = never-treated facilities.

---

## 6. TRAPS — every one of these has already bitten someone

1. **COVID closures `i5n2-q8ck` look like a natural experiment and are NOT.** 381 facilities
   but only **8 distinct close dates, all May-Jun 2020** — simultaneous citywide, no control
   group. Already checked and ruled out. Do not re-litigate.
2. **Retired 311 complaint types return 0 rows SILENTLY.** "Dirty Conditions",
   "Sanitation Condition", "Homeless Street Condition" were retired in 2021. A naive pull
   looks like a clean null result.
3. **DSNY "Dirty Condition" is a control, not an outcome** — 107k rows but descriptors are
   Trash/Dog Waste/Glass/Syringes, **nothing human-waste**.
4. **Capital tracker: 247 rows are only 191 projects.** Bundles repeat the same cost across
   park rows; **summing raw overstates spend ~2.4x**. Dedup on `trackerid`. Also only
   128/191 costs parse to a number — **33% are text bands** ("Between $3 million and $5 million").
5. **Taxi zone shapefile has 263 rows but 260 IDs.** Zone 56 (Corona) is 2 rows, zone 103
   (Governors/Ellis/Liberty) is 3. **Joining raw double- and triple-counts trips.** Dissolve
   on `locationid` first. Drop LocationID 1 (Newark, New Jersey) and 264/265 (no geometry).
6. **Taxi zones nest badly** — only 36% fall in a single NTA (60% for CDs). Use `w_pop`
   (population-weighted), not `w_from`; they disagree >0.10 on the top tract for 120 of 259
   zones. Better: aggregate zones UP to CD rather than disaggregating down.
7. **`api.census.gov` now rejects keyless requests** — every one 302s to `/missing_key.html`.
   Use the bulk Summary Files at www2.census.gov (already done; 2,327 tracts, validates to
   city population 8,483,844).
8. **Parks `enfh-gkve` JSON returns `multipolygon` EMPTY.** Geometry must come from the
   GeoJSON export endpoint. Cached for you as `data_raw/parksprops_sf_20260920.rds`.
9. **MTA data is on `data.ny.gov`, NOT `data.cityofnewyork.us`.**
10. **PIP `prop_id` -> Parks `gispropnum` is many-to-one** (961 sites -> 608 parks) and only
    52% raw; strip the zone suffix (`M010-ZN16`) for 98%. Do not aggregate on it blindly.
11. **The restroom inventory is 15 months stale** — catalog claims 2025-11-05 but
    `rowsUpdatedAt` is **2025-06-27**. Belongs on the limitations slide.
12. **`ifelse()` returns a value shaped like its TEST.** A scalar test silently recycles one
    value across groups. This corrupted population weights once already.
14. **Subway `39hk-dx4f` is 496 stops but only 445 complexes.** Many-to-one — collapse to
    `complex_id` before joining ridership.
15. **Hotels `tjus-cn27` is a 5-YEAR PANEL (2021-2025), not a snapshot.** Filter to one
    `taxyear` or hotel counts inflate ~5x. Within a year, `RH` rows are condo units — count
    distinct `bin`/`bbl`.
16. **`c5iv-bn4s` is on data.cityofnewyork.us, NOT data.ny.gov** (404s there). The reverse of
    the MTA rule in #9 — the two hosts are easy to mix up.
17. **SoQL: you cannot `$group` by an alias** (HTTP 400 `column-not-in-group-bys`) — repeat the
    full expression. And `sum(x) AS x` shadows the source column; rename the aggregate.
18. **Join rule, learned expensively on an abandoned earlier project:** always check key
    cardinality with `count(key) |> count(n)` BEFORE aggregating, and never collapse a
    many-to-one key with a "most recent wins" tie-break. Doing exactly that manufactured a
    false headline finding in the archived tree-hazard project.

---

## 7. What was wrong with the teammates' proposal (so you don't rebuild it)

`../Restroom Gap and ROI (CHOSEN TOPIC)/NYC_Public_Restroom_Gap_ROI_Proposal.pdf`

- **The engine is arithmetic, not analytics.** `RGI = 100 x [0.35*Demand + 0.30*SupplyGap
  + ...]` estimates nothing — no coefficient, no standard error, no prediction, no
  counterfactual. Uses none of the course's taught methods.
- **The weights die to one question:** "move Demand from 0.35 to 0.30 — does your top-10
  change?" Note the nesting: subway ridership silently carries 0.35 x 0.35 = 12.25%.
- **`SROI = NPV / CapEx` breaks mechanically** — extending hours has CapEx ~ 0, so SROI ->
  infinity and the decision matrix recommends "extend hours" everywhere regardless of data.
- **"Annual Access Value"**, the load-bearing benefit term, is never defined and no NYC
  dataset provides it. (External research confirms: **no rigorous US cost-benefit or WTP
  study for public toilets exists**. Build the benefit side as *cost avoidance* instead.)
- **Supply is mismeasured where the project aims** — `i7jb-7jku` lists *public* restrooms
  only, so Midtown (Starbucks, hotel lobbies, department stores) is scored a "restroom
  desert". First objection any NYC official raises.
- **Timing:** its 8-slide plan runs **14:00 against a 12:00 limit**.
- **The promised `restroom_roi_analysis_template.R` does not exist** anywhere on disk.

**Worth KEEPING from their work (say so when reporting back):** the two-stage discipline
(never compute ROI outside the Stage-1 shortlist) and the decision-maker -> decision
mapping. Both are genuinely good executive framing.

---

## 8. Course constraints (these are graded)

- **12 minutes presentation + 3 minutes Q&A.** Groups of 6~8. No slide count specified.
- Own topic is explicitly allowed: *"propose your own question that is relevant, interesting
  and important based on the provided datasets or ones you find on Kaggle.com (as long as it
  is sourced from NYC)."* Source: `../Guidelines for the Final Presentation.pdf` — note the
  OLDER `Project_data_part_1/Project_Outline.pdf` says "Airbnb datasets" and 5~7 members;
  **the newer file governs.**
- Graded on **clarity, depth, intuition, practicality** (syllabus).
- Instructor's own slide: *"Everyone is using LLM, so up your game!"* — a hand-weighted
  composite index is precisely the baseline output being warned against.
- **Presentation order is first-come:** email the group list to lily959@hku.hk, cc
  weimingz@hku.hk. **No evidence this has been done.** Free positioning, currently unclaimed.

---

## 9. File map

```
Restroom_Rebuild/
├── 00_START_HERE.md      <- this file (what is TRUE)
├── WORKLOG.md             <- shared ledger (what is HAPPENING) — READ + WRITE EVERY SESSION
├── CONVENTIONS.md         <- Socrata pull rules, join rules, environment
├── notes/
│   ├── external_evidence.md   308 lines, every claim has URL + access date,
│   │                          and a "thin ice" section flagging 6 unverified numbers
│   ├── 311_outcome.md         complaint-type census, missingness, bias diagnostics
│   ├── geography.md           unit choice, crosswalk quality, ACS method
│   ├── supply.md              inventory, hours parser audit, cost distribution, PIP
│   └── outcome_count_reconciliation.md
├── R/
│   ├── geo_helpers.R      socrata_get (paged, cached, $order=:id), socrata_geojson,
│   │                      load_geo, points_to_area, areal_crosswalk  <- SOURCE THIS
│   ├── parse_hours.R      free-text hours -> facility x day x open/close
│   ├── pull_supply.R      01_geography.R  02_acs_demographics.R
│   ├── 03_community_boards_and_outcome_test.R
│   └── demand_00_helpers.R  demand_01_pull.R
└── data_raw/              ~34 files, named <source>_<datasetid>_<YYYYMMDD>.csv
                           Key: nta_analysis_base_*.csv and cd_analysis_base_*.csv are
                           the joined modelling tables. Start there.
```

**Environment:** R 4.6.1 at `/usr/local/bin/Rscript`. `sf` works (GEOS/GDAL/PROJ ok).
Also installed: httr, jsonlite, tidyverse, data.table, leaflet, sp, terra, s2, geojsonsf.
Use **EPSG:4326** for storage, **EPSG:2263** for area/distance.

---

## 10. Immediate next steps, in order

0. **Read `WORKLOG.md`** — CURRENT STATE plus the last 3 entries. Claim your work there.
1. **Read `notes/demand.md`** if the demand workstream has landed; if `data_raw/` has no
   subway/employment files, that lane never finished and needs re-running.
2. **Get the human's decision on §4** (Route A / B / C). Do not pick alone.
3. **Build the modelling table** at residential NTA (n=197) from `nta_analysis_base_*.csv`
   plus demand measures.
4. **Run the one-liner benchmark FIRST**, before any model, so there is something to beat.
5. **Then** the chosen route's model.
6. Sensitivity + the phone-only 311 bias check.
7. Visuals, then deck to 12:00.

**Before you stop:** append to `WORKLOG.md` §LOG, rewrite §CURRENT STATE, clear your
claim, and promote any durable new fact into this file. A session that does the work
but skips the ledger has cost the next session everything it learned.

**Standing habit that made this work defensible:** state caveats before being asked, and
record failures as findings. Several agents' most valuable output was what did NOT work.
