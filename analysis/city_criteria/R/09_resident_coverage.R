# 09_resident_coverage.R -- how many restrooms would it take to give RESIDENTS evening access?
# Units: residents on the 150 m grid (Census ACS 2020-24, from Build_Plan/prototype/cache/prep.rds). Covered = a restroom
# open at the tested hour within 500 m (straight line). Two stages, as in 05_gap.R:
#   stage 1 existing restrooms at their own locations: repair/reopen broken ones, or keep day-only ones open to 10pm;
#   stage 2 new units, allowed at ANY residential grid point (a coverage bound, not a siting plan -- no feasibility check).
# Greedy maximal covering weighted by residents. Reports existing restrooms used and new units needed to reach given
# resident-coverage levels at 9pm, with daytime (2pm) for comparison. Writes outputs/resident_coverage_*.csv.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
FT <- 0.3048006096; M2FT <- function(m) m / FT
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); sup <- P$sup
rp <- st_sfc(P$demand_pts$residents, crs = st_crs(sup)); rw <- P$demand$residents$w
stopifnot(length(rp) == length(rw)); cat("resident points:", length(rp), "| residents:", round(sum(rw)), "\n")
open_at <- function(h, ph_close = 16) { cl <- ifelse(sup$placeholder, ph_close, sup$w_close)
  sup$operational & !sup$removed_closed & !sup$removed_fail & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h }   # broken excluded (audit 26 Sep)
broken <- sup$removed_closed | sup$removed_fail | sup$reopen_add
p2s <- st_is_within_distance(rp, sup, dist = M2FT(500))          # point -> restrooms within 500 m
s2p <- st_is_within_distance(sup, rp, dist = M2FT(500))          # restroom -> points
p2p <- st_is_within_distance(rp, rp, dist = M2FT(500))           # point -> points (symmetric)
cat("neighbour lists built\n")

cover_plan <- function(hour = 21, ph_close = 16, levels = c(.8, .9, .95, 1), fixed_new = NULL) {
  ok <- open_at(hour, ph_close)
  cov <- vapply(p2s, function(j) any(ok[j]), TRUE); tot <- sum(rw)
  start <- sum(rw[cov]) / tot
  # stage 1: eligible existing restrooms (not already open at `hour`)
  elig <- which((broken | (open_at(14, ph_close) & !ok & !broken)) & !ok)
  g1 <- rep(0, nrow(sup)); g1[elig] <- vapply(s2p[elig], function(j) sum(rw[j][!cov[j]]), 0)
  n1 <- 0; act <- character(0)
  while (max(g1) > 0) { i <- which.max(g1); newly <- s2p[[i]][!cov[s2p[[i]]]]; cov[newly] <- TRUE; n1 <- n1 + 1; g1[i] <- 0
    act <- c(act, ifelse(broken[i], "repair", ifelse(sup$placeholder[i], "park hours", "other hours")))
    tf <- intersect(unique(unlist(p2s[newly])), elig); g1[tf] <- vapply(s2p[tf], function(j) sum(rw[j][!cov[j]]), 0) }
  after1 <- sum(rw[cov]) / tot
  n_fixed <- 0L
  if (!is.null(fixed_new)) { hitp <- unique(unlist(st_is_within_distance(fixed_new, rp, dist = M2FT(500)))); cov[hitp] <- TRUE; n_fixed <- length(fixed_new) }
  after_fixed <- sum(rw[cov]) / tot
  # stage 2: new units at residential grid points
  g2 <- vapply(p2p, function(j) sum(rw[j][!cov[j]]), 0); n2 <- n_fixed; hit <- rep(NA_integer_, length(levels)); curv <- numeric(0)
  lv <- levels; for (k in seq_along(lv)) if (after_fixed >= lv[k] - 1e-9) hit[k] <- n_fixed
  while (any(is.na(hit)) && max(g2) > 0) {
    i <- which.max(g2); newly <- p2p[[i]][!cov[p2p[[i]]]]; cov[newly] <- TRUE; n2 <- n2 + 1; g2[i] <- 0
    tp <- unique(unlist(p2p[newly])); g2[tp] <- vapply(p2p[tp], function(j) sum(rw[j][!cov[j]]), 0)
    sh <- sum(rw[cov]) / tot; curv <- c(curv, sh)
    for (k in seq_along(lv)) if (is.na(hit[k]) && sh >= lv[k] - 1e-9) hit[k] <- n2
  }
  list(start = start, existing = n1, actions = table(factor(act, levels = c("park hours", "other hours", "repair"))),
       after_existing = after1, after_fixed = after_fixed, new_units = setNames(hit, sprintf("%g%%", 100 * levels)), curve = curv)
}
out <- list(); curves <- list()
G <- readRDS(file.path(CM, "cache/gap.rds")); fx <- st_transform(st_as_sf(G$New, coords = c("lon", "lat"), crs = 4326), st_crs(sup))
for (sc in list(list(h = 21, ph = 16, lab = "9pm, parks close 4pm"), list(h = 21, ph = 22, lab = "9pm, parks open to 10pm"),
                list(h = 14, ph = 16, lab = "2pm (daytime)"), list(h = 21, ph = 16, lab = "9pm, the 24 busiest-area units built first", fx = TRUE))) {
  r <- cover_plan(sc$h, sc$ph, fixed_new = if (isTRUE(sc$fx)) st_geometry(fx) else NULL)
  cat(sc$lab, ": start", round(r$start, 3), "| existing", r$existing, paste(names(r$actions), r$actions, collapse = ", "),
      "-> ", round(r$after_existing, 3), "| new units to reach", paste(names(r$new_units), r$new_units, collapse = "  "), "\n")
  out[[sc$lab]] <- data.table(scenario = sc$lab, residents_covered_now = round(r$start, 3), existing_restrooms = r$existing,
                              park_hours = r$actions[["park hours"]], other_hours = r$actions[["other hours"]], repair = r$actions[["repair"]],
                              covered_after_existing = round(r$after_existing, 3), covered_after_fixed = round(r$after_fixed, 3), t(r$new_units))
  curves[[sc$lab]] <- data.table(scenario = sc$lab, new_units = seq_along(r$curve), residents_covered = round(r$curve, 4))
}
R <- rbindlist(out, fill = TRUE); print(R)
fwrite(R, file.path(CM, "outputs/resident_coverage_summary.csv")); fwrite(rbindlist(curves), file.path(CM, "outputs/resident_coverage_curves.csv"))
