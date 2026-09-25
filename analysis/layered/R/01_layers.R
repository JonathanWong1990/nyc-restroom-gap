# 01_layers.R -- LAYERED DIAGNOSIS of NYC's high-complaint neighbourhoods.
#   Layer 1 (problem): complaint model residual ratio (observed / expected 311 complaints).
#   Layer 2 (missing): residents with NO listed-operational restroom within 500 m even at 2pm Wednesday.
#   Layer 3 (closed) : residents covered at 2pm but not at 9pm; share recoverable if placeholder park hours -> 22:00.
#   Layer 4 (broken) : Parks restrooms serving the NTA that are PIP long-term closed / repeatedly failing;
#                      coverage lost at 2pm if they are removed; 2026 Jan-Jun PIP failure rate.
# Reuses Build_Plan/prototype/cache/prep.rds and the prototype's open-at-hour rule (02_greedy.R) unchanged.
# READ-ONLY inputs: Build_Plan/prototype/cache, Restroom_Rebuild/data_raw, Restroom_Rebuild/outputs.
# Writes only Build_Plan/layered/{cache,outputs}.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(data.table); library(jsonlite); library(MASS)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"
D    <- file.path(BASE, "Restroom_Rebuild/data_raw")
LY   <- file.path(BASE, "Build_Plan/layered"); OUT <- file.path(LY, "outputs")
FT   <- 0.3048006096; M2FT <- function(m) m / FT
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds"))
sup <- P$sup; cand <- P$cand; nta <- P$nta
nres <- nta[nta$ntatype == "0", ]
stopifnot(nrow(nres) == 197, nrow(sup) == 1071, sum(sup$operational) == 975)
t0 <- Sys.time()

# ---- Layer 1: complaint model + empirical-Bayes confidence --------------------------------------
sc <- fread(file.path(D, "model_nta_scored_20260920.csv"))
stopifnot(nrow(sc) == 197, !anyDuplicated(sc$nta2020), all(sc$nta2020 %in% nres$nta2020))
top29 <- sc[resid_ratio >= 1.5]$nta2020
stopifnot(length(top29) == 29)
# A6_empirical_bayes.R, replicated exactly (same data, same formula): P(true RR > 1.5 | y)
d6 <- read.csv(file.path(D, "model_with_commercial_20260920.csv")) |> filter(!is.na(inc10k), !is.na(pov), pop_total > 0)
F6 <- events_311 ~ l_sub + l_jobs + l_hotel + l_rest + l_dens + inc10k + pov + old + boro + offset(log(pop_total))
m6 <- glm.nb(F6, data = d6)
d6$p_gt_15 <- 1 - pgamma(1.5, shape = m6$theta + d6$events_311, rate = m6$theta + fitted(m6))
stopifnot(!anyDuplicated(d6$nta2020))
SIX <- c("East Harlem (North)", "Astoria (East)-Woodside (North)", "East Elmhurst",
         "Williamsbridge-Olinville", "Brighton Beach", "Midtown-Times Square")
six_eb <- d6$ntaname[d6$p_gt_15 > 0.95]
cat("EB P>0.95 recomputed (A6):", paste(sort(six_eb), collapse = "; "), "\n")
stopifnot(setequal(six_eb, SIX))                         # recomputation reproduces the named six
sc <- merge(sc, as.data.table(d6)[, .(nta2020, eb_p_gt_1_5 = p_gt_15)], by = "nta2020", all.x = TRUE)
stopifnot(nrow(sc) == 197)
sc[, confident_six := ntaname %in% SIX]
stopifnot(sum(sc$confident_six) == 6, all(sc[confident_six == TRUE]$nta2020 %in% top29))

