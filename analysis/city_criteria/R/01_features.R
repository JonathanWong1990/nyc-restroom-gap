# 01_features.R -- measure Local Law 58's "underserved area" factors at every candidate site and at the City's 17 pilot sites.
# LL58 (2025) defines an underserved area as one with insufficient access "because of a lack of public bathrooms or limited
# opening hours ... considering factors such as population density, estimated daily foot traffic, public transportation
# routes, distance to existing public bathrooms ..., land use including current commercial and tourist corridors, and equity
# concerns" (Restroom_Rebuild/data_raw/ll58_2025_text_20260926.pdf). Complaints (Giorgia's "biohazard") are added as an
# extra factor that is NOT in the law, so its role can be tested separately.
# Candidate universe = Build_Plan/prototype candidate sites (Parks land, DOT plazas, busy-street frontage; 5,814 points).
# READ-ONLY inputs. Writes City_Criteria_Model/cache/features.rds and outputs/features_pilot_vs_candidates.csv.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"
D <- file.path(BASE, "Restroom_Rebuild/data_raw"); CM <- file.path(BASE, "City_Criteria_Model")
dir.create(file.path(CM, "cache"), showWarnings = FALSE); dir.create(file.path(CM, "outputs"), showWarnings = FALSE)
FT <- 0.3048006096; M2FT <- function(m) m / FT
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds"))

# ---- sites: candidates + the 17 pilots --------------------------------------------------------------
cand <- P$cand[, c("type", "cand_id")]; cand$pilot <- 0L; cand$name <- NA_character_
pil <- P$pil; parks <- readRDS(file.path(D, "parksprops_sf_20260920.rds")) |> st_transform(2263) |> st_make_valid()
plz <- st_read(file.path(D, "nycdot_k5k6-6jex_plazas_polygon_20260923.geojson"), quiet = TRUE) |> st_transform(2263) |> st_make_valid()
in_plz  <- lengths(st_is_within_distance(pil, plz, dist = M2FT(30))) > 0
in_park <- lengths(st_is_within_distance(pil, parks, dist = M2FT(30))) > 0
pil_sf <- st_sf(type = ifelse(in_plz, "plaza", ifelse(in_park, "park", "busy_street")), cand_id = NA_integer_, pilot = 1L,
                name = pil$published_name, geometry = st_geometry(pil))
sites <- rbind(cand, pil_sf)
cat("pilot site types:\n"); print(table(pil_sf$type))
n <- nrow(sites)

