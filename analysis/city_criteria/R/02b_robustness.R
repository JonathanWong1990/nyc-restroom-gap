# 02b_robustness.R -- two checks on the revealed weights (02_revealed_weights.R):
#  (1) like-with-like: add site-type controls (park / plaza / busy street), so pilots are compared with sites of their own kind
#      -- the candidate pool is 70% park points, many deep inside large parks where few people live;
#  (2) collinearity: population, foot traffic, transit and jobs rise together; combine them into one "busyness" index
#      (mean of their standardised logs) so the model cannot hand all the credit to one of them.
options(scipen = 999, stringsAsFactors = FALSE, warn = 1)
suppressPackageStartupMessages({library(data.table); library(logistf)})
BASE <- "/Users/jonathanwong/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project"; CM <- file.path(BASE, "City_Criteria_Model")
X <- readRDS(file.path(CM, "cache/features.rds"))$X
d <- X[pilot == 1 | control_ok == TRUE]
z <- function(v) (v - mean(v)) / sd(v)
d[, `:=`(z_pop = z(log1p(residents)), z_ped = z(log1p(foot_traffic)), z_sub = z(log1p(subway)), z_job = z(log1p(jobs)),
         z_dist = z(log1p(dist_2pm_m)), z_dist9 = z(log1p(dist_9pm_m)), z_pov = z(poverty), z_311 = z(log1p(complaints)))]
d[, busy := z((z_pop + z_ped + z_sub + z_job) / 4)]
d[, `:=`(plaza = as.integer(type == "plaza"), street = as.integer(type == "busy_street"))]
cat("correlations among the four busyness parts:\n"); print(round(cor(d[, .(z_pop, z_ped, z_sub, z_job)]), 2))
cat("site types -- pilots:", paste(names(table(d[pilot == 1]$type)), table(d[pilot == 1]$type), collapse = ", "),
    "| candidates:", paste(names(table(d[pilot == 0]$type)), table(d[pilot == 0]$type), collapse = ", "), "\n")

auc <- function(s, y) { r <- rank(s); n1 <- sum(y); n0 <- sum(!y); (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
fit <- function(f, label) {
  m <- logistf(f, data = d, plconf = NULL); ci <- confint(m)
  data.table(model = label, term = names(coef(m))[-1], coef = round(coef(m)[-1], 2), ci_low = round(ci[-1, 1], 2),
             ci_high = round(ci[-1, 2], 2), p = signif(m$prob[-1], 2), auc = round(auc(m$linear.predictors, d$pilot), 3))
}
R <- rbind(
  fit(pilot ~ z_pop + z_ped + z_sub + z_job + z_dist + z_pov, "M1 six factors (as 02)"),
  fit(pilot ~ z_pop + z_ped + z_sub + z_job + z_dist + z_pov + plaza + street, "M2 six factors + site type"),
  fit(pilot ~ busy + z_dist + z_pov, "M3 busyness index"),
  fit(pilot ~ busy + z_dist + z_pov + plaza + street, "M4 busyness index + site type"),
  fit(pilot ~ busy + z_dist9 + z_pov + plaza + street, "M5 as M4, distance to restroom open at 9pm"),
  fit(pilot ~ busy + z_dist + z_pov + plaza + street + z_311, "M6 as M4 + complaints"))
print(R, nrows = 100)
fwrite(R, file.path(CM, "outputs/robustness_models.csv"))

# leave-one-pilot-out for M4 (the candidate preferred model)
pid <- which(d$pilot == 1); loo <- integer(length(pid))
for (k in seq_along(pid)) {
  m <- logistf(pilot ~ busy + z_dist + z_pov + plaza + street, data = d[-pid[k]], plconf = NULL)
  lp <- as.vector(cbind(1, as.matrix(d[, .(busy, z_dist, z_pov, plaza, street)])) %*% coef(m))
  loo[k] <- round(100 * mean(lp[d$pilot == 0] < lp[pid[k]]))
}
cat("M4 leave-one-out: median", median(loo), "| each:", loo, "\n")
fwrite(data.table(pilot = d[pid]$name, loo_pct_M4 = loo), file.path(CM, "outputs/leave_one_out_M4.csv"))

# save the preferred model (M4) for scoring: weights on busyness / distance / equity; site-type terms are controls only
m4 <- logistf(pilot ~ busy + z_dist + z_pov + plaza + street, data = d, plconf = NULL)
saveRDS(list(coef = coef(m4)[c("busy", "z_dist", "z_pov")], var = m4$var[2:4, 2:4]),
        file.path(CM, "cache/fit_M4.rds"))