# ---- assign every demand point to a 2020 NTA (spatial; boundary ties -> first; misses -> nearest) --
assign_nta <- function(pts) {
  j <- st_intersects(pts, nta)
  a <- nta$nta2020[vapply(j, function(x) if (length(x)) x[1] else NA_integer_, 1L)]
  if (anyNA(a)) a[is.na(a)] <- nta$nta2020[st_nearest_feature(pts[is.na(a)], nta)]
  a
}
dn <- lapply(P$demand_pts, function(p) assign_nta(st_sf(geometry = p)))
stopifnot(identical(dn$residents, dn$workers))
W <- lapply(P$demand, `[[`, "w")
for (o in names(W)) stopifnot(length(W[[o]]) == length(dn[[o]]))
res_in_nonres <- sum(W$residents[!dn$residents %in% nres$nta2020])
cat(sprintf("residents on points in non-residential NTAs (parks/airports etc., excluded from per-NTA shares): %.0f of %.0f (%.2f%%)\n",
            res_in_nonres, sum(W$residents), 100 * res_in_nonres / sum(W$residents)))

# ---- open-at-hour rule: copied verbatim from Build_Plan/prototype/R/02_greedy.R -------------------
open_vec <- function(h, ph_close, set = "base", restore_closed = FALSE, fix_fail = FALSE, extend = FALSE) {
  cl <- ifelse(sup$placeholder, if (extend) 22 else ph_close, sup$w_close)
  op <- sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h
  inset <- sup$operational
  if (set == "strict") inset <- inset & !sup$removed_closed & !sup$removed_fail
  if (restore_closed) inset <- inset | sup$removed_closed | sup$reopen_add
  if (fix_fail) inset <- inset | sup$removed_fail
  op & inset
}
cov_existing <- function(o, rad, ov) vapply(P$inc[[paste0(o, "_", rad)]]$supply, function(x) any(ov[x]), TRUE)
OV <- list(b14 = open_vec(14, 16), s14 = open_vec(14, 16, "strict"),
           b21 = open_vec(21, 16), e21 = open_vec(21, 16, extend = TRUE))
cat("open restrooms: 2pm", sum(OV$b14), "| 2pm strict", sum(OV$s14), "| 9pm", sum(OV$b21), "| 9pm extended", sum(OV$e21), "\n")

# share of NTA demand in `mask` (weighted), per residential NTA
nta_share <- function(o, mask) {
  x <- data.table(nta = dn[[o]], w = W[[o]], m = mask)[nta %in% nres$nta2020]
  a <- x[, .(tot = sum(w), val = sum(w * m)), by = nta]
  a[, share := ifelse(tot > 0, val / tot, NA_real_)]
  a[match(nres$nta2020, a$nta), share]
}
nta_tot <- function(o) { x <- data.table(nta = dn[[o]], w = W[[o]])[, .(t = sum(w)), by = nta]
  v <- x$t[match(nres$nta2020, x$nta)]; v[is.na(v)] <- 0; v }

L <- data.table(nta2020 = nres$nta2020, residents = nta_tot("residents"),
                street_m = nta_tot("streets"), subway_entries = nta_tot("subway"))
layer23 <- function(rad, suffix) {
  out <- list()
  for (o in c("residents", "streets", "subway")) {
    c14 <- cov_existing(o, rad, OV$b14); c21 <- cov_existing(o, rad, OV$b21); e21 <- cov_existing(o, rad, OV$e21)
    out[[paste0("L2_", o, suffix)]] <- nta_share(o, !c14)
    if (o == "residents") {
      gap <- c14 & !c21
      out[[paste0("L3_", o, suffix)]]       <- nta_share(o, gap)
      out[[paste0("L3_ext_recov", suffix)]] <- nta_share(o, gap & e21)
      out[[paste0("cov21_not14", suffix)]]  <- nta_share(o, c21 & !c14)
    }
  }
  as.data.table(out)
}
L <- cbind(L, layer23(500, ""), layer23(400, "_400m"))
L[, L3_ext_recov_frac := ifelse(L3_residents > 0, L3_ext_recov / L3_residents, NA_real_)]
L[, L3_ext_recov_frac_400m := ifelse(L3_residents_400m > 0, L3_ext_recov_400m / L3_residents_400m, NA_real_)]
cat("max share covered at 9pm but not 2pm (should be ~0):", max(L$cov21_not14, na.rm = TRUE), "\n")

