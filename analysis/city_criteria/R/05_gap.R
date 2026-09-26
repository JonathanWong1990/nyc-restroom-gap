# 05_gap.R -- DEMAND minus SUPPLY (owner-approved spine, 26 Sep 2026).
#  1. Pilot model (M7): chosen (1) vs not (0) ~ busyness + distance to a restroom open at 2pm + at 9pm + equity + site type.
#     Demand weights come from the demand terms (busyness, equity); supply enters through the two distances.
#  2. Demand score at every candidate site; SUPPLY = listed restrooms by time of day (500 m).
#  3. GAP site = top third of demand AND no restroom open within 500 m at 9pm (evening), and not within 500 m of a pilot unit.
#     Types: all-day gap (none open at 2pm either) vs evening-only gap (a restroom nearby by day, closed by 9pm).
#  4. How many sites close the gap: greedy maximal covering -- place a unit at the candidate covering the most uncovered
#     gap demand within 500 m, repeat until every gap site is covered. N comes out of the data.
#  5. What each chosen site needs first: repair (broken restroom nearby) / extend hours (restroom nearby by day) / build.
#  6. Sensitivity: random demand weights, demand threshold, evening hour, radius, park-hours assumption.
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

# ---- 2. demand at every candidate site ----------------------------------------------------------------------------
cand <- X[pilot == 0]; cs <- sites[X$pilot == 0, ]; nC <- nrow(cand)
Zc <- mk(cand, d)
comp <- as.matrix(Zc[, .(z_pop, z_ped, z_sub, z_job)])
demand_raw <- function(wbusy4 = rep(.25, 4), wb = WD[1], we = WD[2]) as.vector(wb * (comp %*% wbusy4) + we * Zc$z_pov)
pct <- function(v) frank(v, ties.method = "average") / length(v)
D0 <- pct(demand_raw())

# ---- supply by time of day ---------------------------------------------------------------------------------------
open_at <- function(h, ph_close = 16) { cl <- ifelse(sup$placeholder, ph_close, sup$w_close)
  sup$operational & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h }
nb_sup500 <- st_is_within_distance(cs, sup, dist = M2FT(500)); nb_sup400 <- st_is_within_distance(cs, sup, dist = M2FT(400))
covered <- function(ok, nb) vapply(nb, function(j) any(ok[j]), TRUE)
pil_block500 <- lengths(st_is_within_distance(cs, P$pil, dist = M2FT(500))) > 0
pil_block400 <- lengths(st_is_within_distance(cs, P$pil, dist = M2FT(400))) > 0
nb500 <- st_is_within_distance(cs, cs, dist = M2FT(500)); nb400 <- st_is_within_distance(cs, cs, dist = M2FT(400))
cov14 <- covered(open_at(14), nb_sup500); cov21 <- covered(open_at(21), nb_sup500)
cat("candidate sites covered within 500 m: 2pm", round(mean(cov14), 3), "| 9pm", round(mean(cov21), 3), "\n")
pc_pil <- sapply(seq_len(17), function(i) mean(demand_raw() <= as.vector(WD[1] * (as.matrix(mk(X[pilot == 1][i], d)[, .(z_pop, z_ped, z_sub, z_job)]) %*% rep(.25, 4)) + WD[2] * mk(X[pilot == 1][i], d)$z_pov)))
pil9 <- X[pilot == 1]$dist_9pm_m > 500; pil2 <- X[pilot == 1]$dist_2pm_m > 500
cat("pilots: top-third demand", sum(pc_pil >= 2 / 3), "| no 9pm restroom", sum(pil9), "| both (in our gap definition)", sum(pc_pil >= 2 / 3 & pil9),
    "| no 2pm restroom", sum(pil2), "\n")

# ---- 3-4. gap and greedy cover -----------------------------------------------------------------------------------
greedy <- function(gap, w, nb) {           # cover every gap site; unit may go on any candidate site
  unc <- gap; gain <- vapply(nb, function(j) sum(w[j][unc[j]]), 0); sel <- integer(0)
  while (any(unc)) {
    i <- which.max(gain); sel <- c(sel, i)
    newly <- nb[[i]][unc[nb[[i]]]]; unc[newly] <- FALSE
    touched <- unique(unlist(nb[newly])); gain[touched] <- vapply(nb[touched], function(j) sum(w[j][unc[j]]), 0)
  }
  sel
}
run_gap <- function(D, thr = 2 / 3, hour = 21, rad = 500, ph_close = 16) {
  nbs <- if (rad == 500) nb_sup500 else nb_sup400; nbc <- if (rad == 500) nb500 else nb400
  blk <- if (rad == 500) pil_block500 else pil_block400
  ce <- covered(open_at(hour, ph_close), nbs)
  gap <- D >= thr & !ce & !blk
  list(gap = gap, sel = greedy(gap, D, nbc))
}
B <- run_gap(D0); gap0 <- B$gap; sel0 <- B$sel
cat("gap sites:", sum(gap0), "of", nC, "| all-day:", sum(gap0 & !cov14), "| evening-only:", sum(gap0 & cov14), "\n")
cat("sites needed to cover every gap site:", length(sel0), "\n")

