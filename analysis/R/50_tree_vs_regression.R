# 50_tree_vs_regression.R — Session 7 honesty check: does a tree beat the regression?
# With n=197 it probably should not. Report the result either way.
suppressMessages({library(dplyr); library(rpart); library(MASS)})
options(scipen=999); set.seed(6093); D <- "data_raw"
d <- read.csv(file.path(D,"model_nta_scored_20260920.csv")) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0) |>
  mutate(rate = events_311/pop_total*1e5)
cat("n =", nrow(d), " predictors: subway, jobs, hotels, restrooms, density, income, poverty, 65+, borough\n\n")

Fnb <- events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total))
Ftr <- rate     ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro

res <- replicate(200, {
  i <- sample(nrow(d), round(0.7*nrow(d))); tr <- d[i,]; te <- d[-i,]
  nb <- try(glm.nb(Fnb, data=tr), silent=TRUE)
  if(inherits(nb,"try-error")) return(rep(NA,4))
  p_nb <- predict(nb, newdata=te, type="response")
  t1 <- rpart(Ftr, data=tr, method="anova", control=rpart.control(cp=0.01, minsplit=15))
  p_t <- predict(t1, newdata=te) * te$pop_total/1e5
  cp  <- t1$cptable[which.min(t1$cptable[,"xerror"]),"CP"]
  p_tp<- predict(prune(t1, cp=cp), newdata=te) * te$pop_total/1e5
  c(nb=cor(p_nb,te$events_311,method="spearman"),
    tree=cor(p_t,te$events_311,method="spearman"),
    tree_pruned=cor(p_tp,te$events_311,method="spearman"),
    bench=cor(te$subway_riders,te$events_311,method="spearman"))
})
res <- res[, !is.na(res[1,]), drop=FALSE]
cat("OUT-OF-SAMPLE Spearman across", ncol(res), "random 70/30 splits:\n")
cat(sprintf("%-22s %9s %9s %9s\n","method","mean","median","sd"))
for(r in rownames(res)) cat(sprintf("%-22s %9.3f %9.3f %9.3f\n",
  c(nb="negative binomial", tree="decision tree", tree_pruned="decision tree (pruned)",
    bench="benchmark: subway only")[r], mean(res[r,]), median(res[r,]), sd(res[r,])))
cat(sprintf("\nregression beats tree in %.0f%% of splits\n", 100*mean(res["nb",]>res["tree",])))
cat(sprintf("regression beats benchmark in %.0f%% of splits\n", 100*mean(res["nb",]>res["bench",])))
cat(sprintf("tree beats benchmark in %.0f%% of splits\n", 100*mean(res["tree",]>res["bench",])))
