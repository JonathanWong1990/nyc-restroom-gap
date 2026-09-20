# 95_convergent_shortlist.R — the defensible shortlist: areas ranked high by BOTH
# instruments (citizen-reported 311 and officer-issued summonses), which have opposite biases.
suppressMessages({library(dplyr)}); options(scipen=999); D <- "data_raw"
d <- read.csv(file.path(D,"model_v2_scored_20260920.csv"))

# normalise each instrument to a percentile rank, then require BOTH to be high
d <- d |> mutate(
  r311  = rank(resid_ratio)/n(),                 # 311-based unmet need (the ranking model)
  rsumm = rank(summons/pmax(alcohol,1))/n(),     # enforcement-normalised summons intensity
  both  = pmin(r311, rsumm))                     # an area is only as strong as its weaker signal
cat("=== CONVERGENT SHORTLIST — high on BOTH instruments ===\n")
cat("Each area scored by its WEAKER percentile, so a high score requires both to agree.\n\n")
print(d |> arrange(desc(both)) |>
  transmute(neighbourhood=substr(ntaname,1,32),
            pct_311=round(100*r311), pct_summons=round(100*rsumm),
            weaker=round(100*both), complaints=events_311, summonses=summons,
            restrooms) |> head(15), row.names=FALSE)

cat("\n=== How much do the two instruments agree? ===\n")
cat(sprintf("Spearman(311 unmet need, normalised summons intensity) = %.3f\n",
            cor(d$r311, d$rsumm, method="spearman")))
cat(sprintf("Areas in the top quartile of BOTH: %d of %d\n",
            sum(d$r311>0.75 & d$rsumm>0.75), nrow(d)))
cat("\nAreas high on 311 but NOT on summonses (possible reporting artifacts):\n")
print(d |> filter(r311>0.9, rsumm<0.5) |> arrange(desc(r311)) |>
  transmute(neighbourhood=substr(ntaname,1,32), pct_311=round(100*r311),
            pct_summons=round(100*rsumm)) |> head(6), row.names=FALSE)
cat("\nAreas high on summonses but NOT on 311 (possible enforcement artifacts):\n")
print(d |> filter(rsumm>0.9, r311<0.5) |> arrange(desc(rsumm)) |>
  transmute(neighbourhood=substr(ntaname,1,32), pct_311=round(100*r311),
            pct_summons=round(100*rsumm)) |> head(6), row.names=FALSE)
write.csv(d, file.path(D,"model_convergent_20260920.csv"), row.names=FALSE)
