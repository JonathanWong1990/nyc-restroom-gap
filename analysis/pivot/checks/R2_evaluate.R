# R2: headline comparison + stress tests on the independently built panel (R1).
suppressMessages(library(data.table))
OUT <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Overnight_2026-09-24/2_pivot_replication"
pan <- readRDS(file.path(OUT, "panel.rds"))
vis <- readRDS(file.path(OUT, "visits.rds"))
sink(file.path(OUT, "R2_output.txt"), split = TRUE)
pan[, yU := fifelse(is.na(y), 0L, y)]        # "known failure" indicator (unknown -> not counted)
pan[is.na(days_since_fail), days_since_fail := 9999]

# ---------- fractional-tie top-k allocation ----------
# weight in [0,1] per row: full selection above the cutoff, tie group at cutoff shares the rest
alloc <- function(score, k) {
  n <- length(score); if (k >= n) return(rep(1, n))
  s <- sort(score, decreasing = TRUE); cut <- s[k]
  above <- score > cut; tie <- score == cut
  w <- numeric(n); w[above] <- 1
  w[tie] <- (k - sum(above)) / sum(tie)
  w
}
cap_k <- function(n, frac) ceiling(frac * n)   # 20% of 685/683/682 -> 137 each = 411

# ---------- logistic models ----------
f_mine  <- y ~ last_U + last3_share + smooth3 + log1p(n3) + log(days_since) + boro + half
f_their <- y ~ last_U + last3_share + days_since + boro + half   # as described in findings.md
fitp <- function(f, d) glm(f, data = d[status == "rated"], family = binomial)
# selection-stage check (train -> 2024)
sel <- pan[stage == "select"]
for (nm in c("mine","their")) {
  f <- if (nm == "mine") f_mine else f_their
  sel[, (paste0("lg_", nm)) := predict(fitp(f, pan[stage == "train"]), newdata = sel, type = "response")]
}
# refit through 2024, frozen for test
tt <- pan[stage == "test"]
for (nm in c("mine","their")) {
  f <- if (nm == "mine") f_mine else f_their
  tt[, (paste0("lg_", nm)) := predict(fitp(f, pan[stage != "test"]), newdata = tt, type = "response")]
}
tt[, `:=`(s_last3 = last3_share, s_smooth3 = smooth3, s_lastU = last_U)]
sel[, `:=`(s_last3 = last3_share, s_smooth3 = smooth3, s_lastU = last_U)]

evaluate <- function(d, frac, scores, universe = rep(TRUE, nrow(d))) {
  d <- d[universe]
  res <- d[, {
    k <- cap_k(.N, frac)
    out <- list(n = .N, k = k, U = sum(yU), random = k * sum(yU) / .N)
    for (s in scores) out[[s]] <- sum(alloc(get(s), k) * yU)
    out
  }, by = P]
  tot <- res[, lapply(.SD, sum), .SDcols = -"P"][, P := as.IDate(NA)]
  rbind(res, tot)
}
S <- c("s_lastU","s_last3","s_smooth3","lg_their","lg_mine")

cat("\n===== Data checks =====\n")
print(pan[, .(n = .N, rated = sum(status == "rated"), U = sum(yU), unrated = sum(status == "unrated"),
              novisit = sum(status == "novisit")), by = stage])
cat("Distinct props in rated test sample:", tt[status == "rated", uniqueN(prop_id)],
    " parent parks:", tt[status == "rated", uniqueN(propnum)], "\n")

cat("\n===== 2024 selection stage, all-eligible 20% =====\n")
print(evaluate(sel, .20, c(S[1:3], "lg_their", "lg_mine")))

cat("\n===== HEADLINE: test 2025-2026H1, all-eligible, 20% =====\n")
h20 <- evaluate(tt, .20, S); print(h20)
cat("\n===== 10% and 30% =====\n")
print(evaluate(tt, .10, S)[is.na(P)]); print(evaluate(tt, .30, S)[is.na(P)])

cat("\n===== Conditional (rated-only universe) 20% =====\n")
print(evaluate(tt, .20, S, tt$status == "rated")[is.na(P)])

# ---------- bootstrap (parent-park cluster) for key differences at 20% ----------
set.seed(6093)
cl <- unique(tt$propnum); B <- 1000
bt <- replicate(B, {
  pick <- sample(cl, length(cl), replace = TRUE)
  d <- tt[data.table(propnum = pick)[, .(m = .N), by = propnum], on = "propnum"]
  d <- d[rep(seq_len(.N), m)]
  e <- evaluate(d, .20, S)[is.na(P)]
  c(lg_vs_rand = e$lg_their - e$random, lg_vs_sm = e$lg_their - e$s_smooth3,
    sm_vs_lastU = e$s_smooth3 - e$s_lastU, sm_vs_rand = e$s_smooth3 - e$random)
})
cat("\n===== Cluster-bootstrap 95% CIs (captured failures, pooled 3 periods, 20%) =====\n")
print(t(apply(bt, 1, quantile, c(.025, .5, .975))))

# =================== STRESS TESTS ===================
cat("\n===== ST1 leakage =====\n")
# (a) visits dated before P but entered on/after P (would leak if not filtered)
Ps <- sort(unique(pan$P))
lk <- rbindlist(lapply(Ps, function(p) data.table(P = p,
  n_before = vis[d < p, .N], entered_late = vis[d < p & e >= p, .N],
  late_props_in_panel = vis[d < p & e >= p & prop_id %in% pan[P == p, prop_id], uniqueN(prop_id)],
  visits_on_P = vis[d == p, .N])))
