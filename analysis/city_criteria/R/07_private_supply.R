# 07_private_supply.R -- ROBUSTNESS: do chain food outlets (Starbucks, McDonald's, ...) already fill the gap? (26 Sep 2026)
#  Treated as a SUPPLY question: chain outlets within 500 m are added to the listed restrooms, then the gap and the
#  two-stage cover from 05_gap.R are re-run unchanged (demand, threshold, radius, pilots, stage-1 eligibility all as in 05).
#  Data: Restroom_Rebuild/data_raw/commercial_chains_dohmh_20260920.csv (DOHMH inspections). It has NO opening hours and
#  NO information on whether a toilet exists or is open to non-customers, so every scenario below is an ASSUMPTION:
#   A  none (base, must reproduce 05: gap 1,247; stage 1 = 154 existing; stage 2 = 24 new)
#   B  every outlet counts at 2pm and 9pm (upper bound: all open at 9pm, all let anyone use the toilet)
#   C  by day every outlet counts; at 9pm only late-night fast food (burger / fried chicken / taco chains) counts
#   C+ C plus the fast-casual chains that often close ~10pm (Chipotle, Shake Shack, Subway) -- extra sensitivity row
#   D  C, but only a random 50% of outlets let non-customers use the toilet (200 draws; same draw used at 2pm and 9pm)
#  Does NOT source 05_gap.R (it writes outputs). Functions open_at / covered / greedy / run_gap are copied from 05.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
FT <- 0.3048006096; M2FT <- function(m) m / FT
F0 <- readRDS(file.path(CM, "cache/features.rds")); X <- F0$X; sites <- F0$sites
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); sup <- P$sup
G <- readRDS(file.path(CM, "cache/gap.rds")); D0 <- G$D0
cand <- X[pilot == 0]; cs <- sites[X$pilot == 0, ]; nC <- nrow(cand)
stopifnot(length(D0) == nC)

# ---- copied from 05_gap.R (verbatim except run_gap gains two chain-supply arguments, default = none) ---------------
open_at <- function(h, ph_close = 16) { cl <- ifelse(sup$placeholder, ph_close, sup$w_close)
  sup$operational & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h }
nb_sup <- list(`500` = st_is_within_distance(cs, sup, dist = M2FT(500)))
nb_fac <- list(`500` = st_is_within_distance(sup, cs, dist = M2FT(500)))
nb_cs  <- list(`500` = st_is_within_distance(cs, cs, dist = M2FT(500)))
pil_blk <- list(`500` = lengths(st_is_within_distance(cs, P$pil, dist = M2FT(500))) > 0)
covered <- function(ok, nb) vapply(nb, function(j) any(ok[j]), TRUE)
broken <- sup$removed_closed | sup$removed_fail | sup$reopen_add
greedy <- function(unc, w, nb, stop_at_zero = FALSE) {      # nb: candidate -> gap-site indices
  gain <- vapply(nb, function(j) sum(w[j][unc[j]]), 0); sel <- integer(0)
  while (any(unc)) {
    i <- which.max(gain); if (gain[i] <= 0) { if (stop_at_zero) break else stop("uncoverable gap site") }
    sel <- c(sel, i); newly <- nb[[i]][unc[nb[[i]]]]; unc[newly] <- FALSE; gain[i] <- 0
    touched <- which(vapply(nb, function(j) any(j %in% newly), TRUE)); gain[touched] <- vapply(nb[touched], function(j) sum(w[j][unc[j]]), 0)
  }
  list(sel = sel, unc = unc)
}
# ch9 / ch14: logical, length nC -- candidate site has a chain outlet counted as supply within 500 m at 9pm / 2pm
run_gap <- function(D, thr = 2 / 3, hour = 21, rad = 500, ph_close = 16, ch9 = rep(FALSE, nC), ch14 = rep(FALSE, nC)) {
  r <- as.character(rad); ev <- open_at(hour, ph_close)
  gap <- D >= thr & !(covered(ev, nb_sup[[r]]) | ch9) & !pil_blk[[r]]
  day_only <- open_at(14, ph_close) & !ev & !broken
  elig <- which((broken | day_only) & !ev)
  action <- ifelse(broken, "Repair or reopen", ifelse(sup$placeholder, "Keep park restroom open to 10pm", "Extend other operator's hours"))
  s1 <- greedy(gap, D, nb_fac[[r]][elig], stop_at_zero = TRUE)
  fac <- elig[s1$sel]
  s2 <- greedy(s1$unc, D, nb_cs[[r]])
  list(gap = gap, fac = fac, fac_action = action[fac], new = s2$sel, left_after_s1 = sum(s1$unc),
       day = covered(open_at(14, ph_close), nb_sup[[r]]) | ch14)
}

