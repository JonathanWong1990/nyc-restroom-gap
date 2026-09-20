# 03_community_boards_and_outcome_test.R -----------------------------------
# Added after the 311 workstream reported the outcome is sparse.
# Does three things:
#   A. pulls Community District + CDTA boundaries
#   B. counts the de-duped 311 "Urinating in Public" events per NTA / CD / tract
#      so the unit of analysis is chosen on the OUTCOME, not on geometry alone
#   C. builds every crosswalk + the per-capita denominators at CD and NTA level
# --------------------------------------------------------------------------

PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
source(file.path(PROJ, "R", "geo_helpers.R"))
suppressPackageStartupMessages({library(dplyr)})
RAW <- file.path(PROJ, "data_raw"); f <- function(x) file.path(RAW, x)
STAMP <- "20260920"

# ===== A. boundaries ======================================================
cds   <- socrata_geojson("5crt-au7u", f(sprintf("nycopendata_5crt-au7u_communitydistricts_%s.geojson", STAMP)))
cdtas <- socrata_geojson("xn3r-zk6y", f(sprintf("nycopendata_xn3r-zk6y_cdta2020_%s.geojson", STAMP)))
tracts <- load_geo(f(sprintf("nycopendata_63ge-mke6_tracts2020_%s.geojson", STAMP)))
ntas   <- load_geo(f(sprintf("nycopendata_9nt8-h7nd_nta2020_%s.geojson", STAMP)))
tz_raw <- load_geo(f(sprintf("nycopendata_8meu-9t5y_taxizones_%s.geojson", STAMP)))
tz_raw$locationid <- as.integer(tz_raw$locationid)
tzones <- tz_raw %>% group_by(locationid, zone, borough) %>%
  summarise(geometry = st_union(geometry), .groups = "drop") %>% st_make_valid()

# boro_cd = borough digit + 2-digit CD. 01-18 are real boards; 64/80-84/95 etc.
# are "joint interest areas" (parks, airports, cemeteries) with no board.
cds$boro_cd  <- sprintf("%03d", as.integer(cds$boro_cd))
cds$cd_num   <- as.integer(substr(cds$boro_cd, 2, 3))
cds$borocode <- as.integer(substr(cds$boro_cd, 1, 1))
cds$boroname <- c("Manhattan","Bronx","Brooklyn","Queens","Staten Island")[cds$borocode]
cds$cb_label <- sprintf("%02d %s", cds$cd_num, toupper(cds$boroname))
cat("\n=== community districts ===\n")
cat("rows:", nrow(cds), " real boards (cd 01-18):", sum(cds$cd_num <= 18),
    " joint interest areas:", sum(cds$cd_num > 18), "\n")
cds_real <- cds %>% filter(cd_num <= 18)
cat("CDTA rows:", nrow(cdtas), " CRS:", st_crs(cds)$epsg, "/", st_crs(cdtas)$epsg, "\n")

# ===== B. THE DECISION: outcome density per candidate unit ================
cat("\n=== 311 outcome density by candidate unit ===\n")
ev <- read.csv(f(sprintf("nyc311_urination_publictoilet_erm2-nwe9_%s.csv", STAMP)),
               colClasses = "character")
cat("events in file:", nrow(ev), "\n")
ev$latitude <- as.numeric(ev$latitude); ev$longitude <- as.numeric(ev$longitude)
cat("with usable coords:", sum(is.finite(ev$latitude) & is.finite(ev$longitude)),
    sprintf(" (%.1f%%)\n", 100*mean(is.finite(ev$latitude))))

# Reproduce the 311 workstream's outcome definition: "Urinating in Public",
# public-space location types, one count per address per month.
# Their headline is 3,603; this recipe gives 3,738 (+3.7%) -- the residual is an
# unknown de-dup detail on their side. Reported, not hidden.
PUBLIC_LOC <- c("Street/Sidewalk", "Park/Playground", "Subway Station")
ev$ym <- substr(ev$created_date, 1, 7)
ev_dd <- ev %>% filter(complaint_type == "Urinating in Public",
                       location_type %in% PUBLIC_LOC) %>%
  distinct(incident_address, ym, .keep_all = TRUE)
