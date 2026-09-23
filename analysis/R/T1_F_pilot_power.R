# T1_F_pilot_power.R -- test F: power of a matched difference-in-differences around the
# 17 modular pilot sites (2026-09-23, mechanism-tests subagent).
#
# DESIGN BEING POWERED: 17 treated catchments (circle of 250 m or 400 m around each pilot
# site, outputs/pilot_sites.csv from R/P1_pilot_sites.R) vs 3 matched control catchments
# each, one year before vs one year after opening. Units operate 7am-10pm, so the 311
# outcome is restricted to complaints FILED 07:00-21:59 (filing time != incident time).
#
# OUTCOMES
#   311: "Urinating in Public", public location types, one per incident_address x month,
#        coordinates required (the project's 3,629 series), filed 07:00-21:59 (and all hours).
#   Summons: OATH public-urination summonses, de-duplicated to coordinate-month (as C1/90/91).
#        No time of day in the data (every occur_date is 00:00), so no hours filter.
#   Placebo: OATH alcohol summonses, same de-dup; the triple difference (urination DiD minus
#        alcohol DiD) is powered too, because that is what the placebo design would estimate.
#
# REHEARSAL WINDOWS (the pilot has not run; we use the last two complete years as stand-ins)
#   311:      match = Sep 2023-Aug 2024, pre = Sep 2024-Aug 2025, post = Sep 2025-Aug 2026
#   summons:  match = Jul 2023-Jun 2024, pre = Jul 2024-Jun 2025, post = Jul 2025-Jun 2026
#
# METHOD (empirical, placebo-in-space; no distributional assumption)
#   1. Pool = 20,000 random points in residential NTAs, >= 800 m from every pilot site.
#   2. Count outcomes in each circle for match/pre/post.
#   3. Matched DiD estimator: d = log((T_post+.5)/(T_pre+.5)) - log((C_post/3+.5)/(C_pre/3+.5)),
#      T/C summed over catchments; controls = 3 nearest pool points on (match+pre) count,
#      same borough, without replacement.
#   4. Null distribution: 2,000 placebo draws, each picking 17 pseudo-treated pool points
#      whose (match+pre) count equals the corresponding pilot site's (nearest available),
#      then matching controls as in 3. SD of d under the null -> MDE (log) = (1.96+0.84)*SD.
#      Reported as the smallest detectable REDUCTION, 1 - exp(-MDE_log).
#   5. Optimistic Poisson floor for comparison: MDE_log = 2.80*sqrt(1/T0+1/T1+1/C0+1/C1)
#      using the pilot catchments' actual pre counts (assumes pure Poisson, no overdispersion).
# ---------------------------------------------------------------------------------------
options(scipen = 999, stringsAsFactors = FALSE)
suppressPackageStartupMessages({library(dplyr); library(sf); library(jsonlite)})
PROJ <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild"
D <- file.path(PROJ, "data_raw"); OUT <- file.path(PROJ, "outputs")
set.seed(6093)
NPOOL <- 20000; NPLAC <- 2000; K <- 3; Z <- qnorm(.975) + qnorm(.8); FT <- 1/0.3048
RES <- list(); ROWS <- list()
row <- function(item, est=NA, lo=NA, hi=NA, p=NA, n=NA, note="")
  ROWS[[length(ROWS)+1]] <<- data.frame(test="F", item=item, estimate=est, lo=lo, hi=hi, p=p, n=n, note=note)

