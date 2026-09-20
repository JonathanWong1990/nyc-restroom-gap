# 91_rebuild_outcome.R — rebuild the modelling table on the OATH summons outcome.
# Enforcement intensity is controlled with the alcohol-summons placebo (same officers,
# same blocks, not restroom-dependent).
suppressMessages({library(sf); library(dplyr)})
options(scipen=999); D <- "data_raw"

nta <- st_read(file.path(D,"nycopendata_9nt8-h7nd_nta2020_20260920.geojson"), quiet=TRUE) |>
  st_transform(2263) |> select(nta2020)

to_nta <- function(f, dedup=TRUE){
  x <- read.csv(file.path(D,f), stringsAsFactors=FALSE)
  x$lat <- suppressWarnings(as.numeric(x$latitude)); x$lon <- suppressWarnings(as.numeric(x$longitude))
  x <- x |> filter(!is.na(lat), !is.na(lon)) |>
    mutate(ym=substr(occur_date,1,7), klat=round(lat,5), klon=round(lon,5))
  s <- st_as_sf(x, coords=c("lon","lat"), crs=4326) |> st_transform(2263) |>
    st_join(nta, join=st_within) |> st_drop_geometry() |> filter(!is.na(nta2020))
  if(dedup) s <- s |> distinct(klat, klon, ym, nta2020, .keep_all=TRUE)
  s
}
u <- to_nta("nypd_oath_urination_hxbk-grd3_20260920.csv")
a <- to_nta("nypd_oath_alcohol_placebo_hxbk-grd3_20260920.csv")
cat("urination summonses (deduped, on an NTA):", nrow(u), "\n")
cat("alcohol   summonses (deduped, on an NTA):", nrow(a), "\n")
cat("window:", min(u$ym), "to", max(u$ym), "\n\n")

out <- u |> count(nta2020, name="summons")
enf <- a |> count(nta2020, name="alcohol")

base <- read.csv(file.path(D,"model_nta_scored_20260920.csv"))
d <- base |> left_join(out, by="nta2020") |> left_join(enf, by="nta2020") |>
  mutate(summons=ifelse(is.na(summons),0,summons), alcohol=ifelse(is.na(alcohol),0,alcohol))
cat("NTAs with zero summonses:", sum(d$summons==0), " zero alcohol:", sum(d$alcohol==0), "\n")

# 311 restricted to the same 2023-2026 window, for a like-for-like comparison
e <- read.csv(file.path(D,"nyc311_urination_publictoilet_erm2-nwe9_20260920.csv")) |>
  filter(complaint_type=="Urinating in Public",
         location_type %in% c("Street/Sidewalk","Park/Playground","Subway Station"),
         !is.na(latitude), !is.na(longitude)) |>
  mutate(dt=as.Date(substr(created_date,1,10)), ym=format(dt,"%Y-%m")) |>
  filter(dt>=as.Date("2023-01-01"), dt<=as.Date("2026-06-30")) |>
  distinct(incident_address, ym, .keep_all=TRUE)
e311 <- st_as_sf(e, coords=c("longitude","latitude"), crs=4326) |> st_transform(2263) |>
  st_join(nta, join=st_within) |> st_drop_geometry() |> filter(!is.na(nta2020)) |>
  count(nta2020, name="c311_win")
d <- d |> left_join(e311, by="nta2020") |> mutate(c311_win=ifelse(is.na(c311_win),0,c311_win))

cat("\n=== ENFORCEMENT CHECK (the non-negotiable caveat) ===\n")
cat(sprintf("cor(summons, alcohol) raw     : %.3f\n", cor(d$summons, d$alcohol)))
cat(sprintf("cor(summons, alcohol) Spearman: %.3f\n", cor(d$summons, d$alcohol, method="spearman")))
d$share <- ifelse(d$alcohol+d$summons>0, d$summons/(d$summons+d$alcohol), NA)
cat(sprintf("urination share of the two: median %.3f  range %.3f-%.3f\n",
    median(d$share,na.rm=TRUE), min(d$share,na.rm=TRUE), max(d$share,na.rm=TRUE)))
cat(sprintf("cor(share, alcohol) Spearman  : %.3f  <- should be far weaker\n",
    cor(d$share, d$alcohol, method="spearman", use="complete.obs")))
write.csv(d, file.path(D,"model_v2_table_20260920.csv"), row.names=FALSE)
cat("\nwrote model_v2_table_20260920.csv\n")
