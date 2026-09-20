# 99_offset_test.R — is the shortlist an artifact of using RESIDENT population as exposure?
# Also: taxi activity is described as a strong demand measure but was never in the model.
suppressMessages({library(dplyr); library(MASS)}); options(scipen=999); set.seed(6093); D <- "data_raw"
d <- read.csv(file.path(D,"model_with_commercial_20260920.csv")) |>
  filter(!is.na(inc10k), !is.na(pov), pop_total>0)

# bring in taxi activity, which the data table calls "strong" but the model never used
xw <- read.csv(file.path(D,"crosswalk_taxizone_to_nta_20260920.csv"))
tl <- read.csv(file.path(D,"tlc_c5iv-bn4s_zonemonth_20260920.csv")) |>
  filter(pickup_dropoff=="Drop-off") |> group_by(locationid) |>
  summarise(trips=sum(trip_count), .groups="drop")
taxi <- xw |> inner_join(tl, by="locationid") |> group_by(nta2020) |>
  summarise(taxi=sum(trips*w_from), .groups="drop")
d <- d |> left_join(taxi, by="nta2020") |> mutate(taxi=ifelse(is.na(taxi),0,taxi), l_taxi=log1p(taxi/1000))
cat("NTAs with taxi data:", sum(d$taxi>0), "of", nrow(d), "\n\n")

rank_of <- function(f, exposure){
  m <- glm.nb(f, data=d)
  p <- predict(m, type="response")
  r <- d$events_311/pmax(p,.01)
  list(m=m, r=r, top=d$ntaname[order(-r)][1:10])
}
A <- rank_of(events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(pop_total)))
# alternative exposure: daytime presence = residents + workers (+ hotel rooms proxy)
d$exposure2 <- d$pop_total + d$jobs
B <- rank_of(events_311 ~ l_sub+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+offset(log(exposure2)))
# alternative: no offset at all, population as a free covariate
d$l_pop <- log(d$pop_total)
C <- rank_of(events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+inc10k+pov+old+boro+l_pop)
# with taxi added
D2 <- rank_of(events_311 ~ l_sub+l_jobs+l_hotel+l_rest+l_dens+l_taxi+inc10k+pov+old+boro+offset(log(pop_total)))

cat("=== DOES THE SHORTLIST SURVIVE A DIFFERENT EXPOSURE? ===\n")
cat(sprintf("A  resident population offset (published)   AIC %.0f\n", AIC(A$m)))
cat(sprintf("B  residents + jobs offset                  AIC %.0f\n", AIC(B$m)))
cat(sprintf("C  population as a free covariate           AIC %.0f\n", AIC(C$m)))
cat(sprintf("D  published + taxi activity                AIC %.0f\n", AIC(D2$m)))
cat(sprintf("\ntaxi coefficient: IRR %.3f, p = %.3f\n",
    exp(coef(D2$m)["l_taxi"]), summary(D2$m)$coefficients["l_taxi",4]))
cat(sprintf("population coefficient when freed: %.3f (offset assumes 1.0), p = %.4f\n",
    coef(C$m)["l_pop"], summary(C$m)$coefficients["l_pop",4]))

cat("\nrank agreement with the published ranking:\n")
for(nm in c("B","C","D")){
  o <- get(ifelse(nm=="D","D2",nm))
  cat(sprintf("  %s: Spearman %.3f | top-10 overlap %d/10\n", nm,
      cor(A$r, o$r, method="spearman"), length(intersect(A$top, o$top))))
}
cat("\nTop 10 under each specification:\n")
print(data.frame(published=substr(A$top,1,26), residents_plus_jobs=substr(B$top,1,26),
                 pop_freed=substr(C$top,1,26)), row.names=FALSE)