# ---- Layer 4: broken Parks restrooms --------------------------------------------------------------
# a restroom "serves" an NTA if it is within 500 m of any populated resident point in the NTA, or inside it
s2d <- st_is_within_distance(sup, P$demand_pts$residents, dist = M2FT(500))      # supply -> resident pts
inside <- st_intersects(sup, nres)
parks <- sup$operator == "NYC Parks"
sup$ltc    <- sup$removed_closed | sup$reopen_add           # PIP long-term closed (listed Operational or not)
sup$broken <- sup$ltc | sup$removed_fail
serve <- rbindlist(lapply(which(parks), function(j) {
  pts <- s2d[[j]]; pts <- pts[W$residents[pts] > 0]
  n1 <- unique(dn$residents[pts]); n2 <- nres$nta2020[inside[[j]]]
  nn <- intersect(unique(c(n1, n2)), nres$nta2020)
  if (!length(nn)) return(NULL)
  # share of each NTA's residents within 500 m of this restroom
  sh <- vapply(nn, function(k) sum(W$residents[pts][dn$residents[pts] == k]) / L$residents[L$nta2020 == k], 0)
  data.table(facility_id = sup$facility_id[j], nta2020 = nn, res_share_served = sh)
}))
stopifnot(!anyDuplicated(serve[, .(facility_id, nta2020)]))
serve <- merge(serve, as.data.table(st_drop_geometry(sup))[, .(facility_id, facility_name, status, operational,
               removed_closed, reopen_add, removed_fail, ltc, broken)], by = "facility_id")
l4 <- serve[, .(parks_restrooms_serving = .N,
                n_long_term_closed = sum(ltc),
                n_ltc_listed_operational = sum(removed_closed),
                n_repeatedly_failing = sum(removed_fail),
                max_res_share_one_broken = if (any(broken)) max(res_share_served[broken]) else 0,
                broken_names = paste(sprintf("%s [%s, %.0f%%]", facility_name[broken],
                                             ifelse(ltc[broken], "long-term closed", "failing"),
                                             100 * res_share_served[broken]), collapse = "; ")), by = nta2020]
L <- merge(L, l4, by = "nta2020", all.x = TRUE)
for (v in c("parks_restrooms_serving", "n_long_term_closed", "n_ltc_listed_operational", "n_repeatedly_failing",
            "max_res_share_one_broken")) L[is.na(get(v)), (v) := 0]
L[is.na(broken_names), broken_names := ""]
s14 <- cov_existing("residents", 500, OV$s14)
L$L2_residents_strict <- nta_share("residents", !s14)[match(L$nta2020, nres$nta2020)]
L[, L4_lost_pp := 100 * (L2_residents_strict - L2_residents)]
stopifnot(all(L$L4_lost_pp >= -1e-9))
# gain if long-term-closed restrooms reopened on top of base supply (incl. ones the register already lists closed)
r14 <- cov_existing("residents", 500, open_vec(14, 16, restore_closed = TRUE))
L$L4_reopen_gain_pp <- 100 * (L$L2_residents - nta_share("residents", !r14)[match(L$nta2020, nres$nta2020)])

# PIP 2026 Jan-Jun comfort-station failure rate (A/U only), properties serving the NTA (same 500 m / inside rule)
ins <- fread(file.path(D, "pipInspections_mp8v-wjtf_20260920.csv"), showProgress = FALSE)
mas <- fread(file.path(D, "pipInspectionsMaster_yg3y-7juh_20260920.csv"), select = c("prop_id", "inspection_id", "date"),
             showProgress = FALSE)
