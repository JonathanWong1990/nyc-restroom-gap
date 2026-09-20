# 20_regression.R — Session 4/5 regression ranking model.
# Must beat the one-liner benchmark (subway ridership, Spearman 0.713) OUT OF SAMPLE.
suppressMessages({library(dplyr); library(MASS)})
options(scipen=999); set.seed(6093); D <- "data_raw"
d <- read.csv(file.path(D,"model_nta_table_20260920.csv"))
cat("neighbourhoods:", nrow(d), "  complaints total:", sum(d$events_311), "\n")

d <- d |> mutate(
  l_sub   = log1p(subway_riders/1000),
  l_jobs  = log1p(jobs/1000),
  l_hotel = log1p(hotels),
  l_rest  = log1p(restrooms),
  l_dens  = log1p(pop_density),
  inc10k  = med_hh_income_hhwtd/10000,
  pov     = poverty_rate*100,
  old     = pct_65plus*100,
  boro    = factor(boroname))
cat("missing income:", sum(is.na(d$inc10k)), " poverty:", sum(is.na(d$pov)), "\n\n")
d <- d |> filter(!is.na(inc10k), !is.na(pov), pop_total > 0)
cat("estimation sample:", nrow(d), "\n\n")

F <- events_311 ~ l_sub + l_jobs + l_hotel + l_rest + l_dens + inc10k + pov + old +
       boro + offset(log(pop_total))

cat("=== NEGATIVE BINOMIAL (full sample) ===\n")
m <- glm.nb(F, data=d)
co <- summary(m)$coefficients
print(round(co[, c(1,2,4)], 4))
cat("\ntheta =", round(m$theta,3), "  AIC =", round(AIC(m)), "\n")
null <- glm.nb(events_311 ~ 1 + offset(log(pop_total)), data=d)
cat("McFadden pseudo-R2 =", round(1 - logLik(m)/logLik(null), 3), "\n")

cat("\nIncidence rate ratios (effect of a 1-unit change):\n")
irr <- data.frame(term=rownames(co), IRR=round(exp(co[,1]),3),
                  p=round(co[,4],4), row.names=NULL)
print(irr[!grepl("Intercept", irr$term), ], row.names=FALSE)

## ---- OUT-OF-SAMPLE: model vs benchmark, 200 random 70/30 splits ------------
cat("\n=== OUT-OF-SAMPLE TEST: 200 random 70/30 splits ===\n")
res <- replicate(200, {
  i  <- sample(nrow(d), round(0.7*nrow(d)))
  tr <- d[i,]; te <- d[-i,]
  fit <- try(glm.nb(F, data=tr), silent=TRUE)
  if(inherits(fit,"try-error")) return(c(NA,NA,NA))
  pm <- try(predict(fit, newdata=te, type="response"), silent=TRUE)
  if(inherits(pm,"try-error")) return(c(NA,NA,NA))
  c(model     = cor(pm,            te$events_311, method="spearman"),
    benchmark = cor(te$subway_riders, te$events_311, method="spearman"),
    jobs      = cor(te$jobs,         te$events_311, method="spearman"))
})
res <- res[, !is.na(res[1,]), drop=FALSE]
cat("valid splits:", ncol(res), "\n")
cat(sprintf("%-28s %8s %8s %8s\n","","mean rho","median","sd"))
for(r in rownames(res)) cat(sprintf("%-28s %8.3f %8.3f %8.3f\n",
    r, mean(res[r,]), median(res[r,]), sd(res[r,])))
win <- mean(res["model",] > res["benchmark",])
cat(sprintf("\nMODEL BEATS BENCHMARK in %.0f%% of splits (mean margin %+.3f)\n",
            100*win, mean(res["model",]-res["benchmark",])))

## ---- residuals = measured unmet need --------------------------------------
d$pred <- predict(m, type="response")
d$resid_ratio <- d$events_311 / pmax(d$pred, 0.01)
cat("\n=== TOP 12 by UNMET NEED (more complaints than characteristics predict) ===\n")
print(d |> arrange(desc(resid_ratio)) |>
  transmute(neighbourhood=substr(ntaname,1,38), actual=events_311,
            predicted=round(pred,1), ratio=round(resid_ratio,2),
            restrooms, subway_m=round(subway_riders/1e6,1)) |> head(12), row.names=FALSE)
write.csv(d, file.path(D,"model_nta_scored_20260920.csv"), row.names=FALSE)
saveRDS(m, file.path(D,"model_nb_20260920.rds"))
