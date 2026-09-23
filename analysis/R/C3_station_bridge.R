# C3_station_bridge.R ----------------------------------------------------------
# QUESTION: our model picks NEIGHBOURHOODS where complaints exceed what crowds
# predict. A teammate's screen ranks SUBWAY STATIONS by ridership and straight-line
# distance to the nearest listed restroom (score = 60*entry_pct_rank +
# 25*distance_pct_rank + 15*[no restroom within 500 m], reverse-engineered exactly,
# R^2 = 1, from her transit_hub_gap_screen_2025.csv). The site said "our model picks
# the neighbourhood, her screen picks the corner". Never tested. This script tests
# whether the station screen carries information about WHERE complaints occur,
# beyond ridership.
#
# DATA (all from data_raw/, nothing new pulled)
#   Complaints : 311 "Urinating in Public", public-space location types, coords
#                required, then one per incident_address x year-month = 3,629
#                (identical recipe to Z0 key outcome_dedup_coords).
#   NTAs       : 2020 NTAs; residential = ntatype 0 (197). Points outside the
#                residential set snapped to nearest residential NTA (10_modelling_table).
#   Ratio      : model_nta_scored_20260920.csv resid_ratio (29 NTAs >= 1.5).
#   Six        : A6 high-confidence NTAs (posterior P(RR>1.5) > 0.95).
#   Stations   : 424 complexes with 2025 entries >= 1,000 (C2 recipe; ak4z is
#                already one row per complex-month -> no stop->complex trap).
#   Restrooms  : 975 "Operational" rows (C2/teammate definition = "listed").
#                Open-at-hour: parsed hours, Wednesday, placeholder "8am-4pm, Open
#                later seasonally" closes 16:00 (off-season). 9pm result is the same
#                in-season (placeholder closes 20:00 either way).
#   Parks      : parksprops_sf_20260920.rds (all 2,061 properties) -> removed from
#                the null's land.
#   Population : ACS 2020-24 tract pop (tracts nest in NTAs) for weighted null and
#                catchment population.
# DISTANCES: straight line, EPSG:2263 (feet) -> metres.
# -----------------------------------------------------------------------------
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(MASS); library(ggplot2); library(jsonlite)})
sf_use_s2(FALSE)
select <- dplyr::select

PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
D    <- file.path(PROJ, "data_raw"); OUT <- file.path(PROJ, "outputs")
MAPD <- file.path(OUT, "station_bridge_maps"); dir.create(MAPD, showWarnings = FALSE, recursive = TRUE)
FT   <- 0.3048006096          # ft -> m
M2FT <- 1 / FT
set.seed(6093)
SIX <- c("East Harlem (North)", "Astoria (East)-Woodside (North)", "East Elmhurst",
         "Williamsbridge-Olinville", "Brighton Beach", "Midtown-Times Square")
PLACEHOLDER <- "8am-4pm, Open later seasonally"
J <- list(script = "R/C3_station_bridge.R", built = as.character(Sys.Date()))

