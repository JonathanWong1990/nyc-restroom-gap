# 96_commercial_supply.R — does informal (commercial) restroom capacity change the ranking?
suppressMessages({library(sf); library(dplyr); library(MASS)})
options(scipen=999); set.seed(6093); D <- "data_raw"
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> dplyr::select(nta2020)
cc <- read.csv(file.path(D,"commercial_chains_dohmh_20260920.csv"), stringsAsFactors=FALSE) |>
  filter(!is.na(latitude), !is.na(longitude))
cat("commercial chain locations:", nrow(cc), "\n")
csf <- st_as_sf(cc, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263) |>
  st_join(nta, join=st_within) |> st_drop_geometry()
cat("assigned to an NTA:", sum(!is.na(csf$nta2020)),
    sprintf(" (%.1f%%)\n", 100*mean(!is.na(csf$nta2020))))
chains <- csf |> filter(!is.na(nta2020)) |> count(nta2020, name="chains")

d <- read.csv(file.path(D,"model_nta_scored_20260920.csv")) |>
  left_join(chains, by="nta2020") |>
  mutate(chains=ifelse(is.na(chains),0,chains), l_chain=log1p(chains)) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0)
cat("NTAs with zero chain locations:", sum(d$chains==0), "of", nrow(d), "\n")
cat(sprintf("chains per NTA: median %.0f, max %.0f\n", median(d$chains), max(d$chains)))
cat(sprintf("\ncor(municipal restrooms, chain locations) = %.3f\n",
            cor(d$restrooms, d$chains, method="spearman")))

cl_nb <- function(fit, cl){
  X <- model.matrix(fit); mu <- fitted(fit); y <- fit$y; th <- fit$theta
  u <- X*((y-mu)/(1+mu/th)); uc <- rowsum(u, cl); G <- length(unique(cl))
  sqrt(diag(vcov(fit) %*% crossprod(uc) %*% vcov(fit) * (G/(G-1))))
}
F0 <- events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total))
F1 <- update(F0, . ~ . + l_chain)
m0 <- glm.nb(F0, data=d); m1 <- glm.nb(F1, data=d)
s1 <- cl_nb(m1, d$cdta2020); co <- summary(m1)$coefficients
cat("\n=== DOES COMMERCIAL SUPPLY MATTER? ===\n")
k <- which(rownames(co)=="l_chain")
cat(sprintf("l_chain IRR %.3f  clustered p = %.4f\n", exp(co[k,1]),
            2*pnorm(-abs(co[k,1]/s1[k]))))
cat(sprintf("AIC without %.0f  ->  with %.0f\n", AIC(m0), AIC(m1)))

cat("\n=== DOES IT CHANGE THE RANKING? ===\n")
d$r0 <- d$events_311/pmax(predict(m0,type="response"),.01)
d$r1 <- d$events_311/pmax(predict(m1,type="response"),.01)
cat(sprintf("Spearman(ranking with vs without commercial supply) = %.3f\n",
            cor(d$r0, d$r1, method="spearman")))
cat(sprintf("top-10 overlap: %d/10\n",
  length(intersect(d$nta2020[order(-d$r0)][1:10], d$nta2020[order(-d$r1)][1:10]))))
cat("\nBiggest movers once informal supply is accounted for:\n")
d$move <- rank(-d$r1) - rank(-d$r0)
print(d |> arrange(move) |> transmute(neighbourhood=substr(ntaname,1,30),
      rank_before=rank(-r0)[order(move)][seq_len(n())]*0+round(rank(-r0)),
      rank_after=round(rank(-r1)), chains, restrooms) |> head(5), row.names=FALSE)
print(d |> arrange(desc(move)) |> transmute(neighbourhood=substr(ntaname,1,30),
      rank_before=round(rank(-r0)), rank_after=round(rank(-r1)), chains, restrooms) |>
      head(5), row.names=FALSE)
write.csv(d, file.path(D,"model_with_commercial_20260920.csv"), row.names=FALSE)