stopifnot(!anyDuplicated(mas$inspection_id))
ins[, cs_overall_condition := toupper(trimws(cs_overall_condition))]
ii <- merge(ins, mas, by.x = "inspectionid", by.y = "inspection_id")
stopifnot(nrow(ii) == nrow(ins))                                 # every station inspection has one master row
ii[, date := as.IDate(date)]
cat("PIP data end:", format(max(ii$date)), "\n")
p26 <- ii[year(date) == 2026 & as.integer(format(date, "%j")) <= 179 & cs_overall_condition %in% c("A", "U"),
          .(n_rated = .N, n_u = sum(cs_overall_condition == "U")), by = prop_id]
al <- fread(file.path(D, "pipAllSites_buk3-3qpr_20260920.csv"), showProgress = FALSE,
            select = c("prop_id", "multipolygon.coordinates"))
al <- al[prop_id %in% p26$prop_id & !is.na(multipolygon.coordinates) & nzchar(multipolygon.coordinates) & !duplicated(prop_id)]
geo <- lapply(al$multipolygon.coordinates, function(s) { x <- fromJSON(s, simplifyVector = FALSE)
  tryCatch(st_multipolygon(lapply(x, function(p) lapply(p, function(rg) do.call(rbind, lapply(rg, function(pt) c(pt[[1]], pt[[2]])))))),
           error = function(e) NULL) })
ok <- !vapply(geo, is.null, TRUE)
pp <- st_transform(st_make_valid(st_sf(prop_id = al$prop_id[ok], geometry = st_sfc(geo[ok], crs = 4326))), 2263)
cat(sprintf("PIP 2026 H1: %d props with rated station inspections (%d inspections); with polygon: %d (%d inspections)\n",
            nrow(p26), sum(p26$n_rated), nrow(pp), sum(p26[prop_id %in% pp$prop_id]$n_rated)))
pos <- which(W$residents > 0)
hp <- st_is_within_distance(pp, P$demand_pts$residents[pos], dist = M2FT(500))
hi <- st_intersects(pp, nres)
pn <- rbindlist(lapply(seq_len(nrow(pp)), function(k) {
  nn <- intersect(unique(c(dn$residents[pos][hp[[k]]], nres$nta2020[hi[[k]]])), nres$nta2020)
  if (length(nn)) data.table(prop_id = pp$prop_id[k], nta2020 = nn) }))
stopifnot(!anyDuplicated(pn))
pn <- merge(pn, p26, by = "prop_id")
pr <- pn[, .(pip26_props = .N, pip26_n_rated = sum(n_rated), pip26_fail_rate = sum(n_u) / sum(n_rated)), by = nta2020]
L <- merge(L, pr, by = "nta2020", all.x = TRUE)
L[is.na(pip26_props), `:=`(pip26_props = 0L, pip26_n_rated = 0L)]
cat(sprintf("citywide PIP 2026 H1 station fail rate: %.3f (n=%d)\n", sum(p26$n_u) / sum(p26$n_rated), sum(p26$n_rated)))

# ---- join Layer 1 + diagnosis ---------------------------------------------------------------------
L <- merge(sc[, .(nta2020, ntaname, boroname, events_311, pred, resid_ratio, eb_p_gt_1_5, confident_six)], L, by = "nta2020")
stopifnot(nrow(L) == 197, !anyDuplicated(L$nta2020))
L[, in_29 := nta2020 %in% top29]

