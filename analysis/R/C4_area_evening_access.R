# C4_area_evening_access.R -----------------------------------------------------
# QUESTION: among our priority areas, where is the EVENING restroom gap worst?
# For each of the six high-confidence NTAs (A6) and all 29 NTAs with ratio >= 1.5:
# the walk to the nearest restroom OPEN at 2pm, 6pm and 9pm (Wednesday), under the
# two C2 hour scenarios, measured from four kinds of origin:
#   stations_in   : subway complexes INSIDE the NTA polygon (entry-weighted mean + median)
#   stations_400  : complexes inside OR within 400 m of the NTA (C3's "near" set)
#   hotspots      : C3 hot-spot centroids (DBSCAN eps 150 m, minPts 5; fallback 4
#                   if none), complaint-weighted mean + complaint-weighted median
#   complaints    : every de-duplicated complaint in the NTA (median + mean), and
#                   the evening/night subset (filed 18:00-05:59)
# plus the number of restrooms in the NTA and how many are open at each hour.
#
# Everything reuses existing definitions -- nothing new is pulled:
#   complaints 3,629 (Z0/C3 recipe) ; NTA rule = 10_modelling_table (residential,
#   snap park-NTA points to nearest residential) ; 424 station complexes (C2) ;
#   975 operational restrooms and open-at-hour logic (C2: parsed hours, placeholder
#   "8am-4pm, Open later seasonally" closes 16:00 off-season / 20:00 in-season;
#   unparseable/blank = closed) ; straight line EPSG:2263, 72 m/min (C2).
# 9pm is identical in both scenarios by construction (placeholder closes by 20:00).
# The audit's scratch figure (walkthrough_claim_audit.md G5: Midtown 8.7 min vs
# 22.3-50.6 elsewhere, median station walk, 9pm) is reproduced/checked in section 6.
# -----------------------------------------------------------------------------
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(jsonlite)})
sf_use_s2(FALSE); select <- dplyr::select

PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
D <- file.path(PROJ, "data_raw"); OUT <- file.path(PROJ, "outputs")
FT <- 0.3048006096; M2FT <- 1 / FT
WALK <- 72; DOW <- 4                      # Wednesday (1 = Sunday, parse_hours.R)
HRS <- c(14, 18, 21); SCEN <- c(off_season = 16, in_season = 20)
PLACEHOLDER <- "8am-4pm, Open later seasonally"
SIX <- c("East Harlem (North)", "Astoria (East)-Woodside (North)", "East Elmhurst",
         "Williamsbridge-Olinville", "Brighton Beach", "Midtown-Times Square")

