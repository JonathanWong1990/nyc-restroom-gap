# 05_gap.R -- DEMAND minus SUPPLY (owner-approved spine, 26 Sep 2026).
#  1. Pilot model (M7): chosen (1) vs not (0) ~ busyness + distance to a restroom open at 2pm + at 9pm + equity + site type.
#     Demand weights come from the demand terms (busyness, equity); supply enters through the two distances.
#  2. Demand score at every candidate site; SUPPLY = listed restrooms by time of day (500 m).
#  3. GAP site = top third of demand AND no restroom open within 500 m at 9pm (evening), and not within 500 m of a pilot unit.
#     Types: all-day gap (none open at 2pm either) vs evening-only gap (a restroom nearby by day, closed by 9pm).
#  4. Closing the gap in two stages (revised 26 Sep after ChatGPT review, REVIEW_FINDINGS.md #1):
#     stage 1 -- EXISTING restrooms at their own coordinates: repair/reopen broken ones, or extend hours of ones open by
#     day but shut in the evening; greedy maximal covering over these facilities while any adds coverage;
#     stage 2 -- NEW units at candidate sites for whatever gap remains. Every count is a facility, deduplicated.
#  5. Sensitivity: random demand weights, demand threshold, evening hour, radius, park-hours assumption.
#  Demand scaling (review #2): the busyness composite is re-standardised with the fitting data's mean/sd, exactly as in
#  the model, before the demand weights are applied (also for alternative composites in the sensitivity runs).
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table); library(logistf)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
FT <- 0.3048006096; M2FT <- function(m) m / FT
F0 <- readRDS(file.path(CM, "cache/features.rds")); X <- F0$X; sites <- F0$sites
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds")); sup <- P$sup
set.seed(6093)
z <- function(v, ref = v) (v - mean(ref)) / sd(ref)