diagnose <- function(x, t23 = 0.40, t4pp = 10, t4sh = 0.10, sfx = "") {
  l2 <- x[[paste0("L2_residents", sfx)]]; l3 <- x[[paste0("L3_residents", sfx)]]; rf <- x[[paste0("L3_ext_recov_frac", sfx)]]
  b <- l2 >= t23
  f <- x$L4_lost_pp >= t4pp | x$max_res_share_one_broken >= t4sh
  e <- l3 >= t23 & !is.na(rf) & rf >= 0.5
  prim <- ifelse(b, "BUILD", ifelse(f, "FIX", ifelse(e, "EXTEND HOURS", "VERIFY")))
  data.table(flag_build = b, flag_fix = f, flag_extend = e, primary_action = prim,
             flags = mapply(function(b, f, e) { s <- c("BUILD", "FIX", "EXTEND HOURS")[c(b, f, e)]
               if (length(s)) paste(s, collapse = "+") else "VERIFY" }, b, f, e))
}
L <- cbind(L, diagnose(L))
setorder(L, -resid_ratio)

# ---- sensitivity ---------------------------------------------------------------------------------
base29 <- L[in_29 == TRUE]
scen <- CJ(t23 = c(0.30, 0.40, 0.50), t4 = c(5, 10, 15)); scen[, t4sh := t4 / 100]
scen <- rbind(scen[, radius_m := 500L], data.table(t23 = 0.40, t4 = 10, t4sh = 0.10, radius_m = 400L),
              data.table(t23 = 0.40, t4 = 10, t4sh = Inf, radius_m = 500L))   # last: FIX on lost coverage only (no single-restroom clause)
sens <- rbindlist(lapply(seq_len(nrow(scen)), function(i) {
  s <- scen[i]; dd <- diagnose(base29, s$t23, s$t4, s$t4sh, if (s$radius_m == 400) "_400m" else "")
  ch <- dd$primary_action != base29$primary_action
  data.table(layer2_3_threshold_pct = 100 * s$t23, layer4_threshold_pp = s$t4, layer4_single_restroom_share_pct = ifelse(is.finite(s$t4sh), 100 * s$t4sh, NA),
             radius_layer2_3_m = s$radius_m,
             n_BUILD = sum(dd$primary_action == "BUILD"), n_FIX = sum(dd$primary_action == "FIX"),
             n_EXTEND = sum(dd$primary_action == "EXTEND HOURS"), n_VERIFY = sum(dd$primary_action == "VERIFY"),
             n_changed_vs_base = sum(ch),
             changed = paste(sprintf("%s: %s->%s", base29$ntaname[ch], base29$primary_action[ch], dd$primary_action[ch]), collapse = "; "))
}))
stopifnot(sens[layer2_3_threshold_pct == 40 & layer4_threshold_pp == 10 & radius_layer2_3_m == 500 & layer4_single_restroom_share_pct %in% 10]$n_changed_vs_base == 0)
fwrite(sens, file.path(OUT, "sensitivity.csv"))
print(sens[, 1:9])

# ---- where exactly to build: greedy within each BUILD NTA --------------------------------------------
# Objective = this NTA's residents with no restroom open at 2pm within 500 m (the Layer 2 gap). Stop when Layer 2
# < 40% or 10 sites, or when no candidate adds coverage. Busy streets / subway entries in the NTA newly covered
# are reported as secondary (not optimised). New sites assumed open at 2pm.
# (A) prototype candidate set (Parks land / DOT plazas / busy-street frontage) inside or within 250 m of the NTA.
# (B) diagnostic only: ANY 150 m residential grid point inside or within 250 m of the NTA (i.e. a sidewalk anywhere),
#     to separate "the gap is fixable by building" from "the prototype's candidate land cannot reach the gap".
cov14 <- list(residents = cov_existing("residents", 500, OV$b14), streets = cov_existing("streets", 500, OV$b14),
              subway = cov_existing("subway", 500, OV$b14))
