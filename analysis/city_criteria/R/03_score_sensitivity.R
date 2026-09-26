# 03_score_sensitivity.R -- score every candidate site on the six LL58 factors, pick the next N sites under many
# weightings, and report which neighbourhoods are chosen regardless of the weights (the professor's robustness test).
# Score = sum_k w_k * percentile_k (percentile among all candidate sites; distance: farther from an open restroom = higher).
# Selection: greedy top score with 500 m spacing from already-selected sites and from the 17 pilot sites.
# Then a reality lens per selected site: repair / longer hours / build, from the restroom register + Parks inspections.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(data.table)})
sf_use_s2(FALSE)
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
FT <- 0.3048006096; M2FT <- function(m) m / FT
F0 <- readRDS(file.path(CM, "cache/features.rds")); X <- F0$X; sites <- F0$sites
W <- readRDS(file.path(CM, "cache/fits.rds"))
P <- readRDS(file.path(BASE, "Build_Plan/prototype/cache/prep.rds"))
set.seed(6093)
N_PICK <- 50; N_RANDOM <- 2000
QUOTA <- Sys.getenv("QUOTA") == "1"; SUF <- if (QUOTA) "_borough_quota" else ""

LAW <- W$LAW; K <- names(LAW)
cand <- X[pilot == 0]; cs <- sites[X$pilot == 0, ]
pr <- sapply(LAW, function(f) frank(cand[[f]], ties.method = "average") / nrow(cand)); colnames(pr) <- K

# ---- weight scenarios ------------------------------------------------------------------------------------------
# revealed weights from the preferred model M4 (02b_robustness.R): busyness (split equally over population, foot traffic,
# transit, land use), distance to an open restroom, equity; site type is a control and does not enter the score
M4 <- readRDS(file.path(CM, "cache/fit_M4.rds"))
to6 <- function(b3) { b3 <- pmax(b3, 0); if (sum(b3) == 0) b3 <- c(1, 1, 1); b3 <- b3 / sum(b3)
  setNames(c(rep(b3[1] / 4, 4), b3[2], b3[3]), K) }
rev <- to6(M4$coef)
named <- list(
  revealed_by_pilots = rev,
  equal_law_factors  = setNames(rep(1 / 6, 6), K),
  footfall_heavy     = setNames(c(.12, .40, .12, .12, .12, .12), K),
  transit_heavy      = setNames(c(.12, .12, .40, .12, .12, .12), K),
  equity_heavy       = setNames(c(.12, .12, .12, .12, .12, .40), K),
  access_heavy       = setNames(c(.12, .12, .12, .12, .40, .12), K),
  no_population      = setNames(c(0, .2, .2, .2, .2, .2), K))
# (a) uncertainty in the revealed weights: draw coefficients from their fitted covariance, keep the positive part
L3 <- t(chol(M4$var))
draws_rev <- lapply(seq_len(N_RANDOM), function(i) to6(as.vector(M4$coef + L3 %*% rnorm(3))))
# (b) any weighting at all: uniform over all weight combinations (Dirichlet(1,...,1))
draws_any <- lapply(seq_len(N_RANDOM), function(i) { g <- rgamma(6, 1); setNames(g / sum(g), K) })

pil <- P$pil
blocked0 <- lengths(st_is_within_distance(cs, pil, dist = M2FT(500))) > 0
nb <- st_is_within_distance(cs, cs, dist = M2FT(500))
boro <- P$nta$boroname[match(cand$nta2020, P$nta$nta2020)]
BPOP <- c(Bronx = 1404779, Brooklyn = 2631580, Manhattan = 1629477, Queens = 2323052, `Staten Island` = 494956)  # ACS 2020-24 tract totals by borough
QN <- round(N_PICK * BPOP / sum(BPOP)); QN[which.max(QN)] <- QN[which.max(QN)] + N_PICK - sum(QN)
pick <- function(w) {
  s <- as.vector(pr %*% w[K]); o <- order(-s)
  blocked <- blocked0; sel <- integer(0); got <- setNames(integer(5), names(BPOP))
  for (i in o) { if (blocked[i]) next; if (QUOTA && got[boro[i]] >= QN[boro[i]]) next
    sel <- c(sel, i); got[boro[i]] <- got[boro[i]] + 1L; blocked[nb[[i]]] <- TRUE; if (length(sel) == N_PICK) break }
  sel
}
run <- function(ws) { sels <- lapply(ws, pick); sels }
cat("running named scenarios...\n"); S_named <- run(named)
cat("running", N_RANDOM, "revealed-uncertainty draws and", N_RANDOM, "any-weight draws...\n")
S_rev <- run(draws_rev); S_any <- run(draws_any)