# ---- 1. pilot model ---------------------------------------------------------------------------------------------
d <- X[pilot == 1 | control_ok == TRUE]
mk <- function(dd, ref) {
  data.table(z_pop = z(log1p(dd$residents), log1p(ref$residents)), z_ped = z(log1p(dd$foot_traffic), log1p(ref$foot_traffic)),
             z_sub = z(log1p(dd$subway), log1p(ref$subway)), z_job = z(log1p(dd$jobs), log1p(ref$jobs)),
             z_d2 = z(log1p(dd$dist_2pm_m), log1p(ref$dist_2pm_m)), z_d9 = z(log1p(dd$dist_9pm_m), log1p(ref$dist_9pm_m)),
             z_pov = z(dd$poverty, ref$poverty), plaza = as.integer(dd$type == "plaza"), street = as.integer(dd$type == "busy_street"))
}
Zd <- mk(d, d); bref <- (Zd$z_pop + Zd$z_ped + Zd$z_sub + Zd$z_job) / 4
Zd[, busy := (((z_pop + z_ped + z_sub + z_job) / 4) - mean(bref)) / sd(bref)]
Zd[, pilot := d$pilot]
m7 <- logistf(pilot ~ busy + z_d2 + z_d9 + z_pov + plaza + street, data = Zd, plconf = NULL)
ci <- confint(m7)
M7 <- data.table(term = names(coef(m7))[-1], coef = round(coef(m7)[-1], 2), ci_low = round(ci[-1, 1], 2), ci_high = round(ci[-1, 2], 2))
print(M7)
auc <- function(s, y) { r <- rank(s); n1 <- sum(y); n0 <- sum(!y); (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
cat("AUC:", round(auc(m7$linear.predictors, Zd$pilot), 3), "\n")
pid <- which(Zd$pilot == 1); loo <- integer(length(pid)); Xm <- as.matrix(Zd[, .(busy, z_d2, z_d9, z_pov, plaza, street)])
for (k in seq_along(pid)) { mm <- logistf(pilot ~ busy + z_d2 + z_d9 + z_pov + plaza + street, data = Zd[-pid[k]], plconf = NULL)
  lp <- as.vector(cbind(1, Xm) %*% coef(mm)); loo[k] <- round(100 * mean(lp[Zd$pilot == 0] < lp[pid[k]])) }
cat("LOO median", median(loo), "mean", round(mean(loo)), "| each:", loo, "\n")
fwrite(M7, file.path(CM, "outputs/gap_pilot_model.csv"))
Zd[, z_311 := z(log1p(d$complaints))]
m7c <- logistf(pilot ~ busy + z_d2 + z_d9 + z_pov + plaza + street + z_311, data = Zd, plconf = NULL)
cat("complaints added to M7:", round(coef(m7c)["z_311"], 2), "CI", round(confint(m7c)["z_311", ], 2), "\n")
m7s <- logistf(pilot ~ z_pop + z_ped + z_sub + z_job + z_d2 + z_d9 + z_pov + plaza + street, data = Zd, plconf = NULL)
cat("six factors separately:", paste(names(coef(m7s))[-1], round(coef(m7s)[-1], 2), collapse = " | "), "\n")
fwrite(data.table(pilot = d[pid]$name, loo_pct = loo), file.path(CM, "outputs/gap_leave_one_out.csv"))
wb <- max(coef(m7)["busy"], 0); we <- max(coef(m7)["z_pov"], 0); WD <- c(busy = wb, equity = we) / (wb + we)
cat("demand weights: busyness", round(WD[1], 3), "equity", round(WD[2], 3), "\n")

# ---- 2. demand at every candidate site (busyness composite re-standardised as in the model) ------------------------
cand <- X[pilot == 0]; cs <- sites[X$pilot == 0, ]; nC <- nrow(cand)
Zc <- mk(cand, d); Zp <- mk(X[pilot == 1], d)
compF <- as.matrix(Zd[, .(z_pop, z_ped, z_sub, z_job)])
demand_raw <- function(Z, w4 = rep(.25, 4), wb = WD[1], we = WD[2]) {
  f <- as.vector(compF %*% w4); m <- mean(f); s <- sd(f)
  wb * (as.vector(as.matrix(Z[, .(z_pop, z_ped, z_sub, z_job)]) %*% w4) - m) / s + we * Z$z_pov
}
stopifnot(abs(mean(as.vector(compF %*% rep(.25, 4))) - mean(bref)) < 1e-12)
pct <- function(v) frank(v, ties.method = "average") / length(v)
DR0 <- demand_raw(Zc); D0 <- pct(DR0)

# ---- supply by time of day ---------------------------------------------------------------------------------------
open_at <- function(h, ph_close = 16) { cl <- ifelse(sup$placeholder, ph_close, sup$w_close)
  sup$operational & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h }
nb_sup <- list(`500` = st_is_within_distance(cs, sup, dist = M2FT(500)), `400` = st_is_within_distance(cs, sup, dist = M2FT(400)))
nb_fac <- list(`500` = st_is_within_distance(sup, cs, dist = M2FT(500)), `400` = st_is_within_distance(sup, cs, dist = M2FT(400)))
nb_cs  <- list(`500` = st_is_within_distance(cs, cs, dist = M2FT(500)), `400` = st_is_within_distance(cs, cs, dist = M2FT(400)))
pil_blk <- list(`500` = lengths(st_is_within_distance(cs, P$pil, dist = M2FT(500))) > 0, `400` = lengths(st_is_within_distance(cs, P$pil, dist = M2FT(400))) > 0)
covered <- function(ok, nb) vapply(nb, function(j) any(ok[j]), TRUE)
cov14 <- covered(open_at(14), nb_sup$`500`); cov21 <- covered(open_at(21), nb_sup$`500`)
cat("candidate sites covered within 500 m: 2pm", round(mean(cov14), 3), "| 9pm", round(mean(cov21), 3), "\n")
pc_pil <- sapply(demand_raw(Zp), function(v) mean(DR0 <= v))
pil9 <- X[pilot == 1]$dist_9pm_m > 500; pil2 <- X[pilot == 1]$dist_2pm_m > 500
cat("pilots: top-third demand", sum(pc_pil >= 2 / 3), "| no 9pm restroom", sum(pil9), "| both (in our gap definition)", sum(pc_pil >= 2 / 3 & pil9),
    "| no 2pm restroom", sum(pil2), "\n")

# ---- 3-4. gap, then two-stage cover ---------------------------------------------------------------------------------
broken <- sup$removed_closed | sup$removed_fail | sup$reopen_add
greedy <- function(unc, w, nb, stop_at_zero = FALSE) {      # nb: candidate -> gap-site indices
  gain <- vapply(nb, function(j) sum(w[j][unc[j]]), 0); sel <- integer(0)
  while (any(unc)) {
    i <- which.max(gain); if (gain[i] <= 0) { if (stop_at_zero) break else stop("uncoverable gap site") }
    sel <- c(sel, i); newly <- nb[[i]][unc[nb[[i]]]]; unc[newly] <- FALSE; gain[i] <- 0
    # recompute gains only for candidates that could reach the newly covered sites
    touched <- which(vapply(nb, function(j) any(j %in% newly), TRUE)); gain[touched] <- vapply(nb[touched], function(j) sum(w[j][unc[j]]), 0)
  }
  list(sel = sel, unc = unc)
}
run_gap <- function(D, thr = 2 / 3, hour = 21, rad = 500, ph_close = 16) {
  r <- as.character(rad); ev <- open_at(hour, ph_close)
  gap <- D >= thr & !covered(ev, nb_sup[[r]]) & !pil_blk[[r]]
  # stage 1: existing facilities that could serve at `hour` after an intervention (not already open then)
  day_only <- open_at(14, ph_close) & !ev & !broken
  elig <- which((broken | day_only) & !ev)
  action <- ifelse(broken, "Repair or reopen", ifelse(sup$placeholder, "Keep park restroom open to 10pm", "Extend other operator's hours"))
  s1 <- greedy(gap, D, nb_fac[[r]][elig], stop_at_zero = TRUE)
  fac <- elig[s1$sel]
  s2 <- greedy(s1$unc, D, nb_cs[[r]])
  list(gap = gap, fac = fac, fac_action = action[fac], new = s2$sel, left_after_s1 = sum(s1$unc))
}
B <- run_gap(D0); gap0 <- B$gap
cat("gap sites:", sum(gap0), "of", nC, "| all-day:", sum(gap0 & !cov14), "| evening-only:", sum(gap0 & cov14), "\n")
cat("stage 1 existing facilities:", length(B$fac), "->", table(B$fac_action), "| gap sites left:", B$left_after_s1,
    "| stage 2 new units:", length(B$new), "\n")
# how much of the gap stage 1 closes, and the diminishing returns
boro_c <- P$nta$boroname[match(cand$nta2020, P$nta$nta2020)]
sup_nta <- P$nta$ntaname[st_nearest_feature(sup, P$nta)]; sup_boro <- P$nta$boroname[st_nearest_feature(sup, P$nta)]
cum <- cumsum(vapply(seq_along(B$fac), function(k) { prev <- if (k == 1) integer(0) else unique(unlist(nb_fac$`500`[B$fac[1:(k - 1)]]))
  sum(setdiff(nb_fac$`500`[[B$fac[k]]], prev) %in% which(gap0)) }, 0L))
cat("stage 1 covers", tail(cum, 1), "gap sites; first 50 facilities cover", cum[min(50, length(cum))], "\n")
Fac <- data.table(order = seq_along(B$fac), facility_id = sup$facility_id[B$fac], facility_name = sup$facility_name[B$fac], operator = sup$operator[B$fac],
                  action = B$fac_action, ntaname = sup_nta[B$fac], borough = sup_boro[B$fac], gap_sites_newly_covered = diff(c(0, cum)),
                  cumulative_gap_sites = cum)
ll <- st_coordinates(st_transform(sup[B$fac, ], 4326)); Fac[, `:=`(lon = round(ll[, 1], 5), lat = round(ll[, 2], 5))]
New <- cbind(cand[B$new, .(ntaname, type, lon = round(lon, 5), lat = round(lat, 5), residents = round(residents))],
             borough = boro_c[B$new], demand_pct = round(100 * D0[B$new]), gap_type = ifelse(cov14[B$new], "evening-only", "all-day"))
print(table(Fac$action)); print(table(Fac$borough)); print(table(New$borough))
# independent check: all chosen facilities (after intervention) + new units cover every gap site
ok_after <- open_at(21); ok_after[B$fac] <- TRUE
chk <- covered(ok_after, nb_sup$`500`) | vapply(seq_len(nC), function(i) any(nb_cs$`500`[[i]] %in% B$new), TRUE)
stopifnot(all(chk[gap0]))
cat("check: every gap site covered by the chosen facilities + new units\n")

# ---- 5. sensitivity ----------------------------------------------------------------------------------------------
fac_hit <- function(o) B$fac %in% o$fac                                   # exact facility retained
near_new <- nb_cs$`500`[B$new]
new_hit <- function(o) vapply(near_new, function(nb) any(o$new %in% nb), TRUE)   # area-level within 500 m
summ <- function(o) data.table(gap_sites = sum(o$gap), existing = length(o$fac), repair = sum(o$fac_action == "Repair or reopen"),
                               park_hours = sum(o$fac_action == "Keep park restroom open to 10pm"),
                               other_hours = sum(o$fac_action == "Extend other operator's hours"), new_units = length(o$new))
RW <- list(); FH <- list(); NH <- list()
cat("sensitivity: random demand weights (200 runs)...\n")
for (r in 1:200) { g <- rgamma(4, 1); w4 <- g / sum(g); we_r <- runif(1, 0, 0.5)
  o <- run_gap(pct(demand_raw(Zc, w4, 1 - we_r, we_r))); RW[[r]] <- summ(o); FH[[r]] <- fac_hit(o); NH[[r]] <- new_hit(o) }
RW <- rbindlist(RW)
cat("sensitivity: settings grid...\n")
SG <- list()
for (thr in c(0.5, 2 / 3, 0.75)) for (hour in c(20, 21, 22)) for (rad in c(400, 500)) for (ph in c(16, 22)) {
  if (hour == 22 && ph == 22) next                                       # identical to ph 16 at 10pm
  o <- run_gap(D0, thr, hour, rad, ph); SG[[length(SG) + 1]] <- cbind(data.table(threshold = round(thr, 2), hour, radius = rad, park_close = ph), summ(o)) }
SG <- rbindlist(SG); print(SG)
Fac$kept_random_weights <- round(rowMeans(do.call(cbind, FH)), 2)
New$area_kept_random_weights <- round(rowMeans(do.call(cbind, NH)), 2)
cat("random weights: existing", paste(range(RW$existing), collapse = "-"), "(median", median(RW$existing), ") | new units",
    paste(range(RW$new_units), collapse = "-"), "(median", median(RW$new_units), ")\n")
cat("base facilities kept in >=80% of random-weight runs:", sum(Fac$kept_random_weights >= .8), "of", nrow(Fac),
    "| new-unit areas kept (500 m) in >=80%:", sum(New$area_kept_random_weights >= .8), "of", nrow(New), "\n")

fwrite(Fac, file.path(CM, "outputs/gap_existing_facilities.csv")); fwrite(New, file.path(CM, "outputs/gap_new_units.csv"))
fwrite(SG, file.path(CM, "outputs/gap_sensitivity_settings.csv")); fwrite(RW, file.path(CM, "outputs/gap_sensitivity_random_weights.csv"))
saveRDS(list(D0 = D0, gap0 = gap0, cov14 = cov14, cov21 = cov21, B = B, Fac = Fac, New = New, WD = WD, M7 = M7, loo = loo,
             pc_pil = pc_pil, pil9 = pil9, pil2 = pil2, RW = RW, SG = SG, cum = cum),
        file.path(CM, "cache/gap.rds"))