# ---- 0. Load ----------------------------------------------------------------
nta_all <- st_read(file.path(D, "nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet = TRUE) |>
  st_transform(2263) |> st_make_valid()
nta <- nta_all |> filter(ntatype == 0) |> select(nta2020, ntaname, boroname)
sc  <- read.csv(file.path(D, "model_nta_scored_20260920.csv"))
stopifnot(all(SIX %in% sc$ntaname))
hi  <- sc |> filter(resid_ratio >= 1.5) |> arrange(desc(resid_ratio))
cat("NTAs with ratio >= 1.5:", nrow(hi), "\n")

# complaints (Z0 recipe)
ev <- read.csv(file.path(D, "nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))
u  <- ev[ev$complaint_type == "Urinating in Public", ]
pu <- u[u$location_type %in% c("Street/Sidewalk", "Park/Playground", "Subway Station"), ]
pu$ym <- substr(pu$created_date, 1, 7)
pc <- pu[is.finite(suppressWarnings(as.numeric(pu$latitude))), ]
cm <- pc[!duplicated(pc[, c("incident_address", "ym")]), ]
stopifnot(nrow(cm) == 3629)
cm$hour <- as.integer(substr(cm$created_date, 12, 13))
# top-1% repeat addresses, defined on the RAW urination series (Z0's 22.6% statistic)
ac <- sort(table(u$incident_address[u$incident_address != ""]), decreasing = TRUE)
top1 <- names(ac)[seq_len(ceiling(0.01 * length(ac)))]
cat(sprintf("top-1%% addresses: %d of %d, %.1f%% of raw complaints\n", length(top1), length(ac),
            100 * sum(ac[top1]) / sum(ac)))
cm$top1 <- cm$incident_address %in% top1
cm_sf <- st_as_sf(cm, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |> st_transform(2263)
j <- st_join(cm_sf, nta[, c("nta2020")], join = st_within)
j <- j[!duplicated(j$unique_key), ]
miss <- is.na(j$nta2020)
j$nta2020[miss] <- nta$nta2020[st_nearest_feature(j[miss, ], nta)]
j$snapped <- miss
cm_sf <- j; cat("complaints:", nrow(cm_sf), " snapped to nearest residential NTA:", sum(miss), "\n")

# stations (C2 recipe)
m <- read.csv(file.path(D, "mta_ak4z-sape_monthly_20260920.csv"))
m25 <- m[substr(m$month, 1, 4) == "2025", ]
stopifnot(identical(names(table(table(paste(m25$month, m25$station_complex_id)))), "1"))
st <- m25 |> group_by(station_complex_id) |>
  summarise(station = first(station_complex), borough = first(borough), nlat = n_distinct(latitude),
            lat = first(latitude), lon = first(longitude), entries = sum(as.numeric(ridership)), .groups = "drop")
stopifnot(all(st$nlat == 1))
st <- st[st$entries >= 1000, ]; stopifnot(nrow(st) == 424)
st_sf <- st_as_sf(st, coords = c("lon", "lat"), crs = 4326, remove = FALSE) |> st_transform(2263)

# restrooms + open at 6pm/9pm, Wednesday, off-season
r <- read.csv(file.path(D, "nycrestrooms_i7jb-7jku_20260920.csv")); r$facility_id <- seq_len(nrow(r))
ph <- read.csv(file.path(D, "parsed_hours_20260920.csv"))
stopifnot(all(ph$facility_name[ph$day_of_week == 1] == r$facility_name))
op <- r[r$status == "Operational" & !is.na(r$latitude), ]; stopifnot(nrow(op) == 975)
open_at <- function(h, dow = 4, ph_close = 16) {
  p <- ph[ph$day_of_week == dow & ph$parsed & ph$is_open %in% TRUE & ph$facility_id %in% op$facility_id, ]
  p$close_hour[p$facility_id %in% op$facility_id[op$hours_of_operation == PLACEHOLDER]] <- ph_close
  unique(p$facility_id[p$open_hour <= h & p$close_hour > h])
}
op$open18 <- op$facility_id %in% open_at(18); op$open21 <- op$facility_id %in% open_at(21)
stopifnot(identical(op$open21, op$facility_id %in% open_at(21, ph_close = 20)))  # 9pm season-invariant
cat("restrooms open Wed 6pm (off-season):", sum(op$open18), " 9pm:", sum(op$open21), "\n")
rs_sf <- st_as_sf(op, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |> st_transform(2263)

parks <- readRDS(file.path(D, "parksprops_sf_20260920.rds")) |> st_transform(2263) |> st_make_valid()
parks <- parks[!st_is_empty(parks), ]
parks_u <- st_union(st_buffer(parks, 0))

tr <- st_read(file.path(D, "nycopendata_63ge-mke6_tracts2020_20260920.geojson"), quiet = TRUE) |>
  st_transform(2263) |> st_make_valid() |> select(geoid, nta2020)
acs <- read.csv(file.path(D, "census_acs5_2024_tract_demographics_20260920.csv"), colClasses = c(geoid = "character"))
tr$pop <- acs$pop_total[match(tr$geoid, acs$geoid)]; tr$pop[is.na(tr$pop)] <- 0
cat("tract pop total:", sum(tr$pop), "\n")

# ---- helper distances (metres) -----------------------------------------------
nn_dist <- function(from, to) { i <- st_nearest_feature(from, to)
  list(i = i, d = as.numeric(st_distance(from, to[i, ], by_element = TRUE)) * FT) }
s_near  <- nn_dist(cm_sf, st_sf)
cm_sf$st_i <- s_near$i; cm_sf$d_st <- s_near$d
cm_sf$in_park <- lengths(st_intersects(cm_sf, parks)) > 0
cm_sf$d_rr   <- nn_dist(cm_sf, rs_sf)$d
cm_sf$d_rr21 <- nn_dist(cm_sf, rs_sf[rs_sf$open21, ])$d
st_sf$d_rr   <- nn_dist(st_sf, rs_sf)$d
st_sf$d_rr18 <- nn_dist(st_sf, rs_sf[rs_sf$open18, ])$d
st_sf$d_rr21 <- nn_dist(st_sf, rs_sf[rs_sf$open21, ])$d

# ---- TEST 1. Understand the data, per high-ratio NTA ------------------------
t1 <- lapply(seq_len(nrow(hi)), function(k) {
  id <- hi$nta2020[k]; poly <- nta[nta$nta2020 == id, ]
  land <- st_difference(st_geometry(poly), parks_u)
  x <- cm_sf[cm_sf$nta2020 == id, ]
  st_in  <- lengths(st_intersects(st_sf, poly)) > 0
  st_400 <- as.numeric(st_distance(st_sf, poly)) * FT <= 400
  rr_in  <- lengths(st_intersects(rs_sf, poly)) > 0
  data.frame(nta2020 = id, ntaname = hi$ntaname[k], boro = hi$boroname[k], six = hi$ntaname[k] %in% SIX,
             ratio = round(hi$resid_ratio[k], 2), model_events = hi$events_311[k],
             complaints = nrow(x), distinct_addresses = length(unique(x$incident_address)),
             in_park = sum(x$in_park), subway_loc_type = sum(x$location_type == "Subway Station"),
             top1_addr = sum(x$top1),
             stations_inside = sum(st_in), stations_within_400m = sum(st_400),
             restrooms_inside = sum(rr_in), open_6pm = sum(rr_in & rs_sf$open18), open_9pm = sum(rr_in & rs_sf$open21),
             land_km2 = round(as.numeric(st_area(poly)) * FT^2 / 1e6, 2),
             nonpark_km2 = round(as.numeric(st_area(land)) * FT^2 / 1e6, 2))
}) |> bind_rows()
t1$thin <- t1$complaints < 30
cat("\n=== TEST 1 ===\n"); print(t1[, -1], row.names = FALSE)

# ---- TEST 2. Station proximity vs null ---------------------------------------
# Null U : uniform over the NTA's non-park land.   Null P : tract-population weighted
# (pick tract by pop, uniform within tract's non-park land).  Null U+ : whole NTA incl. parks.
NNULL <- 20000; NBOOT <- 2000
share_near <- function(pts, R) mean(as.numeric(st_distance(pts, st_sf[st_nearest_feature(pts, st_sf), ], by_element = TRUE)) * FT <= R)
sample_in <- function(g, n) { if (n == 0) return(st_sfc(crs = 2263)); s <- st_sample(g, n, exact = TRUE); s }
null_pts <- function(id) {
  poly <- st_geometry(nta[nta$nta2020 == id, ]); land <- st_difference(poly, parks_u)
  U  <- sample_in(land, NNULL); Uall <- sample_in(poly, NNULL)
  tt <- tr[tr$nta2020 == id & tr$pop > 0, ]
  tl <- suppressWarnings(st_difference(st_geometry(tt), parks_u))
  ok <- !st_is_empty(tl); tt <- tt[ok, ]; tl <- tl[ok]
  k  <- as.vector(rmultinom(1, NNULL, tt$pop))
  P  <- do.call(c, lapply(seq_along(k), function(i) sample_in(tl[i], k[i])))
  list(U = U, P = P, Uall = Uall)
}
t2_one <- function(id, x) {
  nl <- null_pts(id); out <- list()
  for (R in c(250, 400)) {
    obs <- mean(x$d_st <= R)
    e <- c(U = share_near(nl$U, R), P = share_near(nl$P, R), Uall = share_near(nl$Uall, R))
    # cluster bootstrap by address (repeat-month events at one address are not independent)
    a <- split(x$d_st <= R, x$incident_address)
    bs <- replicate(NBOOT, { s <- sample(length(a), replace = TRUE); mean(unlist(a[s])) })
    out[[as.character(R)]] <- data.frame(nta2020 = id, radius_m = R, n = nrow(x), obs_share = obs,
      exp_uniform = e[["U"]], exp_popw = e[["P"]], exp_uniform_incl_parks = e[["Uall"]],
      ratio_uniform = obs / e[["U"]], ratio_popw = obs / e[["P"]],
      ratio_popw_lo = quantile(bs, .025) / e[["P"]], ratio_popw_hi = quantile(bs, .975) / e[["P"]],
      ratio_uniform_lo = quantile(bs, .025) / e[["U"]], ratio_uniform_hi = quantile(bs, .975) / e[["U"]],
      p_binom_popw = binom.test(sum(x$d_st <= R), nrow(x), e[["P"]])$p.value,
      obs_share_excl_subwayloc = mean(x$d_st[x$location_type != "Subway Station"] <= R))
  }
  bind_rows(out)
}
t2 <- lapply(hi$nta2020, function(id) t2_one(id, cm_sf[cm_sf$nta2020 == id, ])) |> bind_rows()
t2 <- left_join(t2, t1[, c("nta2020", "ntaname", "six")], by = "nta2020")
# pooled across the 29: complaint-weighted expected share
# NB: weighted means computed BEFORE n is overwritten (summarise evaluates in order)
pool <- t2 |> group_by(radius_m) |> summarise(obs = weighted.mean(obs_share, n),
  exp_popw = weighted.mean(exp_popw, n), exp_uniform = weighted.mean(exp_uniform, n), n = sum(n), .groups = "drop") |> mutate(ratio_popw = obs / exp_popw, ratio_uniform = obs / exp_uniform)
# same pooled test for the other 168 residential NTAs (does the 'near stations' pattern differ?)
rest_ids <- setdiff(sc$nta2020, hi$nta2020)
rest_ids <- rest_ids[rest_ids %in% unique(cm_sf$nta2020)]
cat("\nnull for other NTAs:", length(rest_ids), "\n")
NNULL <- 4000
t2r <- lapply(rest_ids, function(id) { x <- cm_sf[cm_sf$nta2020 == id, ]; nl <- null_pts(id)
  data.frame(nta2020 = id, n = nrow(x), R = c(250, 400),
             obs = c(mean(x$d_st <= 250), mean(x$d_st <= 400)),
             exp_popw = c(share_near(nl$P, 250), share_near(nl$P, 400)),
             exp_uniform = c(share_near(nl$U, 250), share_near(nl$U, 400))) }) |> bind_rows()
pool_rest <- t2r |> group_by(radius_m = R) |> summarise(obs = weighted.mean(obs, n),
  exp_popw = weighted.mean(exp_popw, n), exp_uniform = weighted.mean(exp_uniform, n), n = sum(n), .groups = "drop") |>
  mutate(ratio_popw = obs / exp_popw, ratio_uniform = obs / exp_uniform)
cat("\n=== TEST 2 (six, 400 m) ===\n")
print(t2 |> filter(six) |> transmute(ntaname, R = radius_m, n, obs = round(obs_share, 2), U = round(exp_uniform, 2),
      P = round(exp_popw, 2), ratioP = round(ratio_popw, 2), lo = round(ratio_popw_lo, 2), hi = round(ratio_popw_hi, 2),
      p = signif(p_binom_popw, 2), obs_noSubLoc = round(obs_share_excl_subwayloc, 2)), row.names = FALSE)
cat("pooled 29:\n"); print(pool); cat("pooled other NTAs:\n"); print(pool_rest)

# ---- TEST 3. Citywide station-level test -------------------------------------
land_u <- st_union(st_geometry(nta_all))
vor <- st_voronoi(st_union(st_geometry(st_sf)), envelope = st_as_sfc(st_bbox(st_buffer(st_sf, 20000))))
vor <- st_collection_extract(vor, "POLYGON"); vor <- vor[unlist(st_intersects(st_sf, vor))]  # align order
stopifnot(length(vor) == nrow(st_sf), all(lengths(st_intersects(st_sf, vor, sparse = TRUE)) >= 1))
catch_for <- function(R) {
  b <- st_buffer(st_geometry(st_sf), R * M2FT)
  cs <- do.call(c, lapply(seq_along(b), function(i) st_intersection(st_intersection(b[i], vor[i]), land_u)))
  cs
}
catch_pop <- function(cs) {
  tra <- as.numeric(st_area(tr))
  ix <- st_intersects(cs, tr)
  vapply(seq_along(cs), function(i) { k <- ix[[i]]; if (!length(k)) return(0)
    a <- as.numeric(st_area(st_intersection(st_geometry(tr)[k], cs[i]))); sum(tr$pop[k] * a / tra[k]) }, 0)
}
S <- st_drop_geometry(st_sf) |> select(station_complex_id, station, borough, entries, d_rr, d_rr18, d_rr21)
S$nta2020 <- nta$nta2020[st_nearest_feature(st_sf, nta)]
S$nta_ratio <- sc$resid_ratio[match(S$nta2020, sc$nta2020)]
S$in_hi <- S$nta2020 %in% hi$nta2020; S$in_six <- S$nta2020 %in% sc$nta2020[sc$ntaname %in% SIX]
# teammate score, rebuilt from our data (percent ranks over 424)
S$team_score <- 60 * rank(S$entries) / nrow(S) + 25 * rank(S$d_rr) / nrow(S) + 15 * (S$d_rr > 500)
for (R in c(250, 400, 600)) {
  cs <- catch_for(R)
  S[[paste0("area_km2_", R)]] <- as.numeric(st_area(cs)) * FT^2 / 1e6
  S[[paste0("pop_", R)]] <- catch_pop(cs)
  near <- cm_sf$d_st <= R
  S[[paste0("y_", R)]] <- tabulate(cm_sf$st_i[near], nbins = nrow(S))
  S[[paste0("y_", R, "_no_top1")]] <- tabulate(cm_sf$st_i[near & !cm_sf$top1], nbins = nrow(S))
  S[[paste0("y_", R, "_no_subloc")]] <- tabulate(cm_sf$st_i[near & cm_sf$location_type != "Subway Station"], nbins = nrow(S))
}
S$l_ent <- log(S$entries); S$l_drr <- log2(S$d_rr); S$l_drr21 <- log2(S$d_rr21); S$l_drr18 <- log2(S$d_rr18)
S$far500 <- as.integer(S$d_rr > 500)
cat("\n=== TEST 3 data ===\n")
cat("complaints assigned within 400 m:", sum(S$y_400), "of", nrow(cm_sf), "; stations with 0:", sum(S$y_400 == 0), "\n")
print(summary(S[, c("y_400", "entries", "d_rr", "d_rr21", "area_km2_400", "pop_400")]))
cat("Spearman(entries, d_rr):", round(cor(S$entries, S$d_rr, method = "spearman"), 3),
    " Spearman(pop_400, d_rr):", round(cor(S$pop_400, S$d_rr, method = "spearman"), 3), "\n")

irr <- function(fit, terms) { ct <- coef(summary(fit)); se <- ct[terms, 2]; b <- ct[terms, 1]
  data.frame(term = terms, IRR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = ct[terms, 4]) }
fitnb <- function(f, d) suppressWarnings(glm.nb(f, data = d, control = glm.control(maxit = 100)))
specs <- list(
  A_ridership        = y ~ l_ent + borough,
  B_plus_dist        = y ~ l_ent + l_drr + borough,
  C_plus_dist9pm     = y ~ l_ent + l_drr21 + borough,
  D_ctrl_plus_dist   = y ~ l_ent + log(pop + 100) + log(area) + l_drr + borough,
  E_ctrl_plus_dist9  = y ~ l_ent + log(pop + 100) + log(area) + l_drr21 + borough,
  F_ctrl_far500      = y ~ l_ent + log(pop + 100) + log(area) + far500 + borough,
  G_ctrl_dist_x_hi   = y ~ l_ent + log(pop + 100) + log(area) + l_drr * in_hi + borough,
  H_per_entry        = y ~ offset(l_ent) + log(pop + 100) + log(area) + l_drr + borough,
  I_ctrl_ntaratio    = y ~ l_ent + log(pop + 100) + log(area) + log(nta_ratio + 0.1) + l_drr + borough)
run_models <- function(R, ycol) {
  d <- S; d$y <- d[[ycol]]; d$pop <- d[[paste0("pop_", R)]]; d$area <- d[[paste0("area_km2_", R)]]
  lapply(names(specs), function(nm) { f <- fitnb(specs[[nm]], d)
    tt <- intersect(c("l_ent", "l_drr", "l_drr21", "far500", "log(nta_ratio + 0.1)", "log(pop + 100)", "log(area)", "l_drr:in_hiTRUE", "in_hiTRUE"), rownames(coef(summary(f))))
    cbind(radius_m = R, outcome = ycol, model = nm, AIC = AIC(f), theta = f$theta, irr(f, tt)) }) |> bind_rows()
}
t3 <- bind_rows(lapply(c(250, 400, 600), function(R) run_models(R, paste0("y_", R))),
                run_models(400, "y_400_no_top1"), run_models(400, "y_400_no_subloc"))
rownames(t3) <- NULL
cat("\n=== TEST 3 IRRs (400 m main) ===\n")
print(t3 |> filter(radius_m == 400, outcome == "y_400") |> mutate(across(c(AIC, theta, IRR, lo, hi), ~round(.x, 3)), p = signif(p, 2)), row.names = FALSE)
cat("\nrobustness, distance terms only:\n")
print(t3 |> filter(term %in% c("l_drr", "l_drr21", "far500")) |> transmute(radius_m, outcome, model, term,
      IRR = round(IRR, 3), lo = round(lo, 3), hi = round(hi, 3), p = signif(p, 2)), row.names = FALSE)
# Spearman partial: complaints per entry vs distance
S$rate400 <- S$y_400 / S$entries
cat("Spearman(complaints per entry, d_rr):", round(cor(S$rate400, S$d_rr, method = "spearman"), 3), "\n")

# Out of sample: 200 random 70/30 splits, Spearman(pred, actual) in the test set
oos_f <- list(entries_only_rule = NULL, team_score_rule = NULL,
  A_ridership = y ~ l_ent + borough, B_plus_dist = y ~ l_ent + l_drr + borough,
  C_plus_dist9pm = y ~ l_ent + l_drr21 + borough,
  D_ctrl = y ~ l_ent + log(pop + 100) + log(area) + borough,
  D_ctrl_plus_dist = y ~ l_ent + log(pop + 100) + log(area) + l_drr + borough,
  E_ctrl_plus_dist9 = y ~ l_ent + log(pop + 100) + log(area) + l_drr21 + borough)
d <- S; d$y <- d$y_400; d$pop <- d$pop_400; d$area <- d$area_km2_400
NS <- 200; set.seed(6093)
oos <- sapply(seq_len(NS), function(s) {
  te <- sample(nrow(d), round(.3 * nrow(d))); tr_ <- d[-te, ]; ts <- d[te, ]
  sapply(names(oos_f), function(nm) {
    p <- if (nm == "entries_only_rule") ts$entries else if (nm == "team_score_rule") ts$team_score else
      predict(fitnb(oos_f[[nm]], tr_), ts, type = "response")
    top <- order(-p)[1:20]; truth <- order(-ts$y)[1:20]
    c(rho = cor(p, ts$y, method = "spearman"), top20 = length(intersect(top, truth)))
  })
}, simplify = "array")
oos_rho <- oos["rho", , ]; oos_top <- oos["top20", , ]
oos_sum <- data.frame(ranking = names(oos_f), mean_rho = rowMeans(oos_rho),
  rho_lo = apply(oos_rho, 1, quantile, .025), rho_hi = apply(oos_rho, 1, quantile, .975),
  mean_top20_overlap = rowMeans(oos_top),
  beats_A_share = apply(oos_rho, 1, function(v) mean(v > oos_rho["A_ridership", ])),
  beats_Dctrl_share = apply(oos_rho, 1, function(v) mean(v > oos_rho["D_ctrl", ])))
cat("\n=== TEST 3 out-of-sample (200 splits, 127 test stations each) ===\n")
print(oos_sum |> mutate(across(where(is.numeric), ~round(.x, 3))), row.names = FALSE)
diffB <- oos_rho["B_plus_dist", ] - oos_rho["A_ridership", ]
diffD <- oos_rho["D_ctrl_plus_dist", ] - oos_rho["D_ctrl", ]
diffT <- oos_rho["team_score_rule", ] - oos_rho["entries_only_rule", ]
cat(sprintf("rho gain from distance: B-A mean %.3f [%.3f, %.3f]; Dctrl+dist - Dctrl %.3f [%.3f, %.3f]; team - entries %.3f [%.3f, %.3f]\n",
    mean(diffB), quantile(diffB, .025), quantile(diffB, .975), mean(diffD), quantile(diffD, .025), quantile(diffD, .975),
    mean(diffT), quantile(diffT, .025), quantile(diffT, .975)))
# full-sample rank agreement of the teammate's screen with complaints
full_rho <- c(entries = cor(S$entries, S$y_400, method = "spearman"), team_score = cor(S$team_score, S$y_400, method = "spearman"),
              d_rr = cor(S$d_rr, S$y_400, method = "spearman"), pop_400 = cor(S$pop_400, S$y_400, method = "spearman"))
print(round(full_rho, 3))
# teammate's top-12-by-score and top-50-by-score: how many complaints, vs top-by-entries?
tops <- sapply(c(12, 50), function(k) c(team = sum(S$y_400[order(-S$team_score)[1:k]]), entries = sum(S$y_400[order(-S$entries)[1:k]]),
  oracle = sum(sort(S$y_400, decreasing = TRUE)[1:k])))
colnames(tops) <- c("top12", "top50"); print(tops)

# ---- TEST 4. Within-NTA hot spots (six NTAs) -----------------------------------
dbscan_simple <- function(xy, eps, minpts) {
  n <- nrow(xy); dm <- as.matrix(dist(xy)); nb <- lapply(seq_len(n), function(i) which(dm[i, ] <= eps))
  core <- lengths(nb) >= minpts; cl <- integer(n); cid <- 0L
  for (i in which(core)) { if (cl[i]) next; cid <- cid + 1L; q <- i; cl[i] <- cid
    while (length(q)) { p <- q[1]; q <- q[-1]
      if (core[p]) for (k in nb[[p]]) if (!cl[k]) { cl[k] <- cid; if (core[k]) q <- c(q, k) } } }
  cl }
hot <- list(); sens <- list()
parks_named <- parks[, c("signname", "typecategory")]
for (nm in SIX) {
  id <- sc$nta2020[sc$ntaname == nm]; x <- cm_sf[cm_sf$nta2020 == id, ]; xy <- st_coordinates(x) * FT
  for (eps in c(100, 150, 200)) for (mp in c(4, 5, 8)) {
    cl <- dbscan_simple(xy, eps, mp); inc <- cl > 0
    if (!any(inc)) { sens[[length(sens) + 1]] <- data.frame(ntaname = nm, eps, minpts = mp, n_clusters = 0, share_in_clusters = 0,
       share_of_clustered_station_anchored = NA); next }
    cen <- st_as_sf(as.data.frame(aggregate(xy[inc, ] / FT, list(cl = cl[inc]), mean)), coords = c("X", "Y"), crs = 2263)
    dst <- nn_dist(cen, st_sf)$d; sz <- tabulate(cl[inc])
    sens[[length(sens) + 1]] <- data.frame(ntaname = nm, eps, minpts = mp, n_clusters = max(cl), share_in_clusters = mean(inc),
       share_of_clustered_station_anchored = sum(sz[dst <= 250]) / sum(sz))
  }
  cl <- dbscan_simple(xy, 150, 5); params <- "eps150_min5"
  if (max(cl) == 0) { cl <- dbscan_simple(xy, 150, 4); params <- "eps150_min4 (fallback: none at min5)" }
  x$cluster <- cl
  for (k in seq_len(max(cl))) {
    xk <- x[x$cluster == k, ]; cen <- st_centroid(st_union(xk))
    si <- st_nearest_feature(cen, st_sf); dS <- as.numeric(st_distance(cen, st_sf[si, ])) * FT
    ri <- st_nearest_feature(cen, rs_sf); ri21 <- st_nearest_feature(cen, rs_sf[rs_sf$open21, ])
    pk <- st_nearest_feature(cen, parks_named); dpk <- as.numeric(st_distance(cen, parks_named[pk, ])) * FT
    ll <- st_coordinates(st_transform(cen, 4326))
    hot[[length(hot) + 1]] <- data.frame(ntaname = nm, cluster = k, n = nrow(xk), share_of_nta = nrow(xk) / nrow(x),
      distinct_addr = length(unique(xk$incident_address)), top_addr_share = max(table(xk$incident_address)) / nrow(xk),
      top_addresses = paste(head(names(sort(table(xk$incident_address), decreasing = TRUE)), 3), collapse = " | "),
      params = params,
      lat = ll[2], lon = ll[1],
      nearest_station = st_sf$station[si], station_entries_2025 = st_sf$entries[si], d_station_m = round(dS),
      nearest_restroom = rs_sf$facility_name[ri], d_restroom_m = round(as.numeric(st_distance(cen, rs_sf[ri, ])) * FT),
      nearest_open9pm = rs_sf$facility_name[rs_sf$open21][ri21],
      d_open9pm_m = round(as.numeric(st_distance(cen, rs_sf[rs_sf$open21, ][ri21, ])) * FT),
      station_nearest_restroom_m = round(st_sf$d_rr[si]), station_nearest_open9pm_m = round(st_sf$d_rr21[si]),
      nearest_park = parks_named$signname[pk], d_park_m = round(dpk), share_in_park = mean(xk$in_park),
      share_subway_loctype = mean(xk$location_type == "Subway Station"),
      share_evening_night = mean(xk$hour >= 18 | xk$hour < 6),
      years = paste(range(substr(xk$created_date, 1, 4)), collapse = "-"))
  }
  # map
  poly <- nta[nta$nta2020 == id, ]; bb <- st_bbox(st_buffer(poly, 1000))
  clip <- function(g) suppressWarnings(st_crop(g, bb))
  stp <- clip(st_sf); rsp <- clip(rs_sf); pkp <- clip(parks)
  x$grp <- ifelse(x$cluster > 0, "in hot spot", "other")
  g <- ggplot() + geom_sf(data = pkp, fill = "#cfe8c8", colour = NA) +
    geom_sf(data = poly, fill = NA, colour = "grey30", linewidth = 0.5) +
    geom_sf(data = st_buffer(stp, 250 * M2FT), fill = NA, colour = "#2a78d6", linetype = "22", linewidth = 0.3) +
    geom_sf(data = x, aes(colour = grp), size = 1.1, alpha = 0.8) +
    geom_sf(data = stp, aes(size = entries / 1e6), shape = 22, fill = "#2a78d6", colour = "white") +
    geom_sf(data = rsp, aes(shape = ifelse(open21, "open 9pm", "listed, closed 9pm")), colour = "#7a3e9d", size = 2.2) +
    scale_colour_manual(values = c("in hot spot" = "#d0342c", other = "grey55"), name = "Complaint") +
    scale_shape_manual(values = c("open 9pm" = 17, "listed, closed 9pm" = 2), name = "Restroom") +
    scale_size_continuous(range = c(1.5, 5), name = "Station entries\n2025 (M)") +
    coord_sf(xlim = bb[c(1, 3)], ylim = bb[c(2, 4)], expand = FALSE, datum = NA) +
    labs(title = nm, subtitle = sprintf("%d de-duplicated complaints\nhot spots = DBSCAN %s; dashed ring = 250 m around a station", nrow(x), params)) +
    theme_void(base_size = 9) + theme(plot.background = element_rect(fill = "white", colour = NA), legend.position = "right",
                                      plot.title = element_text(face = "bold"))
  ggsave(file.path(MAPD, paste0("C3_", gsub("[^A-Za-z]+", "_", nm), ".png")), g, width = 6.5, height = 5, dpi = 110)
}
hot <- bind_rows(hot); sens <- bind_rows(sens)
hot$station_anchored <- hot$d_station_m <= 250
cat("\n=== TEST 4 hot spots (eps 150, minPts 5) ===\n")
print(hot |> transmute(ntaname = substr(ntaname, 1, 16), cluster, n, shr = round(share_of_nta, 2), addr = distinct_addr,
      top = substr(top_addresses, 1, 60), station = substr(nearest_station, 1, 22), dS = d_station_m, dR = d_restroom_m,
      d9 = d_open9pm_m, park = substr(nearest_park, 1, 20), dpk = d_park_m, eve = round(share_evening_night, 2), anch = station_anchored), row.names = FALSE)
cat("\nsensitivity:\n"); print(sens |> mutate(across(where(is.numeric), ~round(.x, 2))), row.names = FALSE)

# time of day near vs away from stations
tod <- function(x) { near <- x$d_st <= 250; ev <- x$hour >= 18 | x$hour < 6
  data.frame(n_near = sum(near), n_away = sum(!near), eve_near = mean(ev[near]), eve_away = mean(ev[!near]),
             p = if (sum(near) > 5 && sum(!near) > 5) fisher.test(table(near, ev))$p.value else NA) }
tod_tab <- bind_rows(cbind(scope = "citywide", tod(cm_sf)),
                     cbind(scope = "29 high-ratio", tod(cm_sf[cm_sf$nta2020 %in% hi$nta2020, ])),
                     bind_rows(lapply(SIX, function(nm) cbind(scope = nm, tod(cm_sf[cm_sf$nta2020 == sc$nta2020[sc$ntaname == nm], ])))))
cat("\n=== time of day (share 6pm-6am) ===\n"); print(tod_tab |> mutate(across(c(eve_near, eve_away, p), ~signif(.x, 3))), row.names = FALSE)

# ---- Write ------------------------------------------------------------------
S_out <- S |> select(station_complex_id, station, borough, nta2020, nta_ratio, in_hi, in_six, entries, d_rr, d_rr18, d_rr21,
                     team_score, starts_with("y_"), starts_with("pop_"), starts_with("area_km2_"))
write.csv(S_out, file.path(OUT, "station_bridge.csv"), row.names = FALSE)
J$definitions <- list(complaints = "Urinating in Public, public-space types, coords, 1 per address-month = 3,629",
  stations = "424 complexes, 2025 entries (C2 recipe)", restrooms = "975 Operational; open at 6pm/9pm = Wednesday, placeholder closes 16:00",
  distances = "straight line EPSG:2263", assignment = "each complaint to its nearest complex if within R",
  controls = "catchment = R-buffer ∩ Voronoi cell ∩ land; population by areal interpolation of ACS tracts",
  team_score = "60*entry_pct_rank + 25*distance_pct_rank + 15*[no restroom within 500 m] (reverse-engineered, R^2=1)",
  top1 = sprintf("%d addresses = top 1%% of raw urination addresses", length(top1)))
J$counts <- list(complaints = nrow(cm_sf), snapped = sum(cm_sf$snapped), subway_loc_type = sum(cm_sf$location_type == "Subway Station"),
  in_park = sum(cm_sf$in_park), top1_events = sum(cm_sf$top1), restrooms_open_6pm = sum(op$open18), restrooms_open_9pm = sum(op$open21),
  assigned_within = setNames(lapply(c(250, 400, 600), function(R) sum(cm_sf$d_st <= R)), c("m250", "m400", "m600")))
J$test1 <- t1; J$test2 <- t2; J$test2_pooled_29 <- pool; J$test2_pooled_other <- pool_rest
J$test3_irr <- t3; J$test3_oos <- oos_sum
J$test3_oos_gain <- list(B_minus_A = c(mean = mean(diffB), quantile(diffB, c(.025, .975))),
  Dctrl_dist_minus_Dctrl = c(mean = mean(diffD), quantile(diffD, c(.025, .975))),
  team_minus_entries = c(mean = mean(diffT), quantile(diffT, c(.025, .975))))
J$test3_fullsample_spearman <- as.list(full_rho); J$test3_topk_complaints <- tops
J$test4_hotspots <- hot; J$test4_sensitivity <- sens; J$time_of_day <- tod_tab
write_json(J, file.path(OUT, "station_bridge.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("\nWrote outputs/station_bridge.{csv,json} and", length(list.files(MAPD)), "maps\n")
