# 02_greedy.R -- greedy maximal covering per demand objective x hour x supply scenario, consensus by NTA,
# radius sensitivity, fix/hours-vs-build, pilot comparison, complaint-route validation.
# Reads cache/prep.rds (01_prep.R) and Restroom_Rebuild/data_raw/model_nta_scored_20260920.csv (read-only).
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(sf); library(dplyr); library(data.table); library(Matrix); library(ggplot2)})
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"
PT   <- file.path(BASE, "Build_Plan/prototype"); OUT <- file.path(PT, "outputs")
P <- readRDS(file.path(PT, "cache/prep.rds"))
cand <- P$cand; sup <- P$sup; OBJ <- names(P$demand)
K_MAX <- 1145; K_TOP <- 100
SIX <- c("East Harlem (North)", "Astoria (East)-Woodside (North)", "East Elmhurst",
         "Williamsbridge-Olinville", "Brighton Beach", "Midtown-Times Square")
t0 <- Sys.time()

# ---- supply: which supply points are open at hour h ----------------------------------------
# set = "base"   : operational & open at h (C2 rule, Wednesday)
#       "strict" : base minus PIP long-term-closed matches minus repeatedly-failing matches
# extra flags for the fix-vs-build question: restore_closed, fix_fail, extend (placeholder close -> 22:00)
open_vec <- function(h, ph_close, set = "base", restore_closed = FALSE, fix_fail = FALSE, extend = FALSE) {
  cl <- ifelse(sup$placeholder, if (extend) 22 else ph_close, sup$w_close)
  op <- sup$w_ok & !is.na(sup$w_open) & sup$w_open <= h & cl > h
  inset <- sup$operational
  if (set == "strict") inset <- inset & !sup$removed_closed & !sup$removed_fail
  if (restore_closed) inset <- inset | sup$removed_closed | sup$reopen_add
  if (fix_fail) inset <- inset | sup$removed_fail
  op & inset
}
cov_existing <- function(o, rad, ov) {
  s <- P$inc[[paste0(o, "_", rad)]]$supply
  vapply(s, function(x) any(ov[x]), TRUE)
}

# ---- greedy maximal covering -----------------------------------------------------------------
build_mats <- function(cl, nd) {
  i <- rep(seq_along(cl), lengths(cl)); j <- unlist(cl)
  list(A = sparseMatrix(i = j, j = i, x = 1, dims = c(nd, length(cl))),     # demand x cand
       B = sparseMatrix(i = i, j = j, x = 1, dims = c(length(cl), nd)))     # cand x demand
}
MATS <- list()
greedy <- function(o, rad, cov0, K) {
  key <- paste0(o, "_", rad)
  if (is.null(MATS[[key]])) MATS[[key]] <<- build_mats(P$inc[[key]]$cand, length(P$demand[[o]]$w))
  A <- MATS[[key]]$A; B <- MATS[[key]]$B
  w <- P$demand[[o]]$w; wr <- w * !cov0
  gain <- as.vector(crossprod(A, wr))
  eps <- 1e-9 * sum(w)
  sel <- integer(0); gs <- numeric(0)
  for (k in seq_len(K)) {
    jb <- which.max(gain)
    if (gain[jb] <= eps) break
    d <- A@i[(A@p[jb] + 1):A@p[jb + 1]] + 1L
    d <- d[wr[d] > 0]
    gs <- c(gs, sum(wr[d])); sel <- c(sel, jb)
    gain <- gain - as.vector(B[, d, drop = FALSE] %*% wr[d])
    wr[d] <- 0
  }
  list(sel = sel, gain = gs, base_cov = sum(w * cov0), total = sum(w))
}

CONF <- data.frame(conf = c("base_14", "base_21_off", "base_21_in", "strict_14", "strict_21_off", "strict_21_in"),
                   set = rep(c("base", "strict"), each = 3), hour = rep(c(14, 21, 21), 2),
                   ph_close = rep(c(16, 16, 20), 2))
