# 02_acs_demographics.R ----------------------------------------------------
# ACS 5-year demographics for every NYC census tract (and rolled to NTA).
#
# WHY NOT api.census.gov: as of 2026-09-20 the Census API returns
#   HTTP 302 -> /missing_key.html with header `X-DataWebAPI-KeyError: 1`
# for ANY request without an API key, including small ones. The old
# "no key needed for <500 calls/day" behaviour is gone.
# FALLBACK USED: the keyless table-based Summary File flat files at
#   https://www2.census.gov/programs-surveys/acs/summary_file/<yr>/table-based-SF/
# One pipe-delimited file per table, all US geographies, ~18 MB each.
# --------------------------------------------------------------------------

PROJ <- Sys.getenv("RESTROOM_PROJ", unset = ".")   # run from the project root, or set RESTROOM_PROJ
source(file.path(PROJ, "R", "geo_helpers.R"))
suppressPackageStartupMessages({library(dplyr); library(data.table)})

RAW   <- file.path(PROJ, "data_raw")
CACHE <- file.path(PROJ, "data_cache")
dir.create(CACHE, showWarnings = FALSE)
STAMP <- "20260920"
YEAR  <- 2024           # ACS 2020-2024 5-year estimates
NYC_CO <- c("005","047","061","081","085")   # Bronx Kings NewYork Queens Richmond

acs_table <- function(tbl) {
  fp <- file.path(CACHE, sprintf("acsdt5y%d-%s.dat", YEAR, tolower(tbl)))
  if (!file.exists(fp)) {
    url <- sprintf("https://www2.census.gov/programs-surveys/acs/summary_file/%d/table-based-SF/data/5YRData/acsdt5y%d-%s.dat",
                   YEAR, YEAR, tolower(tbl))
    message("[download] ", tbl)
    ok <- FALSE
    for (a in 1:4) {
      r <- try(httr::GET(url, httr::write_disk(fp, overwrite = TRUE), httr::timeout(600)), silent = TRUE)
      if (!inherits(r, "try-error") && httr::status_code(r) == 200) { ok <- TRUE; break }
      Sys.sleep(2^a)
    }
    if (!ok) stop("ACS download failed: ", tbl)
  } else message("[cache] ", tbl)
  # keep only NYC TRACT rows: GEO_ID summary level 140 + state 36 + NYC county
  pat <- paste0("^1400000US36(", paste(NYC_CO, collapse = "|"), ")")
  d <- fread(fp, sep = "|", colClasses = "character", showProgress = FALSE)
  d <- d[grepl(pat, d$GEO_ID)]
  d[, geoid := substr(GEO_ID, 10, 20)]
  d
}
num <- function(x) { v <- suppressWarnings(as.numeric(x)); v[v <= -555555555] <- NA; v }

# --- pull -----------------------------------------------------------------
pop  <- acs_table("B01003")   # total population
inc  <- acs_table("B19013")   # median household income
pov  <- acs_table("B17001")   # poverty status
age  <- acs_table("B01001")   # sex by age  -> 65+
dis  <- acs_table("B18101")   # sex by age by disability status
hh   <- acs_table("B11001")   # households -- the correct weight for a median HH income

sum_cells <- function(d, tbl, cells) {
  cn <- sprintf("%s_E%03d", tbl, cells)
  miss <- setdiff(cn, names(d)); if (length(miss)) stop("missing ", paste(miss, collapse=","))
  rowSums(sapply(cn, function(k) num(d[[k]])), na.rm = TRUE)
}

demo <- data.frame(
  geoid      = pop$geoid,
  pop_total  = num(pop$B01003_E001),
  pop_moe    = num(pop$B01003_M001),
  stringsAsFactors = FALSE
)
demo$med_hh_income <- num(inc$B19013_E001)[match(demo$geoid, inc$geoid)]
# ACS null sentinels: -666666666 (suppressed), -999999999, -555555555 (no MOE).
# num() maps anything <= -555555555 to NA, so no sentinel survives into a mean.
demo$households <- num(hh$B11001_E001)[match(demo$geoid, hh$geoid)]
stopifnot(all(is.na(demo$med_hh_income) | demo$med_hh_income > 0))

# poverty: 002 = income in past 12 months below poverty level, 001 = universe
demo$pov_universe <- num(pov$B17001_E001)[match(demo$geoid, pov$geoid)]
demo$pov_below    <- num(pov$B17001_E002)[match(demo$geoid, pov$geoid)]
demo$poverty_rate <- ifelse(demo$pov_universe > 0, demo$pov_below / demo$pov_universe, NA)

# age 65+ : male 020-025, female 044-049
a65 <- data.frame(geoid = age$geoid,
                  pop_65plus = sum_cells(age, "B01001", c(20:25, 44:49)))
demo$pop_65plus <- a65$pop_65plus[match(demo$geoid, a65$geoid)]
demo$pct_65plus <- ifelse(demo$pop_total > 0, demo$pop_65plus / demo$pop_total, NA)

# disability: every "With a disability" cell
dis_cells <- c(4,7,10,13,16,19, 23,26,29,32,35,38)
dd <- data.frame(geoid = dis$geoid,
                 dis_universe = num(dis$B18101_E001),
                 pop_disabled = sum_cells(dis, "B18101", dis_cells),
                 pop_disabled_65plus = sum_cells(dis, "B18101", c(16,19,35,38)))
