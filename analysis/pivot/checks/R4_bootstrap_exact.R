# R4: parent-park cluster bootstrap (1000 draws, fixed fitted scores, re-ranked per draw)
# using the exact-match logistic spec from R3. Differences in known failures captured, 411 slots.
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
ev <- function(d) d[, { k <- ceiling(.2 * .N); r <- k * sum(yU) / .N
  list(rand = r, lastU = sum(alloc(last_U, k) * yU), l3 = sum(alloc(last3w, k) * yU),
       sm = sum(alloc(smooth3, k) * yU), lg = sum(alloc(lg, k) * yU)) }, by = P][, lapply(.SD, sum), .SDcols = -"P"]
print(ev(tt))
set.seed(6093); cl <- unique(tt$propnum); sp <- split(tt, by = "propnum")
b <- rbindlist(lapply(1:1000, function(i) { e <- ev(rbindlist(sp[sample(cl, length(cl), TRUE)]))
  e[, .(lg_minus_sm = lg - sm, lg_minus_l3 = lg - l3, sm_minus_rand = sm - rand, lg_minus_rand = lg - rand, lastU_minus_rand = lastU - rand)] }))
q <- b[, lapply(.SD, quantile, c(.025, .5, .975))]; q[, stat := c("2.5%","50%","97.5%")]
print(q); cat("As percentage points of 411 slots:\n"); print(q[, lapply(.SD, function(x) if (is.numeric(x)) round(100 * x / 411, 1) else x)])
