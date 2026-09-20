# A1_noise_floor.R — Is the shortlist distinguishable from the model's own noise?
# Parametric bootstrap: simulate outcomes FROM the fitted model (a world with no unmet
# need beyond what the covariates explain) and see what ranking artifacts appear anyway.
suppressMessages({library(dplyr); library(MASS)}); options(scipen=999); set.seed(20260920)
d <- read.csv("data_raw/model_with_commercial_20260920.csv") |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0)
F <- events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total))
m <- glm.nb(F, data=d); th <- m$theta; mu <- fitted(m)
cat("n =", nrow(d), "  theta =", round(th,3), "  observed ratio>=1.5:",
    sum(d$events_311/pmax(mu,.01) >= 1.5), "  max ratio:",
    round(max(d$events_311/pmax(mu,.01)),2), "\n\n")

B <- 500; n15 <- numeric(B); mx <- numeric(B)
for(b in 1:B){
  y <- rnegbin(length(mu), mu=mu, theta=th)
  db <- d; db$events_311 <- y
  f <- try(glm.nb(F, data=db), silent=TRUE)
  p <- if(inherits(f,"try-error")) mu else fitted(f)
  r <- y/pmax(p,.01)
  n15[b] <- sum(r>=1.5); mx[b] <- max(r)
}
cat("=== UNDER THE NULL (no neighbourhood has unmet need beyond the covariates) ===\n")
cat(sprintf("areas with ratio>=1.5 : mean %.1f   95%% range %.0f-%.0f   OBSERVED %d\n",
    mean(n15), quantile(n15,.025), quantile(n15,.975), sum(d$events_311/pmax(mu,.01)>=1.5)))
cat(sprintf("maximum ratio         : median %.2f  95th pct %.2f      OBSERVED %.2f\n",
    median(mx), quantile(mx,.95), max(d$events_311/pmax(mu,.01))))

cat("\n=== PER-NEIGHBOURHOOD TESTS (is any area individually above expectation?) ===\n")
pv <- pnbinom(d$events_311-1, size=th, mu=mu, lower.tail=FALSE)
cat("p<0.05 uncorrected:", sum(pv<0.05), " (chance expectation:", round(0.05*nrow(d),1), ")\n")
cat("surviving Benjamini-Hochberg FDR 0.05:", sum(p.adjust(pv,"BH")<0.05), "\n")
cat("surviving Bonferroni:", sum(p.adjust(pv,"bonferroni")<0.05), "\n")
cat("\nsmallest p-values:\n")
print(data.frame(neighbourhood=substr(d$ntaname,1,32), observed=d$events_311,
      expected=round(mu,1), ratio=round(d$events_311/pmax(mu,.01),2),
      p_raw=signif(pv,3), p_BH=signif(p.adjust(pv,"BH"),3))[order(pv),][1:8,], row.names=FALSE)
