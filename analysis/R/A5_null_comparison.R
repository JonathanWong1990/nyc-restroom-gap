# A5_null_comparison.R — WHICH null are we testing against?
#
# A1_noise_floor.R simulates from the fitted NEGATIVE BINOMIAL. That is a valid
# test, but not of the question its original write-up claimed. A negative binomial
# draw is Poisson with a Gamma-distributed rate: its overdispersion parameter theta
# IS between-neighbourhood variation in the underlying rate. Simulating from it
# therefore produces cities that already contain unmet need of exactly the magnitude
# estimated from the real data. It cannot answer "what if nothing were wrong?".
#
# This script runs BOTH nulls side by side so the difference is explicit:
#   NULL A  NB(mu, theta)  — places genuinely differ. Tests: are the extremes a
#                            separate category, or the top of a smooth continuum?
#   NULL B  Poisson(mu)    — places do NOT differ; only sampling luck. Tests: is
#                            there any real between-neighbourhood variation at all?
suppressMessages({library(dplyr); library(MASS)}); options(scipen=999); set.seed(20260920)
D <- Sys.getenv("RESTROOM_PROJ", unset="."); dd <- file.path(D, "data_raw")
d <- read.csv(file.path(dd,"model_with_commercial_20260920.csv")) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0)
F <- events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total))
m <- glm.nb(F, data=d); th <- m$theta; mu <- fitted(m)
obs_r <- d$events_311/pmax(mu,.01); obs_max <- max(obs_r); obs_n15 <- sum(obs_r>=1.5)

cat("theta =", round(th,3), "-> implied sd of true relative risk across areas =",
    round(sqrt(1/th),3), "\n")
cat("OBSERVED: areas >=1.5x:", obs_n15, "  max ratio:", round(obs_max,2), "\n\n")

run <- function(gen, B=500){
  n15 <- mx <- numeric(B)
  for(b in 1:B){
    y <- gen(); db <- d; db$events_311 <- y
    f <- try(glm.nb(F, data=db), silent=TRUE)
    p <- if(inherits(f,"try-error")) mu else fitted(f)
    r <- y/pmax(p,.01); n15[b] <- sum(r>=1.5); mx[b] <- max(r)
  }
  list(n15=n15, mx=mx)
}
report <- function(lab, s){
  cat(lab, "\n")
  cat(sprintf("  areas >=1.5x : mean %.1f  95%% range %.0f-%.0f   OBSERVED %d\n",
      mean(s$n15), quantile(s$n15,.025), quantile(s$n15,.975), obs_n15))
  cat(sprintf("  max ratio    : median %.2f  95th pct %.2f       OBSERVED %.2f\n",
      median(s$mx), quantile(s$mx,.95), obs_max))
  cat(sprintf("  p(simulated max >= observed) = %.3f\n\n", mean(s$mx >= obs_max)))
}
report("=== NULL A: NB(mu, theta) — areas DO differ (what A1 tests) ===",
       run(function() rnegbin(length(mu), mu=mu, theta=th)))
report("=== NULL B: Poisson(mu) — areas do NOT differ (a true no-effect null) ===",
       run(function() rpois(length(mu), lambda=mu)))

cat("READING:\n")
cat("  Against Poisson, the observed spread is far beyond luck -> real variation exists.\n")
cat("  Against NB, the observed count of extremes is about what the estimated spread\n")
cat("  predicts -> the extremes are the top of a continuum, not a distinct category.\n")
cat("  Both are true. Neither says any individual area is or is not underserved;\n")
cat("  for that, see A6_empirical_bayes.R.\n")