cat("de-duped public-space urination events:", nrow(ev_dd),
    "(coordinator reported 3,603)\n")

ev <- points_to_area(ev, ntas,    area_id = "nta2020")
ev <- points_to_area(ev, tracts,  area_id = "geoid")
ev <- points_to_area(ev, cds_real, area_id = c("boro_cd","cb_label"))

# --- correctness spot-check: spatial CD vs 311's own community_board text --
chk <- ev %>% filter(!is.na(cb_label), nzchar(community_board),
                     !grepl("Unspecified|0 Unspecified", community_board))
cat("\nspot-check spatial CD vs 311 community_board field:",
    sprintf("%d of %d agree (%.2f%%)\n", sum(chk$cb_label == chk$community_board),
            nrow(chk), 100*mean(chk$cb_label == chk$community_board)))
print(head(chk %>% filter(cb_label != community_board) %>%
             count(community_board, cb_label, sort = TRUE), 5))

dens <- function(key, universe_n, label, d = ev) {
  tab <- table(d[[key]])
  cnt <- c(as.integer(tab), rep(0L, max(0, universe_n - length(tab))))
  cat(sprintf("%-16s units=%4d  total=%5d  median=%6.1f  mean=%6.1f  zeros=%4d  <5 ev=%4d  <10 ev=%4d  max=%d\n",
              label, length(cnt), sum(cnt), median(cnt), mean(cnt),
              sum(cnt == 0), sum(cnt < 5), sum(cnt < 10), max(cnt)))
  invisible(cnt)
}
cat("\n")
c_cd  <- dens("boro_cd", nrow(cds_real), "Community Dist")
c_nta <- dens("nta2020", nrow(ntas),     "NTA 2020")
c_ct  <- dens("geoid",   nrow(tracts),   "Census tract")

# NTAs are not all residential; type 0 = residential, 5 = park/airport/cemetery, 9 = rikers
nta_res <- ntas %>% filter(ntatype == "0")
cnt_res <- table(ev$nta2020[ev$nta2020 %in% nta_res$nta2020])
cnt_res <- c(as.integer(cnt_res), rep(0L, nrow(nta_res) - length(cnt_res)))
cat(sprintf("%-16s units=%4d  total=%5d  median=%6.1f  mean=%6.1f  zeros=%4d  <5 ev=%4d  <10 ev=%4d  max=%d\n",
            "NTA (resid only)", length(cnt_res), sum(cnt_res), median(cnt_res), mean(cnt_res),
            sum(cnt_res == 0), sum(cnt_res < 5), sum(cnt_res < 10), max(cnt_res)))

# ---- THE DECIDING TABLE: same thing on the DE-DUPED outcome --------------
# ev_dd was built before the spatial tags, so re-tag it by unique_key
key_map <- ev[, c("unique_key","nta2020","geoid","boro_cd","cb_label")]
ev_dd <- left_join(ev_dd[, setdiff(names(ev_dd), c("nta2020","geoid","boro_cd","cb_label"))],
                   key_map, by = "unique_key")
cat("\n--- DE-DUPED public-space outcome (n =", nrow(ev_dd), ") ---\n")
dens("boro_cd", nrow(cds_real), "Community Dist", ev_dd)
dens("nta2020", nrow(ntas),     "NTA 2020",       ev_dd)
dens("geoid",   nrow(tracts),   "Census tract",   ev_dd)
cnt_rd <- table(ev_dd$nta2020[ev_dd$nta2020 %in% nta_res$nta2020])
cnt_rd <- c(as.integer(cnt_rd), rep(0L, nrow(nta_res) - length(cnt_rd)))
cat(sprintf("%-16s units=%4d  total=%5d  median=%6.1f  mean=%6.1f  zeros=%4d  <5 ev=%4d  <10 ev=%4d  max=%d\n",
            "NTA (resid only)", length(cnt_rd), sum(cnt_rd), median(cnt_rd), mean(cnt_rd),
            sum(cnt_rd == 0), sum(cnt_rd < 5), sum(cnt_rd < 10), max(cnt_rd)))