demo <- left_join(demo, dd, by = "geoid")
demo$disability_rate <- ifelse(demo$dis_universe > 0, demo$pop_disabled / demo$dis_universe, NA)

demo$borocode <- c("005"="2","047"="3","061"="1","081"="4","085"="5")[substr(demo$geoid,3,5)]
demo$acs_year <- sprintf("%d-%d 5yr", YEAR-4, YEAR)

# --- sanity ---------------------------------------------------------------
cat("\n=== ACS", YEAR, "5-year, NYC tracts ===\n")
cat("rows:", nrow(demo), " unique geoid:", length(unique(demo$geoid)), "\n")
cat("citywide population:", format(sum(demo$pop_total, na.rm=TRUE), big.mark=","),
    " (NYC ~8.3M expected)\n")
cat("tracts with pop == 0 :", sum(demo$pop_total == 0, na.rm=TRUE), "\n")
cat("tracts with pop < 200:", sum(demo$pop_total < 200, na.rm=TRUE), "\n")
cat("citywide poverty rate:", round(sum(demo$pov_below,na.rm=TRUE)/sum(demo$pov_universe,na.rm=TRUE),4),
    " (NYC ~0.17-0.18 expected)\n")
cat("citywide 65+ share   :", round(sum(demo$pop_65plus,na.rm=TRUE)/sum(demo$pop_total,na.rm=TRUE),4),
    " (NYC ~0.16 expected)\n")
cat("citywide disability  :", round(sum(demo$pop_disabled,na.rm=TRUE)/sum(demo$dis_universe,na.rm=TRUE),4),
    " (NYC ~0.11 expected)\n")
cat("median of tract median HH income:", median(demo$med_hh_income, na.rm=TRUE), "\n")
cat("missing per column:\n"); print(colSums(is.na(demo)))

write.csv(demo, file.path(RAW, sprintf("census_acs5_%d_tract_demographics_%s.csv", YEAR, STAMP)),
          row.names = FALSE)

# --- roll up to NTA (exact: NTAs are unions of whole tracts) ---------------
lut <- read.csv(file.path(RAW, sprintf("lookup_tract_to_nta_%s.csv", STAMP)), colClasses="character")
m <- left_join(demo, lut[, c("geoid","nta2020","ntaname","boroname")], by = "geoid")
cat("\ntracts with no NTA match (water-only tracts absent from the clipped boundary file):",
    sum(is.na(m$nta2020)), "->", m$geoid[is.na(m$nta2020)], "\n")

# NOTE: NTA BX0802 (Kingsbridge-Marble Hill) straddles a county line -- Marble Hill
# is legally New York County but physically attached to the Bronx. Grouping by
# borough would split it into two rows, so we group on nta2020 alone.
#
# BUG FIXED 2026-09-20: the income aggregate was written inside the same
# summarise() that creates `pop_total`, so `pop_total` resolved to the NEW
# scalar sum rather than the tract vector, and the weighted mean collapsed to NA
# for 259 of 262 NTAs. Weights are now computed BEFORE the summarise.
# Weight is HOUSEHOLDS, not people: B19013 is a median over households.
agg_income <- function(d, key) {
  d %>% filter(!is.na(med_hh_income), !is.na(households), households > 0) %>%
    group_by(across(all_of(key))) %>%
    summarise(med_hh_income_hhwtd = round(weighted.mean(med_hh_income, households)),
              inc_tracts_used = n(), .groups = "drop")
}

nta <- m %>% filter(!is.na(nta2020)) %>% group_by(nta2020, ntaname) %>%
  summarise(n_tracts = n(),
            boroname = names(sort(table(boroname), decreasing = TRUE))[1],
            n_boroughs = n_distinct(boroname),
            pop_total = sum(pop_total, na.rm=TRUE),
            households = sum(households, na.rm=TRUE),
            pop_65plus = sum(pop_65plus, na.rm=TRUE),
            pop_disabled = sum(pop_disabled, na.rm=TRUE),
            pov_below = sum(pov_below, na.rm=TRUE),
            pov_universe = sum(pov_universe, na.rm=TRUE),
            dis_universe = sum(dis_universe, na.rm=TRUE),
            .groups="drop") %>%
  left_join(agg_income(m %>% filter(!is.na(nta2020)), "nta2020"), by = "nta2020") %>%
  mutate(poverty_rate    = ifelse(pov_universe > 0, pov_below/pov_universe, NA),
         pct_65plus      = ifelse(pop_total   > 0, pop_65plus/pop_total, NA),
         disability_rate = ifelse(dis_universe> 0, pop_disabled/dis_universe, NA))

cat("\n=== NTA aggregate missingness (of", nrow(nta), "NTAs) ===\n")
for (v in c("med_hh_income_hhwtd","poverty_rate","pct_65plus","disability_rate","pop_total"))
  cat(sprintf("  %-22s NA = %3d\n", v, sum(is.na(nta[[v]]))))
cat("  median of NTA hh-weighted median income:", median(nta$med_hh_income_hhwtd, na.rm=TRUE), "\n")

write.csv(nta, file.path(RAW, sprintf("census_acs5_%d_nta_demographics_%s.csv", YEAR, STAMP)),
          row.names = FALSE)
cat("NTA rollup rows:", nrow(nta), " pop total:", format(sum(nta$pop_total), big.mark=","), "\n")

cat("\nDONE 02_acs_demographics\n")
