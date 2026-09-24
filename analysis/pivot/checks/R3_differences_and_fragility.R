# R3: written AFTER reading Maintenance_Pivot_Feasibility/R/M1 to explain differences.
# (1) exact-match their definitions to show where 79.1 and 88 come from;
# (2) how fragile the logistic's 88 is to innocuous specification choices;
# (3) chronic-site accounting done properly (weighted, not "weight > 0").
suppressMessages(library(data.table))
OUT <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Overnight_2026-09-24/2_pivot_replication"
pan <- readRDS(file.path(OUT, "panel.rds")); vis <- readRDS(file.path(OUT, "visits.rds"))
sink(file.path(OUT, "R3_output.txt"), split = TRUE)
pan[, yU := fifelse(is.na(y), 0L, y)]
alloc <- function(score, k) { n <- length(score); if (k >= n) return(rep(1, n))
  cut <- sort(score, decreasing = TRUE)[k]; w <- as.numeric(score > cut)
  w[score == cut] <- (k - sum(w)) / sum(score == cut); w }
yield <- function(d, s, frac = .2) d[, sum(alloc(get(s), ceiling(frac * .N)) * yU), by = P][, sum(V1)]

# their last-three = last three rated visits WITHIN the 3-year window (mine: over all history)
l3w <- rbindlist(lapply(sort(unique(pan$P)), function(p) {
  hr <- vis[d < p & e < p & d >= p - 1095 & rating != "N"][order(prop_id, -d)]
  hr[, head(.SD, 3), by = prop_id][, .(P = p, last3w = mean(rating == "U")), by = prop_id]
}))
pan <- merge(pan, l3w, by = c("prop_id", "P"), all.x = TRUE)
pan[, boro1 := factor(substr(prop_id, 1, 1), levels = c("B","M","Q","R","X"))]
pan[, boroS := factor(boro, levels = c("B","M","Q","R","X"))]
cat("Rows where borough from prop_id != borough from sites table:", pan[as.character(boro1) != as.character(boroS), .N], "\n")
tr <- pan[stage != "test" & status == "rated"]; tt <- pan[stage == "test"]

specs <- list(
  their_exact        = y ~ last_U + last3w + log1p(days_since) + boro1 + half,
  their_linear_days  = y ~ last_U + last3w + days_since + boro1 + half,
  their_boro_sites   = y ~ last_U + last3w + log1p(days_since) + boroS + half,
  their_last3_allhist= y ~ last_U + last3_share + log1p(days_since) + boro1 + half,
  no_borough         = y ~ last_U + last3w + log1p(days_since) + half,
  plus_smooth3       = y ~ last_U + last3w + smooth3 + log1p(days_since) + boro1 + half,
  smooth3_only       = y ~ smooth3,
  history_counts     = y ~ u3 + n3 + last_U + log1p(days_since),
  my_R2_spec         = y ~ last_U + last3_share + smooth3 + log1p(n3) + log(days_since) + boroS + half)
res <- rbindlist(lapply(names(specs), function(nm) {
  f <- glm(specs[[nm]], data = tr, family = binomial)
  tt[, sc := predict(f, newdata = tt, type = "response")]
  # 2024 selection metric as they computed it: rated-only, 20% of rated, mean precision per period
  f0 <- glm(specs[[nm]], data = pan[stage == "train" & status == "rated"], family = binomial)
  v <- pan[stage == "select" & status == "rated"]; v[, sc := predict(f0, newdata = v, type = "response")]
  vp <- v[, { k <- ceiling(.2 * .N); sum(alloc(sc, k) * y) / k }, by = P][, mean(V1)]
  data.table(spec = nm, sel2024_precision_rated = round(vp, 4), test_all_eligible_20 = yield(tt, "sc"),
             test_10 = yield(tt, "sc", .1), test_30 = yield(tt, "sc", .3))
}))
tt[, `:=`(last3w_s = last3w)]
cat("\nRule benchmarks (test, all-eligible 20%): last3 within 3y window =", yield(tt, "last3w_s"),
    "; last3 all history =", yield(tt, "last3_share"), "; smooth3 =", yield(tt, "smooth3"), "\n")
cat("\nLogistic specification sensitivity (known failures captured of 411 slots):\n"); print(res)

# ---- chronic accounting (weighted) using their exact logistic + rules ----
f <- glm(specs$their_exact, data = tr, family = binomial)
tt[, lg := predict(f, newdata = tt, type = "response")]
tt[, pid := prop_id]
for (s in c("last_U", "last3w", "smooth3", "lg")) {
  tt[, w := alloc(get(s), ceiling(.2 * .N)), by = P]
  cap <- tt[yU == 1 & w > 0, .(cw = sum(w), periods = .N), by = pid]
  ex <- tt[yU == 1, .(cw = sum(w), from_lastU = sum(w * last_U), from_prior_fail3y = sum(w * (u3 > 0)),
                      from_no_prior_fail = sum(w * (u3 == 0)))]
  cat(sprintf("%-8s captured=%.1f | from sites last-rated U=%.1f | any U in prior 3y=%.1f | no U in prior 3y=%.1f | props w/ full-weight captured fail=%d\n",
      s, ex$cw, ex$from_lastU, ex$from_prior_fail3y, ex$from_no_prior_fail, tt[yU == 1 & w == 1, uniqueN(pid)]))
}
cat("Test failures total 244; at sites with any U in prior 3y:", tt[yU == 1 & u3 > 0, .N],
    "; eligible site-periods with any prior-3y U:", tt[u3 > 0, .N], "of", nrow(tt), "\n")
cat("Failure rate (rated) by prior-3y U count:\n")
print(tt[status == "rated", .(n = .N, rate = round(mean(y), 3)), by = .(u3 = pmin(u3, 3))][order(u3)])
# repeat offenders: props that fail in >=2 of the 3 test periods
rp <- tt[yU == 1, .N, by = pid][N >= 2, pid]
cat("Props failing in >=2 test periods:", length(rp), "accounting for", tt[yU == 1 & pid %in% rp, .N], "of 244 failures\n")
sink()