# ---- 1. Load (C2/C3 recipes) --------------------------------------------------
nta_all <- st_read(file.path(D, "nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet = TRUE) |>
  st_transform(2263) |> st_make_valid()
nta <- nta_all |> filter(ntatype == 0) |> select(nta2020, ntaname, boroname)
sc <- read.csv(file.path(D, "model_nta_scored_20260920.csv"))
hi <- sc |> filter(resid_ratio >= 1.5) |> arrange(desc(resid_ratio)); stopifnot(nrow(hi) == 29, all(SIX %in% hi$ntaname))
to_res <- function(p) { k <- sapply(st_within(p, nta), function(z) if (length(z)) z[1] else NA)
  k[is.na(k)] <- st_nearest_feature(p[is.na(k), ], nta); nta$nta2020[k] }

ev <- read.csv(file.path(D, "nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))
u  <- ev[ev$complaint_type == "Urinating in Public", ]
pu <- u[u$location_type %in% c("Street/Sidewalk", "Park/Playground", "Subway Station"), ]
pu$ym <- substr(pu$created_date, 1, 7)
pc <- pu[is.finite(suppressWarnings(as.numeric(pu$latitude))), ]
cm <- pc[!duplicated(pc[, c("incident_address", "ym")]), ]; stopifnot(nrow(cm) == 3629)
cm$hour <- as.integer(substr(cm$created_date, 12, 13)); cm$evening <- cm$hour >= 18 | cm$hour < 6
cm_sf <- st_as_sf(cm, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |> st_transform(2263)
cm_sf$nta2020 <- to_res(cm_sf)

m <- read.csv(file.path(D, "mta_ak4z-sape_monthly_20260920.csv")); m25 <- m[substr(m$month, 1, 4) == "2025", ]
stopifnot(identical(names(table(table(paste(m25$month, m25$station_complex_id)))), "1"))
st <- m25 |> group_by(station_complex_id) |>
  summarise(station = first(station_complex), nlat = n_distinct(latitude), lat = first(latitude), lon = first(longitude),
            entries = sum(as.numeric(ridership)), .groups = "drop")
stopifnot(all(st$nlat == 1)); st <- st[st$entries >= 1000, ]; stopifnot(nrow(st) == 424)
st_sf <- st_as_sf(st, coords = c("lon", "lat"), crs = 4326, remove = FALSE) |> st_transform(2263)

r <- read.csv(file.path(D, "nycrestrooms_i7jb-7jku_20260920.csv")); r$facility_id <- seq_len(nrow(r))
ph <- read.csv(file.path(D, "parsed_hours_20260920.csv"))
stopifnot(all(ph$facility_name[ph$day_of_week == 1] == r$facility_name))
op <- r[r$status == "Operational" & !is.na(r$latitude), ]; stopifnot(nrow(op) == 975)
ph <- ph[ph$facility_id %in% op$facility_id, ]
ph$placeholder <- ph$facility_id %in% op$facility_id[op$hours_of_operation == PLACEHOLDER]
ph$is24 <- ph$parsed & ph$is_open %in% TRUE & ph$open_hour == 0 & ph$close_hour >= 24
open_ids <- function(h, ph_close, dow = DOW) {                 # identical to C2
  p <- ph[ph$day_of_week == dow & ph$parsed & ph$is_open %in% TRUE, ]
  p$close_hour[p$placeholder] <- ph_close
  if (h < 24) ids <- p$facility_id[p$open_hour <= h & p$close_hour > h] else ids <- p$facility_id[p$close_hour > 24 | p$is24]
  unique(ids)
}
rs_sf <- st_as_sf(op, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |> st_transform(2263)
rs_sf$nta2020 <- to_res(rs_sf)
OPEN <- list(); for (s in names(SCEN)) for (h in HRS) OPEN[[paste(s, h)]] <- open_ids(h, SCEN[[s]])
stopifnot(setequal(OPEN[["off_season 21"]], OPEN[["in_season 21"]]))
cat("restrooms open Wed:", paste(names(OPEN), lengths(OPEN), sep = "=", collapse = "  "), "\n")

# distance (m) from any set of origins to the nearest restroom open under key k
dmat_to <- function(orig) { x <- matrix(as.numeric(st_distance(orig, rs_sf)), nrow = length(st_geometry(orig))) * FT
  colnames(x) <- rs_sf$facility_id; x }
near_open <- function(dm, k) { cols <- colnames(dm) %in% as.character(OPEN[[k]]); apply(dm[, cols, drop = FALSE], 1, min) }
near_any  <- function(dm) apply(dm, 1, min)

# ---- 2. Origins per NTA -------------------------------------------------------
dm_st <- dmat_to(st_sf); dm_cm <- dmat_to(cm_sf)
dbscan_simple <- function(xy, eps, minpts) {                  # identical to C3
  n <- nrow(xy); dm <- as.matrix(dist(xy)); nb <- lapply(seq_len(n), function(i) which(dm[i, ] <= eps))
  core <- lengths(nb) >= minpts; cl <- integer(n); cid <- 0L
  for (i in which(core)) { if (cl[i]) next; cid <- cid + 1L; q <- i; cl[i] <- cid
    while (length(q)) { p <- q[1]; q <- q[-1]
      if (core[p]) for (k in nb[[p]]) if (!cl[k]) { cl[k] <- cid; if (core[k]) q <- c(q, k) } } }
  cl }
wmedian <- function(x, w) { o <- order(x); x <- x[o]; w <- w[o]; x[which(cumsum(w) >= sum(w) / 2)[1]] }

rows <- list(); hs_all <- list(); cnt <- list()
for (k in seq_len(nrow(hi))) {
  id <- hi$nta2020[k]; nm <- hi$ntaname[k]; poly <- nta[nta$nta2020 == id, ]
  s_in  <- which(lengths(st_intersects(st_sf, poly)) > 0)
  s_400 <- which(as.numeric(st_distance(st_sf, poly)) * FT <= 400)
  ci <- which(cm_sf$nta2020 == id)
  # hot spots (C3 definition)
  xy <- st_coordinates(cm_sf[ci, ]) * FT; params <- NA; hs <- NULL
  if (length(ci) >= 4) {
    cl <- dbscan_simple(xy, 150, 5); params <- "eps150_min5"
    if (max(cl) == 0) { cl <- dbscan_simple(xy, 150, 4); params <- "eps150_min4 (fallback)" }
    if (max(cl) > 0) {
      cen <- aggregate(xy[cl > 0, , drop = FALSE] / FT, list(cluster = cl[cl > 0]), mean)
      hs <- st_as_sf(cen, coords = c("X", "Y"), crs = 2263); hs$n <- tabulate(cl[cl > 0])
      hs$ntaname <- nm; hs$nta2020 <- id; hs_all[[id]] <- hs
    } else params <- "none (no cluster at minPts 4)"
  }
  dm_hs <- if (!is.null(hs)) dmat_to(hs) else NULL
  cnt[[id]] <- data.frame(nta2020 = id, ntaname = nm, six = nm %in% SIX, ratio = round(hi$resid_ratio[k], 2),
    complaints = length(ci), evening_complaints = sum(cm_sf$evening[ci]), thin = length(ci) < 30,
    stations_in = length(s_in), stations_400 = length(s_400), hotspots = if (is.null(hs)) 0 else nrow(hs),
    hotspot_complaints = if (is.null(hs)) 0 else sum(hs$n), hotspot_params = params,
    restrooms = sum(rs_sf$nta2020 == id),
    restrooms_open_14 = sum(rs_sf$nta2020 == id & rs_sf$facility_id %in% OPEN[["off_season 14"]]),
    restrooms_open_18_off = sum(rs_sf$nta2020 == id & rs_sf$facility_id %in% OPEN[["off_season 18"]]),
    restrooms_open_18_in = sum(rs_sf$nta2020 == id & rs_sf$facility_id %in% OPEN[["in_season 18"]]),
    restrooms_open_21 = sum(rs_sf$nta2020 == id & rs_sf$facility_id %in% OPEN[["off_season 21"]]))
  for (s in names(SCEN)) for (h in HRS) {
    key <- paste(s, h)
    add <- function(measure, dmx, w, idx = NULL) {
      if (is.null(dmx) || (!is.null(idx) && !length(idx))) {
        rows[[length(rows) + 1]] <<- data.frame(nta2020 = id, ntaname = nm, six = nm %in% SIX, scenario = s, hour = h,
          measure = measure, n_origins = 0, weight_total = 0, median_min = NA, wmean_min = NA, share_over_500m = NA); return(invisible()) }
      d <- near_open(if (is.null(idx)) dmx else dmx[idx, , drop = FALSE], key); ww <- if (is.null(idx)) w else w[idx]
      rows[[length(rows) + 1]] <<- data.frame(nta2020 = id, ntaname = nm, six = nm %in% SIX, scenario = s, hour = h,
        measure = measure, n_origins = length(d), weight_total = sum(ww),
        median_min = if (measure %in% c("stations_in", "stations_400", "complaints", "complaints_evening")) median(d) / WALK else wmedian(d, ww) / WALK,
        wmean_min = weighted.mean(d, ww) / WALK, share_over_500m = weighted.mean(d > 500, ww))
    }
    add("stations_in",  dm_st, st$entries, s_in)
    add("stations_400", dm_st, st$entries, s_400)
    add("hotspots", dm_hs, if (is.null(hs)) NULL else hs$n)
    add("complaints", dm_cm, rep(1, nrow(dm_cm)), ci)
    add("complaints_evening", dm_cm, rep(1, nrow(dm_cm)), ci[cm_sf$evening[ci]])
  }
}
res <- bind_rows(rows) |> mutate(across(c(median_min, wmean_min, share_over_500m), ~round(.x, 2)))
cnt <- bind_rows(cnt)
# "stations" weights are 2025 entries (entry-weighted mean); hotspots weighted by complaints; complaints unweighted
res$weighting <- ifelse(grepl("^stations", res$measure), "2025 entries", ifelse(res$measure == "hotspots", "complaints in hot spot", "none (each complaint = 1)"))

# ---- 3. Check hot spots against C3's saved output (six NTAs) -----------------
c3 <- fromJSON(file.path(OUT, "station_bridge.json"))$test4_hotspots
mine <- bind_rows(lapply(hs_all[sc$nta2020[sc$ntaname %in% SIX]], function(h) data.frame(ntaname = h$ntaname, n = h$n)))
chk <- all(sapply(SIX, function(nm) identical(sort(mine$n[mine$ntaname == nm]), sort(c3$n[c3$ntaname == nm]))))
cat("hot spots identical to C3 (cluster sizes, six NTAs):", chk, "\n"); stopifnot(chk)

# ---- 4. Wide table for the six and the 29 -------------------------------------
wide <- res |> mutate(col = paste0(measure, "_", ifelse(scenario == "off_season", "off", "in"), "_", hour)) |>
  select(nta2020, col, median_min) |> tidyr::pivot_wider(names_from = col, values_from = median_min)
wide_w <- res |> mutate(col = paste0(measure, "_", ifelse(scenario == "off_season", "off", "in"), "_", hour, "_wmean")) |>
  select(nta2020, col, wmean_min) |> tidyr::pivot_wider(names_from = col, values_from = wmean_min)
tab <- cnt |> left_join(wide, by = "nta2020") |> left_join(wide_w, by = "nta2020")
write.csv(res, file.path(OUT, "area_evening_access.csv"), row.names = FALSE)
write.csv(tab, file.path(OUT, "area_evening_access_wide.csv"), row.names = FALSE)

show <- function(meas, s = "off_season") {
  x <- res |> filter(measure == meas, scenario == s) |> select(ntaname, six, hour, median_min, wmean_min, n_origins) |>
    tidyr::pivot_wider(names_from = hour, values_from = c(median_min, wmean_min))
  x <- x[order(-x$median_min_21), ]; x }
cat("\n=== SIX: median walk (min), Wednesday off-season, by origin ===\n")
for (mz in c("stations_in", "stations_400", "hotspots", "complaints", "complaints_evening")) {
  cat("\n--", mz, "--\n"); print(as.data.frame(show(mz) |> filter(six) |> mutate(ntaname = substr(ntaname, 1, 28))), row.names = FALSE) }
cat("\n=== SIX: in-season 6pm (the only hour the scenario changes) ===\n")
print(res |> filter(six, hour == 18) |> select(ntaname, measure, scenario, median_min) |>
        tidyr::pivot_wider(names_from = scenario, values_from = median_min) |> as.data.frame(), row.names = FALSE)
cat("\n=== counts (six) ===\n"); print(cnt |> filter(six) |> select(-nta2020, -six), row.names = FALSE)

# ---- 5. Rank agreement of the measures at 9pm (29 NTAs) -----------------------
r21 <- res |> filter(scenario == "off_season", hour == 21) |> select(ntaname, six, measure, median_min) |>
  tidyr::pivot_wider(names_from = measure, values_from = median_min)
cat("\n=== 29 NTAs, 9pm median walk (min) ===\n")
print(as.data.frame(r21[order(-r21$complaints), ] |> mutate(ntaname = substr(ntaname, 1, 30))), row.names = FALSE)
sp <- function(a, b) { ok <- is.finite(r21[[a]]) & is.finite(r21[[b]]); c(rho = round(cor(r21[[a]][ok], r21[[b]][ok], method = "spearman"), 3), n = sum(ok)) }
agree <- rbind(stations_400_vs_complaints = sp("stations_400", "complaints"), stations_in_vs_complaints = sp("stations_in", "complaints"),
               hotspots_vs_complaints = sp("hotspots", "complaints"), complaints_vs_evening = sp("complaints", "complaints_evening"))
cat("\nSpearman across the 29 (9pm medians):\n"); print(agree)
six21 <- r21 |> filter(six)
rank_six <- lapply(c("stations_in", "stations_400", "hotspots", "complaints", "complaints_evening"), function(mz) {
  v <- six21[[mz]]; o <- order(-v); paste(sprintf("%s %.1f", six21$ntaname[o], v[o]), collapse = " > ") })
names(rank_six) <- c("stations_in", "stations_400", "hotspots", "complaints", "complaints_evening")
cat("\nSix ranked worst -> best at 9pm:\n"); for (n in names(rank_six)) cat(" ", n, ":", rank_six[[n]], "\n")

# ---- 6. Audit reproduction (G5: median station walk, Wed, off-season) ---------
aud <- data.frame(ntaname = c("Midtown-Times Square", "East Harlem (North)", "Brighton Beach", "Williamsbridge-Olinville",
                              "Astoria (East)-Woodside (North)"),
                  a14 = c(4.9, 5.6, 3.3, 4.8, 5.3), a18 = c(4.9, 7.0, 22.3, 12.8, 31.9), a21 = c(8.7, 27.8, 22.3, 30.1, 50.6))
rep_tab <- lapply(c("stations_in", "stations_400"), function(mz) res |> filter(measure == mz, scenario == "off_season", ntaname %in% aud$ntaname) |>
  select(ntaname, hour, median_min) |> tidyr::pivot_wider(names_from = hour, values_from = median_min, names_prefix = paste0(mz, "_")))
rep_tab <- aud |> left_join(rep_tab[[1]], by = "ntaname") |> left_join(rep_tab[[2]], by = "ntaname")
cat("\n=== AUDIT G5 reproduction ===\n"); print(rep_tab, row.names = FALSE)

# ---- 7. JSON -----------------------------------------------------------------
pick <- function(nm, mz, s, h, f = "median_min") res[[f]][res$ntaname == nm & res$measure == mz & res$scenario == s & res$hour == h]
six_tab <- lapply(SIX, function(nm) { cc <- cnt[cnt$ntaname == nm, ]
  list(ntaname = nm, ratio = cc$ratio, complaints = cc$complaints, thin = cc$thin, stations_in = cc$stations_in, stations_400 = cc$stations_400,
       hotspots = cc$hotspots, restrooms = cc$restrooms, restrooms_open_9pm = cc$restrooms_open_21,
       median_walk_min = setNames(lapply(c("stations_in", "stations_400", "hotspots", "complaints", "complaints_evening"), function(mz)
         list(`14_off` = pick(nm, mz, "off_season", 14), `18_off` = pick(nm, mz, "off_season", 18), `18_in` = pick(nm, mz, "in_season", 18),
              `21` = pick(nm, mz, "off_season", 21))), c("stations_in", "stations_400", "hotspots", "complaints", "complaints_evening")),
       weighted_mean_walk_min_21 = setNames(lapply(c("stations_in", "stations_400", "hotspots", "complaints"), function(mz)
         pick(nm, mz, "off_season", 21, "wmean_min")), c("stations_in", "stations_400", "hotspots", "complaints"))) })
js <- list(script = "R/C4_area_evening_access.R", built = as.character(Sys.Date()),
  method = list(day = "Wednesday", hours = HRS, scenarios = list(off_season = "placeholder closes 16:00", in_season = "placeholder closes 20:00"),
    nine_pm_note = "9pm identical in both scenarios (placeholder closes by 20:00)", distance = "straight line EPSG:2263; walk 72 m/min; lower bounds",
    origins = list(stations_in = "complexes inside the NTA polygon; median over stations, mean weighted by 2025 entries",
                   stations_400 = "complexes inside or within 400 m of the NTA (C3 'near')",
                   hotspots = "C3 DBSCAN hot-spot centroids (eps 150 m, minPts 5, fallback 4); median and mean weighted by complaints",
                   complaints = "every de-duplicated complaint assigned to the NTA (C3/Z0 recipe, 10_modelling_table NTA rule)",
                   complaints_evening = "subset filed 18:00-05:59")),
  restrooms_open_wed = lapply(OPEN, length), six = six_tab, six_ranked_worst_first_9pm = rank_six,
  spearman_29_9pm = as.data.frame(agree), audit_G5_reproduction = rep_tab, counts_29 = cnt)
write_json(js, file.path(OUT, "area_evening_access.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
cat("\nWrote outputs/area_evening_access.{csv,json} + area_evening_access_wide.csv\n")
