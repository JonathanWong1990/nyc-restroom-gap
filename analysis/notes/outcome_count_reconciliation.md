# Reconciliation: how many 311 events? (settled 2026-09-20)

Two workstreams reported different totals (3,603 vs 3,738). Not a data error —
different filters. Verified directly against
`data_raw/nyc311_urination_publictoilet_erm2-nwe9_20260920.csv` (8,193 rows:
7,926 "Urinating in Public" + 267 "Public Toilet").

| Filter | Events |
|---|---|
| Urinating in Public, location_type in {Street/Sidewalk, Park/Playground, Subway Station} | 4,706 |
| ...de-duplicated to one per `incident_address` x year-month | **3,738** |
| ...additionally requiring non-NA latitude/longitude | **3,629** |
| ...additionally dropping pseudo community boards >18 (36 rows: park/airport codes like "64 MANHATTAN", "81 QUEENS") | **3,593** |

311 workstream reported 3,603; residual ~10 rows is a de-dup tie-break difference, immaterial.

**Arithmetic note (corrected 2026-09-20):** the coordinate filter drops **122 rows PRE-dedup**
but only **109 POST-dedup** (3,738 - 109 = 3,629). An earlier version of this note subtracted
122 from 3,738 and did not reconcile. The ladder values are all correct; only the stated
drop-count was.

**Also note:** 3,629 is the citywide figure. The MODELLED total is **3,556** — 3,623 survive
the NTA spatial join and 67 of those land in non-residential NTAs, which are excluded.

## Decision
**Use 3,629** — the coords-required version — because every spatial model needs
lat/lon anyway. Report 3,738 only if a non-spatial CD-level count is ever needed.

## Why the de-dup is non-negotiable
Raw = 7,926. Top 1% of addresses produce 22.6% of complaints. Raw ranking puts
East Harlem #1 (223 of its 384 from five adjacent E 122nd St addresses) and the
Rockaways #2 (286 of 327 from three addresses on Bayport Place). De-duped, the top
ten becomes Midtown / UWS / Chelsea / Village / UES / FiDi / Elmhurst / Jackson
Heights / Astoria / Downtown Brooklyn. Show both — the contrast is a slide.