ev_dd$yr <- substr(ev_dd$created_date, 1, 4)
for (k in c("boro_cd","nta2020")) {
  u <- if (k == "boro_cd") nrow(cds_real) else nrow(ntas)
  t <- ev_dd %>% filter(!is.na(.data[[k]])) %>% count(.data[[k]], yr)
  cat(sprintf("  [dedup] %s x year: %d non-zero of %d cells (%.0f%%)\n",
              k, nrow(t), u*length(unique(ev_dd$yr)), 100*nrow(t)/(u*length(unique(ev_dd$yr)))))
}
t <- ev_dd %>% filter(nta2020 %in% nta_res$nta2020) %>% count(nta2020, yr)
cat(sprintf("  [dedup] residential NTA x year: %d non-zero of %d cells (%.0f%%)\n",
            nrow(t), nrow(nta_res)*length(unique(ev_dd$yr)),
            100*nrow(t)/(nrow(nta_res)*length(unique(ev_dd$yr)))))

# panel viability: unit x year non-zero cells
ev$yr <- substr(ev$created_date, 1, 4)
pan <- function(key, u) {
  t <- ev %>% filter(!is.na(.data[[key]]), !is.na(yr)) %>% count(.data[[key]], yr)
  cells <- u * length(unique(ev$yr[!is.na(ev$yr)]))
  cat(sprintf("  %s x year: %d non-zero of %d cells (%.0f%%)\n",
              key, nrow(t), cells, 100*nrow(t)/cells))
}
cat("\npanel density:\n"); pan("boro_cd", nrow(cds_real)); pan("nta2020", nrow(ntas))

# ===== C. crosswalks + denominators =======================================
cat("\n=== crosswalks ===\n")
# tract -> CDTA is EXACT (CDTAs are unions of whole 2020 tracts) - use attributes
lut <- read.csv(f(sprintf("lookup_tract_to_nta_%s.csv", STAMP)), colClasses = "character")
cat("tract->CDTA exact via attribute, distinct CDTAs:", length(unique(lut$cdta2020)), "\n")

# NTA -> CDTA is also exact (NTA code prefix = CDTA code)
ntas$cdta_from_prefix <- substr(ntas$nta2020, 1, 4)
cat("NTA->CDTA prefix matches cdta2020 field:", all(ntas$cdta_from_prefix == ntas$cdta2020), "\n")

# real Community District polygons do NOT align to tracts -> areal weights
xw_ct_cd  <- areal_crosswalk(tracts,   cds_real, "geoid",      "boro_cd")
xw_nta_cd <- areal_crosswalk(ntas,     cds_real, "nta2020",    "boro_cd")
xw_tz_cd  <- areal_crosswalk(tzones,   cds_real, "locationid", "boro_cd")
tidy <- function(x, id) x %>% filter(w_from > 0.005) %>% group_by(.data[[id]]) %>%
  mutate(w_from = w_from/sum(w_from)) %>% ungroup()
xw_ct_cd  <- tidy(xw_ct_cd, "geoid")
xw_nta_cd <- tidy(xw_nta_cd,"nta2020")
xw_tz_cd  <- tidy(xw_tz_cd, "locationid")

q <- function(x, id, lab) {
  s <- x %>% group_by(.data[[id]]) %>% summarise(n = n(), mx = max(w_from), .groups="drop")
  cat(sprintf("%-22s %4d units | exactly one CD: %4d (%.0f%%) | biggest CD >=95%%: %4d (%.0f%%) | median max-w %.3f\n",
              lab, nrow(s), sum(s$n==1), 100*mean(s$n==1),
              sum(s$mx>=.95), 100*mean(s$mx>=.95), median(s$mx)))
}
q(xw_ct_cd, "geoid", "tract -> CD");  q(xw_nta_cd,"nta2020","NTA -> CD")
q(xw_tz_cd, "locationid", "taxi zone -> CD")