bn <- base29[primary_action == "BUILD"]$nta2020
bpoly <- nres[match(bn, nres$nta2020), ]
nearA <- st_is_within_distance(bpoly, cand, dist = M2FT(250))
nearB <- st_is_within_distance(bpoly, P$demand_pts$residents, dist = M2FT(250))
run_greedy <- function(code, cc, c2d, c2s, c2u, K = 10) {
  inN <- dn$residents == code; tot <- sum(W$residents[inN])
  wr <- W$residents * (inN & !cov14$residents)                       # uncovered residents of THIS NTA only
  ws <- W$streets * (dn$streets == code & !cov14$streets); wu <- W$subway * (dn$subway == code & !cov14$subway)
  l2_0 <- l2 <- sum(wr) / tot; rows <- list()
  while (l2 >= 0.40 && length(rows) < K && length(cc)) {
    g <- vapply(seq_along(cc), function(i) sum(wr[c2d[[i]]]), 0)
    if (max(g) <= 1e-9) break
    i <- which.max(g)
    gs <- sum(ws[c2s[[i]]]); gu <- sum(wu[c2u[[i]]])
    wr[c2d[[i]]] <- 0; ws[c2s[[i]]] <- 0; wu[c2u[[i]]] <- 0
    l2 <- sum(wr) / tot
    rows[[length(rows) + 1]] <- data.table(idx = cc[i], new_residents_covered = round(g[i]), new_busy_street_m = round(gs),
                                           new_subway_entries = round(gu), L2_after = round(l2, 4))
  }
  r <- rbindlist(rows); if (nrow(r)) r[, rank := seq_len(.N)]
  list(rows = r, s = data.table(candidates_in_reach = length(cc), sites = nrow(r), L2_before = l2_0, L2_after = l2, reached = l2 < 0.40))
}
bs <- list(); bsum <- list()
for (k in seq_along(bn)) {
  code <- bn[k]
  ca <- nearA[[k]]
  A <- run_greedy(code, ca, P$inc$residents_500$cand[ca], P$inc$streets_500$cand[ca], P$inc$subway_500$cand[ca])
  cb <- nearB[[k]]; pb <- P$demand_pts$residents[cb]
  B <- run_greedy(code, cb, st_is_within_distance(pb, P$demand_pts$residents, dist = M2FT(500)),
                  st_is_within_distance(pb, P$demand_pts$streets, dist = M2FT(500)),
                  st_is_within_distance(pb, P$demand_pts$subway, dist = M2FT(500)))
  if (nrow(A$rows)) bs[[length(bs) + 1]] <- cbind(nta2020 = code, candidate_set = "prototype candidates (Parks/plaza/busy street)",
    A$rows, cand_id = cand$cand_id[A$rows$idx], cand_type = cand$type[A$rows$idx], lat = round(cand$lat[A$rows$idx], 6),
    lon = round(cand$lon[A$rows$idx], 6), site_nta = cand$nta[A$rows$idx])
  if (nrow(B$rows)) { ll <- st_coordinates(st_transform(P$demand_pts$residents[B$rows$idx], 4326))
    bs[[length(bs) + 1]] <- cbind(nta2020 = code, candidate_set = "diagnostic: any residential grid point", B$rows,
      cand_id = NA_integer_, cand_type = "street grid point (unverified)", lat = round(ll[, 2], 6), lon = round(ll[, 1], 6),
      site_nta = dn$residents[B$rows$idx]) }
  bsum[[k]] <- data.table(nta2020 = code, build_cands_in_reach = A$s$candidates_in_reach, build_sites_needed = A$s$sites,
                          L2_before = A$s$L2_before, build_L2_after = A$s$L2_after, build_target_reached = A$s$reached,
                          anyloc_sites = B$s$sites, anyloc_L2_after = B$s$L2_after, anyloc_target_reached = B$s$reached)
}
bs <- rbindlist(bs); bsum <- rbindlist(bsum)
stopifnot(nrow(bsum) == length(bn), all(abs(bsum$L2_before - L$L2_residents[match(bsum$nta2020, L$nta2020)]) < 1e-9))
bs <- merge(bs, L[, .(nta2020, ntaname, boroname)], by = "nta2020")
bs[, site_in_nta := nta$ntaname[match(site_nta, nta$nta2020)]]
setorder(bs, nta2020, candidate_set, rank)
bs <- bs[order(-grepl("^prototype", candidate_set))]
fwrite(bs[, .(ntaname, boroname, nta2020, candidate_set, rank, cand_id, cand_type, lat, lon, site_in_nta,
              new_residents_covered, new_busy_street_m, new_subway_entries, L2_after)], file.path(OUT, "build_sites.csv"))