# ---- 5. what each chosen site needs first --------------------------------------------------------------------------
o14 <- open_at(14); o21 <- open_at(21)
fix <- rbindlist(lapply(sel0, function(i) {
  j <- nb_sup500[[i]]
  broken <- j[sup$removed_closed[j] | sup$removed_fail[j] | sup$reopen_add[j]]
  day <- j[o14[j] & !o21[j] & !(sup$removed_closed[j] | sup$removed_fail[j])]
  data.table(n_broken = length(broken), n_day_only = length(day), n_day_only_park = sum(sup$placeholder[day]),
             broken_names = paste(unique(sup$facility_name[broken]), collapse = "; "),
             day_names = paste(unique(sup$facility_name[day]), collapse = "; "))
}))
boro <- P$nta$boroname[match(cand$nta2020, P$nta$nta2020)]
S <- cbind(cand[sel0, .(ntaname, type, lon = round(lon, 5), lat = round(lat, 5), residents = round(residents), subway, jobs = round(jobs),
                        dist_2pm_m = round(dist_2pm_m), dist_9pm_m = round(dist_9pm_m), poverty = round(poverty, 3))],
           borough = boro[sel0], demand_pct = round(100 * D0[sel0]), gap_type = ifelse(cov14[sel0], "evening-only", "all-day"), fix)
S[, first_action := fifelse(n_broken > 0, "Repair or reopen nearby",
                    fifelse(n_day_only_park > 0, "Keep a nearby park restroom open later",
                    fifelse(n_day_only > 0, "Extend another operator's hours", "Build a new unit")))]
S[, order := .I]
print(table(S$first_action)); print(table(S$borough)); print(table(S$gap_type))

# ---- 6. sensitivity ----------------------------------------------------------------------------------------------
near0 <- nb500[sel0]
loc_hit <- function(sel) vapply(near0, function(nb) any(sel %in% nb), TRUE)
R <- list()
cat("sensitivity: random demand weights...\n")
for (r in 1:300) { g <- rgamma(4, 1); w4 <- g / sum(g); we_r <- runif(1, 0, 0.5)
  D <- pct(demand_raw(w4, 1 - we_r, we_r)); o <- run_gap(D)
  R[[length(R) + 1]] <- list(kind = "random weights", n = length(o$sel), hit = loc_hit(o$sel)) }
cat("sensitivity: settings grid...\n")
for (thr in c(0.5, 2 / 3, 0.75)) for (hour in c(20, 21, 22)) for (rad in c(400, 500)) for (ph in c(16, 22)) {
  o <- run_gap(D0, thr, hour, rad, ph)
  R[[length(R) + 1]] <- list(kind = "settings", thr = thr, hour = hour, rad = rad, ph = ph, n = length(o$sel), hit = loc_hit(o$sel), ngap = sum(o$gap)) }
rw <- Filter(function(x) x$kind == "random weights", R); sg <- Filter(function(x) x$kind == "settings", R)
S$stable_weights <- round(rowMeans(sapply(rw, `[[`, "hit")), 2)
S$stable_settings <- round(rowMeans(sapply(sg, `[[`, "hit")), 2)
nrw <- sapply(rw, `[[`, "n"); cat("N under random weights: median", median(nrw), "range", range(nrw), "\n")
SG <- rbindlist(lapply(sg, function(x) data.table(threshold = round(x$thr, 2), hour = x$hour, radius = x$rad, park_close = x$ph, gap_sites = x$ngap, sites_needed = x$n,
                                                  share_of_base_locations = round(mean(x$hit), 2))))
print(SG[order(threshold, hour, radius, park_close)])
cat("locations hit in >=80% of random-weight runs:", sum(S$stable_weights >= .8), "of", nrow(S),
    "| >=50% of settings runs:", sum(S$stable_settings >= .5), "| both:", sum(S$stable_weights >= .8 & S$stable_settings >= .5), "\n")
# chance baseline: same number of sites placed at random candidates (spaced 500 m)
rnd <- replicate(300, { o <- sample(nC); b <- rep(FALSE, nC); s <- integer(0)
  for (i in o) { if (b[i]) next; s <- c(s, i); b[nb500[[i]]] <- TRUE; if (length(s) == length(sel0)) break }; mean(loc_hit(s)) })
cat("chance: share of base locations hit by the same number of random sites:", round(mean(rnd), 3), "\n")

fwrite(S, file.path(CM, "outputs/gap_sites_selected.csv")); fwrite(SG, file.path(CM, "outputs/gap_sensitivity_settings.csv"))
fwrite(data.table(run = seq_along(nrw), sites_needed = nrw), file.path(CM, "outputs/gap_sensitivity_random_weights.csv"))
saveRDS(list(D0 = D0, gap0 = gap0, cov14 = cov14, cov21 = cov21, sel0 = sel0, S = S, WD = WD, M7 = M7, loo = loo,
             pc_pil = pc_pil, pil9 = pil9, pil2 = pil2, chance = mean(rnd), nrw = nrw, SG = SG),
        file.path(CM, "cache/gap.rds"))