wsum <- function(pts, w, rad_m) { idx <- st_is_within_distance(sites, pts, dist = M2FT(rad_m)); vapply(idx, function(i) sum(w[i]), 0) }
# 1 population density: residents within 500 m
f_res <- wsum(P$demand_pts$residents, P$demand$residents$w, 500)
# 4 land use, commercial: workers (jobs) within 500 m
f_job <- wsum(P$demand_pts$workers, P$demand$workers$w, 500)
# 3 public transportation: subway entries within 500 m
f_sub <- wsum(P$demand_pts$subway, P$demand$subway$w, 500)
# 2 foot traffic: DOT modelled pedestrian demand -- length-weighted category score of street segments within 250 m
seg <- st_read(file.path(BASE, "Pedestrian_Demand_Test/data/dotpedmob_fwpa-qxaf_20260925_dedup.geojson"), quiet = TRUE) |> st_transform(2263)
seg <- seg[!duplicated(st_as_text(st_geometry(seg))), ]
CAT <- c(Baseline = 1, Community = 2, Neighborhood = 3, Regional = 4, Global = 5)
seg$w <- CAT[seg$category] * as.numeric(st_length(seg)) * FT
stopifnot(!anyNA(seg$w))
f_ped <- vapply(st_is_within_distance(sites, seg, dist = M2FT(250)), function(i) sum(seg$w[i]), 0) / 1000
# 4 land use, tourist: hotels within 500 m
ht <- fread(file.path(D, "nyc_tjus-cn27_hotels_20260920.csv"))[!is.na(latitude) & !is.na(longitude)]
ht <- unique(ht, by = "bbl"); hts <- st_transform(st_as_sf(ht, coords = c("longitude", "latitude"), crs = 4326), 2263)
f_hot <- lengths(st_is_within_distance(sites, hts, dist = M2FT(500)))
# 5 distance to existing public bathrooms: nearest listed-operational restroom open at 2pm, and at 9pm (LL58: "limited opening hours")
sup <- P$sup
open_at <- function(h) { cl <- ifelse(sup$placeholder, 16, sup$w_close); sup$operational & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h }
nn_m <- function(ok) { s <- sup[ok, ]; as.numeric(st_distance(sites, s[st_nearest_feature(sites, s), ], by_element = TRUE)) * FT }
f_d14 <- nn_m(open_at(14)); f_d21 <- nn_m(open_at(21))
cat("restrooms open 2pm:", sum(open_at(14)), " 9pm:", sum(open_at(21)), "\n")
# 6 equity: poverty rate of the census tract the site sits in (nearest tract if on a boundary / in water)
tr <- st_read(file.path(D, "nycopendata_63ge-mke6_tracts2020_20260920.geojson"), quiet = TRUE) |> st_transform(2263)
acs <- fread(file.path(D, "census_acs5_2024_tract_demographics_20260920.csv"), colClasses = c(geoid = "character"))
tr <- merge(tr, acs[, .(geoid, poverty_rate, pop_total)], by = "geoid")
tr <- tr[!is.na(tr$poverty_rate) & tr$pop_total > 0, ]
f_pov <- tr$poverty_rate[st_nearest_feature(sites, tr)]
# extra (not in LL58): public-urination 311 complaints within 500 m, 2020-2026
u <- fread(file.path(D, "nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))[complaint_type == "Urinating in Public" & !is.na(latitude)]
us <- st_transform(st_as_sf(u, coords = c("longitude", "latitude"), crs = 4326), 2263)
f_311 <- lengths(st_is_within_distance(sites, us, dist = M2FT(500)))

X <- data.table(site = seq_len(n), pilot = sites$pilot, name = sites$name, type = sites$type,
                residents = f_res, foot_traffic = f_ped, subway = f_sub, jobs = f_job, hotels = f_hot,
                dist_2pm_m = f_d14, dist_9pm_m = f_d21, poverty = f_pov, complaints = f_311)
xy <- st_coordinates(st_transform(sites, 4326)); X[, `:=`(lon = xy[, 1], lat = xy[, 2])]
X$nta2020 <- P$nta$nta2020[st_nearest_feature(sites, P$nta)]; X$ntaname <- P$nta$ntaname[match(X$nta2020, P$nta$nta2020)]
# controls: candidate points within 300 m of a pilot are dropped from the comparison group (they are "the same place")
near_pilot <- lengths(st_is_within_distance(sites, pil, dist = M2FT(300))) > 0
X[, control_ok := pilot == 0 & !near_pilot]
stopifnot(sum(X$pilot) == 17, !anyNA(X[, .(residents, foot_traffic, subway, jobs, hotels, dist_2pm_m, dist_9pm_m, poverty, complaints)]))
saveRDS(list(X = X, sites = sites), file.path(CM, "cache/features.rds"))

# where each pilot sits among the candidates, per factor (percentile; distance percentiles: higher = farther from a restroom)
F <- c("residents", "foot_traffic", "subway", "jobs", "hotels", "dist_2pm_m", "dist_9pm_m", "poverty", "complaints")
ctl <- X[control_ok == TRUE]
pct <- sapply(F, function(f) sapply(X[pilot == 1][[f]], function(v) round(100 * mean(ctl[[f]] <= v))))
out <- cbind(X[pilot == 1, .(name, type, ntaname)], as.data.table(pct))
fwrite(out, file.path(CM, "outputs/features_pilot_percentiles.csv"))
summ <- data.table(factor = F, pilot_median = sapply(F, function(f) median(X[pilot == 1][[f]])),
                   candidate_median = sapply(F, function(f) median(ctl[[f]])),
                   pilot_median_percentile = apply(pct, 2, median))
fwrite(summ, file.path(CM, "outputs/features_pilot_vs_candidates.csv"))
print(summ); cat("controls:", nrow(ctl), "\n")
