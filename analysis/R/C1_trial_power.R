# C1_trial_power.R — how large an effect could the proposed hours trial actually detect?
suppressMessages({library(dplyr)}); options(scipen=999); set.seed(6093); D <- "data_raw"
d <- read.csv(file.path(D,"model_nta_interventions_20260920.csv"))
hrs <- d |> filter(resid_ratio>=1.5, intervention=="Extend operating hours")
cat("trial neighbourhoods:", nrow(hrs), " facilities inside them:", sum(hrs$restrooms), "\n")

YRS <- 6.71
base_yr <- sum(hrs$events_311)/YRS                       # all channels
e <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv"),
              stringsAsFactors=FALSE) |>
  filter(complaint_type=="Urinating in Public",
         location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"))
phone <- mean(e$open_data_channel_type=="PHONE")
cat(sprintf("\nbaseline in those areas: %.0f complaints/yr (all channels)\n", base_yr))
cat(sprintf("phone-filed share: %.1f%% -> %.0f phone complaints/yr across the ten\n",
            100*phone, base_yr*phone))

# events available in a 10-month trial, treated half the time on average
months <- 10
for (outcome in c("all channels","phone only")) {
  rate <- if (outcome=="all channels") base_yr else base_yr*phone
  n_tot <- rate * months/12
  n_treat <- n_tot/2                                   # staggered: ~half the exposure is treated
  # detectable ratio at 80% power, 5% two-sided, Poisson counts
  mde <- function(n1) { z <- qnorm(0.975)+qnorm(0.8); exp(z*sqrt(2/max(n1,1))) }
  cat(sprintf("\n%s: ~%.0f events in the trial window, ~%.0f under treatment\n",
              outcome, n_tot, n_treat))
  cat(sprintf("  smallest detectable change: %.0f%%\n", 100*(mde(n_treat)-1)))
}
cat("\nFor comparison, the abandoned winterization design could detect +/-20%.\n")

cat("\n=== what the trial would actually cost ===\n")
cat(sprintf("per facility: 4 extra hours x 365 x $35 = $%s/yr\n", format(4*365*35, big.mark=",")))
cat(sprintf("across %d facilities in the ten areas: $%s/yr\n",
            sum(hrs$restrooms), format(sum(hrs$restrooms)*4*365*35, big.mark=",")))
cat(sprintf("for a 10-month trial: $%s\n", format(round(sum(hrs$restrooms)*4*365*35*10/12), big.mark=",")))

## --- the project's own Dead-ends note says enforcement contaminates LEVELS, not CHANGES,
## --- so a before/after trial should use the denser summons series, not 311.
suppressMessages(library(sf))
nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> dplyr::select(nta2020)
o <- read.csv(file.path(D,"nypd_oath_urination_hxbk-grd3_20260920.csv"), stringsAsFactors=FALSE)
o$lat <- suppressWarnings(as.numeric(o$latitude)); o$lon <- suppressWarnings(as.numeric(o$longitude))
o <- o |> filter(!is.na(lat), !is.na(lon))
osf <- st_as_sf(o, coords=c("lon","lat"), crs=4326) |> st_transform(2263) |>
  st_join(nta, join=st_within) |> st_drop_geometry() |> filter(!is.na(nta2020))
SUM_YRS <- 3.5
sm <- osf |> filter(nta2020 %in% hrs$nta2020) |> nrow()
cat("\n=== if the trial used SUMMONSES instead of 311 complaints ===\n")
cat(sprintf("summonses in the ten trial areas: %d over %.1f years = %.0f/yr\n", sm, SUM_YRS, sm/SUM_YRS))
n_tot <- (sm/SUM_YRS) * 10/12; n_treat <- n_tot/2
z <- qnorm(0.975)+qnorm(0.8)
cat(sprintf("~%.0f events in a 10-month window, ~%.0f under treatment\n", n_tot, n_treat))
cat(sprintf("smallest detectable change: %.0f%%\n", 100*(exp(z*sqrt(2/n_treat))-1)))
cat("\nand with the alcohol series available as a placebo, the same way it was used before.\n")
