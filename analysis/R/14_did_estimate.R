# 14_did_estimate.R — two-way FE Poisson + event study. Clustered SEs computed by hand
# (sandwich is not installed).
suppressMessages({library(dplyr)})
options(scipen=999); D <- "data_raw"
panel <- readRDS(file.path(D,"did_panel_20260920.rds"))

# identifying sample: parks whose closure status actually changes
vary <- panel |> group_by(park) |> summarise(v=n_distinct(closed), .groups="drop")
p <- panel |> filter(park %in% vary$park[vary$v>1]) |>
  mutate(park=factor(park), ym=factor(ym))
cat("estimation sample:", nrow(p), "park-months,", nlevels(droplevels(p$park)), "parks\n")
cat("closed share:", sprintf("%.1f%%", 100*mean(p$closed)),
    " mean complaints:", round(mean(p$complaints),3), "\n\n")

cluster_se <- function(fit, cl){
  X  <- model.matrix(fit); r <- residuals(fit, type="response")
  u  <- X * r
  bread <- summary(fit)$cov.unscaled
  uc <- rowsum(u, cl)
  meat <- crossprod(uc)
  G <- length(unique(cl))
  V <- bread %*% meat %*% bread * (G/(G-1))
  sqrt(diag(V))
}

cat("=== TWFE Poisson: complaints ~ closed + park FE + month FE ===\n")
fit <- glm(complaints ~ closed + park + ym, family=poisson, data=p)
se <- cluster_se(fit, p$park)
b  <- coef(fit)["closed"]; s <- se[names(coef(fit))=="closed"]
z  <- b/s
cat(sprintf("coef(closed) = %.4f   clustered SE = %.4f   z = %.2f   p = %.4f\n",
            b, s, z, 2*pnorm(-abs(z))))
cat(sprintf("=> a closed restroom is associated with a %.1f%% change in nearby complaints\n",
            100*(exp(b)-1)))
cat(sprintf("   95%% CI: %.1f%% to %.1f%%\n",
            100*(exp(b-1.96*s)-1), 100*(exp(b+1.96*s)-1)))

## --- event study: does anything happen BEFORE closure? (pre-trend test) -----
cat("\n=== Event study around first closure onset ===\n")
onset <- p |> arrange(park, ym) |> group_by(park) |>
  mutate(prev=lag(closed)) |> filter(!is.na(prev), prev==0, closed==1) |>
  slice(1) |> transmute(park, onset_ym=as.character(ym)) |> ungroup()
cat("parks with an identifiable closure onset:", nrow(onset), "\n")
ev <- p |> inner_join(onset, by="park") |>
  mutate(t = (as.integer(substr(as.character(ym),1,4))*12 + as.integer(substr(as.character(ym),6,7))) -
             (as.integer(substr(onset_ym,1,4))*12 + as.integer(substr(onset_ym,6,7))),
         bin = cut(t, breaks=c(-Inf,-13,-7,-1,5,11,Inf),
                   labels=c("<=-13","-12..-7","-6..-1","0..5","6..11",">=12"))) |>
  filter(!is.na(bin)) |> mutate(bin=relevel(factor(bin), ref="-6..-1"))
fe <- glm(complaints ~ bin + park + ym, family=poisson, data=ev)
ses <- cluster_se(fe, ev$park)
cf <- coef(fe); idx <- grep("^bin", names(cf))
cat(sprintf("%-10s %9s %9s %9s\n","window","coef","pct chg","z"))
for(i in idx) cat(sprintf("%-10s %9.3f %8.1f%% %9.2f\n",
    sub("^bin","",names(cf)[i]), cf[i], 100*(exp(cf[i])-1), cf[i]/ses[i]))
cat("(reference window = -6..-1 months, i.e. just before closure)\n")