write.csv(xw_ct_cd[,c("geoid","boro_cd","w_from")],      f(sprintf("crosswalk_tract_to_cd_%s.csv", STAMP)), row.names=FALSE)
write.csv(xw_nta_cd[,c("nta2020","boro_cd","w_from")],   f(sprintf("crosswalk_nta_to_cd_%s.csv", STAMP)), row.names=FALSE)
write.csv(xw_tz_cd[,c("locationid","boro_cd","w_from")], f(sprintf("crosswalk_taxizone_to_cd_%s.csv", STAMP)), row.names=FALSE)

# --- population-weighted taxi-zone crosswalks -----------------------------
# Area weights assume trips are spread evenly over a zone's acreage. They are
# not: they track people. Re-weight the zone->tract shares by tract population.
demo <- read.csv(f(sprintf("census_acs5_2024_tract_demographics_%s.csv", STAMP)), colClasses=c(geoid="character"))
xw_tz_ct <- read.csv(f(sprintf("crosswalk_taxizone_to_tract_%s.csv", STAMP)), colClasses=c(geoid="character"))
xw_tz_ct$pop <- demo$pop_total[match(xw_tz_ct$geoid, demo$geoid)]
xw_tz_ct <- xw_tz_ct %>% group_by(locationid) %>%
  # NOTE: ifelse() returns a value shaped like its TEST, so a scalar test here
  # would recycle one number across the whole group. Use if/else.
  mutate(pop_in_piece = w_from * ifelse(is.na(pop), 0, pop),
         w_pop = if (sum(pop_in_piece) > 0) pop_in_piece/sum(pop_in_piece) else w_from) %>%
  ungroup()
stopifnot(max(abs(tapply(xw_tz_ct$w_pop, xw_tz_ct$locationid, sum) - 1)) < 1e-8)
cat("\nzones where area-weight and pop-weight disagree by >0.10 on the top tract:",
    xw_tz_ct %>% group_by(locationid) %>%
      summarise(d = max(abs(w_from - w_pop)), .groups="drop") %>% filter(d > .10) %>% nrow(), "\n")
write.csv(xw_tz_ct[,c("locationid","geoid","w_from","w_pop")],
          f(sprintf("crosswalk_taxizone_to_tract_%s.csv", STAMP)), row.names=FALSE)

# --- CD-level denominators (the per-capita base) --------------------------
# NB: same scoping trap as in 02 -- the income weight is built BEFORE summarise(),
# never inside it, or `pop_total` resolves to the new scalar sum.
cd_src <- xw_ct_cd %>% left_join(demo, by = "geoid")
cd_inc <- cd_src %>%
  filter(!is.na(med_hh_income), !is.na(households), households > 0) %>%
  mutate(wt = w_from * households) %>%
  group_by(boro_cd) %>%
  summarise(med_hh_income_hhwtd = round(weighted.mean(med_hh_income, wt)),
            inc_tracts_used = n(), .groups = "drop")
cd_pop <- cd_src %>%
  group_by(boro_cd) %>%
  summarise(pop_total    = sum(w_from * pop_total,    na.rm=TRUE),
            households   = sum(w_from * households,   na.rm=TRUE),
            pop_65plus   = sum(w_from * pop_65plus,   na.rm=TRUE),
            pop_disabled = sum(w_from * pop_disabled, na.rm=TRUE),
            pov_below    = sum(w_from * pov_below,    na.rm=TRUE),
            pov_universe = sum(w_from * pov_universe, na.rm=TRUE),
            dis_universe = sum(w_from * dis_universe, na.rm=TRUE),
            .groups="drop") %>%
  left_join(cd_inc, by = "boro_cd") %>%
  mutate(poverty_rate = pov_below/pov_universe,
         pct_65plus   = pop_65plus/pop_total,
         disability_rate = pop_disabled/dis_universe) %>%
  left_join(st_drop_geometry(cds_real)[,c("boro_cd","cb_label","boroname","cd_num")], by="boro_cd")
