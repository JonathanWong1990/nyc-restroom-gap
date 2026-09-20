# Restroom Rebuild — shared conventions

Independent rebuild. Built from the CONCEPT only, not from the teammates'
proposal, data, or verification notes. Do not read
`Restroom Gap and ROI (CHOSEN TOPIC)/` — contamination defeats the purpose.

## The concept (all we inherit)
NYC public restroom access: where is access weakest relative to real demand,
and what is the cheapest intervention that closes the biggest gap?
Audience: NYC Mayor's Office of Operations, Parks, DOT Public Realm, MTA.

## Where things go
- `data_raw/` — every pulled file, named `<source>_<datasetid>_<YYYYMMDD>.csv`
- `notes/` — one markdown per workstream: what was pulled, dataset ID, row count,
  date pulled, schema, missingness, and anything that FAILED. Failures are findings.

## Socrata pull rules (learned the hard way on a previous project)
- `options(scipen = 999)` FIRST or R sends `$offset=1e+05` and Socrata rejects it
- ALWAYS pass `$order=:id` — offset paging without a sort can duplicate/drop rows
- Page in 25k-50k chunks, sleep ~1.5s between pages, retry with backoff
- Cache: if the file exists on disk, read it; don't re-pull
- Endpoint: https://data.cityofnewyork.us/resource/<id>.json  (NYC Open Data)
  MTA/state data lives on https://data.ny.gov/resource/<id>.json instead

## Bound every pull BEFORE you start (learned 2026-09-20, cost ~1 hour)
- State the STOPPING CONDITION in the script, not just the start point. A loop that
  walks forward week-by-week will happily pull a year nobody needed.
- Prefer SERVER-SIDE aggregation (`$select=...sum(x)...&$group=...`) over downloading
  rows. Ask "what table does the model actually consume?" and pull THAT.
- A pull loop inside one long Rscript call CANNOT receive a stop message until the
  call returns. Break long pulls into batches so they stay interruptible.
- Transport: `demand_00_helpers.R` shells out to system `curl`, not `httr::GET` —
  on heavy aggregations httr reported phantom connection failures well inside its own
  timeout, while curl surfaces the real cause (`curl 52 Empty reply` = server's own 60s
  budget). If using `system2()`, `shQuote()` every argument or SoQL parentheses become
  shell syntax errors.

## Join rules (non-negotiable)
- Before aggregating on ANY key, check cardinality: `count(key) |> count(n)`
- Never collapse a many-to-one key with a "most recent wins" tie-break
- Record the join yield AND spot-check that it resolved CORRECTLY, not just that
  it resolved

## Environment
R 4.6.1 at /usr/local/bin/Rscript. Installed: sf (GEOS/GDAL/PROJ ok), httr,
jsonlite, dplyr, tidyverse, data.table, leaflet, sp, terra, s2, units, geojsonsf.