# ---- 1. base case must reproduce 05 --------------------------------------------------------------------------------
cov14 <- covered(open_at(14), nb_sup$`500`)
A <- run_gap(D0)
stopifnot(identical(A$gap, G$gap0), sum(A$gap) == 1247, identical(A$fac, G$B$fac), length(A$fac) == 154,
          identical(A$new, G$B$new), length(A$new) == 24, identical(cov14, G$cov14),
          sum(A$gap & !cov14) == 65, sum(A$gap & cov14) == 1182,
          sum(A$fac_action == "Keep park restroom open to 10pm") == 103, sum(A$fac_action == "Extend other operator's hours") == 35,
          sum(A$fac_action == "Repair or reopen") == 16)
cat("base reproduced: gap 1247 (1182 evening-only, 65 all-day) | stage 1: 154 (103/35/16) | stage 2: 24\n")

# ---- 2. chain outlets --------------------------------------------------------------------------------------------
ch <- fread(file.path(BASE, "Restroom_Rebuild/data_raw/commercial_chains_dohmh_20260920.csv"), encoding = "UTF-8")
n_raw <- nrow(ch)
bad_geo <- is.na(ch$latitude) | is.na(ch$longitude) | ch$latitude == 0 | ch$longitude == 0
not_chain <- grepl("^MCDONALD AVENUE DINER$|^WENDY TERIYAKI|^THE JUICE HOUSE \\(Near Dunkin", ch$name)   # name-match false positives
cat("chain file:", n_raw, "rows | dropped: no coordinates", sum(bad_geo), "| not the chain", sum(not_chain & !bad_geo), "\n")
ch <- ch[!bad_geo & !not_chain]
dup <- duplicated(ch[, .(chain, latitude, longitude)])
cat("same chain at identical coordinates (kept; does not change coverage):", sum(dup), "| outlets used:", nrow(ch), "\n")
# late-night list [ASSUMED, not observed hours]: burger / fried-chicken / taco fast food, whose NYC outlets typically trade
# past 9pm (many to 11pm-late night or 24h). Matched on the chain OR the inspection name, so co-branded outlets
# (e.g. "DUNKIN' / POPEYES", "KFC / TACO BELL") count if any brand in them is late-night.
LATE <- c("McDonald’s", "Burger King", "Wendy’s", "Popeyes", "KFC", "Taco Bell")
late_rx <- "MCDONALD'?S|BURGER KING|WENDY'?S|POPEYES|KFC|KENTUCKY FRIED|TACO BELL"
ch[, late := chain %in% LATE | grepl(late_rx, toupper(name))]
MID <- c("Chipotle", "Shake Shack", "Subway")            # fast casual / sandwich: commonly close 9-10pm -> marginal at 9pm
ch[, late_plus := late | chain %in% MID]
chs <- st_transform(st_as_sf(ch, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE), st_crs(cs))
nb_ch <- st_is_within_distance(cs, chs, dist = M2FT(500))           # candidate site -> chain outlets within 500 m
print(ch[, .(outlets = .N, late_9pm_in_C = sum(late)), by = chain][order(-outlets)])

# ---- 3. descriptives ---------------------------------------------------------------------------------------------
g0 <- which(A$gap); nw <- A$new
any_ch <- lengths(nb_ch) > 0
cat("\nbase gap sites with any chain outlet within 500 m:", sum(any_ch[g0]), "of", length(g0),
    "| with a late-night (C-list) outlet:", sum(covered(ch$late, nb_ch)[g0]), "\n")
