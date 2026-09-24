# R5: 10/20/30% capacity for exact-match definitions (all-eligible, known failures captured) + per period
suppressMessages(library(data.table))
OUT <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Overnight_2026-09-24/2_pivot_replication"
pan <- readRDS(file.path(OUT, "panel.rds")); vis <- readRDS(file.path(OUT, "visits.rds"))
pan[, yU := fifelse(is.na(y), 0L, y)]
alloc <- function(score, k) { n <- length(score); if (k >= n) return(rep(1, n))
  cut <- sort(score, decreasing = TRUE)[k]; w <- as.numeric(score > cut)
  w[score == cut] <- (k - sum(w)) / sum(score == cut); w }
l3w <- rbindlist(lapply(sort(unique(pan$P)), function(p) {
  hr <- vis[d < p & e < p & d >= p - 1095 & rating != "N"][order(prop_id, -d)]
  hr[, head(.SD, 3), by = prop_id][, .(P = p, last3w = mean(rating == "U")), by = prop_id] }))
pan <- merge(pan, l3w, by = c("prop_id", "P"))
pan[, boro1 := factor(substr(prop_id, 1, 1), levels = c("B","M","Q","R","X"))]
f <- glm(y ~ last_U + last3w + log1p(days_since) + boro1 + half, data = pan[stage != "test" & status == "rated"], family = binomial)
tt <- pan[stage == "test"]; tt[, lg := predict(f, newdata = tt, type = "response")]
for (fr in c(.1, .2, .3)) {
  r <- tt[, { k <- ceiling(fr * .N); list(k = k, U = sum(yU), rand = k * sum(yU) / .N, lastU = sum(alloc(last_U, k) * yU),
    last3 = sum(alloc(last3w, k) * yU), smooth3 = sum(alloc(smooth3, k) * yU), logistic = sum(alloc(lg, k) * yU)) }, by = P]
  cat("\nCapacity", fr, "\n"); print(rbind(r, r[, lapply(.SD, sum), .SDcols = -"P"], fill = TRUE), digits = 4)
}