nta_hits <- function(sels) { h <- table(unlist(lapply(sels, function(s) unique(cand$ntaname[s])))); h / length(sels) }
site_hits <- function(sels) tabulate(unlist(sels), nbins = nrow(cand)) / length(sels)
H <- data.table(ntaname = sort(unique(cand$ntaname)))
H[, share_revealed_draws := as.numeric(nta_hits(S_rev)[ntaname])]
H[, share_any_weights := as.numeric(nta_hits(S_any)[ntaname])]
for (nm in names(named)) H[, (nm) := ntaname %in% unique(cand$ntaname[S_named[[nm]]])]
H[is.na(share_revealed_draws), share_revealed_draws := 0]; H[is.na(share_any_weights), share_any_weights := 0]
H[, named_count := rowSums(.SD), .SDcols = names(named)]
H <- H[share_revealed_draws > 0 | share_any_weights > 0 | named_count > 0][order(-share_revealed_draws, -share_any_weights)]
H[, stability := fifelse(share_revealed_draws >= 0.8 & share_any_weights >= 0.5, "robust",
                  fifelse(share_revealed_draws >= 0.8, "robust to model uncertainty only",
                  fifelse(share_revealed_draws >= 0.5, "depends on weights", "weak")))]
print(table(H$stability))

# ---- site level: the revealed-weight picks, with stability and the reality lens ---------------------------------------
sel <- S_named$revealed_by_pilots
sh_rev <- site_hits(S_rev); sh_any <- site_hits(S_any)
# stability of a location = share of draws picking any site within 500 m of it (sites shift a little between runs)
near <- st_is_within_distance(cs[sel, ], cs, dist = M2FT(500))
loc_share <- function(sels) vapply(near, function(nb) mean(vapply(sels, function(s) any(s %in% nb), TRUE)), 0)
sup <- P$sup
open_at <- function(h) { cl <- ifelse(sup$placeholder, 16, sup$w_close); sup$operational & sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h }
o14 <- open_at(14); o21 <- open_at(21)
nb_sup <- st_is_within_distance(cs[sel, ], sup, dist = M2FT(500))
lens <- rbindlist(lapply(seq_along(sel), function(k) {
  j <- nb_sup[[k]]
  broken <- j[sup$removed_closed[j] | sup$removed_fail[j] | sup$reopen_add[j]]
  open2  <- j[o14[j] & !(sup$removed_closed[j] | sup$removed_fail[j])]
  ext    <- open2[sup$placeholder[open2]]
  data.table(n_open_2pm_500m = length(open2), n_open_9pm_500m = sum(o21[j]), n_park_placeholder_500m = length(ext),
             n_broken_500m = length(broken), broken_names = paste(unique(sup$facility_name[broken]), collapse = "; "))
}))
S <- cbind(cand[sel, .(ntaname, type, lon = round(lon, 5), lat = round(lat, 5), residents = round(residents), subway, dist_2pm_m = round(dist_2pm_m), dist_9pm_m = round(dist_9pm_m), poverty = round(poverty, 3))],
           lens, stable_revealed = round(loc_share(S_rev), 2), stable_any = round(loc_share(S_any), 2))
S[, rank := .I]
S[, reality_lens := fifelse(n_broken_500m > 0, "Repair or reopen nearby first",
                    fifelse(n_open_2pm_500m > 0 & n_open_9pm_500m == 0 & n_park_placeholder_500m > 0, "Extend park hours nearby first",
                    fifelse(n_open_2pm_500m > 0 & n_open_9pm_500m == 0, "Existing restroom closes early: extend other operator's hours",
                    fifelse(n_open_2pm_500m == 0, "Build: no restroom within 500 m", "Covered day and evening: lower priority"))))]
print(table(S$reality_lens)); S[, borough := boro[sel]]; print(table(S$borough))

fwrite(H, file.path(CM, paste0("outputs/sensitivity_neighbourhoods", SUF, ".csv")))
fwrite(S, file.path(CM, paste0("outputs/next50_sites_revealed", SUF, ".csv")))
fwrite(rbindlist(lapply(names(named), function(n) data.table(scenario = n, t(round(named[[n]], 2))))), file.path(CM, paste0("outputs/weight_scenarios", SUF, ".csv")))
# overlap of the named scenarios with the revealed pick (same place = within 500 m)
ov <- sapply(S_named, function(s) mean(vapply(near, function(nb) any(s %in% nb), TRUE)))
print(round(ov, 2))
fwrite(data.table(scenario = names(ov), share_of_revealed_sites_also_picked = round(ov, 2)), file.path(CM, paste0("outputs/scenario_overlap", SUF, ".csv")))
saveRDS(list(S_named = S_named, sel = sel, H = H, S = S), file.path(CM, paste0("cache/selection", SUF, ".rds")))
cat("stable sites (>=80% of revealed draws):", sum(S$stable_revealed >= .8), "of", N_PICK,
    "| also >=50% of any-weight draws:", sum(S$stable_revealed >= .8 & S$stable_any >= .5), "\n")
