# A3_seed_stability.R — backs the published claim that the out-of-sample result is
# stable across random seeds (site says 0.786-0.795). Previously asserted, not scripted.
suppressMessages({library(dplyr); library(MASS)}); options(scipen=999)
D <- "data_raw"
d <- read.csv(file.path(D,"model_nta_scored_20260920.csv")) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0)
F <- events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total))
seeds <- c(6093, 1, 42, 777, 2026, 31337)
out <- lapply(seeds, function(s){
  set.seed(s)
  r <- replicate(200, {
    i <- sample(nrow(d), round(.7*nrow(d))); tr <- d[i,]; te <- d[-i,]
    f <- try(glm.nb(F, data=tr), silent=TRUE); if(inherits(f,"try-error")) return(c(NA,NA))
    p <- try(predict(f, newdata=te, type="response"), silent=TRUE); if(inherits(p,"try-error")) return(c(NA,NA))
    c(cor(p, te$events_311, method="spearman"), cor(te$subway_riders, te$events_311, method="spearman"))
  })
  r <- r[, !is.na(r[1,]), drop=FALSE]
  data.frame(seed=s, model=mean(r[1,]), benchmark=mean(r[2,]), win=mean(r[1,]>r[2,]))
})
res <- do.call(rbind, out)
cat("=== OUT-OF-SAMPLE RESULT ACROSS SEEDS (200 x 70/30 each) ===\n")
print(transform(res, model=round(model,3), benchmark=round(benchmark,3),
                win=paste0(round(100*win),"%")), row.names=FALSE)
cat(sprintf("\nmodel range %.3f-%.3f | benchmark range %.3f-%.3f | wins %.0f-%.0f%%\n",
    min(res$model), max(res$model), min(res$benchmark), max(res$benchmark),
    100*min(res$win), 100*max(res$win)))