DESC <- rbindlist(lapply(sort(unique(ch$chain)), function(k) { ok <- ch$chain == k
  data.table(chain = k, outlets = sum(ok), base_gap_sites_within_500m = sum(covered(ok, nb_ch)[g0]),
             base_new_unit_sites_within_500m = sum(covered(ok, nb_ch)[nw])) }))[order(-base_gap_sites_within_500m)]
print(DESC)
cat("base new-unit sites with any chain within 500 m:", sum(any_ch[nw]), "of", length(nw),
    "| with a late-night (C-list) outlet:", sum(covered(ch$late, nb_ch)[nw]), "\n")
cat("new-unit sites with chains nearby:\n")
for (i in nw[any_ch[nw]]) cat("  ", cand$ntaname[i], ":", paste(sort(unique(ch$chain[nb_ch[[i]]])), collapse = ", "), "\n")

# ---- 4. scenarios ------------------------------------------------------------------------------------------------
near_new <- nb_cs$`500`[A$new]
fac_serves <- lapply(nb_fac$`500`[A$fac], function(j) j[A$gap[j]])   # base gap sites within 500 m of each base facility
new_serves <- lapply(near_new, function(j) j[A$gap[j]])              # ... and of each base new-unit site
stopifnot(all(lengths(fac_serves) > 0), all(lengths(new_serves) > 0))
summ <- function(o, label) data.table(scenario = label,
  gap_sites = sum(o$gap), gap_all_day = sum(o$gap & !o$day), gap_evening_only = sum(o$gap & o$day),
  existing = length(o$fac), repair = sum(o$fac_action == "Repair or reopen"),
  park_hours = sum(o$fac_action == "Keep park restroom open to 10pm"), other_hours = sum(o$fac_action == "Extend other operator's hours"),
  new_units = length(o$new),
  base_gap_no_longer_gap = sum(A$gap & !o$gap),
  base_existing_not_needed = sum(!(A$fac %in% o$fac)),                                   # exact facility no longer chosen
  base_existing_redundant = sum(vapply(fac_serves, function(j) !any(o$gap[j]), TRUE)),   # every base gap site it served is no longer a gap
  base_new_areas_not_needed = sum(!vapply(near_new, function(nb) any(o$new %in% nb), TRUE)),  # no new unit within 500 m (05's area test)
  base_new_redundant = sum(vapply(new_serves, function(j) !any(o$gap[j]), TRUE)))          # every base gap site it served is no longer a gap
cv <- function(ok) covered(ok, nb_ch)
allch <- rep(TRUE, nrow(ch))
S <- list(summ(A, "A: none (base)"),
          summ(run_gap(D0, ch9 = cv(allch), ch14 = cv(allch)), "B: all outlets, 2pm and 9pm (upper bound)"),
          summ(run_gap(D0, ch9 = cv(ch$late), ch14 = cv(allch)), "C: all by day; late-night fast food only at 9pm"),
          summ(run_gap(D0, ch9 = cv(ch$late_plus), ch14 = cv(allch)), "C+: C plus Chipotle, Shake Shack, Subway at 9pm"))
set.seed(6093)
DR <- rbindlist(lapply(1:200, function(r) { acc <- runif(nrow(ch)) < 0.5
  summ(run_gap(D0, ch9 = cv(ch$late & acc), ch14 = cv(acc)), "D") }))
num <- setdiff(names(DR), "scenario")
S <- rbindlist(c(S, list(
  cbind(data.table(scenario = "D: C with 50% non-customer access - median of 200"), DR[, lapply(.SD, median), .SDcols = num]),
  cbind(data.table(scenario = "D: min of 200"), DR[, lapply(.SD, min), .SDcols = num]),
  cbind(data.table(scenario = "D: max of 200"), DR[, lapply(.SD, max), .SDcols = num]))))
print(as.data.frame(S), right = FALSE)
fwrite(S, file.path(CM, "outputs/private_supply_scenarios.csv"))
cat("wrote outputs/private_supply_scenarios.csv\n")