PRIMARY <- c("base_14", "base_21_off")
runs <- list(); curves <- list()
for (o in OBJ) for (ci in seq_len(nrow(CONF))) {
  cf <- CONF[ci, ]
  ov <- open_vec(cf$hour, cf$ph_close, cf$set)
  cov0 <- cov_existing(o, 500, ov)
  g <- greedy(o, 500, cov0, K_MAX)
  id <- paste(o, cf$conf, sep = "|")
  runs[[id]] <- c(g, list(objective = o, conf = cf$conf, n_open = sum(ov), cov0 = cov0))
  cum <- g$base_cov + c(0, cumsum(g$gain))
  kk <- 0:K_MAX
  share <- cum[pmin(kk + 1, length(cum))]                 # flat after saturation
  curves[[id]] <- data.frame(objective = o, config = cf$conf, supply = cf$set, hour = cf$hour,
                             placeholder_close = cf$ph_close, existing_open_restrooms = sum(ov),
                             n_new_sites = kk, share_covered = round(share / g$total, 5))
}
cat("greedy runs:", length(runs), " in", round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")
cc <- do.call(rbind, curves)
stopifnot(all(sapply(curves, function(x) all(diff(x$share_covered) >= -1e-9) && all(x$share_covered <= 1 + 1e-9))))
# greedy gains must be non-increasing (submodularity sanity check)
stopifnot(all(sapply(runs, function(g) all(diff(g$gain) <= 1e-6 * g$total))))
fwrite(cc, file.path(OUT, "coverage_curves.csv"))
# At 21:00 the placeholder close (16:00 vs 20:00) and the closed/failing removals cannot matter: every affected
# restroom is closed by 21:00 either way. Verify the runs are identical rather than assume it.
same21 <- sapply(OBJ, function(o) {
  s0 <- runs[[paste(o, "base_21_off", sep = "|")]]$sel
  all(sapply(c("base_21_in", "strict_21_off", "strict_21_in"), function(cf) identical(runs[[paste(o, cf, sep = "|")]]$sel, s0)))
})
cat("9pm runs identical across off/in-season and base/strict supply:", paste(names(same21), same21, collapse = ", "), "\n")
DISTINCT <- c("base_14", "strict_14", if (all(same21)) "base_21_off" else CONF$conf[CONF$hour == 21])

# ---- first-100 site lists ----------------------------------------------------------------------
nta_tab <- st_drop_geometry(P$nta)[, c("nta2020", "ntaname", "boroname", "ntatype")]
for (o in OBJ) {
  f <- do.call(rbind, lapply(CONF$conf, function(cf) {
    g <- runs[[paste(o, cf, sep = "|")]]; n <- min(K_TOP, length(g$sel))
    x <- st_drop_geometry(cand[g$sel[seq_len(n)], c("cand_id", "type", "lat", "lon", "nta_raw", "nta")])
    data.frame(objective = o, config = cf, rank = seq_len(n), x,
               new_demand_covered = round(g$gain[seq_len(n)], 1), unit = P$demand[[o]]$unit,
               cum_share_covered = round((g$base_cov + cumsum(g$gain[seq_len(n)])) / g$total, 5))
  }))
  f$ntaname <- nta_tab$ntaname[match(f$nta, nta_tab$nta2020)]
  f$ntaname_raw <- nta_tab$ntaname[match(f$nta_raw, nta_tab$nta2020)]
  f$primary <- f$config %in% PRIMARY
  fwrite(f, file.path(OUT, sprintf("first100_sites_%s.csv", o)))
}

# ---- consensus by NTA --------------------------------------------------------------------------
nta_hits <- function(rl) {        # rl: named list of runs -> long table NTA x run with #sites in first 100
  rbindlist(lapply(names(rl), function(id) {
    s <- rl[[id]]$sel[seq_len(min(K_TOP, length(rl[[id]]$sel)))]
    data.table(run = id, nta = cand$nta[s])[, .(n_sites = .N), by = .(run, nta)]
  }))
}
rank_consensus <- function(h_primary, h_all = NULL) {
  a <- h_primary[, .(runs_primary = uniqueN(run), sites_primary = sum(n_sites)), by = nta]
  if (!is.null(h_all)) a <- merge(a, h_all[, .(runs_all = uniqueN(run), sites_all = sum(n_sites)), by = nta], by = "nta", all = TRUE)
  a[is.na(runs_primary), `:=`(runs_primary = 0L, sites_primary = 0L)]
  setorder(a, -runs_primary, -sites_primary)
  a[, rank := .I][]
}
prim_ids <- names(runs)[sub(".*\\|", "", names(runs)) %in% PRIMARY]
stopifnot(length(prim_ids) == 8)
H_prim <- nta_hits(runs[prim_ids])
H_all  <- nta_hits(runs[sub(".*\\|", "", names(runs)) %in% DISTINCT])      # distinct runs only (no duplicates)
cons <- rank_consensus(H_prim, H_all)
setorder(cons, rank)
cons <- merge(cons, as.data.table(nta_tab), by.x = "nta", by.y = "nta2020", all.x = TRUE)
# per-objective/hour detail columns (sites in first 100)
det <- dcast(H_prim[, .(nta, run = gsub("\\|", "_", run), n_sites)], nta ~ run, value.var = "n_sites", fill = 0)
cons <- merge(cons, det, by = "nta", all.x = TRUE)
sc <- fread(file.path(BASE, "Restroom_Rebuild/data_raw/model_nta_scored_20260920.csv"))
stopifnot(!anyDuplicated(sc$nta2020), nrow(sc) == 197)
sc[, ratio_rank := frank(-resid_ratio, ties.method = "min")]
cons <- merge(cons, sc[, .(nta = nta2020, resid_ratio = round(resid_ratio, 3), ratio_rank, events_311)], by = "nta", all.x = TRUE)
cons[, high_complaint_six := ntaname %in% SIX]
setorder(cons, rank)
stopifnot(all(SIX %in% nta_tab$ntaname))
fwrite(cons, file.path(OUT, "consensus_nta.csv"))
top20 <- cons$nta[1:20]

# ---- radius sensitivity (400 / 500 / 750 m), primary 8 runs, first 100 --------------------------
CR <- list(`500` = rank_consensus(H_prim)); rs_rows <- list(); top_by_r <- list(`500` = top20); runs_r <- list()
for (rad in c(400, 750)) {
  rl <- list()
  for (o in OBJ) for (cf in PRIMARY) {
    c1 <- CONF[CONF$conf == cf, ]
    ov <- open_vec(c1$hour, c1$ph_close, c1$set)
    rl[[paste(o, cf, sep = "|")]] <- greedy(o, rad, cov_existing(o, rad, ov), K_TOP)
  }
  runs_r[[as.character(rad)]] <- rl
  cr <- rank_consensus(nta_hits(rl))
  top_by_r[[as.character(rad)]] <- cr$nta[1:20]
  CR[[as.character(rad)]] <- cr
}
rsens <- data.frame(radius_m = c(400, 500, 750),
  top20_overlap_with_500m = sapply(c("400", "500", "750"), function(k) length(intersect(top_by_r[[k]], top20))),
  top20_ntas = sapply(c("400", "500", "750"), function(k) paste(nta_tab$ntaname[match(top_by_r[[k]], nta_tab$nta2020)], collapse = "; ")),
  candidate_grid = "same 150 m candidate set as the 500 m run (no coarsening needed)")
# ties at the 20th place make a strict top-20 cut fragile: also count 500 m top-20 NTAs that score at least
# the 20th-place (runs, sites) at the other radius
tie_in <- function(k) { cr <- CR[[k]]; c20 <- cr[20]
  ok <- cr[runs_primary > c20$runs_primary | (runs_primary == c20$runs_primary & sites_primary >= c20$sites_primary)]$nta
  c(n_tied_at_20th = nrow(cr[runs_primary == c20$runs_primary & sites_primary == c20$sites_primary]),
    overlap_tie_inclusive = length(intersect(top20, ok))) }
ti <- t(sapply(c("400", "500", "750"), tie_in))
rsens$n_ntas_tied_at_20th_place <- ti[, 1]; rsens$top20_overlap_tie_inclusive <- ti[, 2]
rsens <- rsens[, c(1, 2, 6, 5, 3, 4)]
fwrite(rsens, file.path(OUT, "radius_sensitivity.csv"))
print(rsens[, 1:2])

# ---- pilot 17 vs greedy first 17 ---------------------------------------------------------------
pil_rows <- list()
for (o in OBJ) for (cf in c("base_14", "base_21_off")) {
  g <- runs[[paste(o, cf, sep = "|")]]; w <- P$demand[[o]]$w
  pc <- unique(unlist(P$inc[[paste0(o, "_500")]]$pilot))
  pil_gain <- sum(w[pc][!g$cov0[pc]])
  pil_rows[[length(pil_rows) + 1]] <- data.frame(objective = o, config = cf, unit = P$demand[[o]]$unit,
    existing_share = round(g$base_cov / g$total, 4),
    pilot17_new_covered = round(pil_gain), pilot17_share_pts = round(100 * pil_gain / g$total, 2),
    greedy17_new_covered = round(sum(g$gain[1:min(17, length(g$gain))])),
    greedy17_share_pts = round(100 * sum(g$gain[1:min(17, length(g$gain))]) / g$total, 2))
}
pilot_cmp <- do.call(rbind, pil_rows)
pilot_cmp$pilot_as_pct_of_greedy <- round(100 * pilot_cmp$pilot17_new_covered / pilot_cmp$greedy17_new_covered, 1)
fwrite(pilot_cmp, file.path(OUT, "pilot_vs_greedy17.csv"))

# ---- fix / hours before build -------------------------------------------------------------------
share <- function(o, cov) { w <- P$demand[[o]]$w; sum(w * cov) / sum(w) }
fx <- list()
for (o in OBJ) for (cf in c("14_off", "21_off")) {
  h <- as.numeric(sub("_.*", "", cf)); pc <- if (grepl("in", cf)) 20 else 16
  S <- function(...) share(o, cov_existing(o, 500, open_vec(h, pc, ...)))
  base <- S("base"); strict <- S("strict")
  reopen <- S("strict", restore_closed = TRUE); fixf <- S("strict", fix_fail = TRUE)
  ext_all <- S("base", extend = TRUE)   # all 641 placeholder restrooms (number check 25 Sep)
  ext <- S("strict", extend = TRUE); allfix <- S("strict", restore_closed = TRUE, fix_fail = TRUE, extend = TRUE)
  conf_s <- if (h == 14) "strict_14" else paste0("strict_21_", sub(".*_", "", cf))
  g <- runs[[paste(o, conf_s, sep = "|")]]
  b100 <- sum(g$gain[1:min(100, length(g$gain))]) / g$total
  stopifnot(abs(g$base_cov / g$total - strict) < 1e-9)
  fx[[length(fx) + 1]] <- data.frame(objective = o, hour = h, placeholder_close = pc,
    share_base_listed_operational = base, share_strict_quality_supply = strict,
    loss_if_closed_and_failing_removed_pts = 100 * (base - strict),
    gain_reopen_long_term_closed_pts = 100 * (reopen - strict),
    gain_fix_failing_pts = 100 * (fixf - strict),
    gain_extend_all641_placeholder_to_22_pts = 100 * (ext_all - base),
    gain_extend_placeholder_to_22_strict_pts = 100 * (ext - strict),
    gain_all_fix_and_hours_pts = 100 * (allfix - strict),
    gain_first100_new_builds_pts = 100 * b100)
}
fxd <- do.call(rbind, fx); num <- sapply(fxd, is.numeric); fxd[num] <- lapply(fxd[num], round, 4)
fwrite(fxd, file.path(OUT, "fix_hours_vs_build.csv"))

# ---- validation (complaint route: comparison only, never used for selection) ---------------------
res <- cons[ntatype == "0"]
all197 <- merge(sc[, .(nta = nta2020, ntaname, resid_ratio)], cons[, .(nta, runs_primary, sites_primary)], by = "nta", all.x = TRUE)
all197[is.na(runs_primary), `:=`(runs_primary = 0L, sites_primary = 0L)]
stopifnot(nrow(all197) == 197)
rho_runs  <- cor(all197$runs_primary, all197$resid_ratio, method = "spearman")
rho_sites <- cor(all197$sites_primary, all197$resid_ratio, method = "spearman")
top29 <- sc[resid_ratio >= 1.5]$nta2020
six_codes <- nta_tab$nta2020[match(SIX, nta_tab$ntaname)]
six_tab <- cons[match(six_codes, cons$nta), .(ntaname = SIX, rank, runs_primary, sites_primary)]
six_tab[is.na(rank), `:=`(runs_primary = 0L, sites_primary = 0L)]
consensus_set <- cons[runs_primary >= 4]$nta
# null: how many of the six expected in a random 20 of the 197
p_null <- 20 / 197 * 6
sink(file.path(OUT, "validation.txt"))
cat("VALIDATION -- complaint route used ONLY as a check, never to choose sites\n")
cat("Consensus score = number of the 8 primary runs (4 demand objectives x {Wed 2pm, Wed 9pm off-season}, base supply,\n",
    "500 m) in which the NTA (snapped to a residential 2020 NTA) receives >=1 of that run's first 100 greedy sites.\n",
    "Tie-break: total first-100 sites across the 8 runs. (9pm runs are identical under in-season 20:00 and strict supply.)\n\n", sep = "")
cat(sprintf("NTAs receiving any first-100 site in >=1 primary run: %d of 197 residential NTAs\n", nrow(cons)))
cat(sprintf("NTAs chosen in >=4 of 8 runs: %d; in all 8 runs: %d\n\n", length(consensus_set), sum(cons$runs_primary == 8)))
cat("Top-20 consensus NTAs:\n")
print(as.data.frame(cons[1:20, .(rank, ntaname, boroname, runs_primary, sites_primary, resid_ratio, ratio_rank, high_complaint_six)]), row.names = FALSE)
cat("\n1) The six high-complaint NTAs (A6 posterior P(RR>1.5)>0.95):\n")
print(as.data.frame(six_tab), row.names = FALSE)
cat(sprintf("   In consensus top 20: %d of 6 (random 20-of-197 draw would give %.2f on average)\n",
            sum(six_codes %in% top20), p_null))
cat(sprintf("   Chosen in >=4 of 8 runs: %d of 6\n", sum(six_codes %in% consensus_set)))
cat(sprintf("\n2) Model residual ratio (model_nta_scored_20260920.csv, 197 NTAs):\n   Spearman(runs_primary, resid_ratio) = %.3f; Spearman(sites_primary, resid_ratio) = %.3f\n",
            rho_runs, rho_sites))
cat(sprintf("   Top-20 consensus NTAs with resid_ratio >= 1.5 (the 29): %d of 20 (random expectation %.1f)\n",
            sum(top20 %in% top29), 20 * 29 / 197))
cat(sprintf("   Median resid_ratio: top-20 consensus %.2f vs all 197 %.2f\n",
            median(sc$resid_ratio[match(top20, sc$nta2020)]), median(sc$resid_ratio)))
cat("\n3) Radius sensitivity (top-20 consensus overlap with 500 m): ",
    paste0(rsens$radius_m, " m: ", rsens$top20_overlap_with_500m, "/20", collapse = "; "), "\n", sep = "")
cat("\nReading: the consensus is built from where people/workers/riders/busy streets lack an open restroom within\n",
    "500 m. Complaints measure reported nuisance, which also reflects reporting behaviour. Agreement is\n",
    "corroboration, disagreement is not an error in either -- they answer different questions.\n", sep = "")
sink()
saveRDS(list(runs = runs, cons = cons, CONF = CONF, PRIMARY = PRIMARY, pilot_cmp = pilot_cmp, fxd = fxd,
             rsens = rsens, top_by_r = top_by_r), file.path(PT, "cache/runs.rds"))

# ---- coverage curve chart -------------------------------------------------------------------------
lab_o <- c(residents = "Residents", workers = "Workers (jobs)", subway = "Subway entries", streets = "Busy streets (length)")
cp <- cc[cc$config %in% c("base_14", "strict_14", "base_21_off"), ]
L <- c(base_14 = "2pm", strict_14 = "2pm, minus long-term-closed/failing",
       base_21_off = "9pm (identical whether park toilets close 4pm or 8pm, and with closed/failing removed)")
cp$line <- factor(L[cp$config], levels = L)
cp$objective <- factor(lab_o[cp$objective], levels = lab_o)
pcur <- ggplot(cp, aes(n_new_sites, 100 * share_covered, colour = line, linetype = line)) +
  geom_vline(xintercept = 100, colour = "grey70", linewidth = 0.3) +
  geom_line(linewidth = 0.8) + facet_wrap(~objective, nrow = 2) +
  scale_colour_manual(values = c("#2a78d6", "#7aa7e0", "#eb6834"), name = NULL) +
  scale_linetype_manual(values = c("solid", "22", "solid"), name = NULL) +
  guides(colour = guide_legend(ncol = 1), linetype = guide_legend(ncol = 1)) +
  scale_y_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  labs(title = "Share of demand with an open restroom within 500 m, as new sites are added greedily",
       subtitle = "Wednesday. New sites assumed open 7am-10pm. Each panel is a separate objective (never summed). Grey line = 100 sites.",
       x = "New sites added (greedy maximal covering)", y = "Demand covered",
       caption = "Straight-line 500 m; posted hours; DOT modelled pedestrian demand; candidates are grid points on public land/busy frontage, not verified sites.") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", legend.justification = "left", panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"), plot.caption = element_text(colour = "grey40", hjust = 0, size = 7.5),
        plot.background = element_rect(fill = "white", colour = NA), plot.title.position = "plot")
ggsave(file.path(OUT, "coverage_curves.png"), pcur, width = 9, height = 6.5, dpi = 150)
cat("02 done in", round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")