print(lk)
cat("Max entry lag (days) among 2015+ visits:", vis[d >= "2015-01-01", max(e - d)], "\n")
# (b) all history inputs strictly d < P; outcome d >= P, so a same-day visit cannot be both.
cat("Rows where last_d >= P (should be 0):", pan[last_d >= P, .N],
    "; rows where out_d < P (should be 0):", pan[!is.na(out_d) & out_d < P, .N], "\n")
# (c) eligibility uses only history; but the prop universe = props that ever appear in the
#     comfort-station table (a current snapshot).  Check: eligible props whose first cs visit is
#     after P (impossible by construction):
cat("Eligible rows with no prior visit (should be 0):", pan[is.na(last_d), .N], "\n")

cat("\n===== ST2 timing of first visit vs risk =====\n")
tt[, days_to_visit := as.numeric(out_d - P)]
tt[, risk_q := cut(rank(s_smooth3, ties.method = "average") / .N, c(0, .2, .4, .6, .8, 1),
                   labels = paste0("Q", 1:5)), by = P]
print(tt[, .(n = .N, novisit = mean(status == "novisit"), unrated = mean(status == "unrated"),
             med_days_to_visit = median(days_to_visit, na.rm = TRUE),
             visits_in_half = mean(fifelse(is.na(n_vis_half), 0L, n_vis_half)),
             failrate_first = mean(y, na.rm = TRUE)), by = risk_q][order(risk_q)])
cat("Spearman(smooth3, days_to_visit):",
    round(tt[!is.na(days_to_visit), cor(s_smooth3, days_to_visit, method = "spearman")], 3), "\n")
# fail rate by timing of the first visit (month within half)
tt[, visit_month_in_half := ((month(out_d) - 1) %% 6) + 1]
print(tt[status == "rated", .(n = .N, failrate = mean(y)), by = visit_month_in_half][order(visit_month_in_half)])
# alternative outcomes: any U in the half-year; last rated visit in the half
tt[, yAny := fifelse(!is.na(anyU_half) & anyU_half, 1L, 0L)]
tt[, yLastRated := fifelse(!is.na(lastrated_half) & lastrated_half == "U", 1L, 0L)]
alt <- function(col) { d <- copy(tt); d[, yU := get(col)]; evaluate(d, .20, S)[is.na(P)] }
cat("Outcome = any U in half-year:\n"); print(alt("yAny"))
cat("Outcome = last rated visit in half-year is U:\n"); print(alt("yLastRated"))

cat("\n===== ST4 chronic sites =====\n")
# distinct props among failures captured by each rule (props with weight>0 and yU==1)
tt[, (paste0("w_", S)) := lapply(S, function(s) alloc(get(s), cap_k(.N, .2))), by = P]
for (s in c(S, "random")) {
  if (s == "random") next
  w <- tt[[paste0("w_", s)]]
  cap <- tt[w > 0 & yU == 1]
  cat(sprintf("%-10s captured=%.1f  distinct props among captured=%d  props captured in 2+ periods=%d  in all 3=%d\n",
      s, sum(w * tt$yU), uniqueN(cap$prop_id),
      cap[, .N, by = prop_id][N >= 2, .N], cap[, .N, by = prop_id][N >= 3, .N]))
}
cat("All test failures: ", tt[yU == 1, .N], " from distinct props: ", tt[yU == 1, uniqueN(prop_id)],
    "; props failing in 2+ periods: ", tt[yU == 1, .N, by = prop_id][N >= 2, .N], "\n")
# share of test failures at props that had a U in their last rated visit / in last 3 yrs
print(tt[yU == 1, .(fails = .N, last_rated_U = sum(last_U), any_U_prior3y = sum(u3 > 0))])
# universe = sites whose last rated visit was A; select 20% within that universe
cat("\nUniverse: last rated visit = A (new-failure detection)\n")
print(evaluate(tt, .20, S[-1], tt$last_U == 0))
print(tt[last_U == 0, .(n = .N, rated = sum(status == "rated"), U = sum(yU), fail_rate_rated = mean(y, na.rm = TRUE))])
cat("Universe: last rated = A AND no U in prior 3y\n")
print(evaluate(tt, .20, S[-1], tt$last_U == 0 & tt$u3 == 0))

cat("\n===== ST5 'failed last time' rule =====\n")
print(tt[, .(sites_last_U = sum(last_U), slots20 = cap_k(.N, .2), U_among_lastU = sum(yU * last_U),
             rated_lastU = sum(last_U * (status == "rated")),
             U_total = sum(yU)), by = P])
cat("Uncapped 'failed last time' list: slots =", tt[, sum(last_U)], " captured =", tt[, sum(yU * last_U)],
    " precision among rated =", round(tt[last_U == 1 & status == "rated", mean(y)], 3),
    " vs base rated rate =", round(tt[status == "rated", mean(y)], 3), "\n")
# fill-up rule: last-U first, then by smooth3 (lexicographic)
tt[, s_lastU_then_sm := last_U + smooth3]
print(evaluate(tt, .20, c("s_lastU", "s_lastU_then_sm", "s_smooth3", "lg_their"))[is.na(P)])

cat("\n===== AUC (rated test) =====\n")
auc <- function(s, y) { r <- rank(s); n1 <- sum(y); n0 <- length(y) - n1; (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
print(tt[status == "rated", lapply(.SD, function(s) round(auc(s, y), 3)), by = P, .SDcols = S])
saveRDS(tt, file.path(OUT, "test_scored.rds"))
sink()
