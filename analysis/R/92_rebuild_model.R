# 92_rebuild_model.R — ranking model on the summons outcome, enforcement-controlled.
suppressMessages({library(dplyr); library(MASS)})
options(scipen=999); set.seed(6093); D <- "data_raw"
d <- read.csv(file.path(D,"model_v2_table_20260920.csv")) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0, alcohol>0) |>
  mutate(l_alc=log(alcohol))
cat("estimation sample:", nrow(d), "NTAs |", sum(d$summons), "summonses\n\n")

cl_nb <- function(fit, cl){
  X <- model.matrix(fit); mu <- fitted(fit); y <- fit$y; th <- fit$theta
  u <- X*((y-mu)/(1+mu/th)); uc <- rowsum(u, cl); G <- length(unique(cl))
  sqrt(diag(vcov(fit) %*% crossprod(uc) %*% vcov(fit) * (G/(G-1))))
}
F2 <- summons ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+l_alc+boro+offset(log(pop_total))
m <- glm.nb(F2, data=d); se <- cl_nb(m, d$cdta2020); co <- summary(m)$coefficients
cat("=== NB MODEL ON SUMMONSES (clustered by community district) ===\n")
print(data.frame(term=rownames(co), IRR=round(exp(co[,1]),3),
   p_clustered=round(2*pnorm(-abs(co[,1]/se)),4), row.names=NULL)[-1,], row.names=FALSE)
cat("\ntheta", round(m$theta,2), " McFadden R2",
    round(1-logLik(m)/logLik(glm.nb(summons ~ 1 + offset(log(pop_total)), data=d)),3), "\n")

cat("\n=== OUT-OF-SAMPLE (200 x 70/30) ===\n")
r <- replicate(200, {
  i <- sample(nrow(d), round(.7*nrow(d))); tr <- d[i,]; te <- d[-i,]
  f <- try(glm.nb(F2, data=tr), silent=TRUE); if(inherits(f,"try-error")) return(rep(NA,3))
  p <- try(predict(f, newdata=te, type="response"), silent=TRUE)
  if(inherits(p,"try-error")) return(rep(NA,3))
  c(model=cor(p, te$summons, method="spearman"),
    bench=cor(te$subway_riders, te$summons, method="spearman"),
    enf  =cor(te$alcohol, te$summons, method="spearman"))
})
r <- r[, !is.na(r[1,]), drop=FALSE]
for(k in rownames(r)) cat(sprintf("  %-22s %.3f\n",
  c(model="model", bench="benchmark: subway", enf="enforcement alone")[k], mean(r[k,])))
cat(sprintf("  model beats SUBWAY benchmark in      %.0f%% of splits\n", 100*mean(r["model",]>r["bench",])))
cat(sprintf("  model beats ENFORCEMENT benchmark in %.0f%% of splits  <-- the real test\n",
    100*mean(r["model",]>r["enf",])))
cat(sprintf("  model beats subway benchmark in %.0f%% of splits\n", 100*mean(r["model",]>r["bench",])))

## ---- ranking ----
d$pred2 <- predict(m, type="response"); d$ratio2 <- d$summons/pmax(d$pred2,.01)
# resid_ratio (the 311-based ranking) is already carried in the v2 table
cat("\n=== TOP 12 BY UNMET NEED — SUMMONS-BASED ===\n")
print(d |> arrange(desc(ratio2)) |>
  transmute(neighbourhood=substr(ntaname,1,32), summonses=summons,
            predicted=round(pred2), ratio_new=round(ratio2,2),
            ratio_311=round(resid_ratio,2), restrooms) |> head(12), row.names=FALSE)
cat(sprintf("\nagreement between the two rankings: Spearman %.3f | top-10 overlap %d/10\n",
  cor(d$ratio2, d$resid_ratio, method="spearman", use="complete.obs"),
  length(intersect(d$nta2020[order(-d$ratio2)][1:10], d$nta2020[order(-d$resid_ratio)][1:10]))))
write.csv(d, file.path(D,"model_v2_scored_20260920.csv"), row.names=FALSE)