L <- merge(L, bsum[, !"L2_before"], by = "nta2020", all.x = TRUE)
setorder(L, -resid_ratio)
print(merge(bsum, L[, .(nta2020, ntaname)], by = "nta2020"))

# ---- pilot sites vs the 29 (NTA assignment from Restroom_Rebuild/R/P1_pilot_sites.R) -----------------
pl <- fread(file.path(BASE, "Restroom_Rebuild/outputs/pilot_sites.csv"))
stopifnot(nrow(pl) == 17, !anyDuplicated(pl$site_id), all(pl$nta2020 %in% nres$nta2020))
pl <- merge(pl[, .(site_id, published_name, borough, lat, lon, nta2020, snapped_to_residential, raw_nta, ambiguous)],
            L[, .(nta2020, ntaname, resid_ratio, in_29, confident_six, primary_action, flags, L2_residents, L3_residents, L4_lost_pp)],
            by = "nta2020", all.x = TRUE)
stopifnot(nrow(pl) == 17)
# also: does a pilot site's 500 m catchment reach residents of any of the 29?
pil_sf <- st_as_sf(pl, coords = c("lon", "lat"), crs = 4326, remove = FALSE) |> st_transform(2263)
pr29 <- st_is_within_distance(pil_sf, P$demand_pts$residents, dist = M2FT(500))
pl$reaches_29_within_500m <- vapply(pr29, function(x) { x <- x[W$residents[x] > 0]
  paste(unique(L$ntaname[match(intersect(dn$residents[x], top29), L$nta2020)]), collapse = "; ") }, "")
setorder(pl, site_id)
fwrite(pl, file.path(OUT, "pilot_in_29.csv"))
cat("pilot sites inside the 29:", sum(pl$in_29), "\n")

# ---- write tables ----------------------------------------------------------------------------------
rnd <- function(x) { n <- names(x)[sapply(x, is.numeric)]; x[, (n) := lapply(.SD, function(v) round(v, 4)), .SDcols = n]; x }
cols <- c("nta2020", "ntaname", "boroname", "events_311", "pred", "resid_ratio", "eb_p_gt_1_5", "confident_six", "in_29",
          "residents", "L2_residents", "L2_streets", "L2_subway", "L3_residents", "L3_ext_recov", "L3_ext_recov_frac",
          "L2_residents_400m", "L3_residents_400m", "L3_ext_recov_frac_400m",
          "parks_restrooms_serving", "n_long_term_closed", "n_ltc_listed_operational", "n_repeatedly_failing",
          "max_res_share_one_broken", "L4_lost_pp", "L4_reopen_gain_pp", "pip26_props", "pip26_n_rated", "pip26_fail_rate",
          "flag_build", "flag_fix", "flag_extend", "flags", "primary_action", "build_cands_in_reach", "build_sites_needed", "build_L2_after", "build_target_reached", "anyloc_sites", "anyloc_L2_after", "anyloc_target_reached", "broken_names",
          "street_m", "subway_entries")
out <- rnd(copy(L[, ..cols]))
fwrite(out, file.path(OUT, "layers_all197.csv"))
fwrite(out[in_29 == TRUE], file.path(OUT, "diagnosis_29.csv"))
saveRDS(list(L = L, bs = bs, bsum = bsum, pl = pl, sens = sens, OV = OV), file.path(LY, "cache/layers.rds"))
cat("\nprimary action among the 29:\n"); print(table(base29$primary_action))
cat("done in", round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")