## ---- treated sites ----------------------------------------------------------------
pf <- file.path(OUT, "pilot_sites.csv")
PROVISIONAL <- !file.exists(pf)
nta_all <- st_read(file.path(D, "nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet = TRUE) |> st_transform(2263)
res_nta <- nta_all |> filter(ntatype == 0) |> st_make_valid()
if (!PROVISIONAL) {
  ps <- read.csv(pf); stopifnot(nrow(ps) == 17, !anyNA(ps$lat), !anyNA(ps$lon))
  tr <- st_as_sf(ps, coords = c("lon","lat"), crs = 4326) |> st_transform(2263)
  tr$boro <- ps$borough; tr$label <- ps$published_name
  cat("pilot sites from outputs/pilot_sites.csv:", nrow(tr), "\n")
} else {   # placeholder: 17 random points in 17 random shortlist NTAs
  sc <- read.csv(file.path(D, "model_nta_scored_20260920.csv"))
  pick <- sample(sc$nta2020[sc$resid_ratio >= 1.5], 17)
  tr <- st_sample(res_nta[match(pick, res_nta$nta2020), ], rep(1, 17)) |> st_sf()
  tr$boro <- res_nta$boroname[match(pick, res_nta$nta2020)]; tr$label <- pick
  cat("PROVISIONAL: pilot_sites.csv missing, 17 random shortlist catchments used\n")
}

## ---- outcome events ----------------------------------------------------------------
ev <- read.csv(file.path(D, "nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"))
u <- ev[ev$complaint_type == "Urinating in Public" & ev$location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"), ]
u$ym <- substr(u$created_date, 1, 7); u <- u[is.finite(suppressWarnings(as.numeric(u$latitude))), ]
cm <- u[!duplicated(u[, c("incident_address","ym")]), ]; stopifnot(nrow(cm) == 3629)
cm$hour <- as.integer(substr(cm$created_date, 12, 13)); cm$date <- as.Date(substr(cm$created_date, 1, 10))
per311 <- function(dt) ifelse(dt >= as.Date("2023-09-01") & dt < as.Date("2024-09-01"), "match",
                       ifelse(dt >= as.Date("2024-09-01") & dt < as.Date("2025-09-01"), "pre",
                       ifelse(dt >= as.Date("2025-09-01") & dt < as.Date("2026-09-01"), "post", NA)))
cm$period <- per311(cm$date)
cat("311 in windows (all hours) match/pre/post:", paste(table(factor(cm$period, c("match","pre","post"))), collapse = "/"),
    "  (post window runs to 31 Aug 2026; data end", max(substr(ev$created_date,1,10)), ")\n")
mk_sf <- function(df, lat = "latitude", lon = "longitude")
  st_as_sf(df, coords = c(lon, lat), crs = 4326) |> st_transform(2263)
E <- list(
  c311_7to22 = mk_sf(cm[!is.na(cm$period) & cm$hour >= 7 & cm$hour < 22, ]),
  c311_all   = mk_sf(cm[!is.na(cm$period), ]))
perS <- function(dt) ifelse(dt >= as.Date("2023-07-01") & dt < as.Date("2024-07-01"), "match",
                     ifelse(dt >= as.Date("2024-07-01") & dt < as.Date("2025-07-01"), "pre",
                     ifelse(dt >= as.Date("2025-07-01") & dt < as.Date("2026-07-01"), "post", NA)))
load_summ <- function(f){
  o <- read.csv(file.path(D, f)); o$lat <- suppressWarnings(as.numeric(o$latitude)); o$lon <- suppressWarnings(as.numeric(o$longitude))
  o <- o[is.finite(o$lat) & is.finite(o$lon), ]; o$ym <- substr(o$occur_date, 1, 7)
  o <- o[!duplicated(data.frame(round(o$lat,5), round(o$lon,5), o$ym)), ]      # coordinate-month (C1 rule)
  o$period <- perS(as.Date(substr(o$occur_date, 1, 10))); o <- o[!is.na(o$period), ]
  mk_sf(o, "lat", "lon") }
E$summ_urin <- load_summ("nypd_oath_urination_hxbk-grd3_20260920.csv")
E$summ_alc  <- load_summ("nypd_oath_alcohol_placebo_hxbk-grd3_20260920.csv")
for (k in names(E)) cat(sprintf("%-11s events match/pre/post: %s\n", k, paste(table(factor(E[[k]]$period, c("match","pre","post"))), collapse = "/")))

## ---- pool of control / placebo points -----------------------------------------------
pool <- st_sample(res_nta, NPOOL) |> st_sf()
pool$boro <- res_nta$boroname[unlist(lapply(st_intersects(pool, res_nta), `[`, 1))]
far <- lengths(st_is_within_distance(pool, tr, 800*FT)) == 0
pool <- pool[far & !is.na(pool$boro), ]
cat("pool points (>=800 m from every pilot site):", nrow(pool), "\n")

counts <- function(pts, evs, r_m){
  w <- st_is_within_distance(pts, evs, r_m*FT); pr <- evs$period
  t(vapply(w, function(ix) c(match = sum(pr[ix] == "match"), pre = sum(pr[ix] == "pre"), post = sum(pr[ix] == "post")), numeric(3)))
}
did <- function(Tm, Cm) log((sum(Tm[,"post"])+.5)/(sum(Tm[,"pre"])+.5)) - log((sum(Cm[,"post"])/K+.5)/(sum(Cm[,"pre"])/K+.5))
match_controls <- function(base_t, boro_t, base_p, boro_p, exclude = integer(0)){
  used <- exclude; out <- integer(0)
  for (j in seq_along(base_t)) {
    cand <- setdiff(which(boro_p == boro_t[j]), used)
    dd <- abs(base_p[cand] - base_t[j]); cand <- cand[order(dd, runif(length(dd)))][1:K]
    out <- c(out, cand); used <- c(used, cand) }
  out
}

F_tab <- list()
for (R in c(250, 400)) {
  ov <- sum(st_is_within_distance(tr, tr, 2*R*FT, sparse = FALSE)[upper.tri(diag(17))])
  cat(sprintf("\n==== catchment %d m (overlapping pilot-circle pairs: %d) ====\n", R, ov))
  CT <- lapply(E, counts, pts = tr, r_m = R); CP <- lapply(E, counts, pts = pool, r_m = R)
  for (oc in c("c311_7to22", "c311_all", "summ_urin")) {
    Tm <- CT[[oc]]; Pm <- CP[[oc]]
    base_t <- Tm[,"match"] + Tm[,"pre"]; base_p <- Pm[,"match"] + Pm[,"pre"]
    # actual design, rehearsal year (should be ~0: no treatment happened)
    ci <- match_controls(base_t, tr$boro, base_p, pool$boro)
    d_real <- did(Tm, Pm[ci, , drop = FALSE])
    # placebo-in-space null distribution
    AltT <- if (oc == "summ_urin") CT$summ_alc else NULL; AltP <- if (oc == "summ_urin") CP$summ_alc else NULL
    sims <- replicate(NPLAC, {
      pt <- integer(0)
      for (j in 1:17) { cand <- setdiff(which(pool$boro == tr$boro[j]), pt)
        dd <- abs(base_p[cand] - base_t[j]); pt <- c(pt, cand[order(dd, runif(length(dd)))][1]) }
      cc <- match_controls(base_p[pt], pool$boro[pt], base_p, pool$boro, exclude = pt)
      dU <- did(Pm[pt, , drop = FALSE], Pm[cc, , drop = FALSE])
      dA <- if (!is.null(AltP)) did(AltP[pt, , drop = FALSE], AltP[cc, , drop = FALSE]) else NA
      c(dU, dU - dA) })
    sd_null <- sd(sims[1,]); mde_log <- Z*sd_null
    T0 <- sum(Tm[,"pre"]); T1 <- sum(Tm[,"post"]); C0 <- sum(Pm[ci,"pre"]); C1 <- sum(Pm[ci,"post"])
    pois_log <- Z*sqrt(1/max(T0,.5) + 1/max(T1,.5) + 1/max(C0,.5) + 1/max(C1,.5))
    r <- data.frame(radius_m = R, outcome = oc, treated_pre = T0, treated_post = T1,
      treated_pre_per_site = T0/17, sites_with_zero_pre = sum(Tm[,"pre"] == 0),
      controls_pre = C0, controls_post = C1, did_rehearsal = d_real,
      sd_null = sd_null, mde_reduction_pct = 100*(1-exp(-mde_log)), mde_increase_pct = 100*(exp(mde_log)-1),
      poisson_floor_reduction_pct = 100*(1-exp(-pois_log)),
      ddd_sd_null = if (oc == "summ_urin") sd(sims[2,]) else NA,
      ddd_mde_reduction_pct = if (oc == "summ_urin") 100*(1-exp(-Z*sd(sims[2,]))) else NA)
    F_tab[[length(F_tab)+1]] <- r
    cat(sprintf("%-11s treated pre %3d (%.1f/site, %d sites at 0) post %3d | rehearsal DiD %+.2f | null SD %.3f -> MDE %.0f%% reduction (Poisson floor %.0f%%)%s\n",
        oc, T0, T0/17, r$sites_with_zero_pre, T1, d_real, sd_null, r$mde_reduction_pct, r$poisson_floor_reduction_pct,
        if (oc == "summ_urin") sprintf(" | with alcohol placebo (DDD) %.0f%%", r$ddd_mde_reduction_pct) else ""))
    row(sprintf("mde_%dm_%s", R, oc), r$mde_reduction_pct, NA, NA, NA, 17,
        sprintf("smallest detectable reduction at 80%% power, alpha .05 (placebo-in-space, %d draws); treated pre-year events %d; Poisson floor %.0f%%; rehearsal DiD %+.2f%s%s",
                NPLAC, T0, r$poisson_floor_reduction_pct, d_real,
                if (oc == "summ_urin") sprintf("; DDD with alcohol placebo %.0f%%", r$ddd_mde_reduction_pct) else "",
                if (PROVISIONAL) "; PROVISIONAL placeholder sites" else ""))
  }
}
F_tab <- do.call(rbind, F_tab)
print(F_tab |> mutate(across(where(is.numeric), ~round(.x, 2))), row.names = FALSE)
row("hours_trial_mde_comparison", 37, NA, NA, NA, NA, "published hours-trial MDE (C1_trial_power.R, summons, de-duplicated): 37%")
# per-site pre-year counts for the write-up
CT400 <- counts(tr, E$c311_7to22, 400); CT250 <- counts(tr, E$c311_7to22, 250)
site_counts <- data.frame(site = tr$label, pre_250 = CT250[,"pre"], pre_400 = CT400[,"pre"], match_400 = CT400[,"match"], post_400 = CT400[,"post"])
print(site_counts, row.names = FALSE)
RES$F <- list(provisional = PROVISIONAL, sites_source = if (PROVISIONAL) "placeholder" else "outputs/pilot_sites.csv",
  windows = list(c311 = "match Sep23-Aug24, pre Sep24-Aug25, post Sep25-Aug26", summons = "match Jul23-Jun24, pre Jul24-Jun25, post Jul25-Jun26"),
  controls_per_treated = K, placebo_draws = NPLAC, pool_points = nrow(pool), table = F_tab, site_counts_311_7to22 = site_counts,
  hours_trial_mde_pct = 37)

## ---- write F and merge with A-E ------------------------------------------------------
tab <- do.call(rbind, ROWS)
write.csv(tab, file.path(OUT, "t1_tests_F.csv"), row.names = FALSE)
write_json(RES, file.path(OUT, "t1_tests_F.json"), auto_unbox = TRUE, digits = 6, pretty = TRUE, dataframe = "rows")
ae_csv <- file.path(OUT, "t1_tests_AE.csv"); ae_js <- file.path(OUT, "t1_tests_AE.json")
if (file.exists(ae_csv)) {
  write.csv(rbind(read.csv(ae_csv), tab), file.path(OUT, "t1_tests.csv"), row.names = FALSE)
  all <- c(fromJSON(ae_js, simplifyVector = FALSE), fromJSON(file.path(OUT, "t1_tests_F.json"), simplifyVector = FALSE))
  all$meta <- list(scripts = c("R/T1_mechanism_tests.R", "R/T1_F_pilot_power.R"), built = as.character(Sys.Date()),
                   findings = "../Internal_Reviews/mechanism_tests_findings.md")
  write_json(all, file.path(OUT, "t1_tests.json"), auto_unbox = TRUE, digits = 6, pretty = TRUE)
  cat("merged -> outputs/t1_tests.{csv,json}\n")
}
