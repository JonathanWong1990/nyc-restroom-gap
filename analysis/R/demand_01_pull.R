# demand_01_pull.R -- DEMAND workstream: measures of human presence by area.
# Run: Rscript demand_01_pull.R
source("/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild/R/demand_00_helpers.R")

NY  <- "data.ny.gov"              # MTA / state
NYC <- "data.cityofnewyork.us"    # NYC Open Data

# ---------------------------------------------------------------- 1. SUBWAY
# 1a. Station master list (445 complexes, 496 stops) -- coords + ADA status.
pull_cached(sprintf("mta_39hk-dx4f_stations_%s.csv", STAMP), function()
  soql_page(NY, "39hk-dx4f"))

# 1b. Station x MONTH ridership, Feb 2017 - Jul 2026. Small (48k) -- take it all.
#     Carries latitude/longitude directly in the CSV columns (not JSON-only).
pull_cached(sprintf("mta_ak4z-sape_monthly_%s.csv", STAMP), function()
  soql_page(NY, "ak4z-sape"))

# 1c. Station x HOUR x DAY-OF-WEEK profile --> moved to demand_02_hourprofile.R
#     (needs month-sized windows + hour splitting; see that file for why)

# ------------------------------------------------------- 2. TAXI / RIDESHARE
# Pre-aggregated: zone x month x industry x pickup/dropoff. 138,706 rows
# covering 3.99 BILLION trips, Jan 2019 - Jul 2026. Avoids the raw trip tables.
# NOTE: month granularity only -- there is NO hour-of-day dimension here.
pull_cached(sprintf("tlc_c5iv-bn4s_zonemonth_%s.csv", STAMP), function()
  soql_page(NYC, "c5iv-bn4s"))

# Taxi zone polygons, so TLC counts can be joined to any other geography.
pull_cached(sprintf("nyc_8meu-9t5y_taxizones_%s.csv", STAMP), function()
  soql_page(NYC, "8meu-9t5y"))

# ------------------------------------------------- 3. TOURIST / VISITOR PULL
# 3a. Hotels Properties Citywide -- tax-roll derived, taxyear 2021-2025.
#     Has latitude/longitude AND nta. Best available tourist-presence proxy.
pull_cached(sprintf("nyc_tjus-cn27_hotels_%s.csv", STAMP), function()
  soql_page(NYC, "tjus-cn27"))

# 3b. DCLA Cultural Organizations. Pulled, but see notes/demand.md -- this is
#     mostly small community arts nonprofits, NOT a footfall measure.
pull_cached(sprintf("nyc_u35m-9t32_cultural_%s.csv", STAMP), function()
  soql_page(NYC, "u35m-9t32"))

# ------------------------------------------- 4. EMPLOYMENT / DAYTIME POP
# Census LEHD LODES8 Workplace Area Characteristics, NY, 2023, all jobs (JT00).
# Block-level job counts = where people are on a weekday. Filtered to the 5
# NYC counties (Bronx 005, Kings 047, NY 061, Queens 081, Richmond 085).
local({
  fp <- file.path(RAW, sprintf("census_lodes8_nywac2023_%s.csv", STAMP))
  if (file.exists(fp)) { cat("CACHED: lodes\n"); return(invisible(NULL)) }
  cat("PULLING: LODES8 NY WAC 2023\n")
  gz <- tempfile(fileext = ".csv.gz")
  download.file("https://lehd.ces.census.gov/data/lodes/LODES8/ny/wac/ny_wac_S000_JT00_2023.csv.gz",
                gz, quiet = TRUE)
  d <- read.csv(gzfile(gz), colClasses = c(w_geocode = "character"))
  d$county <- substr(d$w_geocode, 3, 5)
  d <- d[d$county %in% c("005","047","061","081","085"), ]
  d$tract <- substr(d$w_geocode, 1, 11)
  write.csv(d, fp, row.names = FALSE)
  cat("WROTE: lodes", nrow(d), "blocks\n")
})

# ------------------------------------------------- 5. PEDESTRIAN COUNTS
# DOT Bi-Annual Pedestrian Counts. Only 114 screenline locations citywide --
# too sparse to use as a predictor. Pulled as a VALIDATION set only.
pull_cached(sprintf("nyc_cqsj-cfgu_pedcounts_%s.csv", STAMP), function()
  soql_page(NYC, "cqsj-cfgu"))

cat("\n=== DONE ===\n"); print(data.frame(file = list.files(RAW)))