cd_pop$land_sqmi <- as.numeric(st_area(st_transform(cds_real, NYC_CRS_FEET)))[match(cd_pop$boro_cd, cds_real$boro_cd)]/27878400
cd_pop$pop_density <- cd_pop$pop_total/cd_pop$land_sqmi
cnt0 <- function(tb, ids) { v <- as.integer(tb[ids]); v[is.na(v)] <- 0L; v }
cd_pop$events_311_raw <- cnt0(table(ev$boro_cd),    cd_pop$boro_cd)   # all 8,193 rows
cd_pop$events_311     <- cnt0(table(ev_dd$boro_cd), cd_pop$boro_cd)   # de-duped public-space
cd_pop$events_per_100k <- 1e5*cd_pop$events_311/cd_pop$pop_total

cat("\n=== CD denominators ===\n")
cat("rows:", nrow(cd_pop), " citywide pop:", format(round(sum(cd_pop$pop_total)), big.mark=","),
    " (vs tract total", format(sum(demo$pop_total, na.rm=TRUE), big.mark=","), ")\n")
cat("pop per CD: min", round(min(cd_pop$pop_total)), " median", round(median(cd_pop$pop_total)),
    " max", round(max(cd_pop$pop_total)), "\n")
cat("events per 100k: min", round(min(cd_pop$events_per_100k),1),
    " median", round(median(cd_pop$events_per_100k),1),
    " max", round(max(cd_pop$events_per_100k),1), "\n")
cat("CD missingness:\n")
for (v in c("med_hh_income_hhwtd","poverty_rate","pct_65plus","disability_rate","pop_total"))
  cat(sprintf("  %-22s NA = %d\n", v, sum(is.na(cd_pop[[v]]))))
cat("  income range:", min(cd_pop$med_hh_income_hhwtd,na.rm=TRUE), "-",
    max(cd_pop$med_hh_income_hhwtd,na.rm=TRUE), " median", median(cd_pop$med_hh_income_hhwtd,na.rm=TRUE), "\n")
write.csv(cd_pop, f(sprintf("cd_analysis_base_%s.csv", STAMP)), row.names=FALSE)

# events + pop at NTA too, so the finer unit stays available
nta_dem <- read.csv(f(sprintf("census_acs5_2024_nta_demographics_%s.csv", STAMP)), colClasses=c(nta2020="character"))
nta_dem$events_311_raw <- cnt0(table(ev$nta2020),    nta_dem$nta2020)
nta_dem$events_311     <- cnt0(table(ev_dd$nta2020), nta_dem$nta2020)
nta_dem$events_per_100k <- ifelse(nta_dem$pop_total > 0, 1e5*nta_dem$events_311/nta_dem$pop_total, NA)
nta_dem$ntatype <- ntas$ntatype[match(nta_dem$nta2020, ntas$nta2020)]
nta_dem$cdta2020 <- substr(nta_dem$nta2020, 1, 4)
nta_dem$is_residential <- nta_dem$ntatype == "0"
cat("\n=== NTA base: missingness, all 262 vs 197 residential ===\n")
for (v in c("med_hh_income_hhwtd","poverty_rate","pct_65plus","disability_rate")) {
  cat(sprintf("  %-22s NA all=%3d  NA residential-only=%3d\n", v,
              sum(is.na(nta_dem[[v]])), sum(is.na(nta_dem[[v]][nta_dem$is_residential]))))
}
cat("  residential NTAs:", sum(nta_dem$is_residential),
    " non-residential:", sum(!nta_dem$is_residential),
    " pop in non-residential:", format(round(sum(nta_dem$pop_total[!nta_dem$is_residential])), big.mark=","), "\n")
write.csv(nta_dem, f(sprintf("nta_analysis_base_%s.csv", STAMP)), row.names=FALSE)

# tract-level event counts, for anyone who wants them
tr <- data.frame(geoid = tracts$geoid)
tr$events_311_raw <- cnt0(table(ev$geoid),    tr$geoid)
tr$events_311     <- cnt0(table(ev_dd$geoid), tr$geoid)
write.csv(tr, f(sprintf("tract_events311_%s.csv", STAMP)), row.names=FALSE)

cat("\nDONE 03\n")
