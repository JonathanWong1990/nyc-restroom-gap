# A6_empirical_bayes.R — How confident are we about each INDIVIDUAL neighbourhood?
#
# The bootstrap in A5 asks family-level questions ("is there variation?", "are the
# extremes a separate group?"). Neither answers the question a budget-holder asks:
# for THIS neighbourhood, how likely is it that true need really is elevated?
#
# The negative binomial already contains the answer. NB(mu, theta) is exactly
# Poisson(mu * RR) with RR ~ Gamma(theta, theta) — mean 1, sd sqrt(1/theta). So the
# fitted model is a Poisson-gamma empirical Bayes model whose prior shape is theta;
# nothing new is estimated. The posterior for one area is conjugate:
#
#     RR_i | y_i  ~  Gamma(shape = theta + y_i, rate = theta + mu_i)
#
# This is standard small-area estimation: thin counts are shrunk toward the citywide
# pattern, and the shrinkage is heavier the thinner the count.
#
# IMPORTANT: this addresses SPARSE COUNTS. It does nothing for VALIDITY — every
# reporting-bias problem in A4_reporting_channel.R applies unchanged.
suppressMessages({library(dplyr); library(MASS)}); options(scipen=999)
D <- Sys.getenv("RESTROOM_PROJ", unset="."); dd <- file.path(D, "data_raw")
d <- read.csv(file.path(dd,"model_with_commercial_20260920.csv")) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0)
F <- events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total))
m <- glm.nb(F, data=d); a <- m$theta; mu <- fitted(m); y <- d$events_311

post_mean <- (a + y)/(a + mu)
p15       <- 1 - pgamma(1.5, shape = a + y, rate = a + mu)
shrink    <- mu/(a + mu)

cat("prior shape a = theta =", round(a,3), "  prior sd of RR =", round(sqrt(1/a),3), "\n")
cat("weight on an area's own data: median", round(median(shrink),3),
    " range", paste(round(range(shrink),2), collapse="-"), "\n\n")
cat("neighbourhoods with posterior P(true relative risk > 1.5):\n")
for (t in c(.95,.90,.80)) cat(sprintf("   > %.2f : %d\n", t, sum(p15 > t)))

o <- order(-p15)[1:10]
cat("\n")
print(data.frame(neighbourhood = substr(d$ntaname[o],1,34), observed = y[o],
      expected = round(mu[o],1), raw_ratio = round((y/pmax(mu,.01))[o],2),
      EB_mean = round(post_mean[o],2), P_gt_1.5 = round(p15[o],3)), row.names=FALSE)

cat("\nSpearman(raw ratio, EB posterior mean) =",
    round(cor(y/pmax(mu,.01), post_mean, method="spearman"),4),
    "  -> shrinkage barely reorders; its value is the confidence statement.\n")

## ---- KILL-CHECK: is the confidence self-generated? -------------------------
## Each area helps estimate the very prior used to score it. Re-fit the model AND
## the prior with the area removed, predict it out of sample, then score it.
cat("\n=== LEAVE-ONE-OUT (model and prior re-estimated without the scored area) ===\n")
top <- order(-p15)[1:7]; res <- data.frame()
for (i in top) {
  fi   <- glm.nb(F, data = d[-i,])
  mu_i <- predict(fi, newdata = d[i,], type = "response")
  p_i  <- 1 - pgamma(1.5, shape = fi$theta + y[i], rate = fi$theta + mu_i)
  res  <- rbind(res, data.frame(neighbourhood = substr(d$ntaname[i],1,32),
           observed = y[i], exp_full = round(mu[i],1), exp_LOO = round(mu_i,1),
           P_full = round(p15[i],3), P_LOO = round(p_i,3)))
}
print(res, row.names=FALSE)
cat("\nsurviving P>0.95 under leave-one-out:", sum(res$P_LOO > 0.95), "of", nrow(res), "\n")
