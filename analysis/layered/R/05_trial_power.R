# 05_trial_power.R -- detectable effect and cost of the evening-hours trial for the final 13 EXTEND HOURS areas.
# Method as Restroom_Rebuild/R/C1_trial_power.R (adapted from review A's c1_new13.R, 25 Sep): public-urination
# summonses de-duplicated to coordinate-month, 3.5 years of data, 10-month staggered trial with ~half the exposure
# treated, 80% power, 5% two-sided, Poisson log-rate ratio. Simplified: ignores clustering in 13 areas and
# overdispersion, so the true detectable change is larger.
# Cost: $35/staffed hour, 365 days, 10 months. The coverage scenario extends placeholder restrooms from 16:00 to 22:00,
# i.e. SIX extra hours; four-hour figures are shown only for comparison with the earlier costing.
# Run from Build_Plan/layered/:  Rscript R/05_trial_power.R
suppressMessages({library(dplyr); library(sf); library(jsonlite)})
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"
D <- file.path(BASE, "Restroom_Rebuild/data_raw")
f <- read.csv("outputs/diagnosis_29_final.csv")
ext <- f$nta2020[f$final_action == "EXTEND HOURS"]; stopifnot(length(ext) == 13)
nta <- st_read(file.path(D, "nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet = TRUE) |> st_transform(2263)

o <- read.csv(file.path(D, "nypd_oath_urination_hxbk-grd3_20260920.csv"), stringsAsFactors = FALSE)
o$lat <- suppressWarnings(as.numeric(o$latitude)); o$lon <- suppressWarnings(as.numeric(o$longitude))
o <- o[!is.na(o$lat) & !is.na(o$lon), ]
osf <- st_as_sf(o, coords = c("lon", "lat"), crs = 4326, remove = FALSE) |> st_transform(2263) |>
  st_join(nta[, "nta2020"], join = st_within) |> st_drop_geometry()
osf$ym <- substr(osf$occur_date, 1, 7)
sm <- osf |> filter(nta2020 %in% ext) |> distinct(round(lat, 5), round(lon, 5), ym) |> nrow()
z <- qnorm(0.975) + qnorm(0.8)
n_treat <- (sm / 3.5) * 10 / 12 / 2
mde <- exp(z * sqrt(2 / n_treat))

P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); sup <- P$sup[P$sup$operational, ]
j <- st_join(sup, nta[, "nta2020"], join = st_within); x <- j[j$nta2020 %in% ext, ]
n_all <- nrow(x); n_parks <- sum(x$operator == "NYC Parks")
cost <- function(n, h) n * h * 365 * 35 * 10 / 12
out <- list(areas = 13, summonses_dedup = sm, detectable_drop = round(1 - 1 / mde, 3), detectable_rise = round(mde - 1, 3),
            restrooms_all = n_all, restrooms_parks = n_parks,
            cost_10mo_6h_parks = cost(n_parks, 6), cost_10mo_6h_all = cost(n_all, 6),
            cost_10mo_4h_parks = cost(n_parks, 4), cost_10mo_4h_all = cost(n_all, 4))
cat(sprintf("13 Extend areas: %d summonses; detectable drop %.0f%%; restrooms %d (Parks %d)\n", sm, 100 * (1 - 1 / mde), n_all, n_parks))
cat(sprintf("10-month cost, 6 extra hours (4pm->10pm): Parks $%.2fM, all $%.2fM | 4 hours: $%.2fM / $%.2fM\n",
            out$cost_10mo_6h_parks / 1e6, out$cost_10mo_6h_all / 1e6, out$cost_10mo_4h_parks / 1e6, out$cost_10mo_4h_all / 1e6))
write_json(out, "outputs/trial_power_extend13.json", auto_unbox = TRUE, pretty = TRUE)
