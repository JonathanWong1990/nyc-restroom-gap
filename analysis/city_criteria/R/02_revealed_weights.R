# 02_revealed_weights.R -- which LL58 factors best explain where the City put its 17 pilot units?
# Case-control logistic regression: 17 pilot sites (1) vs candidate sites not within 300 m of a pilot (0).
# Firth's penalised logistic (logistf) because 17 events is small; predictors are standardised so coefficients compare.
# Validation: leave-one-pilot-out -- refit without pilot i, then see where pilot i ranks among all candidates.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(data.table); library(logistf)})
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
X <- readRDS(file.path(CM, "cache/features.rds"))$X
set.seed(6093)

# one variable per LL58 factor (skewed counts logged); distance: farther from an open restroom = more underserved
LAW <- c(population = "residents", foot_traffic = "foot_traffic", transit = "subway", land_use = "jobs",
         distance_2pm = "dist_2pm_m", equity = "poverty")
EXTRA <- c(complaints = "complaints")
tf <- function(v, f) if (f %in% c("poverty")) v else log1p(v)
d <- X[pilot == 1 | control_ok == TRUE]
Z <- function(dd, vars) { m <- sapply(vars, function(f) tf(dd[[f]], f)); colnames(m) <- names(vars); m }
zs <- function(m, ref) sweep(sweep(m, 2, colMeans(ref)), 2, apply(ref, 2, sd), "/")

fit_w <- function(vars, dd = d) {
  M <- Z(dd, vars); S <- zs(M, M); df <- data.frame(y = dd$pilot, S)
  f <- logistf(y ~ ., data = df, plconf = NULL)
  list(fit = f, coef = coef(f)[-1], ref = M)
}
report <- function(ft, label) {
  ci <- confint(ft$fit)[-1, , drop = FALSE]
  r <- data.table(model = label, factor = names(ft$coef), coef = round(ft$coef, 2),
                  ci_low = round(ci[, 1], 2), ci_high = round(ci[, 2], 2), p = signif(ft$fit$prob[-1], 2))
  r[, weight := round(pmax(coef, 0) / sum(pmax(coef, 0)), 2)]
  r
}
A <- fit_w(LAW); B <- fit_w(c(LAW, EXTRA))
RA <- report(A, "LL58 factors"); RB <- report(B, "LL58 factors + complaints")
print(RA); print(RB)

# in-sample discrimination (AUC) and leave-one-pilot-out rank
auc <- function(score, y) { r <- rank(score); n1 <- sum(y); n0 <- sum(!y); (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
score_lin <- function(ft, vars, dd) { S <- zs(Z(dd, vars), ft$ref); as.vector(S %*% ft$coef) }
for (nm in c("A", "B")) {
  ft <- get(nm); vars <- if (nm == "A") LAW else c(LAW, EXTRA)
  cat(nm, "in-sample AUC:", round(auc(score_lin(ft, vars, d), d$pilot), 3), "\n")
  pil_idx <- which(d$pilot == 1); loo <- integer(length(pil_idx))
  for (k in seq_along(pil_idx)) {
    dk <- d[-pil_idx[k]]; fk <- fit_w(vars, dk)
    s_all <- score_lin(fk, vars, d[d$pilot == 0 | seq_len(nrow(d)) == pil_idx[k]])
    ctl_n <- sum(d$pilot == 0)
    loo[k] <- round(100 * mean(s_all[seq_len(ctl_n)] < s_all[ctl_n + 1]))
  }
  cat(nm, "leave-one-out: held-out pilot beats this % of candidates -- median", median(loo), "| each:", loo, "\n")
  assign(paste0("loo_", nm), loo)
}
fwrite(rbind(RA, RB), file.path(CM, "outputs/revealed_weights.csv"))
fwrite(data.table(pilot = d[pilot == 1]$name, loo_pct_A = loo_A, loo_pct_B = loo_B), file.path(CM, "outputs/leave_one_out.csv"))
saveRDS(list(A = A, B = B, LAW = LAW, EXTRA = EXTRA), file.path(CM, "cache/fits.rds"))
